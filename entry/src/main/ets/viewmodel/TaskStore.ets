import { ConversionSnapshot } from '../models/ConversionSnapshot';
import { TaskStoreDependencies, TaskDependencies } from '../services/TaskDependencies';
import { TaskStorePort } from '../services/ServiceContracts';
import { ErrorHandler } from '../common/ErrorHandler';
import { DemoTask, DemoTaskTiming, TaskListener, isActiveTask, FidelitySelection, TaskRuntime } from '../models/InteractionModels';
import { BridgeError } from '../common/BridgeError';
import { FidelityPolicy } from './FidelityPolicy';
import { DemoFidelityReport } from './DemoFidelityReport';
import { NativeFidelityReport } from './NativeFidelityReport';
import { ConvertRequest, ConvertResult, ProgressEvent } from '../models/NativeProtocol';
import { AuthorizedFile, SessionContext } from '../models/SessionModels';

class SystemTaskRuntime implements TaskRuntime {
  now(): number { return Date.now(); }
  setTimeout(callback: () => void, delayMs: number): number { return setTimeout(callback, delayMs); }
  clearTimeout(id: number): void { clearTimeout(id); }
}

// Session UI records; production ConversionTask/ConvertResult protocol stays unchanged.
// Native dispatch is reserved for authorized prepared requests, never selected by the demo UI.
export class TaskStore implements TaskStorePort {
  private services: TaskStoreDependencies;
  private readonly historyLimit: number = 100;
  private static instance: TaskStore = new TaskStore();
  private tasks: DemoTask[] = [];
  private runningTask: DemoTask | null = null;
  private queuedTasks: DemoTask[] = [];
  private queueOrder: Map<string, number> = new Map<string, number>();
  private orderSequence: number = 0;
  private timings: Map<string, DemoTaskTiming> = new Map<string, DemoTaskTiming>();
  private listeners: TaskListener[] = [];
  private timer: number = -1;
  private sequence: number = 0;
  private listenerSequence: number = 0;
  private nativeRequests: Map<string, ConvertRequest> = new Map<string, ConvertRequest>();
  private nativeResults: Map<string, ConvertResult> = new Map<string, ConvertResult>();
  private nativeRunningId: string = '';
  private nativeIdle: Promise<void> | null = null;
  private resolveNativeIdle: () => void = () => {};
  private nativeSequences: Map<string, number> = new Map<string, number>();
  private closing: boolean = false;
  private advancing: boolean = false;
  private runtime: TaskRuntime;
  private inputSessions: Map<string, string> = new Map<string, string>();
  private inputListener: number = -1;
  private inputRegistrations: Map<string, ConvertRequest> = new Map<string, ConvertRequest>();
  private inputDispatched: Set<string> = new Set<string>();
  private inputCleanup: Promise<void>[] = [];

  constructor(runtime: TaskRuntime = new SystemTaskRuntime(), services: TaskStoreDependencies = new TaskDependencies()) { this.runtime = runtime; this.services = services; }

  static useDefault(store: TaskStore): void { TaskStore.instance = store; }

  /** @deprecated Compatibility only. Obtain the owned instance from ServiceContainer or inject it. */
  static shared(): TaskStore {
    // A recreated UIAbility may reuse the same JS process after onDestroy().
    // Do not reopen while the previous Native dispatcher still owns resources.
    if (TaskStore.instance.closing && TaskStore.instance.nativeRunningId.length === 0) {
      TaskStore.instance = new TaskStore();
    }
    return TaskStore.instance;
  }

  snapshot(): DemoTask[] {
    return this.tasks.map((task: DemoTask) => task.clone());
  }

  subscribe(callback: (tasks: DemoTask[]) => void): number {
    const token = ++this.listenerSequence;
    this.listeners.push({ token: token, callback: callback });
    return token;
  }

  unsubscribe(token: number): void {
    this.listeners = this.listeners.filter((item: TaskListener) => item.token !== token);
  }

  enqueue(fileName: string, sourceId: string, targetId: string, routeId: string, approved: boolean = false,
    fidelity?: FidelitySelection): DemoTask {
    const source = this.services.planner.validateFileName(fileName, sourceId);
    const route = this.services.planner.routes(sourceId, targetId).find((item) => item.id === routeId);
    if (!route) { throw new BridgeError('UNSUPPORTED_FORMAT', 'DEMO_ROUTE_NOT_FOUND'); }
    const selection: FidelitySelection = fidelity ? fidelity : {
      qualityMode: 'balanced', requestedIntent: route.intent, requestedTier: route.fidelityTier
    };
    FidelityPolicy.validate(route, selection);
    if (route.requiresUserApproval && !approved) {
      throw new BridgeError('INVALID_REQUEST', 'DEMO_APPROVAL_REQUIRED');
    }
    this.ensureCapacity();
    const now = this.runtime.now();
    const task = new DemoTask();
    task.id = `demo-${now}-${++this.sequence}`; task.fileName = source;
    task.sourceFormat = this.services.registry.normalizeFormat(sourceId); task.targetFormat = route.to; task.routeId = routeId;
    task.stage = '等待演示'; task.createdAtMs = now;
    task.qualityMode = selection.qualityMode; task.intent = selection.requestedIntent;
    task.requestedIntent = selection.requestedIntent; task.requestedTier = selection.requestedTier;
    this.tasks.unshift(task); this.queueTask(task);
    this.timings.set(task.id, { lastTickMs: now, activeMs: 0,
      plannedTier: route.fidelityTier, allowedDegradations: route.allowedDegradations.slice() });
    this.startTimer();
    this.notify();
    return task.clone();
  }

  enqueueNative(fileName: string, request: ConvertRequest, approved: boolean = false): DemoTask {
    const name = this.services.planner.validateFileName(fileName, request.inputs[0]?.sourceFormatId || '');
    const prepared = this.services.runner.prepare(request, approved);
    if (prepared.taskId.length === 0 || this.tasks.some((task: DemoTask) => task.id === prepared.taskId) ||
      this.nativeRequests.has(prepared.taskId)) { throw new BridgeError('TASK_BUSY', 'NATIVE_TASK_ID_CONFLICT'); }
    this.ensureCapacity();
    const task = new DemoTask();
    task.id = prepared.taskId; task.mode = 'native'; task.fileName = name;
    task.sourceFormat = prepared.inputs[0].sourceFormatId; task.targetFormat = prepared.targetFormatId;
    task.routeId = prepared.plan.routeId; task.qualityMode = prepared.qualityMode;
    task.intent = prepared.intent; task.requestedIntent = prepared.intent; task.requestedTier = prepared.plan.minimumTier;
    task.createdAtMs = this.runtime.now(); task.stage = '等待 Native 能力校验';
    this.tasks.unshift(task); this.queueTask(task); this.nativeRequests.set(task.id, prepared);
    this.startTimer(); this.notify();
    return task.clone();
  }

  // Additive entry point. No authorized files means the original demo enqueue path.
  async submitTask(fileName: string, sourceId: string, targetId: string, routeId: string,
    approved: boolean = false, fidelity?: FidelitySelection, authorizedFiles: AuthorizedFile[] = [],
    session?: SessionContext): Promise<DemoTask> {
    if (authorizedFiles.length === 0) {
      return this.enqueue(fileName, sourceId, targetId, routeId, approved, fidelity);
    }
    const route = this.services.planner.routes(sourceId, targetId).find((item) => item.id === routeId);
    if (!route || !session) { throw new BridgeError('INVALID_REQUEST', 'AUTHORIZED_SUBMISSION_CONTEXT'); }
    const selection: FidelitySelection = fidelity ?? { qualityMode: 'balanced',
      requestedIntent: route.intent, requestedTier: route.fidelityTier };
    let transferred: boolean = false;
    let prepared: ConvertRequest | undefined = undefined;
    try {
      this.ensureCapacity();
      const request: ConvertRequest = await this.services.authorized.prepare(authorizedFiles, session, route,
        selection, approved, () => !this.closing);
      prepared = request;
      const task: DemoTask = this.enqueueNative(authorizedFiles[0].originalName, request, approved);
      this.inputSessions.set(task.id, session.sessionId); this.inputRegistrations.set(task.id, request); transferred = true;
      if (this.inputListener === -1) { this.inputListener = this.subscribe(() => { this.releaseSettledInputs(); }); }
      this.releaseSettledInputs();
      return task;
    } catch (error) {
      this.ensureCapacity();
      const failure: BridgeError = error instanceof BridgeError ? error : new BridgeError('INTERNAL_ERROR', 'NATIVE_INPUT_PREPARATION_FAILED');
      const task: DemoTask = new DemoTask();
      task.id = `native-input-${this.runtime.now()}-${++this.sequence}`; task.mode = 'native';
      task.fileName = authorizedFiles[0].originalName; task.sourceFormat = sourceId; task.targetFormat = targetId;
      task.routeId = routeId; task.qualityMode = selection.qualityMode; task.intent = selection.requestedIntent;
      task.requestedIntent = selection.requestedIntent; task.requestedTier = selection.requestedTier;
      task.status = 'failed'; task.stage = '真实输入提交失败'; task.createdAtMs = this.runtime.now();
      task.error = `${failure.code}:${failure.reason}`;
      this.tasks.unshift(task); this.notify(); return task.clone();
    } finally {
      if (!transferred) {
        if (prepared) {
          try { await this.services.native.releaseTask(prepared.taskId, prepared.attemptId); }
          catch (error) { ErrorHandler.catchBridge(error, 'TaskStore.releaseRegistration'); }
        }
        await this.services.files.destroySession(session.sessionId);
      }
    }
  }

  private releaseSettledInputs(): void {
    for (const entry of this.inputSessions.entries()) {
      if (this.nativeRunningId === entry[0]) { this.inputDispatched.add(entry[0]); }
      const task: DemoTask | undefined = this.tasks.find((item: DemoTask) => item.id === entry[0]);
      if ((!task || !isActiveTask(task.status)) && !this.nativeRequests.has(entry[0]) && this.nativeRunningId !== entry[0]) {
        this.inputSessions.delete(entry[0]);
        const request: ConvertRequest | undefined = this.inputRegistrations.get(entry[0]);
        const dispatched: boolean = this.inputDispatched.has(entry[0]);
        this.inputRegistrations.delete(entry[0]); this.inputDispatched.delete(entry[0]);
        const cleanup: Promise<void> = this.releaseOwnedInput(entry[1], dispatched ? undefined : request);
        this.inputCleanup.push(cleanup);
        cleanup.finally(() => { this.inputCleanup = this.inputCleanup.filter((item: Promise<void>) => item !== cleanup); });
      }
    }
  }

  private async releaseOwnedInput(sessionId: string, request?: ConvertRequest): Promise<void> {
    if (request) {
      try { await this.services.native.releaseTask(request.taskId, request.attemptId); }
      catch (error) { ErrorHandler.swallow('TaskStore.fallback', error); console.error('Native input registration cleanup failed'); }
    }
    try { await this.services.files.destroySession(sessionId); }
    catch (error) { ErrorHandler.catchBridge(error, 'TaskStore.releaseInputs'); }
  }

  // Called at ability teardown after shutdown; never delete input files under a live Native call.
  async releaseAuthorizedSessions(cleanup: () => Promise<void> = () => this.services.files.destroyAllSessions()): Promise<void> {
    try {
      if (this.nativeIdle) { await this.nativeIdle; }
      this.releaseSettledInputs();
      await Promise.all(this.inputCleanup);
      await cleanup();
    } catch (error) {
      if (error instanceof BridgeError) { throw error; }
      throw new BridgeError('IO_ERROR', 'WORKSPACE_REMOVE_FAILED');
    }
  }

  private ensureCapacity(): void {
    if (this.closing) { throw new BridgeError('TASK_INTERRUPTED', 'TASK_STORE_CLOSED'); }
    if (this.tasks.length >= this.historyLimit) {
      let lastFinished: DemoTask | undefined = undefined;
      for (let index: number = this.tasks.length - 1; index >= 0; index--) {
        if (!isActiveTask(this.tasks[index].status)) { lastFinished = this.tasks[index]; break; }
      }
      if (!lastFinished) { throw new BridgeError('TASK_BUSY', 'DEMO_HISTORY_LIMIT'); }
      const evictedId: string = lastFinished.id;
      this.tasks = this.tasks.filter((task: DemoTask) => task.id !== evictedId);
      this.timings.delete(lastFinished.id); this.queueOrder.delete(lastFinished.id);
      this.releaseResult(lastFinished.id);
    }
  }

  // Explicit clock step makes queue/control behaviour testable without waiting for UI timers.
  advance(now: number): void {
    if (this.advancing || this.closing || !Number.isFinite(now)) { return; }
    this.advancing = true;
    try { this.advanceOnce(now); }
    finally {
      this.advancing = false;
      if (this.hasRunnableWork()) { this.startTimer(200); } else { this.stopTimer(); }
    }
  }
  private advanceOnce(now: number): void {
    const task: DemoTask | null = this.runningTask;
    if (task && task.status === 'running' && task.mode === 'demo') {
      const timing: DemoTaskTiming | undefined = this.timings.get(task.id);
      if (timing) {
timing.activeMs += Math.max(0, now - timing.lastTickMs);
timing.lastTickMs = Math.max(timing.lastTickMs, now);
task.elapsedMs = timing.activeMs;
task.progress = Math.min(100, Math.floor(timing.activeMs / FidelityPolicy.durationMs(task.qualityMode) * 100));
if (task.progress < 15) { task.stage = '① 模拟准备'; }
      else if (task.progress < 65) { task.stage = '② 模拟转换'; }
      else if (task.progress < 85) { task.stage = '③ 模拟校验'; }
      else if (task.progress < 95) { task.stage = '④ 模拟提交'; }
      else { task.stage = '⑤ 模拟清理'; }
if (task.progress >= 85 && !task.fidelityReport) {
        task.fidelityReport = DemoFidelityReport.create(task, timing.plannedTier, timing.allowedDegradations);
      }
if (task.progress === 100) {
        task.status = 'completed';
        task.stage = '演示完成 · 无真实输出';
        task.resultLabel = this.services.planner.resultLabel(task.fileName, task.targetFormat);
        task.achievedTier = task.fidelityReport ? task.fidelityReport.achievedTier : undefined;
        this.timings.delete(task.id);
      }
      }
      if (task.status !== 'running') { this.runningTask = null; }
    }
    if (!this.closing && this.nativeRunningId.length === 0 && (!this.runningTask || this.runningTask.status !== 'running')) {
      this.runningTask = null;
      const waiting: DemoTask | undefined = this.queuedTasks.shift();
      if (waiting) {
        waiting.status = 'running'; this.runningTask = waiting;
        const timing: DemoTaskTiming | undefined = this.timings.get(waiting.id);
        if (timing) { timing.lastTickMs = now; }
        waiting.stage = waiting.mode === 'demo' ? '① 模拟准备' : 'Native 能力校验与输入探测';
        if (waiting.mode === 'native') { this.dispatchNative(waiting); }
      }
    }
    if (!this.hasRunnableWork()) { this.stopTimer(); }
    this.notify();
  }

  private queueTask(task: DemoTask): void {
    if (!this.queueOrder.has(task.id)) { this.queueOrder.set(task.id, ++this.orderSequence); }
    this.queuedTasks = this.queuedTasks.filter((item: DemoTask) => item.id !== task.id);
    this.queuedTasks.push(task);
    this.queuedTasks.sort((a: DemoTask, b: DemoTask) => (this.queueOrder.get(a.id) ?? 0) - (this.queueOrder.get(b.id) ?? 0));
  }

  private dispatchNative(task: DemoTask): void {
    if (this.nativeRunningId.length > 0 || this.closing) { return; }
    const request = this.nativeRequests.get(task.id);
    if (!request) { task.status = 'failed'; task.error = 'NATIVE_REQUEST_MISSING'; return; }
    this.nativeRunningId = task.id;
    this.nativeIdle = new Promise<void>((resolve) => { this.resolveNativeIdle = resolve; });
    this.executeNative(task, request);
  }

  private receiveNativeProgress(task: DemoTask, request: ConvertRequest, event: ProgressEvent): void {
    if (task.status !== 'running' || event.taskId !== task.id || event.attemptId !== request.attemptId ||
      !Number.isSafeInteger(event.sequence) || event.sequence < 0 ||
      event.sequence <= (this.nativeSequences.get(task.id) ?? -1)) { return; }
    this.nativeSequences.set(task.id, event.sequence);
    if (event.fraction !== undefined && Number.isFinite(event.fraction)) {
      task.progress = Math.max(task.progress, Math.min(99, Math.max(0, Math.floor(event.fraction * 100))));
    }
    task.stage = `Native · ${event.stage}`;
    // advance() publishes at the same 200 ms cadence as the demo lane.
  }

  private async executeNative(task: DemoTask, request: ConvertRequest): Promise<void> {
    let result: ConvertResult | undefined = undefined;
    let retained = false;
    try {
      result = await this.services.runner.run(request,
        (event: ProgressEvent) => { this.receiveNativeProgress(task, request, event); },
        () => task.status === 'running' && !this.closing);
      if (task.status !== 'running' || this.closing) { return; }
      if (result.schemaVersion !== 1 || !Number.isFinite(result.elapsedMs) || result.elapsedMs < 0) {
        throw new BridgeError('PROTOCOL_INCOMPATIBLE', 'NATIVE_RESULT_METADATA');
      }
      if (result.status === 'success') {
        task.fidelityReport = NativeFidelityReport.read(task, result);
        task.achievedTier = task.fidelityReport?.achievedTier;
        task.progress = 100; task.status = 'completed'; task.stage = 'Native 转换完成 · 输出待导出';
        task.resultLabel = `${result.outputs.length} 个已验证的内部输出，尚未导出到用户目录`;
        this.saveNativeResult(task.id, result); retained = true;
      } else {
        task.status = result.status === 'cancelled' ? 'cancelled' : 'failed';
        task.stage = result.status === 'cancelled' ? 'Native 已取消' : 'Native 转换失败';
        task.error = result.error ? `${result.error.code}:${result.error.reason}` : '';
      }
      task.elapsedMs = result.elapsedMs;
    } catch (error) {
      if (task.status === 'running') {
        const failure: BridgeError = ErrorHandler.catchBridge(error, 'TaskStore');
        task.status = 'failed'; task.stage = 'Native 任务未完成';
        task.error = `${failure.code || 'INTERNAL_ERROR'}:${failure.reason || 'NATIVE_TASK_FAILED'}`;
        task.fidelityReport = undefined; task.achievedTier = undefined;
      }
    } finally {
      if (result && !retained) { await this.services.runner.releaseOutputs(result); }
      this.nativeRequests.delete(task.id); this.nativeSequences.delete(task.id);
      this.nativeRunningId = '';
      this.resolveNativeIdle(); this.nativeIdle = null; this.resolveNativeIdle = () => {};
      if (this.runningTask?.id === task.id) { this.runningTask = null; }
      this.advance(this.runtime.now());
    }
  }

  private saveNativeResult(id: string, result: ConvertResult): void {
    while (!this.nativeResults.has(id) && this.nativeResults.size >= this.historyLimit) {
      const oldest: string | undefined = this.nativeResults.keys().next().value;
      if (!oldest) { break; }
      this.releaseResult(oldest);
    }
    this.nativeResults.set(id, ConversionSnapshot.copyConvertResult(result));
  }

  nativeResultSnapshot(id: string): ConvertResult | undefined {
    const result: ConvertResult | undefined = this.nativeResults.get(id);
    if (!result) { return undefined; }
    this.nativeResults.delete(id); this.nativeResults.set(id, result);
    return ConversionSnapshot.copyConvertResult(result);
  }

  private releaseResult(id: string): void {
    const result = this.nativeResults.get(id);
    if (result) { this.nativeResults.delete(id); this.services.runner.releaseOutputs(result); }
  }

  pause(id: string): boolean {
    const task = this.tasks.find((item: DemoTask) => item.id === id);
    if (!task || task.mode === 'native' || task.status !== 'running') { return false; }
    this.advance(this.runtime.now());
    if (task.status !== 'running') { return false; }
    task.status = 'paused'; task.stage = '演示已暂停'; this.runningTask = null;
    this.advance(this.runtime.now());
    return true;
  }

  resume(id: string): boolean {
    const task = this.tasks.find((item: DemoTask) => item.id === id);
    if (!task || task.mode === 'native' || task.status !== 'paused') { return false; }
    task.status = 'queued'; task.stage = '等待继续演示'; this.queueTask(task);
    this.advance(this.runtime.now()); this.startTimer();
    return true;
  }

  cancel(id: string): boolean {
    const task = this.tasks.find((item: DemoTask) => item.id === id);
    if (!task || !isActiveTask(task.status)) { return false; }
    task.status = 'cancelled'; task.stage = '演示已取消';
    this.queuedTasks = this.queuedTasks.filter((item: DemoTask) => item.id !== id);
    if (this.runningTask?.id === id) { this.runningTask = null; }
    if (task.mode === 'native') {
      task.stage = '已请求取消 Native 任务';
      const request = this.nativeRequests.get(task.id);
      if (request && this.nativeRunningId === task.id) {
        this.services.runner.cancel(request).catch((error: Error) => {
          task.error = ErrorHandler.catchBridge(error, 'TaskStore.cancel', 'TASK_INTERRUPTED', 'NATIVE_CANCEL_FAILED').reason; this.notify();
        });
      } else { this.nativeRequests.delete(task.id); }
    }
    task.fidelityReport = undefined; task.achievedTier = undefined;
    this.timings.delete(task.id);
    this.advance(this.runtime.now());
    return true;
  }

  clearFinished(): number {
    const before = this.tasks.length;
    for (const task of this.tasks) { if (!isActiveTask(task.status)) { this.releaseResult(task.id); this.queueOrder.delete(task.id); } }
    this.tasks = this.tasks.filter((task: DemoTask) => isActiveTask(task.status));
    this.notify();
    return before - this.tasks.length;
  }

  private hasRunnableWork(): boolean {
    return !this.closing && (this.runningTask?.status === 'running' || this.queuedTasks.length > 0);
  }

  private startTimer(delayMs: number = 50): void {
    if (this.timer !== -1 || !this.hasRunnableWork()) { return; }
    this.timer = this.runtime.setTimeout(() => {
      this.timer = -1;
      this.advance(this.runtime.now());
    }, delayMs);
  }

  private stopTimer(): void {
    if (this.timer !== -1) { this.runtime.clearTimeout(this.timer); this.timer = -1; }
  }

  shutdown(): void {
    this.closing = true;
    this.stopTimer();
    for (const task of this.tasks) {
      if (isActiveTask(task.status)) {
        if (task.mode === 'native') { this.cancel(task.id); }
        task.status = 'cancelled'; task.stage = '应用退出，任务取消';
        task.fidelityReport = undefined; task.achievedTier = undefined;
      }
    }
    for (const id of this.nativeResults.keys()) { this.releaseResult(id); }
    this.timings.clear(); this.queuedTasks = []; this.queueOrder.clear(); this.runningTask = null;
    this.notify(); this.listeners = [];
  }

  private notify(): void {
    for (const item of this.listeners.slice()) {
      // A disappearing page must not prevent other observers or cleanup from receiving state.
      try { item.callback(this.snapshot()); } catch (error) { ErrorHandler.swallow('TaskStore.observer', error); }
    }
  }
}

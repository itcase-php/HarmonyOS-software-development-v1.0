import { DemoTask, DemoTaskTiming, TaskListener, isActiveTask, FidelitySelection, TaskRuntime } from '../models/InteractionModels';
import { ConversionPlanner } from './ConversionPlanner';
import { BridgeError } from '../common/BridgeError';
import { FormatRegistry } from '../services/FormatRegistry';
import { FidelityPolicy } from './FidelityPolicy';
import { DemoFidelityReport } from './DemoFidelityReport';
import { NativeFidelityReport } from './NativeFidelityReport';
import { NativeTaskRunner } from '../services/NativeTaskRunner';
import { ConvertRequest, ConvertResult, ProgressEvent } from '../models/NativeProtocol';

class SystemTaskRuntime implements TaskRuntime {
  now(): number { return Date.now(); }
  setTimeout(callback: () => void, delayMs: number): number { return setTimeout(callback, delayMs); }
  clearTimeout(id: number): void { clearTimeout(id); }
}

// Session UI records; production ConversionTask/ConvertResult protocol stays unchanged.
// Native dispatch is reserved for authorized prepared requests, never selected by the demo UI.
export class TaskStore {
  private static instance: TaskStore = new TaskStore();
  private tasks: DemoTask[] = [];
  private timings: Map<string, DemoTaskTiming> = new Map<string, DemoTaskTiming>();
  private listeners: TaskListener[] = [];
  private timer: number = -1;
  private sequence: number = 0;
  private listenerSequence: number = 0;
  private nativeRequests: Map<string, ConvertRequest> = new Map<string, ConvertRequest>();
  private nativeResults: Map<string, ConvertResult> = new Map<string, ConvertResult>();
  private nativeRunningId: string = '';
  private nativeSequences: Map<string, number> = new Map<string, number>();
  private closing: boolean = false;
  private advancing: boolean = false;
  private runtime: TaskRuntime;

  constructor(runtime: TaskRuntime = new SystemTaskRuntime()) { this.runtime = runtime; }

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
    const source = ConversionPlanner.validateFileName(fileName, sourceId);
    const route = ConversionPlanner.routes(sourceId, targetId).find((item) => item.id === routeId);
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
    task.sourceFormat = FormatRegistry.normalizeFormat(sourceId); task.targetFormat = route.to; task.routeId = routeId;
    task.stage = '等待演示'; task.createdAtMs = now;
    task.qualityMode = selection.qualityMode; task.intent = selection.requestedIntent;
    task.requestedIntent = selection.requestedIntent; task.requestedTier = selection.requestedTier;
    this.tasks.unshift(task);
    this.timings.set(task.id, { lastTickMs: now, activeMs: 0,
      plannedTier: route.fidelityTier, allowedDegradations: route.allowedDegradations.slice() });
    this.startTimer();
    this.notify();
    return task.clone();
  }

  enqueueNative(fileName: string, request: ConvertRequest, approved: boolean = false): DemoTask {
    const name = ConversionPlanner.validateFileName(fileName, request.inputs[0]?.sourceFormatId || '');
    const prepared = NativeTaskRunner.prepare(request, approved);
    if (prepared.taskId.length === 0 || this.tasks.some((task: DemoTask) => task.id === prepared.taskId) ||
      this.nativeRequests.has(prepared.taskId)) { throw new BridgeError('TASK_BUSY', 'NATIVE_TASK_ID_CONFLICT'); }
    this.ensureCapacity();
    const task = new DemoTask();
    task.id = prepared.taskId; task.mode = 'native'; task.fileName = name;
    task.sourceFormat = prepared.inputs[0].sourceFormatId; task.targetFormat = prepared.targetFormatId;
    task.routeId = prepared.plan.routeId; task.qualityMode = prepared.qualityMode;
    task.intent = prepared.intent; task.requestedIntent = prepared.intent; task.requestedTier = prepared.plan.minimumTier;
    task.createdAtMs = this.runtime.now(); task.stage = '等待 Native 能力校验';
    this.tasks.unshift(task); this.nativeRequests.set(task.id, prepared);
    this.startTimer(); this.notify();
    return task.clone();
  }

  private ensureCapacity(): void {
    if (this.closing) { throw new BridgeError('TASK_INTERRUPTED', 'TASK_STORE_CLOSED'); }
    if (this.tasks.length >= 100) {
      const lastFinished = this.tasks.slice().reverse().find((task: DemoTask) => !isActiveTask(task.status));
      if (!lastFinished) { throw new BridgeError('TASK_BUSY', 'DEMO_HISTORY_LIMIT'); }
      this.tasks = this.tasks.filter((task: DemoTask) => task.id !== lastFinished.id);
      this.timings.delete(lastFinished.id);
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
    for (const task of this.tasks) {
      if (task.status !== 'running') { continue; }
      if (task.mode === 'native') { this.dispatchNative(task); continue; }
      const timing = this.timings.get(task.id);
      if (!timing) { continue; }
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
        task.resultLabel = ConversionPlanner.resultLabel(task.fileName, task.targetFormat);
        task.achievedTier = task.fidelityReport ? task.fidelityReport.achievedTier : undefined;
        this.timings.delete(task.id);
      }
    }
    if (!this.closing && this.nativeRunningId.length === 0 && !this.tasks.some((task: DemoTask) => task.status === 'running')) {
      const waiting = this.tasks.slice().reverse().find((task: DemoTask) => task.status === 'queued');
      if (waiting) {
        waiting.status = 'running';
        const timing = this.timings.get(waiting.id);
        if (timing) { timing.lastTickMs = now; }
        waiting.stage = waiting.mode === 'demo' ? '① 模拟准备' : 'Native 能力校验与输入探测';
        if (waiting.mode === 'native') { this.dispatchNative(waiting); }
      }
    }
    if (!this.tasks.some((task: DemoTask) => task.status === 'running' || task.status === 'queued')) {
      this.stopTimer();
    }
    this.notify();
  }

  private dispatchNative(task: DemoTask): void {
    if (this.nativeRunningId.length > 0 || this.closing) { return; }
    const request = this.nativeRequests.get(task.id);
    if (!request) { task.status = 'failed'; task.error = 'NATIVE_REQUEST_MISSING'; return; }
    this.nativeRunningId = task.id;
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
      result = await NativeTaskRunner.run(request,
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
        this.nativeResults.set(task.id, JSON.parse(JSON.stringify(result)) as ConvertResult); retained = true;
      } else {
        task.status = result.status === 'cancelled' ? 'cancelled' : 'failed';
        task.stage = result.status === 'cancelled' ? 'Native 已取消' : 'Native 转换失败';
        task.error = result.error ? `${result.error.code}:${result.error.reason}` : '';
      }
      task.elapsedMs = result.elapsedMs;
    } catch (error) {
      if (task.status === 'running') {
        const failure = error as BridgeError;
        task.status = 'failed'; task.stage = 'Native 任务未完成';
        task.error = `${failure.code || 'INTERNAL_ERROR'}:${failure.reason || 'NATIVE_TASK_FAILED'}`;
        task.fidelityReport = undefined; task.achievedTier = undefined;
      }
    } finally {
      if (result && !retained) { await NativeTaskRunner.releaseOutputs(result); }
      this.nativeRequests.delete(task.id); this.nativeSequences.delete(task.id);
      this.nativeRunningId = '';
      this.advance(this.runtime.now());
    }
  }

  private releaseResult(id: string): void {
    const result = this.nativeResults.get(id);
    if (result) { this.nativeResults.delete(id); NativeTaskRunner.releaseOutputs(result); }
  }

  pause(id: string): boolean {
    const task = this.tasks.find((item: DemoTask) => item.id === id);
    if (!task || task.mode === 'native' || task.status !== 'running') { return false; }
    this.advance(this.runtime.now());
    if (task.status !== 'running') { return false; }
    task.status = 'paused'; task.stage = '演示已暂停';
    this.advance(this.runtime.now());
    return true;
  }

  resume(id: string): boolean {
    const task = this.tasks.find((item: DemoTask) => item.id === id);
    if (!task || task.mode === 'native' || task.status !== 'paused') { return false; }
    task.status = 'queued'; task.stage = '等待继续演示';
    this.advance(this.runtime.now()); this.startTimer();
    return true;
  }

  cancel(id: string): boolean {
    const task = this.tasks.find((item: DemoTask) => item.id === id);
    if (!task || !isActiveTask(task.status)) { return false; }
    task.status = 'cancelled'; task.stage = '演示已取消';
    if (task.mode === 'native') {
      task.stage = '已请求取消 Native 任务';
      const request = this.nativeRequests.get(task.id);
      if (request && this.nativeRunningId === task.id) {
        NativeTaskRunner.cancel(request).catch((error: Error) => {
          task.error = (error as BridgeError).reason || 'NATIVE_CANCEL_FAILED'; this.notify();
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
    for (const task of this.tasks) { if (!isActiveTask(task.status)) { this.releaseResult(task.id); } }
    this.tasks = this.tasks.filter((task: DemoTask) => isActiveTask(task.status));
    this.notify();
    return before - this.tasks.length;
  }

  private hasRunnableWork(): boolean {
    return !this.closing && this.tasks.some((task: DemoTask) => task.status === 'running' || task.status === 'queued');
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
    this.timings.clear(); this.notify(); this.listeners = [];
  }

  private notify(): void {
    for (const item of this.listeners.slice()) {
      // A disappearing page must not prevent other observers or cleanup from receiving state.
      try { item.callback(this.snapshot()); } catch (_) { continue; }
    }
  }
}

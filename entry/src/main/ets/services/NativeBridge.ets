import { ErrorHandler } from '../common/ErrorHandler';
import * as protocol from '../models/NativeProtocol';
import { BridgeError } from '../common/BridgeError';
import { errorCodes } from '../generated/ErrorCatalog';
import { NativeModuleLoader, NativeBridgePort } from './ServiceContracts';
interface NativeFailure {
  code?: string;
  reason?: string;
}

interface NativeModuleImport {
  default: protocol.NativeModule;
}



// This is the only application service that imports libentry.so.
// Uses dynamic import so the previewer (which cannot load native .so) can still work.
export class NativeBridgeService implements NativeBridgePort {
  private loader: NativeModuleLoader;
  constructor(loader: NativeModuleLoader = new PlatformNativeLoader()) { this.loader = loader; }

  private nativeModule: protocol.NativeModule | null = null;
  private nativeLoadPromise: Promise<void> | null = null;

  /**
   * Lazily loads the native module via dynamic import.
   * In the Previewer, this will gracefully fail and throw a BridgeError,
   * rather than crashing at module evaluation time.
   */
  private async ensureNativeModule(): Promise<protocol.NativeModule> {
    if (this.nativeModule) {
      return this.nativeModule;
    }
    if (!this.nativeLoadPromise) {
      this.nativeLoadPromise = this.doLoadNativeModule();
    }
    const pending = this.nativeLoadPromise;
    try { await pending; }
    catch (error) {
      // All waiters share one attempt; an older rejection must not clear a newer retry.
      if (this.nativeLoadPromise === pending) { this.nativeLoadPromise = null; }
      throw this.normalize(error);
    }
    if (!this.nativeModule) { throw new BridgeError('INTERNAL_ERROR', 'NATIVE_MODULE_NOT_AVAILABLE'); }
    return this.nativeModule;
  }

  private async doLoadNativeModule(): Promise<void> {
    try {
      const native = await this.loader.load();
      if (!native || typeof native.getCapabilities !== 'function') {
        throw new BridgeError('PROTOCOL_INCOMPATIBLE', 'NATIVE_EXPORTS_MISSING');
      }
      this.nativeModule = native;
    } catch (e) {
      ErrorHandler.swallow('NativeBridge.load', e);
      if (e instanceof BridgeError) { throw e; }
      throw new BridgeError('INTERNAL_ERROR', 'NATIVE_MODULE_NOT_AVAILABLE');
    }
  }

  /** Returns whether the native module is currently available. */
  isNativeAvailable(): boolean {
    return this.nativeModule !== null;
  }

  private requireText(value: string): void {
    if (typeof value !== 'string' || value.length === 0 || value.length > 4096) {
      throw new BridgeError('INVALID_REQUEST', 'STRING_RANGE');
    }
  }

  private requireSchema(version: number): void {
    if (!Number.isInteger(version) || version !== 1) {
      throw new BridgeError('PROTOCOL_INCOMPATIBLE', 'SCHEMA_VERSION');
    }
  }

  private normalize(error: Error): BridgeError {
    if (error instanceof BridgeError) {
      return error;
    }
    if (!error || typeof error !== 'object') {
      return new BridgeError('INTERNAL_ERROR', 'NATIVE_CALL_FAILED');
    }
    const failure = error as NativeFailure;
    const code: protocol.ErrorCode = errorCodes.find((item: protocol.ErrorCode) => item === failure.code) ?? 'INTERNAL_ERROR';
    return new BridgeError(code, typeof failure.reason === 'string' ? failure.reason : 'NATIVE_CALL_FAILED');
  }

  private async call<T>(action: (native: protocol.NativeModule) => Promise<T> | T): Promise<T> {
    try {
      const native = await this.ensureNativeModule();
      return await action(native);
    } catch (error) {
      ErrorHandler.swallow('NativeBridge.call', error);
      throw this.normalize(error);
    }
  }

  async initializeSession(init: protocol.SessionInit): Promise<string> {
    this.requireSchema(init.schemaVersion);
    this.requireText(init.appSandboxRoot);
    this.requireText(init.configVersion);
    if (!/^[a-f0-9]{64}$/.test(init.configSha256)) {
      throw new BridgeError('CONFIG_INVALID', 'CONFIG_HASH');
    }
    return this.call<string>((native) => native.initializeSession(init));
  }

  async registerWorkspace(grant: protocol.WorkspaceGrant): Promise<string> {
    this.requireText(grant.sessionId);
    this.requireText(grant.taskId);
    this.requireText(grant.attemptId);
    this.requireText(grant.relativeDirectory);
    if (grant.relativeDirectory.startsWith('/') || grant.relativeDirectory.includes('..') || grant.relativeDirectory.includes('\\')) {
      throw new BridgeError('INVALID_REQUEST', 'WORKSPACE_PATH');
    }
    return this.call<string>((native) => native.registerWorkspace(grant));
  }

  async getCapabilities(request: protocol.CapabilityRequest): Promise<protocol.CapabilityMatrix> {
    this.requireSchema(request.schemaVersion);
    this.requireText(request.sessionId);
    this.requireText(request.configVersion);
    const result = await this.call<protocol.CapabilityMatrix>((native) => native.getCapabilities(request));
    if (result.schemaVersion !== request.schemaVersion || typeof result.offlineOnly !== 'boolean' || !result.offlineOnly ||
      !Array.isArray(result.routes) || !Array.isArray(result.engines) || result.configVersion !== request.configVersion) {
      throw new BridgeError('PROTOCOL_INCOMPATIBLE', 'CAPABILITY_RESPONSE');
    }
    return result;
  }

  async probeInputs(request: protocol.ProbeRequest): Promise<protocol.InputProbe[]> {
    this.requireSchema(request.schemaVersion);
    this.requireText(request.sessionId);
    this.requireText(request.workspaceRef);
    this.validateInputs(request.inputs, request.resourceBudget);
    return this.call<protocol.InputProbe[]>((native) => native.probeInputs(request));
  }

  async execute(request: protocol.ConvertRequest): Promise<protocol.ConvertResult> {
    this.requireSchema(request.schemaVersion);
    this.requireText(request.taskId);
    this.requireText(request.attemptId);
    this.requireText(request.sessionId);
    this.requireText(request.workspaceRef);
    this.requireText(request.targetFormatId);
    this.validateInputs(request.inputs, request.resourceBudget);
    if (request.plan.steps.length === 0 || request.plan.steps.length > 3 || request.intent !== request.plan.intent ||
      !/^[a-f0-9]{64}$/.test(request.plan.configSha256)) {
      throw new BridgeError('INVALID_REQUEST', 'APPROVED_PLAN');
    }
    const result = await this.call<protocol.ConvertResult>((native) => native.execute(request));
    if ((result.status !== 'success' && result.status !== 'failed' && result.status !== 'cancelled') ||
      result.taskId !== request.taskId || result.attemptId !== request.attemptId ||
      (result.status === 'success' && (result.validation.state !== 'passed' || result.outputs.length === 0))) {
      throw new BridgeError('PROTOCOL_INCOMPATIBLE', 'EXECUTE_RESPONSE');
    }
    return result;
  }

  async subscribeProgress(taskId: string, listener: (event: protocol.ProgressEvent) => void): Promise<string> {
    this.requireText(taskId);
    return this.call<string>((native) => native.subscribeProgress(taskId, listener));
  }

  async unsubscribeProgress(token: string): Promise<boolean> {
    this.requireText(token);
    return this.call<boolean>((native) => native.unsubscribeProgress(token));
  }

  async cancel(taskId: string, attemptId: string): Promise<protocol.ControlAck> {
    this.requireText(taskId);
    this.requireText(attemptId);
    return this.call<protocol.ControlAck>((native) => native.cancel(taskId, attemptId));
  }

  async pause(taskId: string, attemptId: string): Promise<protocol.ControlAck> {
    this.requireText(taskId);
    this.requireText(attemptId);
    return this.call<protocol.ControlAck>((native) => native.pause(taskId, attemptId));
  }

  async resume(taskId: string, attemptId: string): Promise<protocol.ControlAck> {
    this.requireText(taskId);
    this.requireText(attemptId);
    return this.call<protocol.ControlAck>((native) => native.resume(taskId, attemptId));
  }

  async releaseTask(taskId: string, attemptId: string): Promise<void> {
    this.requireText(taskId);
    this.requireText(attemptId);
    return this.call<void>((native) => native.releaseTask(taskId, attemptId));
  }

  async releaseArtifact(ref: string): Promise<void> {
    this.requireText(ref);
    return this.call<void>((native) => native.releaseArtifact(ref));
  }

  async shutdown(): Promise<void> {
    return this.call<void>((native) => native.shutdown());
  }

  // --- helpers (no native dependency) ---

  private validateInputs(inputs: protocol.PreparedInput[], budget: protocol.ResourceBudget): void {
    if (!Array.isArray(inputs) || inputs.length === 0 || inputs.length > 100) {
      throw new BridgeError('INVALID_REQUEST', 'INPUTS_EMPTY');
    }
    const limits: number[] = [budget.maxInputBytes, budget.maxBatchBytes, budget.maxPages, budget.maxPixels,
      budget.maxNativeBytes, budget.maxTempBytes, budget.maxThreads, budget.timeoutMs];
    if (limits.some((limit: number) => !Number.isSafeInteger(limit) || limit <= 0)) {
      throw new BridgeError('INVALID_REQUEST', 'BUDGET_RANGE');
    }
    let total: number = 0;
    for (const input of inputs) {
      this.requireText(input.fileId);
      this.requireText(input.sourceFormatId);
      this.requireText(input.relativePath);
      if (input.relativePath.includes('..') || input.relativePath.includes('\\') || input.relativePath.startsWith('/') ||
        !/^[a-f0-9]{64}$/.test(input.sha256) || !Number.isSafeInteger(input.byteSize) || input.byteSize <= 0) {
        throw new BridgeError('INVALID_REQUEST', 'INPUT_REFERENCE');
      }
      if (input.byteSize > budget.maxInputBytes) { throw new BridgeError('RESOURCE_LIMIT_EXCEEDED', 'INPUT_BYTES'); }
      total += input.byteSize;
      if (!Number.isSafeInteger(total) || total > budget.maxBatchBytes) {
        throw new BridgeError('RESOURCE_LIMIT_EXCEEDED', 'BATCH_BYTES');
      }
    }
  }
}

class PlatformNativeLoader implements NativeModuleLoader {
  async load(): Promise<protocol.NativeModule> {
    const mod = await import('libentry.so') as NativeModuleImport;
    return mod.default;
  }
}

// Compatibility entry point; all operational state belongs to an injectable instance.
export class NativeBridge {
  private static defaultService: NativeBridgePort = new NativeBridgeService();
  /** @deprecated Compatibility only. Obtain the owned instance from ServiceContainer or inject it. */
  static shared(): NativeBridgePort { return NativeBridge.defaultService; }
  static useDefault(service: NativeBridgePort): void { NativeBridge.defaultService = service; }
  static isNativeAvailable(): boolean { return NativeBridge.shared().isNativeAvailable(); }
  static initializeSession(init: protocol.SessionInit): Promise<string> { return NativeBridge.shared().initializeSession(init); }
  static registerWorkspace(grant: protocol.WorkspaceGrant): Promise<string> { return NativeBridge.shared().registerWorkspace(grant); }
  static getCapabilities(request: protocol.CapabilityRequest): Promise<protocol.CapabilityMatrix> { return NativeBridge.shared().getCapabilities(request); }
  static probeInputs(request: protocol.ProbeRequest): Promise<protocol.InputProbe[]> { return NativeBridge.shared().probeInputs(request); }
  static execute(request: protocol.ConvertRequest): Promise<protocol.ConvertResult> { return NativeBridge.shared().execute(request); }
  static subscribeProgress(taskId: string, listener: (event: protocol.ProgressEvent) => void): Promise<string> { return NativeBridge.shared().subscribeProgress(taskId, listener); }
  static unsubscribeProgress(token: string): Promise<boolean> { return NativeBridge.shared().unsubscribeProgress(token); }
  static cancel(taskId: string, attemptId: string): Promise<protocol.ControlAck> { return NativeBridge.shared().cancel(taskId, attemptId); }
  static pause(taskId: string, attemptId: string): Promise<protocol.ControlAck> { return NativeBridge.shared().pause(taskId, attemptId); }
  static resume(taskId: string, attemptId: string): Promise<protocol.ControlAck> { return NativeBridge.shared().resume(taskId, attemptId); }
  static releaseTask(taskId: string, attemptId: string): Promise<void> { return NativeBridge.shared().releaseTask(taskId, attemptId); }
  static releaseArtifact(ref: string): Promise<void> { return NativeBridge.shared().releaseArtifact(ref); }
  static shutdown(): Promise<void> { return NativeBridge.shared().shutdown(); }
}

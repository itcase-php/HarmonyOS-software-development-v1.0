import * as protocol from '../models/NativeProtocol';
import { BridgeError } from '../common/BridgeError';
import { errorCodes } from '../generated/ErrorCatalog';

interface NativeFailure {
  code?: string;
  reason?: string;
}

interface NativeModuleImport {
  default: protocol.NativeModule;
}

// This is the only application service that imports libentry.so.
// Uses dynamic import so the previewer (which cannot load native .so) can still work.
export class NativeBridge {
  private static nativeModule: protocol.NativeModule | null = null;
  private static nativeLoadPromise: Promise<void> | null = null;

  /**
   * Lazily loads the native module via dynamic import.
   * In the Previewer, this will gracefully fail and throw a BridgeError,
   * rather than crashing at module evaluation time.
   */
  private static async ensureNativeModule(): Promise<protocol.NativeModule> {
    if (NativeBridge.nativeModule) {
      return NativeBridge.nativeModule;
    }
    if (!NativeBridge.nativeLoadPromise) {
      NativeBridge.nativeLoadPromise = NativeBridge.doLoadNativeModule();
    }
    const pending = NativeBridge.nativeLoadPromise;
    try { await pending; }
    catch (error) {
      // All waiters share one attempt; an older rejection must not clear a newer retry.
      if (NativeBridge.nativeLoadPromise === pending) { NativeBridge.nativeLoadPromise = null; }
      throw NativeBridge.normalize(error as Error);
    }
    if (!NativeBridge.nativeModule) { throw new BridgeError('INTERNAL_ERROR', 'NATIVE_MODULE_NOT_AVAILABLE'); }
    return NativeBridge.nativeModule;
  }

  private static async doLoadNativeModule(): Promise<void> {
    try {
      const mod = await import('libentry.so') as NativeModuleImport;
      if (!mod.default || typeof mod.default.getCapabilities !== 'function') {
        throw new BridgeError('PROTOCOL_INCOMPATIBLE', 'NATIVE_EXPORTS_MISSING');
      }
      NativeBridge.nativeModule = mod.default;
    } catch (e) {
      if (e instanceof BridgeError) { throw e; }
      throw new BridgeError('INTERNAL_ERROR', 'NATIVE_MODULE_NOT_AVAILABLE');
    }
  }

  /** Returns whether the native module is currently available. */
  static isNativeAvailable(): boolean {
    return NativeBridge.nativeModule !== null;
  }

  private static requireText(value: string): void {
    if (typeof value !== 'string' || value.length === 0 || value.length > 4096) {
      throw new BridgeError('INVALID_REQUEST', 'STRING_RANGE');
    }
  }

  private static requireSchema(version: number): void {
    if (!Number.isInteger(version) || version !== 1) {
      throw new BridgeError('PROTOCOL_INCOMPATIBLE', 'SCHEMA_VERSION');
    }
  }

  private static normalize(error: Error): BridgeError {
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

  private static async call<T>(action: (native: protocol.NativeModule) => Promise<T> | T): Promise<T> {
    try {
      const native = await NativeBridge.ensureNativeModule();
      return await action(native);
    } catch (error) {
      throw NativeBridge.normalize(error as Error);
    }
  }

  static async initializeSession(init: protocol.SessionInit): Promise<string> {
    NativeBridge.requireSchema(init.schemaVersion);
    NativeBridge.requireText(init.appSandboxRoot);
    NativeBridge.requireText(init.configVersion);
    if (!/^[a-f0-9]{64}$/.test(init.configSha256)) {
      throw new BridgeError('CONFIG_INVALID', 'CONFIG_HASH');
    }
    return NativeBridge.call<string>((native) => native.initializeSession(init));
  }

  static async registerWorkspace(grant: protocol.WorkspaceGrant): Promise<string> {
    NativeBridge.requireText(grant.sessionId);
    NativeBridge.requireText(grant.taskId);
    NativeBridge.requireText(grant.attemptId);
    NativeBridge.requireText(grant.relativeDirectory);
    if (grant.relativeDirectory.startsWith('/') || grant.relativeDirectory.includes('..') || grant.relativeDirectory.includes('\\')) {
      throw new BridgeError('INVALID_REQUEST', 'WORKSPACE_PATH');
    }
    return NativeBridge.call<string>((native) => native.registerWorkspace(grant));
  }

  static async getCapabilities(request: protocol.CapabilityRequest): Promise<protocol.CapabilityMatrix> {
    NativeBridge.requireSchema(request.schemaVersion);
    NativeBridge.requireText(request.sessionId);
    NativeBridge.requireText(request.configVersion);
    const result = await NativeBridge.call<protocol.CapabilityMatrix>((native) => native.getCapabilities(request));
    if (result.schemaVersion !== request.schemaVersion || typeof result.offlineOnly !== 'boolean' || !result.offlineOnly ||
      !Array.isArray(result.routes) || !Array.isArray(result.engines) || result.configVersion !== request.configVersion) {
      throw new BridgeError('PROTOCOL_INCOMPATIBLE', 'CAPABILITY_RESPONSE');
    }
    return result;
  }

  static async probeInputs(request: protocol.ProbeRequest): Promise<protocol.InputProbe[]> {
    NativeBridge.requireSchema(request.schemaVersion);
    NativeBridge.requireText(request.sessionId);
    NativeBridge.requireText(request.workspaceRef);
    NativeBridge.validateInputs(request.inputs, request.resourceBudget);
    return NativeBridge.call<protocol.InputProbe[]>((native) => native.probeInputs(request));
  }

  static async execute(request: protocol.ConvertRequest): Promise<protocol.ConvertResult> {
    NativeBridge.requireSchema(request.schemaVersion);
    NativeBridge.requireText(request.taskId);
    NativeBridge.requireText(request.attemptId);
    NativeBridge.requireText(request.sessionId);
    NativeBridge.requireText(request.workspaceRef);
    NativeBridge.requireText(request.targetFormatId);
    NativeBridge.validateInputs(request.inputs, request.resourceBudget);
    if (request.plan.steps.length === 0 || request.plan.steps.length > 3 || request.intent !== request.plan.intent ||
      !/^[a-f0-9]{64}$/.test(request.plan.configSha256)) {
      throw new BridgeError('INVALID_REQUEST', 'APPROVED_PLAN');
    }
    const result = await NativeBridge.call<protocol.ConvertResult>((native) => native.execute(request));
    if ((result.status !== 'success' && result.status !== 'failed' && result.status !== 'cancelled') ||
      result.taskId !== request.taskId || result.attemptId !== request.attemptId ||
      (result.status === 'success' && (result.validation.state !== 'passed' || result.outputs.length === 0))) {
      throw new BridgeError('PROTOCOL_INCOMPATIBLE', 'EXECUTE_RESPONSE');
    }
    return result;
  }

  static async subscribeProgress(taskId: string, listener: (event: protocol.ProgressEvent) => void): Promise<string> {
    NativeBridge.requireText(taskId);
    return NativeBridge.call<string>((native) => native.subscribeProgress(taskId, listener));
  }

  static async unsubscribeProgress(token: string): Promise<boolean> {
    NativeBridge.requireText(token);
    return NativeBridge.call<boolean>((native) => native.unsubscribeProgress(token));
  }

  static async cancel(taskId: string, attemptId: string): Promise<protocol.ControlAck> {
    NativeBridge.requireText(taskId);
    NativeBridge.requireText(attemptId);
    return NativeBridge.call<protocol.ControlAck>((native) => native.cancel(taskId, attemptId));
  }

  static async pause(taskId: string, attemptId: string): Promise<protocol.ControlAck> {
    NativeBridge.requireText(taskId);
    NativeBridge.requireText(attemptId);
    return NativeBridge.call<protocol.ControlAck>((native) => native.pause(taskId, attemptId));
  }

  static async resume(taskId: string, attemptId: string): Promise<protocol.ControlAck> {
    NativeBridge.requireText(taskId);
    NativeBridge.requireText(attemptId);
    return NativeBridge.call<protocol.ControlAck>((native) => native.resume(taskId, attemptId));
  }

  static async releaseTask(taskId: string, attemptId: string): Promise<void> {
    NativeBridge.requireText(taskId);
    NativeBridge.requireText(attemptId);
    return NativeBridge.call<void>((native) => native.releaseTask(taskId, attemptId));
  }

  static async releaseArtifact(ref: string): Promise<void> {
    NativeBridge.requireText(ref);
    return NativeBridge.call<void>((native) => native.releaseArtifact(ref));
  }

  static async shutdown(): Promise<void> {
    return NativeBridge.call<void>((native) => native.shutdown());
  }

  // --- helpers (no native dependency) ---

  private static validateInputs(inputs: protocol.PreparedInput[], budget: protocol.ResourceBudget): void {
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
      NativeBridge.requireText(input.fileId);
      NativeBridge.requireText(input.sourceFormatId);
      NativeBridge.requireText(input.relativePath);
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

import { ConversionSnapshot } from '../models/ConversionSnapshot';
import { ErrorHandler } from '../common/ErrorHandler';
import { ConvertRequest, ConvertResult, ControlAck, PlanStep, ProgressEvent } from '../models/NativeProtocol';
import { registryMetadata } from '../generated/RegistryData';
import { FormatRegistry } from './FormatRegistry';
import { NativeBridge } from './NativeBridge';
import { FidelityPolicy } from '../viewmodel/FidelityPolicy';
import { BridgeError } from '../common/BridgeError';
import { FormatRegistryPort, NativeBridgePort, NativeTaskRunnerPort } from './ServiceContracts';


// Prepared inputs/session/workspace must come from a future authorized FileService.
// There is deliberately no UI switch that fabricates these handles from a filename.
export class NativeTaskRunnerService implements NativeTaskRunnerPort {
  private registry: FormatRegistryPort;
  private native: NativeBridgePort;
  constructor(registry: FormatRegistryPort = FormatRegistry.shared(), native: NativeBridgePort = NativeBridge.shared()) { this.registry = registry; this.native = native; }

  prepare(request: ConvertRequest, approved: boolean): ConvertRequest {
    if (request.schemaVersion !== 1 || [request.taskId, request.attemptId, request.sessionId, request.workspaceRef]
      .some((value: string) => typeof value !== 'string' || value.length === 0 || value.length > 4096)) {
      throw new BridgeError('INVALID_REQUEST', 'NATIVE_REQUEST_CONTEXT');
    }
    const route = this.registry.listPlannedRoutes().find((item) => item.id === request.plan.routeId);
    if (!route || request.inputs.length !== 1 || !route.from.includes(request.inputs[0].sourceFormatId) ||
      route.to !== request.targetFormatId || route.operation !== request.operation) {
      throw new BridgeError('INVALID_REQUEST', 'NATIVE_ROUTE_REQUEST');
    }
    FidelityPolicy.validate(route, { qualityMode: request.qualityMode,
      requestedIntent: request.intent, requestedTier: request.plan.minimumTier });
    if (route.requiresUserApproval && !approved) {
      throw new BridgeError('INVALID_REQUEST', 'NATIVE_APPROVAL_REQUIRED');
    }
    if (request.plan.intent !== request.intent || request.plan.configVersion !== registryMetadata.configVersion ||
      request.plan.configSha256 !== registryMetadata.matrixSha256 ||
      request.plan.policyVersion !== registryMetadata.securityPolicy.version ||
      !this.sameSteps(request.plan.steps, route.steps) ||
      request.plan.allowedDegradations.some((item: string) => !route.allowedDegradations.includes(item)) ||
      request.plan.fallbackRouteIds.some((item: string) => !route.fallbackRouteIds.includes(item))) {
      throw new BridgeError('CONFIG_INVALID', 'NATIVE_APPROVED_PLAN_MISMATCH');
    }
    // ConvertRequest is a JSON DTO (no handles/functions/classes). Deep snapshot also
    // covers optional engine options; callers cannot mutate an enqueued request.
    return ConversionSnapshot.copyConvertRequest(request);
  }

  private sameSteps(a: PlanStep[], b: PlanStep[]): boolean {
    return a.length === b.length && a.every((step: PlanStep, index: number) => {
      const expected = b[index];
      return step.stepId === expected.stepId && step.operation === expected.operation &&
        step.executorEngineId === expected.executorEngineId && step.outputFormatId === expected.outputFormatId &&
        step.engineIds.join('|') === expected.engineIds.join('|') &&
        step.inputFormatIds.join('|') === expected.inputFormatIds.join('|');
    });
  }

  async run(request: ConvertRequest, onProgress: (event: ProgressEvent) => void,
    isActive: () => boolean): Promise<ConvertResult> {
    let token: string = '';
    try {
      const capabilities = await this.native.getCapabilities({ schemaVersion: 1,
        sessionId: request.sessionId, configVersion: request.plan.configVersion });
      if (!isActive()) { throw new BridgeError('CONVERSION_CANCELLED', 'NATIVE_DISPATCH_CANCELLED'); }
      if (!this.registry.availableRoutes(capabilities).some((route) => route.id === request.plan.routeId)) {
        throw new BridgeError('ENGINE_MISSING', 'NATIVE_ROUTE_UNAVAILABLE');
      }
      if (request.plan.steps.some((step: PlanStep) => !capabilities.engines.some((engine) =>
        engine.engineId === step.executorEngineId && engine.version.length > 0 && /^[a-f0-9]{64}$/.test(engine.buildHash)))) {
        throw new BridgeError('ENGINE_MISSING', 'NATIVE_ENGINE_UNAVAILABLE');
      }
      const probes = await this.native.probeInputs({ schemaVersion: 1, sessionId: request.sessionId,
        workspaceRef: request.workspaceRef, inputs: request.inputs, resourceBudget: request.resourceBudget });
      if (!isActive()) { throw new BridgeError('CONVERSION_CANCELLED', 'NATIVE_DISPATCH_CANCELLED'); }
      if (probes.length !== request.inputs.length || probes.some((probe, index: number) =>
        probe.fileId !== request.inputs[index].fileId || probe.actualFormatId !== request.inputs[index].sourceFormatId ||
        probe.protection !== 'none' || probe.needsDeepCheck)) {
        throw new BridgeError('PERMISSION_DENIED', 'NATIVE_INPUT_NOT_VERIFIED');
      }
      token = await this.native.subscribeProgress(request.taskId, onProgress);
      if (!isActive()) { throw new BridgeError('CONVERSION_CANCELLED', 'NATIVE_DISPATCH_CANCELLED'); }
      return await this.native.execute(request);
    } finally {
      // Keep the scheduler slot until dispatch/cleanup settle, even after cancellation.
      if (token.length > 0) {
        try { await this.native.unsubscribeProgress(token); }
        catch (error) { this.logCleanup(error); }
      }
      try { await this.native.releaseTask(request.taskId, request.attemptId); }
      catch (error) { this.logCleanup(error); }
    }
  }

  async cancel(request: ConvertRequest): Promise<ControlAck> {
    return this.native.cancel(request.taskId, request.attemptId);
  }

  async releaseOutputs(result: ConvertResult): Promise<void> {
    const released: string[] = [];
    for (const output of result.outputs) {
      if (released.includes(output.internalRef)) { continue; }
      released.push(output.internalRef);
      try { await this.native.releaseArtifact(output.internalRef); }
      catch (error) { this.logCleanup(error); }
    }
  }

  private logCleanup(error: Error): void {
    const failure: BridgeError = ErrorHandler.catchBridge(error, 'NativeTaskRunner');
    console.error(JSON.stringify({ timestamp: Date.now(), module: 'NativeTaskRunner',
      code: failure.code || 'INTERNAL_ERROR', reason: failure.reason || 'NATIVE_CLEANUP_FAILED' }));
  }
}

export class NativeTaskRunner {
  private static service: NativeTaskRunnerPort | null = null;
  /** @deprecated Compatibility only. Obtain the owned instance from ServiceContainer or inject it. */
  static shared(): NativeTaskRunnerPort { return NativeTaskRunner.service ?? new NativeTaskRunnerService(); }
  static useDefault(service: NativeTaskRunnerPort): void { NativeTaskRunner.service = service; }
  static prepare(request: ConvertRequest, approved: boolean): ConvertRequest { return NativeTaskRunner.shared().prepare(request, approved); }
  static run(request: ConvertRequest, onProgress: (event: ProgressEvent) => void, isActive: () => boolean): Promise<ConvertResult> { return NativeTaskRunner.shared().run(request, onProgress, isActive); }
  static cancel(request: ConvertRequest): Promise<ControlAck> { return NativeTaskRunner.shared().cancel(request); }
  static releaseOutputs(result: ConvertResult): Promise<void> { return NativeTaskRunner.shared().releaseOutputs(result); }
}

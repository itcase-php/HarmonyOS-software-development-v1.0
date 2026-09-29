import { ConvertRequest, ConvertResult, ControlAck, PlanStep, ProgressEvent } from '../models/NativeProtocol';
import { registryMetadata } from '../generated/RegistryData';
import { FormatRegistry } from './FormatRegistry';
import { NativeBridge } from './NativeBridge';
import { FidelityPolicy } from '../viewmodel/FidelityPolicy';
import { BridgeError } from '../common/BridgeError';

// Prepared inputs/session/workspace must come from a future authorized FileService.
// There is deliberately no UI switch that fabricates these handles from a filename.
export class NativeTaskRunner {
  static prepare(request: ConvertRequest, approved: boolean): ConvertRequest {
    if (request.schemaVersion !== 1 || [request.taskId, request.attemptId, request.sessionId, request.workspaceRef]
      .some((value: string) => typeof value !== 'string' || value.length === 0 || value.length > 4096)) {
      throw new BridgeError('INVALID_REQUEST', 'NATIVE_REQUEST_CONTEXT');
    }
    const route = FormatRegistry.listPlannedRoutes().find((item) => item.id === request.plan.routeId);
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
      !NativeTaskRunner.sameSteps(request.plan.steps, route.steps) ||
      request.plan.allowedDegradations.some((item: string) => !route.allowedDegradations.includes(item)) ||
      request.plan.fallbackRouteIds.some((item: string) => !route.fallbackRouteIds.includes(item))) {
      throw new BridgeError('CONFIG_INVALID', 'NATIVE_APPROVED_PLAN_MISMATCH');
    }
    // ConvertRequest is a JSON DTO (no handles/functions/classes). Deep snapshot also
    // covers optional engine options; callers cannot mutate an enqueued request.
    return JSON.parse(JSON.stringify(request)) as ConvertRequest;
  }

  private static sameSteps(a: PlanStep[], b: PlanStep[]): boolean {
    return a.length === b.length && a.every((step: PlanStep, index: number) => {
      const expected = b[index];
      return step.stepId === expected.stepId && step.operation === expected.operation &&
        step.executorEngineId === expected.executorEngineId && step.outputFormatId === expected.outputFormatId &&
        step.engineIds.join('|') === expected.engineIds.join('|') &&
        step.inputFormatIds.join('|') === expected.inputFormatIds.join('|');
    });
  }

  static async run(request: ConvertRequest, onProgress: (event: ProgressEvent) => void,
    isActive: () => boolean): Promise<ConvertResult> {
    let token: string = '';
    try {
      const capabilities = await NativeBridge.getCapabilities({ schemaVersion: 1,
        sessionId: request.sessionId, configVersion: request.plan.configVersion });
      if (!isActive()) { throw new BridgeError('CONVERSION_CANCELLED', 'NATIVE_DISPATCH_CANCELLED'); }
      if (!FormatRegistry.availableRoutes(capabilities).some((route) => route.id === request.plan.routeId)) {
        throw new BridgeError('ENGINE_MISSING', 'NATIVE_ROUTE_UNAVAILABLE');
      }
      if (request.plan.steps.some((step: PlanStep) => !capabilities.engines.some((engine) =>
        engine.engineId === step.executorEngineId && engine.version.length > 0 && /^[a-f0-9]{64}$/.test(engine.buildHash)))) {
        throw new BridgeError('ENGINE_MISSING', 'NATIVE_ENGINE_UNAVAILABLE');
      }
      const probes = await NativeBridge.probeInputs({ schemaVersion: 1, sessionId: request.sessionId,
        workspaceRef: request.workspaceRef, inputs: request.inputs, resourceBudget: request.resourceBudget });
      if (!isActive()) { throw new BridgeError('CONVERSION_CANCELLED', 'NATIVE_DISPATCH_CANCELLED'); }
      if (probes.length !== request.inputs.length || probes.some((probe, index: number) =>
        probe.fileId !== request.inputs[index].fileId || probe.actualFormatId !== request.inputs[index].sourceFormatId ||
        probe.protection !== 'none' || probe.needsDeepCheck)) {
        throw new BridgeError('PERMISSION_DENIED', 'NATIVE_INPUT_NOT_VERIFIED');
      }
      token = await NativeBridge.subscribeProgress(request.taskId, onProgress);
      if (!isActive()) { throw new BridgeError('CONVERSION_CANCELLED', 'NATIVE_DISPATCH_CANCELLED'); }
      return await NativeBridge.execute(request);
    } finally {
      // Keep the scheduler slot until dispatch/cleanup settle, even after cancellation.
      if (token.length > 0) {
        try { await NativeBridge.unsubscribeProgress(token); }
        catch (error) { NativeTaskRunner.logCleanup(error as Error); }
      }
      try { await NativeBridge.releaseTask(request.taskId, request.attemptId); }
      catch (error) { NativeTaskRunner.logCleanup(error as Error); }
    }
  }

  static async cancel(request: ConvertRequest): Promise<ControlAck> {
    return NativeBridge.cancel(request.taskId, request.attemptId);
  }

  static async releaseOutputs(result: ConvertResult): Promise<void> {
    const released: string[] = [];
    for (const output of result.outputs) {
      if (released.includes(output.internalRef)) { continue; }
      released.push(output.internalRef);
      try { await NativeBridge.releaseArtifact(output.internalRef); }
      catch (error) { NativeTaskRunner.logCleanup(error as Error); }
    }
  }

  private static logCleanup(error: Error): void {
    const failure = error as BridgeError;
    console.error(JSON.stringify({ timestamp: Date.now(), module: 'NativeTaskRunner',
      code: failure.code || 'INTERNAL_ERROR', reason: failure.reason || 'NATIVE_CLEANUP_FAILED' }));
  }
}

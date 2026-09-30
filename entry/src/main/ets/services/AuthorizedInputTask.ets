import { ErrorHandler } from '../common/ErrorHandler';
import { FileAuthorizationPort, FormatRegistryPort, NativeBridgePort, NativeTaskRunnerPort, AuthorizedInputTaskPort } from './ServiceContracts';
import { LegacyFileAuthorization } from './FileAuthorizationService';
import { TaskRuntime } from '../models/InteractionModels';
import { SystemRuntime } from '../common/Deadline';
import { util } from '@kit.ArkTS';
import { AuthorizedFile, SessionContext } from '../models/SessionModels';
import { FidelitySelection } from '../models/InteractionModels';
import { ApprovedPlan, ConvertOptions, ConvertRequest, PreparedInput, SessionInit, WorkspaceGrant } from '../models/NativeProtocol';
import { ConversionRouteDefinition } from '../models/RegistryTypes';
import { registryMetadata } from '../generated/RegistryData';
import { BridgeError } from '../common/BridgeError';
import { FileAuthorizationService } from './FileAuthorizationService';
import { FormatRegistry } from './FormatRegistry';
import { NativeBridge } from './NativeBridge';
import { NativeTaskRunner } from './NativeTaskRunner';
import { FidelityPolicy } from '../viewmodel/FidelityPolicy';

export class AuthorizedInputTaskService implements AuthorizedInputTaskPort {
  private files: FileAuthorizationPort;
  private registry: FormatRegistryPort;
  private native: NativeBridgePort;
  private runner: NativeTaskRunnerPort;
  private runtime: TaskRuntime;
  constructor(files: FileAuthorizationPort = new LegacyFileAuthorization(), registry: FormatRegistryPort = FormatRegistry.shared(),
    native: NativeBridgePort = NativeBridge.shared(), runner: NativeTaskRunnerPort = NativeTaskRunner.shared(), runtime: TaskRuntime = new SystemRuntime()) {
    this.files = files; this.registry = registry; this.native = native; this.runner = runner; this.runtime = runtime;
  }

  async prepare(files: AuthorizedFile[], session: SessionContext, route: ConversionRouteDefinition,
    selection: FidelitySelection, approved: boolean, alive: () => boolean): Promise<ConvertRequest> {
    try {
      if (files.length !== 1) { throw new BridgeError('INVALID_REQUEST', 'NATIVE_SINGLE_FILE_REQUIRED'); }
      const current: SessionContext = this.files.getSession(session.sessionId);
      if (current.workspaceRef !== session.workspaceRef || current.inputFiles.length !== 1 ||
        JSON.stringify(current.inputFiles[0]) !== JSON.stringify(files[0])) {
        throw new BridgeError('PERMISSION_DENIED', 'AUTHORIZED_INPUT_MISMATCH');
      }
      if (!route.from.includes(files[0].detectedFormatId) || route.inputConstraints.minInputs > 1 || route.inputConstraints.maxInputs < 1) {
        throw new BridgeError('INVALID_REQUEST', 'NATIVE_ROUTE_REQUEST');
      }
      FidelityPolicy.validate(route, selection);
      if (route.requiresUserApproval && !approved) { throw new BridgeError('INVALID_REQUEST', 'NATIVE_APPROVAL_REQUIRED'); }
      if (!this.registry.isInitialized()) { throw new BridgeError('CONFIG_INVALID', 'REGISTRY_NOT_INITIALIZED'); }
      this.files.claimSession(session.sessionId);
      return await new Promise<ConvertRequest>((resolve, reject) => {
        let active: boolean = true;
        const timeout: number = this.runtime.setTimeout(() => {
          active = false; reject(new BridgeError('CONVERSION_TIMEOUT', 'NATIVE_SESSION_TIMEOUT'));
        }, 5000);
        this.prepareOwned(files[0], current, route, selection, approved, () => active && alive())
          .then((request: ConvertRequest) => { active = false; this.runtime.clearTimeout(timeout); resolve(request); })
          .catch((error: Error) => { active = false; this.runtime.clearTimeout(timeout); reject(error); });
      });
    } catch (error) {
      if (error instanceof BridgeError) { throw error; }
      throw new BridgeError('INTERNAL_ERROR', 'NATIVE_INPUT_PREPARATION_FAILED');
    }
  }

  private async prepareOwned(file: AuthorizedFile, session: SessionContext, route: ConversionRouteDefinition,
    selection: FidelitySelection, approved: boolean, alive: () => boolean): Promise<ConvertRequest> {
    let taskId: string = '';
    let attemptId: string = '';
    let grantRequested: boolean = false;
    try {
      const root: string = this.files.getWorkspaceRoot();
      const init: SessionInit = { schemaVersion: registryMetadata.schemaVersion,
        appSandboxRoot: root.substring(0, root.lastIndexOf('/')), configVersion: registryMetadata.configVersion,
        configSha256: registryMetadata.matrixSha256 };
      const nativeSession: string = await this.native.initializeSession(init);
      if (!alive()) { throw new BridgeError('CONVERSION_CANCELLED', 'NATIVE_INPUT_PREPARATION_CANCELLED'); }
      if (nativeSession.length === 0) { throw new BridgeError('PROTOCOL_INCOMPATIBLE', 'NATIVE_SESSION_HANDLE_EMPTY'); }
      taskId = util.generateRandomUUID(false);
      attemptId = util.generateRandomUUID(false);
      const grant: WorkspaceGrant = { sessionId: nativeSession, taskId: taskId, attemptId: attemptId,
        relativeDirectory: `workspace/${session.sessionId}` };
      grantRequested = true;
      const workspace: string = await this.native.registerWorkspace(grant);
      if (!alive()) { throw new BridgeError('CONVERSION_CANCELLED', 'NATIVE_INPUT_PREPARATION_CANCELLED'); }
      if (workspace.length === 0) { throw new BridgeError('PROTOCOL_INCOMPATIBLE', 'NATIVE_WORKSPACE_HANDLE_EMPTY'); }
      const input: PreparedInput = { fileId: file.fileId, sourceFormatId: file.detectedFormatId,
        relativePath: file.relativePath, byteSize: file.byteSize, sha256: file.sha256 };
      const plan: ApprovedPlan = { routeId: route.id, steps: route.steps, fallbackRouteIds: route.fallbackRouteIds,
        configVersion: registryMetadata.configVersion, configSha256: registryMetadata.matrixSha256,
        intent: selection.requestedIntent, minimumTier: selection.requestedTier,
        allowedDegradations: route.allowedDegradations, policyVersion: registryMetadata.securityPolicy.version };
      const options: ConvertOptions = {};
      const request: ConvertRequest = { schemaVersion: registryMetadata.schemaVersion, sessionId: nativeSession,
        taskId: taskId, attemptId: attemptId, workspaceRef: workspace, operation: route.operation, inputs: [input],
        targetFormatId: route.to, qualityMode: selection.qualityMode, intent: selection.requestedIntent,
        options: options, resourceBudget: registryMetadata.defaultBudget, plan: plan };
      return this.runner.prepare(request, approved);
    } catch (error) {
      if (grantRequested) {
        try { await this.native.releaseTask(taskId, attemptId); }
        catch (error) { ErrorHandler.swallow('AuthorizedInputTask.fallback', error); console.error('Native input registration cleanup failed'); }
      }
      if (error instanceof BridgeError) { throw error; }
      throw new BridgeError('INTERNAL_ERROR', 'NATIVE_INPUT_PREPARATION_FAILED');
    }
  }
}

export class AuthorizedInputTask {
  static prepare(files: AuthorizedFile[], session: SessionContext, route: ConversionRouteDefinition,
    selection: FidelitySelection, approved: boolean, alive: () => boolean): Promise<ConvertRequest> {
    return new AuthorizedInputTaskService().prepare(files, session, route, selection, approved, alive);
  }
}

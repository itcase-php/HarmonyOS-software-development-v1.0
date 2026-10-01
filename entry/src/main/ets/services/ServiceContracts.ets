import * as protocol from '../models/NativeProtocol';
import { RegistryFormat, ConversionRouteDefinition, BundledResourceReader } from '../models/RegistryTypes';
import { NativeModule, CapabilityMatrix, ConvertRequest, ConvertResult, ProgressEvent, ControlAck } from '../models/NativeProtocol';
import { AuthorizedFile, PickedFile, SessionContext } from '../models/SessionModels';
import { DemoTask, FidelitySelection } from '../models/InteractionModels';

export interface FormatRegistryPort {
  isInitialized(): boolean;
  initialize(resources: BundledResourceReader): Promise<void>;
  verifyBundledResources(resources: BundledResourceReader): Promise<void>;
  listFormats(category?: string): RegistryFormat[];
  getFormat(id: string): RegistryFormat | undefined;
  getFormatsByCategory(category: string): RegistryFormat[];
  getFormatsByIds(ids: string[]): RegistryFormat[];
  listPlannedRoutes(): ConversionRouteDefinition[];
  normalizeFormat(id: string): string;
  isBlocked(format: string): boolean;
  availableRoutes(capabilities: CapabilityMatrix): ConversionRouteDefinition[];
  catalogueVersion(): number;
}
export interface NativeBridgePort {
  isNativeAvailable(): boolean;
  initializeSession(init: protocol.SessionInit): Promise<string>;
  registerWorkspace(grant: protocol.WorkspaceGrant): Promise<string>;
  getCapabilities(request: protocol.CapabilityRequest): Promise<protocol.CapabilityMatrix>;
  probeInputs(request: protocol.ProbeRequest): Promise<protocol.InputProbe[]>;
  execute(request: protocol.ConvertRequest): Promise<protocol.ConvertResult>;
  subscribeProgress(taskId: string, listener: (event: protocol.ProgressEvent) => void): Promise<string>;
  unsubscribeProgress(token: string): Promise<boolean>;
  cancel(taskId: string, attemptId: string): Promise<protocol.ControlAck>;
  pause(taskId: string, attemptId: string): Promise<protocol.ControlAck>;
  resume(taskId: string, attemptId: string): Promise<protocol.ControlAck>;
  releaseTask(taskId: string, attemptId: string): Promise<void>;
  releaseArtifact(ref: string): Promise<void>;
  copyArtifactToFd(ref: string, destinationFd: number, sha256: string, byteSize: number): Promise<number>;
  shutdown(): Promise<void>;
}
export interface NativeModuleLoader { load(): Promise<NativeModule>; }
export interface FileAuthorizationPort {
  subscribeExpiry?(listener: (sessionId: string) => void): number;
  unsubscribeExpiry?(token: number): void;
  isAvailable(): boolean;
  getWorkspaceRoot(): string;
  getSession(id: string): SessionContext;
  claimSession(id: string): void;
  pickDocuments(maxCount: number): Promise<PickedFile[]>;
  createSession(): Promise<SessionContext>;
  copyToSandbox(file: PickedFile, id: string): Promise<AuthorizedFile>;
  removeFile(id: string, fileId: string): Promise<void>;
  destroySession(id: string): Promise<void>;
  destroyAllSessions(): Promise<void>;
}
export interface NativeTaskRunnerPort {
  prepare(request: ConvertRequest, approved: boolean): ConvertRequest;
  run(request: ConvertRequest, onProgress: (event: ProgressEvent) => void, active: () => boolean): Promise<ConvertResult>;
  cancel(request: ConvertRequest): Promise<ControlAck>;
  releaseOutputs(result: ConvertResult): Promise<void>;
}
export interface AuthorizedInputTaskPort {
  prepare(files: AuthorizedFile[], session: SessionContext, route: ConversionRouteDefinition,
    selection: FidelitySelection, approved: boolean, alive: () => boolean): Promise<ConvertRequest>;
}
export interface TaskStorePort {
  snapshot(): DemoTask[];
  subscribe(callback: (tasks: DemoTask[]) => void): number;
  unsubscribe(token: number): void;
  enqueue(name: string, source: string, target: string, route: string, approved?: boolean, fidelity?: FidelitySelection): DemoTask;
  submitTask(name: string, source: string, target: string, route: string, approved?: boolean,
    fidelity?: FidelitySelection, files?: AuthorizedFile[], session?: SessionContext): Promise<DemoTask>;
  pause(id: string): boolean;
  resume(id: string): boolean;
  cancel(id: string): boolean;
  clearFinished(): number;
}

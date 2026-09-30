import { common } from '@kit.AbilityKit';
import { FileAuthorizationPlatform, PickedFile } from '../models/SessionModels';
import { TaskRuntime } from '../models/InteractionModels';
import { SystemRuntime, withDeadline } from '../common/Deadline';
import { BridgeError } from '../common/BridgeError';
import { FormatRegistryService, FormatRegistry } from './FormatRegistry';
import { NativeBridgeService, NativeBridge } from './NativeBridge';
import { FileAuthorizationService, FileAuthorizationManager } from './FileAuthorizationService';
import { HarmonyFilePlatform } from './HarmonyFilePlatform';
import { FormatRegistryPort, NativeBridgePort } from './ServiceContracts';
import { TaskDependencies } from './TaskDependencies';
import { TaskStore } from '../viewmodel/TaskStore';
import { NativeTaskRunner } from './NativeTaskRunner';
import { ConversionPlanner } from '../viewmodel/ConversionPlanner';

class PreviewFilePlatform implements FileAuthorizationPlatform {
  isAvailable(): boolean { return false; }
  cacheDir(): string { return '/preview/cache'; }
  uuid(): string { return ''; }
  now(): number { return Date.now(); }
  async pick(maxCount: number): Promise<PickedFile[]> { return []; }
  async exists(path: string): Promise<boolean> { return false; }
  async mkdir(path: string): Promise<void> { throw new BridgeError('UNSUPPORTED_FEATURE', 'FILE_PICKER_UNAVAILABLE'); }
  async freeBytes(path: string): Promise<number> { return 0; }
  async copyUri(uri: string, target: string, max: number, active: () => boolean): Promise<number> {
    throw new BridgeError('UNSUPPORTED_FEATURE', 'FILE_PICKER_UNAVAILABLE');
  }
  async sha256(path: string): Promise<string> { return ''; }
  async unlink(path: string): Promise<void> {}
  async removeDirectory(path: string): Promise<void> {}
}

// One app scope owns every mutable service; static methods only bind legacy page callers.
export class ServiceContainer {
  private static currentScope: ServiceContainer | null = null;
  readonly registry: FormatRegistryPort;
  readonly native: NativeBridgePort;
  readonly files: FileAuthorizationManager;
  readonly tasks: TaskStore;
  readonly dependencies: TaskDependencies;
  private runtime: TaskRuntime;
  private closing: Promise<void> | null = null;
  constructor(registry: FormatRegistryPort = new FormatRegistryService(), native: NativeBridgePort = new NativeBridgeService(),
    platform: FileAuthorizationPlatform = new PreviewFilePlatform(), runtime: TaskRuntime = new SystemRuntime(), ttlMs: number = 30 * 60 * 1000) {
    this.registry = registry; this.native = native; this.runtime = runtime;
    this.files = new FileAuthorizationService(platform, registry, runtime, ttlMs);
    this.dependencies = new TaskDependencies(registry, native, this.files, runtime);
    this.tasks = new TaskStore(runtime, this.dependencies);
  }
  static current(): ServiceContainer {
    if (!ServiceContainer.currentScope) { ServiceContainer.currentScope = new ServiceContainer(); }
    return ServiceContainer.currentScope;
  }
  static initialize(context: common.UIAbilityContext): ServiceContainer {
    const registry: FormatRegistryService = new FormatRegistryService();
    const scope: ServiceContainer = new ServiceContainer(registry, new NativeBridgeService(), new HarmonyFilePlatform(context, registry));
    ServiceContainer.currentScope = scope;
    FormatRegistry.useDefault(scope.registry); NativeBridge.useDefault(scope.native);
    FileAuthorizationService.useDefault(scope.files); TaskStore.useDefault(scope.tasks);
    NativeTaskRunner.useDefault(scope.dependencies.runner); ConversionPlanner.useDefault(scope.dependencies.planner);
    return scope;
  }
  shutdown(): Promise<void> {
    if (!this.closing) { this.closing = this.closeOwned(); }
    return withDeadline(this.closing, 5000,
      () => new BridgeError('CONVERSION_TIMEOUT', 'SERVICE_SHUTDOWN_TIMEOUT'), this.runtime);
  }
  private async closeOwned(): Promise<void> {
    this.tasks.shutdown();
    try { await this.native.shutdown(); }
    finally { await this.tasks.releaseAuthorizedSessions(() => this.files.destroyAllSessions()); }
  }
}

import { FormatRegistryPort, NativeBridgePort, FileAuthorizationPort, NativeTaskRunnerPort,
  AuthorizedInputTaskPort } from './ServiceContracts';
import { FormatRegistry } from './FormatRegistry';
import { NativeBridge } from './NativeBridge';
import { LegacyFileAuthorization } from './FileAuthorizationService';
import { NativeTaskRunnerService } from './NativeTaskRunner';
import { AuthorizedInputTaskService } from './AuthorizedInputTask';
import { ConversionPlannerService } from '../viewmodel/ConversionPlanner';
import { TaskRuntime } from '../models/InteractionModels';
import { SystemRuntime } from '../common/Deadline';

export interface TaskStoreDependencies {
  registry: FormatRegistryPort;
  native: NativeBridgePort;
  files: FileAuthorizationPort;
  runner: NativeTaskRunnerPort;
  authorized: AuthorizedInputTaskPort;
  planner: ConversionPlannerService;
}

export class TaskDependencies implements TaskStoreDependencies {
  registry: FormatRegistryPort;
  native: NativeBridgePort;
  files: FileAuthorizationPort;
  runner: NativeTaskRunnerPort;
  authorized: AuthorizedInputTaskPort;
  planner: ConversionPlannerService;
  constructor(registry: FormatRegistryPort = FormatRegistry.shared(), native: NativeBridgePort = NativeBridge.shared(),
    files: FileAuthorizationPort = new LegacyFileAuthorization(), runtime: TaskRuntime = new SystemRuntime()) {
    this.registry = registry; this.native = native; this.files = files;
    this.runner = new NativeTaskRunnerService(registry, native);
    this.authorized = new AuthorizedInputTaskService(files, registry, native, this.runner, runtime);
    this.planner = new ConversionPlannerService(registry);
  }
}

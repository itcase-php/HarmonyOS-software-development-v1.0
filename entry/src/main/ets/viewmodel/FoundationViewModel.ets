import { resourceManager } from '@kit.LocalizationKit';
import { registryMetadata } from '../generated/RegistryData';
import { CapabilityMatrix, CapabilityRequest } from '../models/NativeProtocol';
import { FormatRegistry } from '../services/FormatRegistry';
import { NativeBridge } from '../services/NativeBridge';
import { BridgeError } from '../common/BridgeError';
import { RawfileResources } from '../services/RawfileResources';
import { FormatRegistryPort, NativeBridgePort } from '../services/ServiceContracts';
import { TaskRuntime } from '../models/InteractionModels';
import { SystemRuntime, withDeadline } from '../common/Deadline';
import { ErrorHandler } from '../common/ErrorHandler';

export class FoundationViewModel {
  private registry: FormatRegistryPort;
  private native: NativeBridgePort;
  private runtime: TaskRuntime;
  constructor(registry: FormatRegistryPort = FormatRegistry.shared(), native: NativeBridgePort = NativeBridge.shared(),
    runtime: TaskRuntime = new SystemRuntime()) {
    this.registry = registry; this.native = native; this.runtime = runtime;
  }
  async inspect(resources?: resourceManager.ResourceManager): Promise<CapabilityMatrix> {
    // Previewer implementations may leave unsupported platform promises pending.
    // Keep the capability action recoverable without blocking the other dashboard actions.
    return withDeadline(this.inspectNative(resources), 5000,
      () => new BridgeError('CONVERSION_TIMEOUT', 'CAPABILITY_CHECK_TIMEOUT'), this.runtime);
  }

  private async inspectNative(resources?: resourceManager.ResourceManager): Promise<CapabilityMatrix> {
    if (resources) {
      // Native 检测前严格校验 rawfile；失败不影响完整目录及演示规划。
      await this.registry.initialize(new RawfileResources(resources));
    }
    const request: CapabilityRequest = {
      schemaVersion: registryMetadata.schemaVersion,
      sessionId: 'capability-only-bootstrap',
      configVersion: registryMetadata.configVersion
    };
    try {
      return await this.native.getCapabilities(request);
    } catch (error) {
      ErrorHandler.swallow('FoundationViewModel.inspect', error);
      // 预览器/模拟器模式下 NativeBridge 不可用，返回保底能力矩阵
      // 让上层能够正常展示演示数据而不阻塞用户操作
      return {
        schemaVersion: registryMetadata.schemaVersion,
        offlineOnly: true,
        abi: 'previewer-demo',
        configVersion: registryMetadata.configVersion,
        engines: [],
        routes: []
      };
    }
  }
}

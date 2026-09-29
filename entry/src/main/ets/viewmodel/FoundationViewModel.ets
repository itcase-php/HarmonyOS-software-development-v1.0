import { resourceManager } from '@kit.LocalizationKit';
import { registryMetadata } from '../generated/RegistryData';
import { CapabilityMatrix, CapabilityRequest } from '../models/NativeProtocol';
import { FormatRegistry } from '../services/FormatRegistry';
import { NativeBridge } from '../services/NativeBridge';
import { BridgeError } from '../common/BridgeError';
import { RawfileResources } from '../services/RawfileResources';

export class FoundationViewModel {
  async inspect(resources?: resourceManager.ResourceManager): Promise<CapabilityMatrix> {
    // Previewer implementations may leave unsupported platform promises pending.
    // Keep the capability action recoverable without blocking the other dashboard actions.
    return new Promise<CapabilityMatrix>((resolve, reject) => {
      const timeout = setTimeout(() => {
        reject(new BridgeError('CONVERSION_TIMEOUT', 'CAPABILITY_CHECK_TIMEOUT'));
      }, 5000);
      this.inspectNative(resources).then((capabilities: CapabilityMatrix) => {
        clearTimeout(timeout); resolve(capabilities);
      }).catch((error: Error) => {
        clearTimeout(timeout); reject(error);
      });
    });
  }

  private async inspectNative(resources?: resourceManager.ResourceManager): Promise<CapabilityMatrix> {
    if (resources) {
      // Native 检测前严格校验 rawfile；失败不影响完整目录及演示规划。
      await FormatRegistry.initialize(new RawfileResources(resources));
    }
    const request: CapabilityRequest = {
      schemaVersion: registryMetadata.schemaVersion,
      sessionId: 'capability-only-bootstrap',
      configVersion: registryMetadata.configVersion
    };
    try {
      return await NativeBridge.getCapabilities(request);
    } catch (_error) {
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

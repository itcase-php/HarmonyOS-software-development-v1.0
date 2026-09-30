import { ErrorHandler } from '../common/ErrorHandler';
import { resourceManager } from '@kit.LocalizationKit';
import { BundledResourceReader } from '../models/RegistryTypes';
import { BridgeError } from '../common/BridgeError';

// Explicit adapter: ArkTS does not permit structural assignment of SDK interfaces.
export class RawfileResources implements BundledResourceReader {
  private resources: resourceManager.ResourceManager;
  constructor(resources: resourceManager.ResourceManager) { this.resources = resources; }
  async getRawFileContent(path: string): Promise<Uint8Array> {
    try { return await this.resources.getRawFileContent(path); }
    catch (error) { ErrorHandler.swallow('RawfileResources.fallback', error); throw new BridgeError('CONFIG_INVALID', 'BUNDLED_RESOURCE_READ_FAILED'); }
  }
}

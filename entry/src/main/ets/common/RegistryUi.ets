import { FormatRegistry } from '../services/FormatRegistry';
import { RawfileResources } from '../services/RawfileResources';
import { BridgeError } from './BridgeError';

// Standalone pages require application resources; missing context is a recoverable error.
export class RegistryUi {
  static async ensure(context: UIContext): Promise<void> {
    if (FormatRegistry.isInitialized()) { return; }
    const resources = context.getHostContext()?.resourceManager;
    if (!resources) { throw new BridgeError('CONFIG_INVALID', 'REGISTRY_CONTEXT_UNAVAILABLE'); }
    await FormatRegistry.initialize(new RawfileResources(resources));
  }
}

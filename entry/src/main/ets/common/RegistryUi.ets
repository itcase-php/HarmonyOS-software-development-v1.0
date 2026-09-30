import { FormatRegistry } from '../services/FormatRegistry';
import { RawfileResources } from '../services/RawfileResources';
import { ErrorHandler } from './ErrorHandler';

// The complete generated catalogue is always usable for browsing and demo planning.
// Resource verification remains strict in FormatRegistry.initialize/verifyBundledResources.
export class RegistryUi {
  static async ensure(context: UIContext): Promise<void> {
    if (FormatRegistry.isInitialized()) { return; }
    try {
      const resources = context.getHostContext()?.resourceManager;
      if (resources) { await FormatRegistry.initialize(new RawfileResources(resources)); }
    } catch (error) {
      ErrorHandler.swallow('RegistryUi.ensure', error);
      // Previewer may lack resources or SDK hashing. Keep all generated entries;
      // failed verification cannot publish a snapshot or enable Native routes.
    }
  }
}

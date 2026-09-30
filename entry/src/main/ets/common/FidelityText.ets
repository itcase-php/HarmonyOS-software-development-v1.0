import { ErrorHandler } from './ErrorHandler';
import { FidelityTier, Intent, QualityMode } from '../models/NativeProtocol';

// Resource lookup stays in the UI layer; FidelityPolicy remains SDK-independent.
export class FidelityText {
  static read(context: UIContext, resource: Resource, args: (string | number)[] = []): string {
    const manager = context.getHostContext()?.resourceManager;
    try { return manager ? manager.getStringSync(resource.id, ...args) : ''; }
    catch (error) { ErrorHandler.swallow('FidelityText.fallback', error);
      ErrorHandler.catchBridge(error, 'FidelityText.resource', 'INTERNAL_ERROR', 'STRING_RESOURCE_LOOKUP_FAILED');
      return '';
    }
  }
  static tier(context: UIContext, tier: FidelityTier): string {
    return FidelityText.read(context, tier === 'extreme' ? $r('app.string.fidelity_extreme') :
      tier === 'standard' ? $r('app.string.fidelity_standard') : $r('app.string.fidelity_compatible'));
  }
  static intent(context: UIContext, intent: Intent): string {
    return FidelityText.read(context, intent === 'layout_preserved' ? $r('app.string.intent_layout') :
      intent === 'structured_rebuild' ? $r('app.string.intent_structure') : $r('app.string.intent_content'));
  }
  static quality(context: UIContext, mode: QualityMode): string {
    return FidelityText.read(context, mode === 'fast' ? $r('app.string.quality_fast') :
      mode === 'balanced' ? $r('app.string.quality_balanced') : $r('app.string.quality_high'));
  }
}

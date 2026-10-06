import { FidelityTier, QualityMode } from '../models/NativeProtocol';
import { FidelitySelection } from '../models/InteractionModels';
import { ConversionRouteDefinition } from '../models/RegistryTypes';
import { BridgeError } from '../common/BridgeError';

export class FidelityPolicy {
  static tierRank(tier: FidelityTier): number {
    switch (tier) { case 'extreme': return 3; case 'standard': return 2; case 'compatible': return 1;
      default: throw new BridgeError('INVALID_REQUEST', 'FIDELITY_OPTIONS_INVALID'); }
  }
  static durationMs(mode: QualityMode): number {
    switch (mode) { case 'fast': return 2000; case 'balanced': return 3500; case 'high_fidelity': return 6000;
      default: throw new BridgeError('INVALID_REQUEST', 'FIDELITY_OPTIONS_INVALID'); }
  }
  static isQualityMode(value: string): boolean {
    return value === 'fast' || value === 'balanced' || value === 'high_fidelity';
  }
  static validate(route: ConversionRouteDefinition, selection: FidelitySelection): void {
    if (!['extreme', 'standard', 'compatible'].includes(route.fidelityTier) ||
      !['layout_preserved', 'structured_rebuild', 'content_only'].includes(route.intent)) {
      throw new BridgeError('CONFIG_INVALID', 'FIDELITY_ROUTE_INVALID');
    }
    if (!FidelityPolicy.isQualityMode(selection.qualityMode) ||
      !['layout_preserved', 'structured_rebuild', 'content_only'].includes(selection.requestedIntent) ||
      !['extreme', 'standard', 'compatible'].includes(selection.requestedTier)) {
      throw new BridgeError('INVALID_REQUEST', 'FIDELITY_OPTIONS_INVALID');
    }
    if (selection.requestedIntent !== route.intent) {
      throw new BridgeError('UNSUPPORTED_FEATURE', 'FIDELITY_INTENT_MISMATCH');
    }
    if (FidelityPolicy.tierRank(route.fidelityTier) < FidelityPolicy.tierRank(selection.requestedTier)) {
      throw new BridgeError('UNSUPPORTED_FEATURE', 'FIDELITY_TIER_UNAVAILABLE');
    }
  }
}

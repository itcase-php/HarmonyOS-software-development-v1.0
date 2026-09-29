import { FidelityTier, Intent, QualityMode } from '../models/NativeProtocol';
import { FidelitySelection } from '../models/InteractionModels';
import { ConversionRouteDefinition } from '../models/RegistryTypes';
import { BridgeError } from '../common/BridgeError';

export class FidelityPolicy {
  static tierRank(tier: FidelityTier): number {
    switch (tier) { case 'extreme': return 3; case 'standard': return 2; case 'compatible': return 1; }
  }
  static tierLabel(tier: FidelityTier): string {
    switch (tier) { case 'extreme': return '极致保真'; case 'standard': return '标准保真'; case 'compatible': return '兼容保真'; }
  }
  static intentLabel(intent: Intent): string {
    switch (intent) {
      case 'layout_preserved': return '保留布局';
      case 'structured_rebuild': return '结构化重建';
      case 'content_only': return '仅提取内容';
    }
  }
  static qualityLabel(mode: QualityMode): string {
    switch (mode) { case 'fast': return '快速'; case 'balanced': return '均衡'; case 'high_fidelity': return '高保真'; }
  }
  static durationMs(mode: QualityMode): number {
    switch (mode) { case 'fast': return 2000; case 'balanced': return 3500; case 'high_fidelity': return 6000; }
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

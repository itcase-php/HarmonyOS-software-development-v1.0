import { describe, it, expect, beforeAll } from '@ohos/hypium';
import { FidelityPolicy } from '../../../main/ets/viewmodel/FidelityPolicy';
import { FidelitySelection } from '../../../main/ets/models/InteractionModels';
import { FidelityTier } from '../../../main/ets/models/NativeProtocol';
import { BridgeError } from '../../../main/ets/common/BridgeError';
import { initializeRegistry, testRoute } from './CoreFixtures';

function invalidSelection(json: string): FidelitySelection { return JSON.parse(json) as FidelitySelection; }
function failure(action: () => void): string {
  try { action(); } catch (error) {
    expect(error instanceof BridgeError).assertTrue();
    return (error as BridgeError).reason;
  }
  return '';
}

export default function fidelityPolicyTest() {
  describe('FidelityPolicy', () => {
    beforeAll(initializeRegistry);
    it('orders extreme standard and compatible tiers', 0, () => {
      expect(FidelityPolicy.tierRank('extreme')).assertEqual(3);
      expect(FidelityPolicy.tierRank('standard')).assertEqual(2);
      expect(FidelityPolicy.tierRank('compatible')).assertEqual(1);
    });
    it('uses the three documented demo durations', 0, () => {
      expect(FidelityPolicy.durationMs('fast')).assertEqual(2000);
      expect(FidelityPolicy.durationMs('balanced')).assertEqual(3500);
      expect(FidelityPolicy.durationMs('high_fidelity')).assertEqual(6000);
    });
    it('accepts matching intent and a minimum at or below the planned tier', 0, () => {
      FidelityPolicy.validate(testRoute(), { qualityMode: 'balanced', requestedIntent: 'layout_preserved', requestedTier: 'standard' });
      FidelityPolicy.validate(testRoute(), { qualityMode: 'fast', requestedIntent: 'layout_preserved', requestedTier: 'compatible' });
    });
    it('rejects an invalid quality value from a boundary', 0, () => {
      expect(failure(() => FidelityPolicy.validate(testRoute(), invalidSelection(
        '{"qualityMode":"turbo","requestedIntent":"layout_preserved","requestedTier":"standard"}')))).assertEqual('FIDELITY_OPTIONS_INVALID');
    });
    it('rejects an invalid requested tier', 0, () => {
      expect(failure(() => FidelityPolicy.validate(testRoute(), invalidSelection(
        '{"qualityMode":"balanced","requestedIntent":"layout_preserved","requestedTier":"ultra"}')))).assertEqual('FIDELITY_OPTIONS_INVALID');
    });
    it('rejects a mismatched or unknown intent', 0, () => {
      expect(failure(() => FidelityPolicy.validate(testRoute(), { qualityMode: 'balanced', requestedIntent: 'content_only', requestedTier: 'standard' }))).assertEqual('FIDELITY_INTENT_MISMATCH');
      expect(failure(() => FidelityPolicy.validate(testRoute(), invalidSelection(
        '{"qualityMode":"balanced","requestedIntent":"unknown","requestedTier":"standard"}')))).assertEqual('FIDELITY_OPTIONS_INVALID');
    });
    it('rejects a requested tier above the route even in high fidelity mode', 0, () => {
      expect(failure(() => FidelityPolicy.validate(testRoute(), { qualityMode: 'high_fidelity', requestedIntent: 'layout_preserved', requestedTier: 'extreme' }))).assertEqual('FIDELITY_TIER_UNAVAILABLE');
    });
    it('accepts empty degradation arrays without changing them', 0, () => {
      const route = testRoute(); route.allowedDegradations = [];
      FidelityPolicy.validate(route, { qualityMode: 'balanced', requestedIntent: route.intent, requestedTier: route.fidelityTier });
      expect(route.allowedDegradations.length).assertEqual(0);
    });
    it('rejects an invalid planned tier rather than comparing undefined ranks', 0, () => {
      const route = testRoute(); route.fidelityTier = 'invalid' as FidelityTier;
      expect(failure(() => FidelityPolicy.validate(route, { qualityMode: 'balanced', requestedIntent: route.intent, requestedTier: 'compatible' }))).assertEqual('FIDELITY_ROUTE_INVALID');
    });
  });
}

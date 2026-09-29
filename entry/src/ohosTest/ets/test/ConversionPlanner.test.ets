import { describe, it, expect, beforeAll } from '@ohos/hypium';
import { ConversionPlanner } from '../../../main/ets/viewmodel/ConversionPlanner';
import { FormatRegistry } from '../../../main/ets/services/FormatRegistry';
import { ConversionRouteDefinition } from '../../../main/ets/models/RegistryTypes';
import { initializeRegistry } from './CoreFixtures';

export default function conversionPlannerTest() {
  describe('ConversionPlanner', () => {
    beforeAll(initializeRegistry);
    it('returns exactly the single-input planned targets for PDF', 0, () => {
      const routes = FormatRegistry.listPlannedRoutes().filter((route: ConversionRouteDefinition) =>
        route.from.includes('pdf') && route.status !== 'unavailable' && route.inputConstraints.minInputs <= 1 && route.inputConstraints.maxInputs >= 1);
      const expected = FormatRegistry.listFormats().filter((format) => routes.some((route) => route.to === format.id));
      expect(ConversionPlanner.targets('pdf').map((item) => item.id).join(',')).assertEqual(expected.map((item) => item.id).join(','));
      expect(expected.length > 0).assertTrue();
    });
    it('normalizes dotted uppercase IDs extensions and migration aliases', 0, () => {
      expect(ConversionPlanner.targets('.PDF').map((item) => item.id).join(',')).assertEqual(ConversionPlanner.targets('pdf').map((item) => item.id).join(','));
      expect(ConversionPlanner.targets('jpg').map((item) => item.id).join(',')).assertEqual(ConversionPlanner.targets('jpeg').map((item) => item.id).join(','));
      for (const alias of ['.JPG', 'jpg']) { expect(FormatRegistry.normalizeFormat(alias)).assertEqual('jpeg'); }
    });
    it('returns no targets for unknown or protected extensions', 0, () => {
      for (const id of ['unknown-test-format', 'ncm', '.QMC']) { expect(ConversionPlanner.targets(id).length).assertEqual(0); }
    });
    it('returns matching routes and no routes for unsupported pairs', 0, () => {
      expect(ConversionPlanner.routes('pdf', 'png')[0]?.id).assertEqual('pdf-png');
      expect(ConversionPlanner.routes('pdf', 'mp3').length).assertEqual(0);
    });
    it('keeps best route ordering within the requested intent', 0, () => {
      const candidates = ConversionPlanner.routes('pdf', 'pptx', 'balanced', 'structured_rebuild', 'compatible');
      expect(ConversionPlanner.bestRoute('pdf', 'pptx', 'structured_rebuild')?.id).assertEqual(candidates[0]?.id);
      for (let index = 1; index < candidates.length; index++) {
        if (candidates[index - 1].pathMode === candidates[index].pathMode) {
          expect(candidates[index - 1].priority <= candidates[index].priority).assertTrue();
        }
      }
    });
    it('does not lower the minimum tier or change intent to find a route', 0, () => {
      expect(ConversionPlanner.bestRoute('pdf', 'png', 'layout_preserved', 'high_fidelity', 'extreme')).assertUndefined();
      expect(ConversionPlanner.bestRoute('pdf', 'png', 'content_only')).assertUndefined();
    });
  });
}

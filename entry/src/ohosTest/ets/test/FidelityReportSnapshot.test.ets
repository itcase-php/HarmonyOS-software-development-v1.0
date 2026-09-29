import { describe, it, expect } from '@ohos/hypium';
import { FidelityReportSnapshot } from '../../../main/ets/models/FidelityReportSnapshot';
import { DemoFidelityReport } from '../../../main/ets/viewmodel/DemoFidelityReport';
import { testTask } from './CoreFixtures';

export default function fidelityReportSnapshotTest() {
  describe('FidelityReportSnapshot', () => {
    it('isolates metric values and nested evidence arrays', 0, () => {
      const original = DemoFidelityReport.create(testTask(), 'standard', []);
      const copy = FidelityReportSnapshot.copy(original);
      copy.metrics[0].value = 0; copy.metrics[0].evidenceRefs.push('changed');
      expect(original.metrics[0].value).assertEqual(0.90); expect(original.metrics[0].evidenceRefs.length).assertEqual(0);
    });
    it('isolates degradations fonts limitations and report evidence', 0, () => {
      const original = DemoFidelityReport.create(testTask(), 'standard', ['fixture-loss']);
      original.fontSubstitutions.push('fixture-font'); original.evidenceRefs.push('fixture-evidence');
      const copy = FidelityReportSnapshot.copy(original);
      copy.degradations[0] = 'changed'; copy.fontSubstitutions[0] = 'changed';
      copy.unsupportedFeatures[0] = 'changed'; copy.evidenceRefs[0] = 'changed';
      expect(original.degradations[0]).assertEqual('fixture-loss'); expect(original.fontSubstitutions[0]).assertEqual('fixture-font');
      expect(original.evidenceRefs[0]).assertEqual('fixture-evidence'); expect(original.unsupportedFeatures[0] !== 'changed').assertTrue();
    });
    it('copies empty containers and optional page counts', 0, () => {
      const original = DemoFidelityReport.create(testTask(), 'standard', []);
      original.metrics = []; original.fontSubstitutions = []; original.unsupportedFeatures = []; original.evidenceRefs = [];
      original.sourcePageCount = 2; original.outputPageCount = 3;
      const copy = FidelityReportSnapshot.copy(original);
      expect(copy.metrics.length).assertEqual(0); expect(copy.degradations.length).assertEqual(0);
      expect(copy.sourcePageCount).assertEqual(2); expect(copy.outputPageCount).assertEqual(3);
    });
  });
}

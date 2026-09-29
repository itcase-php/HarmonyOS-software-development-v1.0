import { describe, it, expect } from '@ohos/hypium';
import { DemoFidelityReport } from '../../../main/ets/viewmodel/DemoFidelityReport';
import { BridgeError } from '../../../main/ets/common/BridgeError';
import { testTask } from './CoreFixtures';

export default function demoFidelityReportTest() {
  describe('DemoFidelityReport', () => {
    it('creates the documented report structure without measured metrics', 0, () => {
      const report = DemoFidelityReport.create(testTask(), 'standard', []);
      expect(report.schemaVersion).assertEqual(1); expect(Array.isArray(report.metrics)).assertTrue();
      expect(Array.isArray(report.fontSubstitutions)).assertTrue(); expect(Array.isArray(report.degradations)).assertTrue();
      expect(Array.isArray(report.unsupportedFeatures)).assertTrue(); expect(report.requiresManualReview).assertTrue();
      expect(report.metrics.some((metric) => metric.state === 'measured')).assertFalse();
    });
    it('makes the layout metric inapplicable for content-only intent', 0, () => {
      const task = testTask(); task.intent = 'content_only'; task.requestedIntent = task.intent;
      const report = DemoFidelityReport.create(task, 'compatible', []);
      expect(report.metrics[0].state).assertEqual('not_applicable'); expect(report.metrics[0].value).assertUndefined();
    });
    it('marks the layout metric estimated for layout-preserved intent', 0, () => {
      expect(DemoFidelityReport.create(testTask(), 'standard', []).metrics[0].state).assertEqual('estimated');
    });
    it('uses 0.98 0.90 and 0.76 only as tier-specific demo examples', 0, () => {
      expect(DemoFidelityReport.create(testTask(), 'extreme', []).metrics[1].value).assertEqual(0.98);
      expect(DemoFidelityReport.create(testTask(), 'standard', []).metrics[1].value).assertEqual(0.90);
      expect(DemoFidelityReport.create(testTask(), 'compatible', []).metrics[1].value).assertEqual(0.76);
    });
    it('copies degradation input and preserves selection metadata', 0, () => {
      const task = testTask(); const losses: string[] = ['fixture-loss'];
      const report = DemoFidelityReport.create(task, 'standard', losses); losses[0] = 'changed';
      expect(report.degradations[0]).assertEqual('fixture-loss'); expect(report.requestedTier).assertEqual(task.requestedTier);
      expect(report.intent).assertEqual(task.requestedIntent);
    });
    it('rejects native tasks instead of inventing real metrics', 0, () => {
      const task = testTask(); task.mode = 'native'; let reason = '';
      try { DemoFidelityReport.create(task, 'extreme', []); }
      catch (error) { expect(error instanceof BridgeError).assertTrue(); reason = (error as BridgeError).reason; }
      expect(reason).assertEqual('DEMO_REPORT_NATIVE_TASK');
    });
  });
}

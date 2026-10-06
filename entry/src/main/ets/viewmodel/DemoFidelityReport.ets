import { FidelityReport, FidelityTier, Metric } from '../models/NativeProtocol';
import { DemoTask } from '../models/InteractionModels';
import { BridgeError } from '../common/BridgeError';
import { FidelityReportSnapshot } from '../models/FidelityReportSnapshot';

// Illustrative data only. No user document is parsed and no metric is measured.
export class DemoFidelityReport {
  static create(task: DemoTask, plannedTier: FidelityTier, allowedDegradations: string[]): FidelityReport {
    if (task.mode !== 'demo') { throw new BridgeError('INVALID_REQUEST', 'DEMO_REPORT_NATIVE_TASK'); }
    const sample = plannedTier === 'extreme' ? 0.98 : plannedTier === 'standard' ? 0.90 : 0.76;
    const metrics: Metric[] = [
      { name: 'layout_similarity_demo', state: task.intent === 'content_only' ? 'not_applicable' : 'estimated',
        value: task.intent === 'content_only' ? undefined : sample, unit: 'ratio',
        algorithmVersion: 'demo-example-v1', evidenceRefs: [] },
      { name: 'content_coverage_demo', state: 'estimated', value: sample, unit: 'ratio',
        algorithmVersion: 'demo-example-v1', evidenceRefs: [] },
      { name: 'page_count', state: 'unavailable', unit: 'pages',
        algorithmVersion: 'not-measured', evidenceRefs: [] }
    ];
    return { schemaVersion: 1, intent: task.requestedIntent, requestedTier: task.requestedTier,
      achievedTier: plannedTier, metrics: metrics, fontSubstitutions: [],
      unsupportedFeatures: ['report_demo_limitation'],
      degradations: allowedDegradations.slice(), requiresManualReview: true,
      detectorVersion: 'demo-fidelity-v1', evidenceRefs: [] };
  }

  static copy(report: FidelityReport): FidelityReport {
    return FidelityReportSnapshot.copy(report);
  }
}

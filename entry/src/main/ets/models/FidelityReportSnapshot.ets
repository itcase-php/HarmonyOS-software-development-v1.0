import { FidelityReport, Metric } from './NativeProtocol';

// Shared by model snapshots and both report sources; never invents a metric.
export class FidelityReportSnapshot {
  static copy(report: FidelityReport): FidelityReport {
    return { schemaVersion: report.schemaVersion, intent: report.intent, requestedTier: report.requestedTier,
      achievedTier: report.achievedTier, sourcePageCount: report.sourcePageCount, outputPageCount: report.outputPageCount,
      metrics: report.metrics.map((metric: Metric): Metric => ({ name: metric.name, state: metric.state,
        value: metric.value, denominator: metric.denominator, unit: metric.unit,
        algorithmVersion: metric.algorithmVersion, evidenceRefs: metric.evidenceRefs.slice() })),
      fontSubstitutions: report.fontSubstitutions.slice(), unsupportedFeatures: report.unsupportedFeatures.slice(),
      degradations: report.degradations.slice(), requiresManualReview: report.requiresManualReview,
      detectorVersion: report.detectorVersion, evidenceRefs: report.evidenceRefs.slice() };
  }
}

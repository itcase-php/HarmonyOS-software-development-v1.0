import { ConvertResult, FidelityReport, Metric } from '../models/NativeProtocol';
import { DemoTask } from '../models/InteractionModels';
import { FidelityReportSnapshot } from '../models/FidelityReportSnapshot';
import { FidelityPolicy } from './FidelityPolicy';
import { BridgeError } from '../common/BridgeError';

export class NativeFidelityReport {
  static read(task: DemoTask, result: ConvertResult): FidelityReport | undefined {
    if (task.mode !== 'native' || result.taskId !== task.id || result.status !== 'success') {
      throw new BridgeError('PROTOCOL_INCOMPATIBLE', 'NATIVE_REPORT_CONTEXT');
    }
    const report = result.fidelity;
    if (!report) { return undefined; } // Missing native evidence stays missing.
    if (report.schemaVersion !== 1 || report.intent !== task.requestedIntent ||
      report.requestedTier !== task.requestedTier) {
      throw new BridgeError('PROTOCOL_INCOMPATIBLE', 'NATIVE_REPORT_OPTIONS');
    }
    if (!Array.isArray(report.metrics) || !Array.isArray(report.fontSubstitutions) ||
      !Array.isArray(report.unsupportedFeatures) || !Array.isArray(report.degradations) ||
      !Array.isArray(report.evidenceRefs) || typeof report.requiresManualReview !== 'boolean' ||
      typeof report.detectorVersion !== 'string' || report.detectorVersion.length === 0 ||
      report.metrics.some((metric: Metric) => !NativeFidelityReport.validMetric(metric)) ||
      (report.sourcePageCount !== undefined && (!Number.isSafeInteger(report.sourcePageCount) || report.sourcePageCount < 0)) ||
      (report.outputPageCount !== undefined && (!Number.isSafeInteger(report.outputPageCount) || report.outputPageCount < 0))) {
      throw new BridgeError('PROTOCOL_INCOMPATIBLE', 'NATIVE_REPORT_METRICS');
    }
    if (report.achievedTier && (!['extreme', 'standard', 'compatible'].includes(report.achievedTier) ||
      FidelityPolicy.tierRank(report.achievedTier) < FidelityPolicy.tierRank(task.requestedTier))) {
      throw new BridgeError('OUTPUT_VALIDATION_FAILED', 'NATIVE_FIDELITY_BELOW_MINIMUM');
    }
    return FidelityReportSnapshot.copy(report);
  }

  private static validMetric(metric: Metric): boolean {
    if (!['measured', 'estimated', 'unavailable', 'not_applicable'].includes(metric.state) ||
      typeof metric.name !== 'string' || typeof metric.unit !== 'string' ||
      typeof metric.algorithmVersion !== 'string' || !Array.isArray(metric.evidenceRefs) ||
      (metric.state === 'measured' && (metric.value === undefined || metric.evidenceRefs.length === 0)) ||
      (metric.value !== undefined && (!Number.isFinite(metric.value) ||
        (metric.unit === 'ratio' && (metric.value < 0 || metric.value > 1)))) ||
      (metric.denominator !== undefined && (!Number.isFinite(metric.denominator) || metric.denominator <= 0))) {
      return false;
    }
    return true;
  }
}

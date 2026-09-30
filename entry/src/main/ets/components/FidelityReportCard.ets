import { FidelityReport, Metric } from '../models/NativeProtocol';
import { ExecutionMode, ReportMetricRow } from '../models/InteractionModels';
import { FidelityText } from '../common/FidelityText';
import { StatusBadge } from './StatusBadge';

@Component
export struct FidelityReportCard {
  @Require @Prop @Watch('prepare') report: FidelityReport | undefined = undefined;
  @Prop @Watch('prepare') mode: ExecutionMode = 'demo';
  @State expanded: boolean = false;
  @State summary: string = '';
  @State intent: string = '';
  @State detector: string = '';
  @State metrics: ReportMetricRow[] = [];
  @State degradations: string[] = [];
  @State substitutions: string[] = [];
  @State unsupported: string[] = [];
  @State reviewText: string = '';

  aboutToAppear(): void { this.prepare(); }

  private metricName(name: string): string {
    switch (name) {
      case 'layout_similarity_demo': return FidelityText.read(this.getUIContext(), $r('app.string.report_layout_demo'));
      case 'layout_similarity': return FidelityText.read(this.getUIContext(), $r('app.string.report_layout'));
      case 'content_coverage_demo': return FidelityText.read(this.getUIContext(), $r('app.string.report_content_demo'));
      case 'content_coverage': return FidelityText.read(this.getUIContext(), $r('app.string.report_content'));
      case 'page_count': return FidelityText.read(this.getUIContext(), $r('app.string.report_pages'));
      default: return name;
    }
  }
  private metricValue(metric: Metric): string {
    if (metric.state === 'not_applicable') { return FidelityText.read(this.getUIContext(), $r('app.string.report_na')); }
    if (metric.state === 'unavailable' || metric.value === undefined) {
      return FidelityText.read(this.getUIContext(), $r('app.string.report_unavailable'));
    }
    const value = metric.unit === 'ratio' ? `${(metric.value * 100).toFixed(0)}%` : `${metric.value} ${metric.unit}`;
    return this.mode === 'demo' ? FidelityText.read(this.getUIContext(), $r('app.string.report_demo_value'), [value]) : value;
  }
  private metricState(metric: Metric): string {
    if (metric.state === 'estimated') {
      return FidelityText.read(this.getUIContext(), this.mode === 'demo' ?
        $r('app.string.report_estimated_demo') : $r('app.string.report_estimated'));
    }
    return FidelityText.read(this.getUIContext(), metric.state === 'measured' ? $r('app.string.report_measured') :
      metric.state === 'not_applicable' ? $r('app.string.report_na') : $r('app.string.report_unavailable'));
  }
  private prepare(): void {
    const report = this.report;
    if (!report) {
      this.summary = ''; this.intent = ''; this.detector = ''; this.reviewText = '';
      this.metrics = []; this.degradations = []; this.substitutions = []; this.unsupported = []; return;
    }
    const achieved = report.achievedTier ? FidelityText.tier(this.getUIContext(), report.achievedTier) :
      FidelityText.read(this.getUIContext(), $r('app.string.report_undetermined'));
    this.summary = FidelityText.read(this.getUIContext(), this.mode === 'demo' ?
      $r('app.string.report_demo_summary') : $r('app.string.report_native_summary'),
      [FidelityText.tier(this.getUIContext(), report.requestedTier), achieved]);
    this.intent = FidelityText.read(this.getUIContext(), $r('app.string.report_intent'),
      [FidelityText.intent(this.getUIContext(), report.intent)]);
    this.reviewText = FidelityText.read(this.getUIContext(), report.requiresManualReview ?
      $r('app.string.report_review') : $r('app.string.report_no_review'));
    this.detector = FidelityText.read(this.getUIContext(), $r('app.string.report_version'),
      [report.detectorVersion, this.reviewText]);
    this.metrics = report.metrics.map((metric: Metric): ReportMetricRow => ({
      name: this.metricName(metric.name), value: this.metricValue(metric),
      state: this.metricState(metric)
    }));
    this.degradations = report.degradations.slice();
    this.substitutions = report.fontSubstitutions.slice();
    this.unsupported = report.unsupportedFeatures.slice();
  }

  build() {
    Column({ space: 10 }) {
      Button(this.expanded ? $r('app.string.report_collapse') : $r('app.string.report_expand')).fontSize(14)
        .backgroundColor($r('app.color.palette_e5ecf5')).fontColor($r('app.color.palette_172b4d'))
        .accessibilityText($r('app.string.report_title'))
        .accessibilityDescription(this.expanded ? $r('app.string.a11y_collapse') : $r('app.string.a11y_expand'))
        .onClick(() => { this.expanded = !this.expanded; })
      Text(this.summary).fontSize(13).fontColor($r('app.color.palette_526077'))
      if (this.expanded) {
        StatusBadge({ text: FidelityText.read(this.getUIContext(), this.mode === 'demo' ?
          $r('app.string.report_demo_badge') : $r('app.string.report_native_badge')), color: this.mode === 'demo' ? $r('app.color.palette_a65c00') : $r('app.color.palette_167644') })
        Text(this.intent).fontSize(14).fontColor($r('app.color.palette_172b4d'))
        Text(this.mode === 'demo' ? $r('app.string.report_demo_notice') : $r('app.string.report_native_notice'))
          .fontSize(13).fontColor($r('app.color.palette_526077'))
        ForEach(this.metrics, (metric: ReportMetricRow) => {
          Column({ space: 4 }) {
            Text(`${metric.name}：${metric.value}`).fontSize(14).fontColor($r('app.color.palette_172b4d'))
            Text(metric.state).fontSize(12).fontColor($r('app.color.palette_526077'))
          }.alignItems(HorizontalAlign.Start)
        }, (metric: ReportMetricRow) => metric.name)
        Text(this.mode === 'demo' ? $r('app.string.report_degradations_demo') : $r('app.string.report_degradations'))
          .fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.palette_172b4d'))
        if (this.degradations.length === 0) {
          Text(this.mode === 'demo' ? $r('app.string.report_no_degradation_demo') : $r('app.string.report_no_degradation'))
            .fontSize(13).fontColor($r('app.color.palette_526077'))
        }
        ForEach(this.degradations, (item: string) => { Text(item).fontSize(13).fontColor($r('app.color.palette_526077')) }, (item: string) => item)
        Text(this.mode === 'demo' ? $r('app.string.report_fonts_demo') : $r('app.string.report_fonts'))
          .fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.palette_172b4d'))
        if (this.substitutions.length === 0) { Text($r('app.string.report_no_fonts')).fontSize(13).fontColor($r('app.color.palette_526077')) }
        ForEach(this.substitutions, (item: string) => { Text(item).fontSize(13).fontColor($r('app.color.palette_526077')) }, (item: string) => item)
        Text($r('app.string.report_limitations')).fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.palette_172b4d'))
        ForEach(this.unsupported, (item: string) => { Text(item).fontSize(13).fontColor($r('app.color.palette_526077')) }, (item: string) => item)
        Text(this.detector).fontSize(12).fontColor($r('app.color.palette_526077'))
      }
    }.alignItems(HorizontalAlign.Start).width('100%')
  }
}

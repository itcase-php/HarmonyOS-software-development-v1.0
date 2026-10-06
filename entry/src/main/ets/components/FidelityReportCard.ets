import { LanguageManager, AppLanguage } from '../common/LanguageManager';
import { FidelityReport, Metric } from '../models/NativeProtocol';
import { ExecutionMode, ReportMetricRow } from '../models/InteractionModels';
import { StatusBadge } from './StatusBadge';

@Component
export struct FidelityReportCard {
  @StorageLink('appLanguage') @Watch('prepare') language: AppLanguage = LanguageManager.currentLanguage;
  private tr(resource: ResourceStr, args: (string | number)[] = []): string {
    return LanguageManager.getString(resource, args, this.language);
  }

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
      case 'layout_similarity_demo': return this.tr($r('app.string.report_layout_demo'));
      case 'layout_similarity': return this.tr($r('app.string.report_layout'));
      case 'content_coverage_demo': return this.tr($r('app.string.report_content_demo'));
      case 'content_coverage': return this.tr($r('app.string.report_content'));
      case 'page_count': return this.tr($r('app.string.report_pages'));
      default: return name;
    }
  }
  private metricValue(metric: Metric): string {
    if (metric.state === 'not_applicable') { return this.tr($r('app.string.report_na')); }
    if (metric.state === 'unavailable' || metric.value === undefined) {
      return this.tr($r('app.string.report_unavailable'));
    }
    const value = metric.unit === 'ratio' ? `${(metric.value * 100).toFixed(0)}%` : `${metric.value} ${metric.unit}`;
    return this.mode === 'demo' ? this.tr('report_demo_value', [value]) : value;
  }
  private metricState(metric: Metric): string {
    if (metric.state === 'estimated') {
      return this.tr(this.mode === 'demo' ?
        this.tr($r('app.string.report_estimated_demo')) : this.tr($r('app.string.report_estimated')));
    }
    return this.tr(metric.state === 'measured' ? this.tr($r('app.string.report_measured')) :
      metric.state === 'not_applicable' ? this.tr($r('app.string.report_na')) : this.tr($r('app.string.report_unavailable')));
  }
  private prepare(): void {
    const report = this.report;
    if (!report) {
      this.summary = ''; this.intent = ''; this.detector = ''; this.reviewText = '';
      this.metrics = []; this.degradations = []; this.substitutions = []; this.unsupported = []; return;
    }
    const achieved = report.achievedTier ? LanguageManager.tier(report.achievedTier) :
      this.tr($r('app.string.report_undetermined'));
    this.summary = this.tr(this.mode === 'demo' ? 'report_demo_summary' : 'report_native_summary',
      [LanguageManager.tier(report.requestedTier), achieved]);
    this.intent = this.tr('report_intent', [LanguageManager.intent(report.intent)]);
    this.reviewText = this.tr(report.requiresManualReview ?
      this.tr($r('app.string.report_review')) : this.tr($r('app.string.report_no_review')));
    this.detector = this.tr('report_version', [report.detectorVersion, this.reviewText]);
    this.metrics = report.metrics.map((metric: Metric): ReportMetricRow => ({
      name: this.metricName(metric.name), value: this.metricValue(metric),
      state: this.metricState(metric)
    }));
    this.degradations = report.degradations.map((value: string) => LanguageManager.detail(value));
    this.substitutions = report.fontSubstitutions.slice();
    this.unsupported = report.unsupportedFeatures.map((value: string) => LanguageManager.detail(value));
  }

  build() {
    Column({ space: 10 }) {
      Button(this.expanded ? this.tr($r('app.string.report_collapse')) : this.tr($r('app.string.report_expand'))).fontSize(14)
        .backgroundColor($r('app.color.palette_e5ecf5')).fontColor($r('app.color.palette_172b4d'))
        .accessibilityText(this.tr($r('app.string.report_title')))
        .accessibilityDescription(this.expanded ? this.tr($r('app.string.a11y_collapse')) : this.tr($r('app.string.a11y_expand')))
        .onClick(() => { this.expanded = !this.expanded; })
      Text(this.summary).fontSize(13).fontColor($r('app.color.palette_526077'))
      if (this.expanded) {
        StatusBadge({ text: this.tr(this.mode === 'demo' ?
          this.tr($r('app.string.report_demo_badge')) : this.tr($r('app.string.report_native_badge'))), color: this.mode === 'demo' ? $r('app.color.palette_a65c00') : $r('app.color.palette_167644') })
        Text(this.intent).fontSize(14).fontColor($r('app.color.palette_172b4d'))
        Text(this.mode === 'demo' ? this.tr($r('app.string.report_demo_notice')) : this.tr($r('app.string.report_native_notice')))
          .fontSize(13).fontColor($r('app.color.palette_526077'))
        ForEach(this.metrics, (metric: ReportMetricRow) => {
          Column({ space: 4 }) {
            Text(`${metric.name}：${metric.value}`).fontSize(14).fontColor($r('app.color.palette_172b4d'))
            Text(metric.state).fontSize(12).fontColor($r('app.color.palette_526077'))
          }.alignItems(HorizontalAlign.Start)
        }, (metric: ReportMetricRow) => metric.name)
        Text(this.mode === 'demo' ? this.tr($r('app.string.report_degradations_demo')) : this.tr($r('app.string.report_degradations')))
          .fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.palette_172b4d'))
        if (this.degradations.length === 0) {
          Text(this.mode === 'demo' ? this.tr($r('app.string.report_no_degradation_demo')) : this.tr($r('app.string.report_no_degradation')))
            .fontSize(13).fontColor($r('app.color.palette_526077'))
        }
        ForEach(this.degradations, (item: string) => { Text(item).fontSize(13).fontColor($r('app.color.palette_526077')) }, (item: string) => item)
        Text(this.mode === 'demo' ? this.tr($r('app.string.report_fonts_demo')) : this.tr($r('app.string.report_fonts')))
          .fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.palette_172b4d'))
        if (this.substitutions.length === 0) { Text(this.tr($r('app.string.report_no_fonts'))).fontSize(13).fontColor($r('app.color.palette_526077')) }
        ForEach(this.substitutions, (item: string) => { Text(item).fontSize(13).fontColor($r('app.color.palette_526077')) }, (item: string) => item)
        Text(this.tr($r('app.string.report_limitations'))).fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.palette_172b4d'))
        ForEach(this.unsupported, (item: string) => { Text(item).fontSize(13).fontColor($r('app.color.palette_526077')) }, (item: string) => item)
        Text(this.detector).fontSize(12).fontColor($r('app.color.palette_526077'))
      }
    }.alignItems(HorizontalAlign.Start).width('100%')
  }
}

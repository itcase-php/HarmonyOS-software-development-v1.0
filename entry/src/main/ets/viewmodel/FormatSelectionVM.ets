import { RegistryFormat, ConversionRouteDefinition } from '../models/RegistryTypes';
import { FidelityTier, Intent, QualityMode } from '../models/NativeProtocol';
import { ConverterNavigationParams, FidelitySelection, IntentChoice } from '../models/InteractionModels';
import { FormatRegistryPort } from '../services/ServiceContracts';
import { FormatRegistry } from '../services/FormatRegistry';
import { ConversionPlannerService } from './ConversionPlanner';
import { FidelityPolicy } from './FidelityPolicy';
import { FidelityConfigVM } from './FidelityConfigVM';
import { ConversionStatusVM } from './ConversionStatusVM';
import { ConverterUiPort, PreviewConverterUi } from './ConverterUiPort';
import { ErrorHandler } from '../common/ErrorHandler';

@Observed
export class FormatSelectionVM {
  sourceId: string = ''; targetId: string = ''; routeId: string = ''; fileName: string = '';
  sourceIndex: number = 0; targetIndex: number = 0; routeIndex: number = 0;
  approved: boolean = false; interactive: boolean = true;
  sourceChoices: SelectOption[] = []; targetChoices: SelectOption[] = []; routeChoices: SelectOption[] = [];
  registryReady: boolean = true; registryLoading: boolean = false;
  formats: RegistryFormat[]; targetFormats: RegistryFormat[] = []; activeRoutes: ConversionRouteDefinition[] = [];
  supportedIntents: IntentChoice[] = []; tiers: FidelityTier[] = ['extreme', 'standard', 'compatible'];
  readonly fidelity: FidelityConfigVM; private status: ConversionStatusVM;
  private registry: FormatRegistryPort; private planner: ConversionPlannerService;
  private ui: ConverterUiPort;
  constructor(registry: FormatRegistryPort = FormatRegistry.shared(), planner: ConversionPlannerService = new ConversionPlannerService(registry),
    fidelity: FidelityConfigVM = new FidelityConfigVM(), status: ConversionStatusVM = new ConversionStatusVM(), ui: ConverterUiPort = new PreviewConverterUi()) {
    this.registry = registry; this.planner = planner; this.fidelity = fidelity; this.status = status; this.ui = ui;
    this.formats = registry.listFormats();
  }
  setUi(ui: ConverterUiPort): void { this.ui = ui; }
  syncInteractivity(): void {
    this.interactive = this.registryReady && !this.status.working && !this.status.confirming && !this.status.inputBusy;
    this.fidelity.interactive = this.interactive;
  }
  selectFormat(id: string): void { const index: number = this.formats.findIndex((format: RegistryFormat) => format.id === id); if (index >= 0) { this.selectSource(index); } }
async loadFormats(): Promise<void> {
    if (this.registryLoading) { return; }
    this.initializeSelections();
    this.registryLoading = true;
    try {
      await this.ui.ensureRegistry(this.registry);
      this.formats = this.registry.listFormats(); this.registryReady = true;
      this.status.errorText = ''; this.syncInteractivity();
      this.initializeSelections();
    } catch (error) { ErrorHandler.swallow('FormatSelection.load', error);
      this.registryReady = false;
      this.status.errorText = this.ui.read( $r('app.string.registry_error'));
      this.syncInteractivity();
    } finally { this.registryLoading = false; }
  }

initializeSelections(): void {
    if (this.sourceId.length !== 0) { return; }
    this.sourceChoices = this.formats.map((format: RegistryFormat): SelectOption => ({
      value: `${format.displayName} (${format.id})`
    }));
    this.fidelity.tierChoices = this.tiers.map((tier: FidelityTier): SelectOption => ({ value: this.ui.tier( tier) }));
    let source = this.formats.findIndex((format: RegistryFormat) => this.planner.targets(format.id).length > 0);
    try {
      const params = this.ui.navigationParams();
      if (params && params.sourceFormatId) {
        const index = this.formats.findIndex((format: RegistryFormat) => format.id === params.sourceFormatId);
        if (index >= 0) { source = index; }
      }
      if (params && params.qualityMode && FidelityPolicy.isQualityMode(params.qualityMode)) {
        this.fidelity.qualityMode = params.qualityMode;
      }
    } catch (error) { ErrorHandler.swallow('FormatSelection.navigation', error); }
    this.selectSource(Math.max(0, source));
  }

selectSource(index: number): void {
    const format = this.formats[index];
    if (!format) { return; }
    this.sourceIndex = index; this.sourceId = format.id;
    this.fileName = `示例文档.${format.extensions[0]}`;
    this.targetFormats = this.planner.targets(this.sourceId);
    this.targetChoices = this.targetFormats.map((target: RegistryFormat): SelectOption => ({
      value: `${target.displayName} (${target.id})`
    }));
    this.selectTarget(0);
  }

selectTarget(index: number): void {
    const target = this.targetFormats[index];
    this.targetIndex = index; this.targetId = target ? target.id : '';
    const first = this.planner.routes(this.sourceId, this.targetId)[0];
    if (first) {
      this.fidelity.requestedIntent = first.intent;
      this.fidelity.requestedTier = first.fidelityTier;
    }
    this.refreshRoutes();
  }

refreshRoutes(preferredId: string = ''): void {
    const allRoutes = this.planner.routes(this.sourceId, this.targetId);
    const intents: IntentChoice[] = [];
    for (const route of allRoutes) {
      if (!intents.some((choice: IntentChoice) => choice.value === route.intent)) {
        intents.push({ value: route.intent, label: this.ui.intent( route.intent) });
      }
    }
    this.supportedIntents = intents;
    this.fidelity.intentChoices = intents.map((choice: IntentChoice): SelectOption => ({ value: choice.label }));
    this.fidelity.intentIndex = Math.max(0, intents.findIndex((choice: IntentChoice) => choice.value === this.fidelity.requestedIntent));
    this.fidelity.tierIndex = Math.max(0, this.tiers.findIndex((tier: FidelityTier) => tier === this.fidelity.requestedTier));
    this.fidelity.intentText = this.ui.intent( this.fidelity.requestedIntent);
    this.fidelity.tierText = this.ui.tier( this.fidelity.requestedTier);
    this.fidelity.qualitySummary = this.ui.read( $r('app.string.quality_duration'),
      [this.ui.quality( this.fidelity.qualityMode), (FidelityPolicy.durationMs(this.fidelity.qualityMode) / 1000).toString()]);
    this.fidelity.selectionSummary = this.ui.read( $r('app.string.fidelity_selection_summary'),
      [this.fidelity.qualitySummary, this.fidelity.tierText]);
    this.activeRoutes = this.planner.routes(this.sourceId, this.targetId, this.fidelity.qualityMode,
      this.fidelity.requestedIntent, this.fidelity.requestedTier);
    this.routeChoices = this.activeRoutes.map((route: ConversionRouteDefinition): SelectOption => ({
      value: this.ui.read( $r('app.string.route_choice'), [
        this.ui.read( route.pathMode === 'direct' ? $r('app.string.path_direct') : $r('app.string.path_relay')),
        this.ui.tier( route.fidelityTier), route.id])
    }));
    const preferred = this.activeRoutes.findIndex((route: ConversionRouteDefinition) => route.id === preferredId);
    this.selectRoute(preferred >= 0 ? preferred : 0);
    this.status.errorText = '';

  }

selectRoute(index: number): void {
    const route = this.activeRoutes[index];
    this.routeIndex = index; this.routeId = route ? route.id : '';
    this.approved = false;
    if (route) {
      this.fidelity.requestedIntent = route.intent;
      this.fidelity.routeDescription = this.ui.read( $r('app.string.route_description'), [
        this.ui.tier( route.fidelityTier),
        this.ui.read( route.pathMode === 'direct' ? $r('app.string.path_direct') : $r('app.string.path_relay')),
        this.ui.intent( route.intent)]);
      this.fidelity.routeNotice = this.ui.read( route.requiresUserApproval ?
        $r('app.string.route_approval_notice') : $r('app.string.route_limit_notice'));
    } else {
      this.fidelity.routeDescription = this.ui.read( $r('app.string.route_missing'));
      this.fidelity.routeNotice = this.ui.read( $r('app.string.route_missing_notice'));
    }
    this.fidelity.routeAvailable = route !== undefined;

  }

selectIntent(index: number): void {
    const intent = this.supportedIntents[index];
    if (intent) { this.fidelity.requestedIntent = intent.value; this.refreshRoutes(); }
  }

selectTier(index: number): void {
    const tier = this.tiers[index];
    if (tier) { this.fidelity.requestedTier = tier; this.refreshRoutes(); }
  }

selectQuality(mode: QualityMode): void {
    if (!this.registryReady || this.status.working || this.status.confirming) { return; }
    this.fidelity.qualityMode = mode; this.refreshRoutes(this.routeId);
  }

useExample(): void {
    const source = this.formats[this.sourceIndex];
    if (source) {
      this.fileName = `示例文档.${source.extensions[0]}`;
      this.status.errorText = ''; this.ui.toast( '已填入演示名称，不会读取设备文件');
    }
  }

selection(): FidelitySelection {
    return { qualityMode: this.fidelity.qualityMode, requestedIntent: this.fidelity.requestedIntent, requestedTier: this.fidelity.requestedTier };
  }
}

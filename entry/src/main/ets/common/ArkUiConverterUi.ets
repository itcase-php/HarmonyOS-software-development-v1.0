import { ConverterUiPort, ConverterDialog } from '../viewmodel/ConverterUiPort';
import { FidelityTier, Intent, QualityMode } from '../models/NativeProtocol';
import { ConverterNavigationParams } from '../models/InteractionModels';
import { FormatRegistryPort } from '../services/ServiceContracts';
import { LanguageManager } from './LanguageManager';
import { UiFeedback } from './UiFeedback';
import { RawfileResources } from '../services/RawfileResources';
import { ErrorHandler } from './ErrorHandler';
import { FidelityPolicy } from '../viewmodel/FidelityPolicy';

export class ArkUiConverterUi implements ConverterUiPort {
  private context: UIContext;
  constructor(context: UIContext) { this.context = context; LanguageManager.bind(context.getHostContext()); }
  read(resource: ResourceStr, args: (string | number)[] = []): string { return LanguageManager.getString(resource, args); }
  tier(tier: FidelityTier): string { return LanguageManager.tier(tier); }
  intent(intent: Intent): string { return LanguageManager.intent(intent); }
  quality(mode: QualityMode): string { return LanguageManager.quality(mode); }
  toast(message: string): void { UiFeedback.toast(this.context, message); }
  showAlertDialog(dialog: ConverterDialog): void { this.context.showAlertDialog(dialog); }
  navigationParams(): ConverterNavigationParams {
    try {
      // SDK Object boundary: copy only validated primitive navigation fields.
      const input = this.context.getRouter().getParams() as ConverterNavigationParams;
      const output: ConverterNavigationParams = {};
      if (input && typeof input.sourceFormatId === 'string') { output.sourceFormatId = input.sourceFormatId; }
      if (input && typeof input.qualityMode === 'string' && FidelityPolicy.isQualityMode(input.qualityMode)) {
        output.qualityMode = input.qualityMode;
      }
      return output;
    } catch (error) { ErrorHandler.swallow('Converter.navigation', error); return {}; }
  }
  async ensureRegistry(registry: FormatRegistryPort): Promise<void> {
    if (registry.isInitialized()) { return; }
    try {
      const resources = this.context.getHostContext()?.resourceManager;
      if (resources) { await registry.initialize(new RawfileResources(resources)); }
    } catch (error) { ErrorHandler.swallow('Converter.registry', error); }
  }
}

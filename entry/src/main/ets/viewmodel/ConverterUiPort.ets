import { FidelityTier, Intent, QualityMode } from '../models/NativeProtocol';
import { ConverterNavigationParams } from '../models/InteractionModels';
import { FormatRegistryPort } from '../services/ServiceContracts';
import { LanguageManager } from '../common/LanguageManager';

export interface ConverterDialogButton { value: string; action: () => void; }
export interface ConverterDialog {
  title: string; message: string; autoCancel: boolean;
  primaryButton: ConverterDialogButton; secondaryButton: ConverterDialogButton; cancel: () => void;
}
export interface ConverterUiPort {
  read(resource: ResourceStr, args?: (string | number)[]): string;
  tier(tier: FidelityTier): string;
  intent(intent: Intent): string;
  quality(mode: QualityMode): string;
  toast(message: string): void;
  showAlertDialog(dialog: ConverterDialog): void;
  navigationParams(): ConverterNavigationParams;
  ensureRegistry(registry: FormatRegistryPort): Promise<void>;
}

export class PreviewConverterUi implements ConverterUiPort {
  read(resource: ResourceStr, args: (string | number)[] = []): string { return LanguageManager.getString(resource, args); }
  tier(tier: FidelityTier): string { return LanguageManager.tier(tier); }
  intent(intent: Intent): string { return LanguageManager.intent(intent); }
  quality(mode: QualityMode): string { return LanguageManager.quality(mode); }
  toast(message: string): void {}
  showAlertDialog(dialog: ConverterDialog): void { throw new Error('Use inline preview confirmation'); }
  navigationParams(): ConverterNavigationParams { return {}; }
  async ensureRegistry(registry: FormatRegistryPort): Promise<void> {}
}

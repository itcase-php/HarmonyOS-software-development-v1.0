import { FidelityTier, Intent, QualityMode } from '../models/NativeProtocol';
import { ConverterNavigationParams } from '../models/InteractionModels';
import { FormatRegistryPort } from '../services/ServiceContracts';
import { FidelityPolicy } from './FidelityPolicy';

export interface ConverterDialogButton { value: string; action: () => void; }
export interface ConverterDialog {
  title: string; message: string; autoCancel: boolean;
  primaryButton: ConverterDialogButton; secondaryButton: ConverterDialogButton; cancel: () => void;
}
export interface ConverterUiPort {
  read(resource: Resource, args?: (string | number)[]): string;
  tier(tier: FidelityTier): string;
  intent(intent: Intent): string;
  quality(mode: QualityMode): string;
  toast(message: string): void;
  showAlertDialog(dialog: ConverterDialog): void;
  navigationParams(): ConverterNavigationParams;
  ensureRegistry(registry: FormatRegistryPort): Promise<void>;
}

export class PreviewConverterUi implements ConverterUiPort {
  read(resource: Resource, args: (string | number)[] = []): string { return ''; }
  tier(tier: FidelityTier): string { return FidelityPolicy.tierLabel(tier); }
  intent(intent: Intent): string { return FidelityPolicy.intentLabel(intent); }
  quality(mode: QualityMode): string { return FidelityPolicy.qualityLabel(mode); }
  toast(message: string): void {}
  showAlertDialog(dialog: ConverterDialog): void { throw new Error('Use inline preview confirmation'); }
  navigationParams(): ConverterNavigationParams { return {}; }
  async ensureRegistry(registry: FormatRegistryPort): Promise<void> {}
}

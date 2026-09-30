import { FidelitySettingsVM, FidelitySelection } from '../models/InteractionModels';

@Observed
export class FidelityConfigVM extends FidelitySettingsVM {
  constructor(selection: FidelitySelection = { qualityMode: 'balanced', requestedIntent: 'layout_preserved', requestedTier: 'standard' }) {
    super(); this.qualityMode = selection.qualityMode; this.requestedIntent = selection.requestedIntent; this.requestedTier = selection.requestedTier;
  }
  selection(): FidelitySelection {
    return { qualityMode: this.qualityMode, requestedIntent: this.requestedIntent, requestedTier: this.requestedTier };
  }
}

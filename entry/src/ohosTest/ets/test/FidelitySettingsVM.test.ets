import { describe, it, expect } from '@ohos/hypium';
import { FidelitySettingsVM } from '../../../main/ets/models/InteractionModels';

export default function fidelitySettingsVMTest() {
  describe('FidelitySettingsVM', () => {
    it('starts with a complete balanced selection and no executable route', 0, () => {
      const vm = new FidelitySettingsVM(); expect(vm.qualityMode).assertEqual('balanced');
      expect(vm.requestedIntent).assertEqual('layout_preserved'); expect(vm.requestedTier).assertEqual('standard');
      expect(vm.routeAvailable).assertFalse(); expect(vm.intentChoices.length).assertEqual(0);
    });
    it('copies selection presentation and interactivity together', 0, () => {
      const vm = new FidelitySettingsVM(); vm.qualityMode = 'fast'; vm.interactive = false;
      vm.routeAvailable = true; vm.routeDescription = 'fixture route'; vm.tierIndex = 2;
      const copy = vm.clone(); expect(copy.qualityMode).assertEqual('fast'); expect(copy.interactive).assertFalse();
      expect(copy.routeAvailable).assertTrue(); expect(copy.routeDescription).assertEqual('fixture route');
      expect(copy.tierIndex).assertEqual(2);
    });
    it('isolates option arrays and individual SelectOption values', 0, () => {
      const vm = new FidelitySettingsVM(); vm.intentChoices = [{ value: 'fixture-intent' }]; vm.tierChoices = [{ value: 'fixture-tier' }];
      const copy = vm.clone(); copy.intentChoices[0].value = 'changed'; copy.tierChoices.push({ value: 'new' });
      expect(vm.intentChoices[0].value).assertEqual('fixture-intent'); expect(vm.tierChoices.length).assertEqual(1);
    });
  });
}

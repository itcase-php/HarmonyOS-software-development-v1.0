import abilityTest from './Ability.test';
import conversionCoreTest from '../../../test/ConversionCore.test';
import fidelityPolicyTest from './FidelityPolicy.test';
import conversionPlannerTest from './ConversionPlanner.test';
import taskStoreTest from './TaskStore.test';
import demoFidelityReportTest from './DemoFidelityReport.test';
import fidelityReportSnapshotTest from './FidelityReportSnapshot.test';
import formatRegistryTest from './FormatRegistry.test';
import fidelitySettingsVMTest from './FidelitySettingsVM.test';

export default function testsuite() {
  abilityTest();
  conversionCoreTest();
  fidelityPolicyTest();
  conversionPlannerTest();
  taskStoreTest();
  demoFidelityReportTest();
  fidelityReportSnapshotTest();
  formatRegistryTest();
  fidelitySettingsVMTest();
}

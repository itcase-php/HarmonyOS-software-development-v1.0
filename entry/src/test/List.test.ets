import localUnitTest from './LocalUnit.test';
import conversionCoreTest from './ConversionCore.test';
import fidelityPolicyTest from '../ohosTest/ets/test/FidelityPolicy.test';
import conversionPlannerTest from '../ohosTest/ets/test/ConversionPlanner.test';
import taskStoreTest from '../ohosTest/ets/test/TaskStore.test';
import demoFidelityReportTest from '../ohosTest/ets/test/DemoFidelityReport.test';
import fidelityReportSnapshotTest from '../ohosTest/ets/test/FidelityReportSnapshot.test';
import formatRegistryTest from '../ohosTest/ets/test/FormatRegistry.test';
import fidelitySettingsVMTest from '../ohosTest/ets/test/FidelitySettingsVM.test';

export default function testsuite() {
  localUnitTest();
  conversionCoreTest();
  fidelityPolicyTest();
  conversionPlannerTest();
  taskStoreTest();
  demoFidelityReportTest();
  fidelityReportSnapshotTest();
  formatRegistryTest();
  fidelitySettingsVMTest();
}

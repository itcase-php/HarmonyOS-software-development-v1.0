import localUnitTest from './LocalUnit.test';
import conversionCoreTest from './ConversionCore.test';

export default function testsuite() {
  localUnitTest();
  conversionCoreTest();
}

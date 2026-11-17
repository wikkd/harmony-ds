import localUnitTest from './LocalUnit.test';
import coreTests from './Core.test';

export default function testsuite() {
  localUnitTest();
  coreTests();
}

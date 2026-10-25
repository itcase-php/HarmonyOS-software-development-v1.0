import importlib.util
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location('ohos_report', Path(__file__).with_name('check-ohos-test-report.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def transcript(total=10, failure=0, error=0, passed=10, ignored=0):
    return f'OHOS_REPORT_RESULT: stream=Tests run: {total}, Failure: {failure}, Error: {error}, Pass: {passed}, Ignore: {ignored}\nOHOS_REPORT_CODE: 0\nTestFinished-ResultCode: 0\n'


class ReportTests(unittest.TestCase):
    def test_complete_success(self):
        self.assertTrue(module.evaluate(transcript(), 10)['passed'])

    def test_hdc_success_does_not_hide_errors(self):
        result = module.evaluate(transcript(error=9, passed=1), 10)
        self.assertFalse(result['passed'])
        self.assertEqual((result['passes'], result['errors']), (1, 9))

    def test_failed_ignored_and_missing_cases_block(self):
        for text in [transcript(failure=1, passed=9), transcript(ignored=1, passed=9), transcript(total=1, passed=1)]:
            self.assertFalse(module.evaluate(text, 10)['passed'])

    def test_incomplete_and_malformed_reports_block(self):
        for text in ['TestFinished-ResultCode: 0\n', transcript(passed=1), transcript().replace('TestFinished-ResultCode: 0', ''), transcript() * 2]:
            self.assertFalse(module.evaluate(text, 10)['passed'])

    def test_crlf_transcript(self):
        self.assertTrue(module.evaluate(transcript().replace('\n', '\r\n'), 10)['passed'])

    def test_recorded_failed_attempt_if_present(self):
        path = Path(__file__).resolve().parents[1] / 'tmp/core-engines/font-core-device-test.log'
        if not path.exists():
            self.skipTest('Local historical transcript is intentionally not committed')
        result = module.evaluate(path.read_text(encoding='utf-8-sig'), 10)
        self.assertFalse(result['passed'])
        self.assertEqual((result['passes'], result['errors']), (1, 9))


if __name__ == '__main__':
    unittest.main()

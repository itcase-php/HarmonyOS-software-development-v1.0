"""Validate a saved aa-test transcript. HDC's exit code alone is not evidence."""
import argparse
import json
import re
from pathlib import Path


def evaluate(text, expected_tests=None):
    summaries = re.findall(r'^(?:OHOS_REPORT_RESULT: stream=)?Tests run:\s*(\d+),\s*Failure:\s*(\d+),\s*Error:\s*(\d+),\s*Pass:\s*(\d+),\s*Ignore:\s*(\d+)\s*$', text, re.M)
    report = {'scope': 'saved OHOS test transcript; no device commands executed', 'passed': False}
    if len(summaries) != 1:
        report['reason'] = 'missing_or_ambiguous_test_summary'
        return report
    total, failure, error, passed, ignored = map(int, summaries[0])
    report.update(tests=total, failures=failure, errors=error, passes=passed, ignored=ignored)
    if total <= 0 or total != failure + error + passed + ignored:
        report['reason'] = 'invalid_test_counts'
    elif expected_tests is not None and total != expected_tests:
        report['reason'] = 'unexpected_test_count'
    elif not re.search(r'^TestFinished-ResultCode:\s*0\s*$', text, re.M):
        report['reason'] = 'missing_successful_runner_completion'
    elif failure or error or ignored or passed != total:
        report['reason'] = 'test_cases_not_all_passed'
    else:
        report['passed'] = True
        report['reason'] = 'all_expected_cases_passed'
    return report


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('log', type=Path)
    parser.add_argument('--expected-tests', type=int)
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    if args.expected_tests is not None and args.expected_tests <= 0:
        parser.error('--expected-tests must be positive')
    report = evaluate(args.log.read_text(encoding='utf-8-sig'), args.expected_tests)
    if args.report:
        args.report.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(report))
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())

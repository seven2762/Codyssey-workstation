#!/usr/bin/env python3
"""Validate measured evidence; report application policy separately from OS CPU load."""
import argparse
from datetime import datetime
from pathlib import Path
import re

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--strict-cpu', action='store_true', help='require OS CPU >= 50%% in cpu_before')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1] / 'evidence'
failures = []


def check(condition, message):
    print(f'{"PASS" if condition else "FAIL"}: {message}')
    if not condition:
        failures.append(message)


def read(label, name):
    return (root / label / name).read_text()


def metadata(label):
    return dict(line.split('=', 1) for line in read(label, 'run.log').splitlines() if '=' in line)


def samples(label):
    rows = []
    for line in read(label, 'monitor.log').splitlines():
        fields = [v.strip() for v in line.split('|')]
        if len(fields) == 7 and re.match(r'^\d{4}-\d\d-\d\d ', fields[0]):
            rows.append((fields[0], int(fields[1]), fields[2],
                         None if fields[3] == '-' else float(fields[3]),
                         int(fields[4]), int(fields[5]), int(re.match(r'\d+', fields[6])[0])))
    return rows


for label in ('oom_before', 'oom_after', 'cpu_before', 'cpu_after', 'deadlock_before', 'deadlock_after', 'scheduling'):
    check(len(samples(label)) >= 3, f'{label}: multiple OS samples')
    check('All Boot Checks Passed!' in read(label, 'app.log'), f'{label}: boot checks passed')

before, after = samples('oom_before'), samples('oom_after')
rss = [r[4] for r in before]
check(len(set(rss)) >= 3 and rss[-1] > rss[0], 'OOM: measured RSS increases')
check('Memory limit exceeded' in read('oom_before', 'app.log') and
      'Self-terminating process' in read('oom_before', 'app.log'), 'OOM: explicit application termination logs')
check(metadata('oom_before')['app_exit_code'] == '137' and
      metadata('oom_before')['timed_out'] == 'false', 'OOM: natural SIGKILL exit before runner cleanup')
check('MEMORY RECOVERED' in read('oom_after', 'app.log') and
      any(b[4] < a[4] for a, b in zip(after, after[1:])), 'OOM: logged recovery and measured RSS drop')
check(int(metadata('oom_after')['elapsed_seconds']) > int(metadata('oom_before')['elapsed_seconds']) and
      metadata('oom_after')['timed_out'] == 'true', 'OOM: longer After observation without self termination')

check('CPU Threshold Violated' in read('cpu_before', 'app.log') and
      metadata('cpu_before')['app_exit_code'] == '143' and
      metadata('cpu_before')['timed_out'] == 'false', 'CPU: threshold log and SIGTERM before runner cleanup')
check('Peak reached (40.00%)' in read('cpu_after', 'app.log') and
      'CPU Threshold Violated' not in read('cpu_after', 'app.log') and
      metadata('cpu_after')['timed_out'] == 'true', 'CPU: lower target reaches cooldown without policy termination')
peak = max(r[3] for r in samples('cpu_before') if r[3] is not None)
print(f'INFO: cpu_before measured OS CPU peak={peak}% (one core=100%); application Current Load is a separate metric')
if args.strict_cpu:
    check(peak >= 50, 'CPU mission: OS-measured CPU reaches 50% (explicit verification criterion)')
elif peak < 50:
    print('LIMITATION: OS CPU spike is not demonstrated; policy verification alone does not complete the CPU mission.')

app = read('deadlock_before', 'app.log')
check(all(s in app for s in ('LOCK ACQUIRED: [Shared_Memory_A]', 'LOCK ACQUIRED: [Socket_Pool_B]',
                            'WAITING for [Shared_Memory_A]', 'WAITING for [Socket_Pool_B]')),
      'Deadlock: opposing resource ownership and waits')
check('futex' in read('deadlock_before', 'threads_snapshot.txt'), 'Deadlock: PID/thread snapshot contains kernel lock waits')
last = samples('deadlock_before')[-5:]
check(last[-1][6] - last[0][6] >= 3 and len({r[1] for r in last}) == 1 and
      len({r[4] for r in last}) == 1 and all(r[3] is not None and r[3] <= 1 for r in last),
      'Deadlock: same live PID, stable RSS and near-zero CPU across final samples')
app_times = re.findall(r'^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d', app, re.M)
stalled_seconds = (datetime.strptime(last[-1][0][:19], '%Y-%m-%d %H:%M:%S') -
                   datetime.strptime(app_times[-1], '%Y-%m-%d %H:%M:%S')).total_seconds()
check(stalled_seconds >= 5, f'Deadlock: PID observed {stalled_seconds:g}s after final app log')
check(metadata('deadlock_before')['timed_out'] == 'true' and
      metadata('deadlock_after')['timed_out'] == 'true' and
      'Status: BLOCKED' not in read('deadlock_after', 'app.log') and
      'Current Heap:' in read('deadlock_after', 'app.log'), 'Deadlock: After workload progresses through observation window')

for report, labels in (
    ('01-oom-memory-leak.md', ('oom_before', 'oom_after')),
    ('02-cpu-spike.md', ('cpu_before', 'cpu_after')),
    ('03-deadlock.md', ('deadlock_before', 'deadlock_after')),
    ('04-scheduling-analysis.md', ('scheduling',)),
):
    document = (root.parent / 'reports' / report).read_text()
    source_lines = {line.strip() for label in labels for path in (root / label).glob('*.log')
                    for line in path.read_text().splitlines()}
    source_lines.update(line.strip() for label in labels
                        for line in read(label, 'threads_snapshot.txt').splitlines())
    quoted_lines = [line.strip() for block in re.findall(r'```text\n(.*?)\n```', document, re.S)
                    for line in block.splitlines() if line.strip()]
    check(bool(quoted_lines) and all(line in source_lines for line in quoted_lines),
          f'{report}: quoted text matches original evidence lines')

raise SystemExit(bool(failures))

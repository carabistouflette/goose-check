#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Retain real-command wall time/RSS smoke samples with default controls."""
import argparse
import hashlib
import json
from pathlib import Path
import platform
import subprocess
import tempfile
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--tool', required=True, type=Path)
parser.add_argument('--out', required=True, type=Path)
parser.add_argument('--rounds', type=int, default=10)
args = parser.parse_args()
if not 1 <= args.rounds <= 1000:
    parser.error('rounds must be in 1..1000')
root = Path(__file__).resolve().parents[1]
tool = args.tool.resolve()
args.out.mkdir(parents=True, exist_ok=False)
def git(*arguments):
    return subprocess.check_output(['git', '-C', str(root), *arguments], text=True).strip()
provenance = {
    'source': git('rev-parse', 'HEAD'), 'status': git('status', '--porcelain'),
    'binary_sha256': hashlib.sha256(tool.read_bytes()).hexdigest(),
    'tool': str(tool), 'platform': platform.platform(),
    'cpu': next((line.split(':', 1)[1].strip() for line in Path('/proc/cpuinfo').read_text().splitlines() if line.startswith('model name')), ''),
    'compiler_revision': (root / 'GOOSE_REVISION').read_text().strip(),
    'build': 'make build CC=gcc; Goose -O2, unsanitized',
    'gcc': subprocess.check_output(['gcc', '--version'], text=True),
    'dependencies': json.loads((root / 'vendor/pins.json').read_text()),
    'rounds': args.rounds,
    'scope': 'Shared-host smoke; no speedup, peak-memory bound or cross-machine claim.',
}
(args.out / 'provenance.json').write_text(json.dumps(provenance, indent=2) + '\n')
workloads = [
    ('match', b'same\n' * 1000, b'same\n' * 1000),
    ('small_change', b'first\nold\nlast\n', b'first\nnew\nlast\n'),
    ('escaped_truncation', b'\0' * 6000, b'\1' * 6000),
    ('matrix_omission', b'a\n' * 512, b'b\n' * 512),
    ('input_omission', b'a' * 65537, b'b' * 65537),
    ('line_omission', b'a\n' * 4097, b'b\n' * 4097),
]
with tempfile.TemporaryDirectory(prefix='goose-check-diff-bench-') as directory:
    temp = Path(directory)
    with (args.out / 'samples.jsonl').open('w') as output:
        for name, expected, actual in workloads:
            fixture = args.out / name
            fixture.mkdir()
            (fixture / 'expected.bin').write_bytes(expected)
            (fixture / 'actual.bin').write_bytes(actual)
            for round_number in range(args.rounds):
                for enabled in ([False, True] if round_number % 2 == 0 else [True, False]):
                    command = [str(tool), '--stdout', str((fixture / 'expected.bin').resolve()),
                               '--stdin', str((fixture / 'actual.bin').resolve()), '--output-limit', '1048576']
                    if enabled:
                        command += ['--diff']
                    command += ['--', '/bin/cat']
                    rss = temp / 'rss'
                    start = time.perf_counter_ns()
                    result = subprocess.run(['/usr/bin/time', '-f', '%M', '-o', str(rss), *command],
                                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
                    elapsed = time.perf_counter_ns() - start
                    assert result.returncode == (0 if expected == actual else 1), (name, result.stderr)
                    assert result.stdout == b''
                    output.write(json.dumps({'workload': name, 'round': round_number,
                        'diff': enabled, 'wall_ns': elapsed, 'max_rss_kib': int(rss.read_text().splitlines()[-1]),
                        'stderr_bytes': len(result.stderr), 'exit': result.returncode}) + '\n')
print(f'retained {len(workloads) * args.rounds * 2} real-command samples in {args.out}')

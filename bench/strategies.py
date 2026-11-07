#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Retain real-command strategy samples; successful and omitted work stay labeled."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess
import tempfile
import time
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--tool', type=Path, required=True)
parser.add_argument('--out', type=Path, required=True)
parser.add_argument('--rounds', type=int, default=10)
args = parser.parse_args()
if not 1 <= args.rounds <= 1000:
    parser.error('rounds must be in 1..1000')
root = Path(__file__).resolve().parents[1]
tool = args.tool.resolve()
def git(*arguments):
    return subprocess.check_output(['git','-C',str(root),*arguments],text=True).strip()
def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
source = git('rev-parse','HEAD')
assert git('status','--porcelain') == '', 'measurement requires clean source'
args.out = args.out.resolve();args.out.mkdir(parents=True,exist_ok=False)
fixtures = root / 'bench/fixtures/sparse'
manifest = json.loads((fixtures/'manifest.json').read_text())
metadata = {'source':source,'status':'','binary_sha256':digest(tool),'platform':platform.platform(),
    'compiler_revision':(root/'GOOSE_REVISION').read_text().strip(),'build':'make build CC=gcc SANITIZE=0; Goose -O2',
    'temporary_storage':os.environ.get('TMPDIR','platform default'),
    'cpu':next((line.split(':',1)[1].strip() for line in Path('/proc/cpuinfo').read_text().splitlines() if line.startswith('model name')),''),
    'diff_caps':{'max_bytes':65536,'max_lines':4096,'lcs_max_cells':262144,'sparse_max_states':262144,'max_work':1048576,'raw_output_limit':16384,'escaped_extra_limit':16384},
    'gcc':subprocess.check_output(['gcc','--version'],text=True),'rounds':args.rounds,
    'dependencies':json.loads((root/'vendor/pins.json').read_text()),
    'scope':'Whole command, including fixture reads, one cat child, diagnostics and time wrapper. Shared-host samples; omitted work is not successful throughput. RSS is process peak, not an allocation guarantee.'}
(args.out/'provenance.json').write_text(json.dumps(metadata,indent=2)+'\n')
with tempfile.TemporaryDirectory(prefix='goose-strategy-rss-') as directory:
    rss = Path(directory)/'rss'
    with (args.out/'samples.jsonl').open('w') as output:
        for case in manifest['cases']:
            a,b=fixtures/case['name']/'old.bin',fixtures/case['name']/'new.bin'
            assert digest(a)==case['old.bin_sha256'] and digest(b)==case['new.bin_sha256']
            for round_number in range(args.rounds):
                modes=['default','lcs','sparse'];offset=round_number%3
                default_diagnostic=None;lcs_diagnostic=None
                for mode in modes[offset:]+modes[:offset]:
                    command=[str(tool),'--diff','--stdout',str(a),'--stdin',str(b),'--output-limit','1048576']
                    if mode!='default': command+=['--diff-algorithm',mode]
                    command+=['--','/bin/cat']
                    start=time.perf_counter_ns()
                    run=subprocess.run(['/usr/bin/time','-f','%M','-o',str(rss),*command],capture_output=True,timeout=15)
                    elapsed=time.perf_counter_ns()-start
                    assert run.returncode==case['expected_exit'] and run.stdout==b'',(case['name'],mode,run.stderr)
                    omitted=b'stdout diff omitted (resource limit)' in run.stderr
                    assert omitted==case['sparse_omitted' if mode=='sparse' else 'lcs_omitted'],(case['name'],mode,run.stderr)
                    if mode=='default':default_diagnostic=run.stderr
                    if mode=='lcs':lcs_diagnostic=run.stderr
                    output.write(json.dumps({'workload':case['name'],'round':round_number,'mode':mode,'wall_ns':elapsed,
                        'max_rss_kib':int(rss.read_text().splitlines()[-1]),'exit':run.returncode,'omitted':omitted,
                        'stderr_bytes':len(run.stderr),'stderr_sha256':hashlib.sha256(run.stderr).hexdigest()})+'\n');output.flush()
                assert default_diagnostic==lcs_diagnostic,'explicit LCS must preserve default diagnostics'
assert git('rev-parse','HEAD')==source and git('status','--porcelain')=='' and digest(tool)==metadata['binary_sha256']
print(f'Retained {len(manifest["cases"])*args.rounds*3} real-command samples with stable source and binary.')

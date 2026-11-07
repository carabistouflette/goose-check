#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Real summary module plus adapter under bounded write-result fixtures."""
import argparse
import os
from pathlib import Path
import subprocess
parser=argparse.ArgumentParser();parser.add_argument('--tool',required=True);args=parser.parse_args()
tool=str(Path(args.tool).resolve())
expected=[b'\ngoose-check: matched\n',b'\ngoose-check: matched\n',b'\ngo',b'',b'\ngo']
for mode,stderr in enumerate(expected):
    result=subprocess.run([tool,str(mode)],capture_output=True,timeout=15,env={**os.environ,'TERM':'dumb','NO_COLOR':'1'})
    code=125 if mode==4 else 0
    stdout=b'' if mode==4 else b'checker outcome preserved\n'
    if result.returncode!=code or result.stdout!=stdout or result.stderr!=stderr:
        raise SystemExit((mode,result.returncode,result.stdout,result.stderr))
print('summary writes: partial offsets, interrupted retry, would-block, attempt cap, fatal cleanup pass')

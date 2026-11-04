#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Actual CLI ownership transfer through selected linker faults."""
import argparse
import os
from pathlib import Path
import signal
import tempfile
from run import owned, PYTHON, CHILD

signal.signal(signal.SIGCHLD,signal.SIG_DFL)
p=argparse.ArgumentParser()
p.add_argument('--tool',required=True)
a=p.parse_args()
tool=str(Path(a.tool).resolve())
for mode in ['prestart','transfer']:
    with tempfile.TemporaryDirectory(prefix='goose check fault ') as temporary:
        root=Path(temporary)
        marker=root/'marker'; trace=root/'trace'
        env={**os.environ,'GOOSE_CHECK_FAULT':mode,'GOOSE_CHECK_TRACE':str(trace)}
        child_mode='mark' if mode=='prestart' else 'hold'
        with owned([tool,'--',PYTHON,str(CHILD),child_mode,str(marker)],env=env) as child:
            out,err=child.communicate(timeout=10)
            expected=143 if mode=='prestart' else 125
            if child.returncode != expected or out:
                raise SystemExit((mode,child.returncode,out,err))
        events=trace.read_text().splitlines()
        if mode=='prestart':
            if marker.exists() or events!=['prestart']:
                raise SystemExit(('prestart launched a child',events))
        elif events!=['registered','clock_failure','deny_pidfd','deny_numeric',
                      'recover_begin','deny_recovery_wait','deny_recovery_wait',
                      'kill_owned','terminal','recover_end']:
            raise SystemExit(('transfer lifecycle differs',events))
        print(mode+' ownership fixture passed')

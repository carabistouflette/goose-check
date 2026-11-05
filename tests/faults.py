#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Actual CLI ownership transfer through selected linker faults."""
import argparse
import os
from pathlib import Path
import signal
import tempfile
from itertools import product
from run import owned, PYTHON, CHILD

signal.signal(signal.SIGCHLD,signal.SIG_DFL)
p=argparse.ArgumentParser()
p.add_argument('--tool',required=True)
a=p.parse_args()
tool=str(Path(a.tool).resolve())
for mode, checked in product(['prestart','transfer'], [False, True]):
    with tempfile.TemporaryDirectory(prefix='goose check fault ') as temporary:
        root=Path(temporary)
        marker=root/'marker'; trace=root/'trace'
        env={**os.environ,'GOOSE_CHECK_FAULT':mode,'GOOSE_CHECK_TRACE':str(trace)}
        child_mode='mark' if mode=='prestart' else 'hold'
        options = []
        if checked:
            expected_stderr = root / 'expected stderr'
            expected_stderr.write_bytes(b'diagnostic-ready\n')
            options = ['--stderr', str(expected_stderr)]
        with owned([tool,*options,'--',PYTHON,str(CHILD),child_mode,str(marker)],env=env) as child:
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
        print(mode+(' checked-stderr' if checked else '')+' ownership fixture passed')

# A private subreaper lets the controller recover an adopted child if the
# checker regresses and dies before its transferred-child cleanup completes.
import ctypes
import time
libc=ctypes.CDLL(None,use_errno=True)
PR_SET_CHILD_SUBREAPER=36
if libc.prctl(PR_SET_CHILD_SUBREAPER,1,0,0,0)!=0:
    raise OSError(ctypes.get_errno(),'cannot establish fault-controller subreaper')
with tempfile.TemporaryDirectory(prefix='goose check broken stderr ') as temporary:
    trace=Path(temporary)/'trace'
    env={**os.environ,'GOOSE_CHECK_FAULT':'transfer','GOOSE_CHECK_TRACE':str(trace)}
    reader,writer=os.pipe()
    os.close(reader)
    complete=False
    try:
        with owned([tool,'--','/bin/sleep','60'],env=env,stderr=writer) as child:
            os.close(writer); writer=None
            deadline=time.monotonic()+3
            while time.monotonic()<deadline:
                if trace.exists() and 'recover_end' in trace.read_text().splitlines():
                    complete=True; break
                time.sleep(.005)
            if not complete:
                # Do this before communicate/wait: the leader PID is reserved.
                try:
                    os.killpg(child.pid,signal.SIGKILL)
                except ProcessLookupError:
                    pass
            out,_=child.communicate(timeout=5)
            # The regression must prove ownership ends before the checker does.
            if complete and (child.returncode!=125 or out):
                raise SystemExit(('closed stderr status',child.returncode,out))
    finally:
        if writer is not None:
            os.close(writer)
        deadline=time.monotonic()+5
        while True:
            try:
                waited,_=os.waitpid(-1,os.WNOHANG)
            except ChildProcessError:
                break
            if waited==0:
                if time.monotonic()>=deadline:
                    raise SystemExit('fault-controller adopted child did not terminate')
                time.sleep(.005)
    if not complete:
        raise SystemExit('checker abandoned ownership when diagnostic stderr broke: '+trace.read_text())
    events=trace.read_text().splitlines()
    if events[-2:]!=['terminal','recover_end']:
        raise SystemExit(('closed stderr cleanup trace',events))
print('broken-stderr ownership fixture passed')

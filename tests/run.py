#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Binary, compiler and cancellation tests through the real Goose CLI."""
import argparse
from contextlib import contextmanager
import json
import os
from pathlib import Path
import selectors
import signal
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parent.parent
CHILD = ROOT / 'tests/child.py'
PYTHON = str(Path(sys.executable).resolve())

@contextmanager
def owned(arguments, env=None):
    p = subprocess.Popen(arguments, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                         start_new_session=True, env=env)
    try:
        yield p
    finally:
        if p.returncode is None:
            # No external reaper/poll: private leader PID remains reserved.
            try:
                os.killpg(p.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                p.communicate(timeout=3)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(p.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                p.communicate(timeout=5)
        else:
            p.communicate(timeout=5)

class Checker(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='goose check tests ')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def fixture(self, name, value):
        p = self.root/name
        p.write_bytes(value)
        return str(p)

    def run_check(self, options, command, code=0):
        with owned([TOOL, *map(str, options), '--', *map(str, command)]) as p:
            out, err = p.communicate(timeout=30)
            self.assertEqual(p.returncode, code, (p.returncode, err[:2000]))
            self.assertEqual(out, b'')
            self.assertNotIn(b'AddressSanitizer', err)
            self.assertNotIn(b'runtime error:', err)
            return err

    def child(self, *args):
        return [PYTHON, str(CHILD), *map(str, args)]

    def test_binary_and_limits(self):
        for size in [0, 1, 65536, 1048576]:
            data = (bytes(range(256))*4096)[:size]
            path = self.fixture('binary', data)
            self.run_check(['--stdin', path, '--stdout', path, '--output-limit', size], self.child('echo'))
        self.run_check([], self.child('echo'))  # Default input delivers EOF.
        path = self.fixture('exact', b'x'*4)
        self.run_check(['--stdout', path, '--output-limit', 4], self.child('output', 4))
        err = self.run_check(['--stdout', path, '--output-limit', 4], self.child('output', 5), 125)
        self.assertIn(b'OutputLimit', err)
        wrong = self.fixture('wrong', b'private-fixture-value')
        err = self.run_check(['--stdout', wrong], self.child('output', 4), 1)
        self.assertIn(b'byte 0', err)
        self.assertNotIn(b'private-fixture-value', err)

    def test_prelaunch_rejections(self):
        marker = self.root/'never-launched'
        command = self.child('mark', marker)
        for options in [['--output-limit', '-1'], ['--timeout-ms', '0'], ['--expect-exit', '256'],
                        ['--timeout-ms', '9999999999999999999999999999'], ['--output-limit', '+1'],
                        ['--expect-exit', '0', '--expect-exit', '0'], ['--unknown', '0']]:
            self.run_check(options, command, 2)
            self.assertFalse(marker.exists())
        for option, size, extra in [('--stdin',1048577,[]), ('--stdout',5,['--output-limit',4])]:
            path = self.fixture('oversized', b'x'*size)
            self.run_check([option, path, *extra], command, 125)
            self.assertFalse(marker.exists())
        target = self.fixture('regular', b'')
        link = self.root/'link'; link.symlink_to(target)
        self.run_check(['--stdin', link], command, 125)
        self.run_check(['--stdin', self.root], command, 125)
        self.assertFalse(marker.exists())
        with owned([TOOL, *command]) as p:
            _, err = p.communicate(timeout=10)
            self.assertEqual(p.returncode, 2, err)
        self.assertFalse(marker.exists())
        self.run_check([], ['relative-program'], 2)

    def test_exit_and_argument_boundaries(self):
        for code in [0, 1, 126, 127, 255]:
            self.run_check(['--expect-exit',code], self.child('exit',code))
        self.run_check([], self.child('exit',127), 1)
        self.run_check([], [self.root/'missing'], 127)
        text = Path(self.fixture('not-executable', b'not a program'))
        self.run_check([], [text], 126)
        text.chmod(0o700)
        self.run_check([], [text], 126)  # No ENOEXEC shell fallback.
        args = ['', 'with spaces', ';literal', '--flag', 'line\nbreak']
        expected = self.fixture('argv', json.dumps(args).encode())
        self.run_check(['--stdout', expected], self.child('args', *args))

    def held(self, number=None):
        marker = self.root/f'pid-{number}'
        options = ['--timeout-ms','2000' if number is None else '10000']
        with owned([TOOL,*options,'--',*self.child('hold',marker)]) as p:
            parent_fd = os.pidfd_open(p.pid)
            child_fd = None
            try:
                deadline = time.monotonic()+5
                while not marker.exists():
                    if time.monotonic() >= deadline:
                        self.fail('child readiness marker missing')
                    time.sleep(.005)
                child = int(marker.read_text())
                child_fd = os.pidfd_open(child)
                self.assertEqual(os.getsid(child),p.pid)
                # Child stderr must already be readable while it remains alive.
                with selectors.DefaultSelector() as s:
                    s.register(p.stderr,selectors.EVENT_READ)
                    self.assertTrue(s.select(3),'stderr was buffered until completion')
                live = os.read(p.stderr.fileno(),len(b'diagnostic-ready\n'))
                self.assertEqual(live,b'diagnostic-ready\n')
                signal.pidfd_send_signal(child_fd,0)
                if number is not None:
                    signal.pidfd_send_signal(parent_fd,number)
                out,err=p.communicate(timeout=6)
                self.assertEqual(out,b'')
                self.assertEqual(p.returncode,125 if number is None else 128+number,err)
                with self.assertRaises(ProcessLookupError):
                    signal.pidfd_send_signal(child_fd,0)
            finally:
                os.close(parent_fd)
                if child_fd is not None:
                    os.close(child_fd)

    def test_live_stderr_timeout_and_parent_cancellation(self):
        for number in [None,signal.SIGINT,signal.SIGTERM]:
            with self.subTest(signal=number):
                self.held(number)

    def test_real_compilers(self):
        source = self.fixture('source.c', b'#include <stdio.h>\nint main(void){int c;while((c=getchar())!=EOF)putchar(c);return 0;}\n')
        program = self.root/'compiled'
        self.run_check(['--stdin',source,'--timeout-ms',60000],[CC,'-x','c','-','-o',program])
        data=self.fixture('compiler-stdin',b'compiled\x00program\xff\n')
        self.run_check(['--stdin',data,'--stdout',data],[program])
        good=self.fixture('good.goose',b'import std; fn main(){print("compiler-ok");}\n')
        expected=self.fixture('good.stdout',b'compiler-ok\n')
        self.run_check(['--stdout',expected,'--timeout-ms',60000],[GOOSE,'run',good])
        bad=self.fixture('bad.goose',b'fn main(){unknown_function();}\n')
        self.run_check(['--expect-exit',1,'--timeout-ms',60000],[GOOSE,'check',bad])

if __name__=='__main__':
    signal.signal(signal.SIGCHLD,signal.SIG_DFL)
    a=argparse.ArgumentParser()
    a.add_argument('--tool',required=True)
    a.add_argument('--goose',required=True)
    a.add_argument('--cc',required=True)
    args,rest=a.parse_known_args()
    TOOL=str(Path(args.tool).resolve()); GOOSE=str(Path(args.goose).resolve()); CC=str(Path(args.cc).resolve())
    before=len(list(Path('/proc/self/fd').iterdir()))
    result=unittest.main(argv=[sys.argv[0],*rest],exit=False).result
    if len(list(Path('/proc/self/fd').iterdir())) != before:
        raise SystemExit('controller descriptor leak')
    try:
        os.waitpid(-1,os.WNOHANG)
    except ChildProcessError:
        pass
    else:
        raise SystemExit('controller retains a child')
    raise SystemExit(not result.wasSuccessful())

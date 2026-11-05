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
def owned(arguments, env=None, stderr=subprocess.PIPE):
    p = subprocess.Popen(arguments, stdout=subprocess.PIPE, stderr=stderr,
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
        self.root = Path(self.temp.name).resolve()

    def fixture(self, name, value):
        p = self.root/name
        p.write_bytes(value)
        return str(p)

    def run_check(self, options, command, code=0, env=None):
        with owned([TOOL, *map(str, options), '--', *map(str, command)], env=env) as p:
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
        args = ['', 'with spaces', ';literal', '--flag', 'line\nbreak', os.fsdecode(b'\xff')]
        expected = self.fixture('argv', json.dumps(args).encode())
        self.run_check(['--stdout', expected], self.child('args', *args))

    def test_streamed_stderr_binary_and_limits(self):
        for size in [0, 1, 8191, 8192, 8193, 65536, 1048576]:
            data = (bytes(range(256)) * 4096)[:size]
            oracle = self.fixture('stderr binary', data)
            self.assertEqual(self.run_check(['--stderr', oracle, '--output-limit', size], self.child('stderr', size)), b'')
        oracle = self.fixture('three', bytes(range(3)))
        for actual, offset in [(2, 2), (4, 3)]:
            err = self.run_check(['--stderr', oracle], self.child('stderr', actual), 1)
            self.assertIn(f'stderr mismatch at byte {offset}'.encode(), err)
        oracle = self.fixture('secret stderr', b'PRIVATE_STDERR_FIXTURE')
        err = self.run_check(['--stderr', oracle], self.child('stderr', 2), 1)
        self.assertNotIn(b'PRIVATE_STDERR_FIXTURE', err)
        for limit in [0, 8192, 65536]:
            oracle = self.fixture('bounded stderr', (bytes(range(256)) * 4096)[:limit])
            err = self.run_check(['--stderr', oracle, '--output-limit', limit], self.child('stderr', limit + 1), 125)
            self.assertIn(b'OutputLimit', err)
        payload = bytes(range(256)) * 256
        stdin = self.fixture('stdin', payload)
        stdout = self.fixture('stdout', payload + payload)
        stderr = self.fixture('stderr', payload)
        self.assertEqual(self.run_check(['--stdin', stdin, '--stdout', stdout, '--stderr', stderr,
                                        '--output-limit', 131072], self.child('dual', 65536)), b'')
        self.run_check(['--stdout', stderr, '--stderr', stderr, '--output-limit', 65536], self.child('dual', 65536))

    def test_streamed_stderr_prelaunch_and_precedence(self):
        marker = self.root / 'not-launched-stderr'
        command = self.child('mark', marker)
        empty = self.fixture('empty stderr', b'')
        for options, code in [(['--stderr', 'relative'], 2), (['--stderr', empty, '--stderr', empty], 2),
                              (['--stderr', self.root / 'missing'], 125), (['--stderr', self.root], 125)]:
            self.run_check(options, command, code); self.assertFalse(marker.exists())
        link = self.root / 'stderr-link'; link.symlink_to(empty)
        self.run_check(['--stderr', link], command, 125); self.assertFalse(marker.exists())
        big = self.fixture('oversized stderr', b'12345')
        self.run_check(['--stderr', big, '--output-limit', 4], command, 125)
        self.assertFalse(marker.exists())
        for extension, content in [('toml', b'output_limit=0\n'), ('json', b'{"output_limit":0}')]:
            config = self.fixture('stderr limits.' + extension, content)
            expected = self.fixture('stderr four', bytes(range(4)))
            for options in [['--config', config, '--output-limit', 4], ['--output-limit', 4, '--config', config]]:
                self.run_check([*options, '--stderr', expected], self.child('stderr', 4))
        err = self.run_check(['--stderr', big], self.child('exit', 7), 1)
        self.assertIn(b'exit mismatch', err); self.assertNotIn(b'stderr mismatch', err)
        err = self.run_check(['--stderr', big], self.child('output', 1), 1)
        self.assertIn(b'stdout mismatch', err); self.assertNotIn(b'stderr mismatch', err)
        self.run_check(['--stderr', empty, '--expect-exit', 7], self.child('exit', 7))

    def test_configured_defaults_precedence_and_fresh_reads(self):
        for extension, document in [('json', b'{"expect_exit":7,"output_limit":0,"timeout_ms":30000}'),
                                    ('toml', b'expect_exit=7\noutput_limit=0\ntimeout_ms=30000\n')]:
            path = self.fixture('settings with spaces.' + extension, document)
            self.run_check(['--config', path], self.child('exit', 7))
            for options in [['--expect-exit', '0', '--config', path],
                            ['--config', path, '--expect-exit', '0'],
                            ['--config', path, '--expect-exit', '0' * 512]]:
                self.run_check(options, ['/bin/true'])
            # File layers are replayed per invocation; removed keys use defaults.
            Path(path).write_bytes(b'{}' if extension == 'json' else b'')
            self.run_check(['--config', path], ['/bin/true'])
            self.run_check(['--config', path], self.child('exit', 7), 1)
            Path(path).unlink()
            self.run_check(['--config', path], ['/bin/true'], 125)
        # Environment does not select a file or configure any checker setting.
        self.run_check([], ['/bin/true'], env=dict(os.environ,
                       GOOSE_CHECK_CONFIG='/private/missing.toml', GOOSE_CHECK_EXPECT_EXIT='7'))
        # Nonzero long CLI tokens and both orders for the other two settings.
        path = self.fixture('precedence.json', b'{"timeout_ms":1,"output_limit":0}')
        expected = self.fixture('precedence.stdout', b'xxxx')
        numeric = ['--timeout-ms', '0' * 512 + '30000', '--output-limit', '0' * 512 + '4']
        for options in [numeric + ['--config', path], ['--config', path] + numeric]:
            self.run_check(options + ['--stdout', expected], self.child('output', 4))
            # This command outlives the file's 1ms budget if its CLI override is lost.
            self.run_check(options, [PYTHON, '-c', 'import time; time.sleep(.05)'])

    def test_invalid_config_never_launches(self):
        marker = self.root/'config-must-not-launch'
        documents = [
            ('json', b'{"timeout_ms":0}'), ('json', b'{"timeout_ms":86400001}'),
            ('json', b'{"output_limit":-1}'), ('json', b'{"output_limit":1048577}'),
            ('json', b'{"expect_exit":256}'), ('json', b'{"expect_exit":false}'),
            ('json', b'{"expect_exit":1.0}'), ('json', b'{"expect_exit":1e0}'),
            ('json', b'{"timeout_ms":"SECRET_CONFIG_VALUE"}'),
            ('json', b'{"SECRET_CONFIG_KEY":1}'), ('json', b'{"command":"SECRET_CONFIG_VALUE"}'),
            ('json', b'{"expect_exit":0,"expect_exit":1}'),
            ('json', b'{"expect_exit":0,"expect_\\u0065xit":1}'),
            ('json', b'{"timeout_ms":[]}'), ('json', b'{"unused":{}}'),
            ('json', b'[]'), ('json', b'{'),
            ('toml', b'timeout_ms=0'), ('toml', b'expect_exit=1.0'),
            ('toml', b'output_limit=true'), ('toml', b'output_limit=[]'),
            ('toml', b'expect_exit=0\nexpect_exit=1'),
            ('toml', b'SECRET_CONFIG_KEY="SECRET_CONFIG_VALUE"'),
            ('toml', b'expect_exit=['),
        ]
        for extension, document in documents:
            path = self.fixture('invalid.' + extension, document)
            err = self.run_check(['--config', path, '--timeout-ms', '30000', '--expect-exit', '0',
                                  '--output-limit', '0'], self.child('mark', marker), 2)
            self.assertNotIn(b'SECRET_CONFIG', err)
            self.assertFalse(marker.exists())
        path = self.fixture('valid.json', b'{}')
        for options in [['--config', path, '--config', path], ['--config', 'relative.toml'],
                        ['--config', self.root/'settings.yaml'], ['--config', ''],
                        ['--config', path, '--expect-exit', '+0']]:
            self.run_check(options, self.child('mark', marker), 2)
            self.assertFalse(marker.exists())
        link = self.root/'link.json'; link.symlink_to(path)
        for path in [link, self.root/'directory.json', self.root/'missing.json']:
            if path.name == 'directory.json':
                path.mkdir()
            self.run_check(['--config', path], self.child('mark', marker), 125)
            self.assertFalse(marker.exists())

    def test_configured_file_and_process_limits(self):
        for extension, document in [('json', b'{"expect_exit":0,"output_limit":0,"timeout_ms":86400000}'),
                                    ('toml', b'expect_exit=0\noutput_limit=0\ntimeout_ms=86400000\n')]:
            exact = document + b' ' * (65536 - len(document))
            path = self.fixture('exact.' + extension, exact)
            self.run_check(['--config', path], ['/bin/true'])
            marker = self.root/'oversize-config-must-not-launch'
            Path(path).write_bytes(exact + b' ')
            self.run_check(['--config', path], self.child('mark', marker), 125)
            self.assertFalse(marker.exists())
        path = self.fixture('limits.toml', b'output_limit=4\ntimeout_ms=30000\n')
        expected = self.fixture('four', b'xxxx')
        self.run_check(['--config', path, '--stdout', expected], self.child('output', 4))
        self.run_check(['--config', path], self.child('output', 5), 125)
        too_big = self.fixture('five', b'xxxxx')
        marker = self.root/'expected-fixture-must-not-launch'
        self.run_check(['--config', path, '--stdout', too_big], self.child('mark', marker), 125)
        self.assertFalse(marker.exists())
        self.run_check(['--config', path, '--stdout', too_big, '--output-limit', '5'], self.child('output', 5))
        # Use the same observable live-child/reaping test under a configured budget.
        self.held(configured=True)

    def test_numeric_and_argument_limits(self):
        marker = self.root/'not-launched'
        for option, value in [('--expect-exit',''), ('--expect-exit','-0'),
                              ('--timeout-ms','86400001'), ('--output-limit','1048577'),
                              ('--timeout-ms','1_000'), ('--expect-exit',' 0'),
                              ('--expect-exit','\u0660')]:
            self.run_check([option,value],self.child('mark',marker),2)
            self.assertFalse(marker.exists())
        self.run_check(['--expect-exit','000127'],self.child('exit',127))
        self.run_check(['--output-limit','0000'],['/bin/true'])
        self.run_check([],['/bin/true',*(['']*4095)])
        self.run_check([],self.child('mark',marker)+['']*4093,2)
        self.assertFalse(marker.exists())
        # Only exercise this CLI bound when the kernel can launch the checker
        # itself with the larger argument set (an independent, smaller limit).
        if os.sysconf('SC_ARG_MAX') > 1250000:
            self.run_check([],self.child('mark',marker)+['a'*131000]*9,2)
            self.assertFalse(marker.exists())

    def test_broken_diagnostic_stderr(self):
        for arguments, code in [(['--bad'],2), (['--','/no/such/goose-check-command'],127),
                                (['--',*self.child('output',1)],1)]:
            reader, writer = os.pipe()
            os.close(reader)
            try:
                with owned([TOOL,*arguments],stderr=writer) as p:
                    os.close(writer); writer=None
                    out,_=p.communicate(timeout=10)
                    self.assertEqual((p.returncode,out),(code,b''))
            finally:
                if writer is not None:
                    os.close(writer)

    def held(self, number=None, configured=False, checked=False):
        marker = self.root/f'pid-{number}'
        options = ['--timeout-ms','2000' if number is None else '10000']
        if configured:
            path = self.fixture('deadline.toml', b'timeout_ms=2000\n')
            options = ['--config', path]
        if checked:
            options += ['--stderr', self.fixture('checked diagnostics', b'diagnostic-ready\n')]
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
                if not checked:
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
                if checked:
                    self.assertNotIn(b'diagnostic-ready', err)
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

    def test_checked_stderr_timeout_and_parent_cancellation(self):
        for number in [None, signal.SIGINT, signal.SIGTERM]:
            with self.subTest(signal=number):
                self.held(number, checked=True)

    def test_real_compilers(self):
        source = str(ROOT / 'examples/echo.c')
        program = self.root/'compiled'
        self.run_check(['--stdin',source,'--timeout-ms',60000],[CC,'-x','c','-','-o',program])
        data=self.fixture('compiler-stdin',b'compiled\x00program\xff\n')
        self.run_check(['--stdin',data,'--stdout',data],[program])
        good=self.fixture('good.goose',b'import std; fn main(){print("compiler-ok");}\n')
        expected=self.fixture('good.stdout',b'compiler-ok\n')
        self.run_check(['--stdout',expected,'--timeout-ms',60000],[GOOSE,'run',good])
        bad=self.fixture('bad.goose',b'fn main(){unknown_function();}\n')
        self.run_check(['--expect-exit',1,'--timeout-ms',60000],[GOOSE,'check',bad])
        defaults=self.fixture('compiler-defaults.toml',b'timeout_ms=60000\noutput_limit=4096\n')
        self.run_check(['--config',defaults,'--stdout',expected],[GOOSE,'run',good])
        Path(defaults).write_bytes(b'timeout_ms=60000\noutput_limit=4096\nexpect_exit=1\n')
        self.run_check(['--config',defaults],[GOOSE,'check',bad])

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

#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Real checker result summaries after direct-child cleanup."""
import argparse
import errno
import fcntl
import os
from pathlib import Path
import pty
import select
import signal
import struct
import subprocess
import sys
import tempfile
import termios
import time
import unittest

ROOT=Path(__file__).resolve().parents[1]
PYTHON=str(Path(sys.executable).resolve())
ENV={**os.environ,'TERM':'xterm-256color','NO_COLOR':''}

class Summary(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(prefix='checker-summary-');self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name)
    def check(self,options=(),command=('/bin/true',),env=None):
        return subprocess.run([TOOL,*map(str,options),'--',*map(str,command)],capture_output=True,env={**ENV,**(env or {})},timeout=15)
    def test_quiet_default_never_and_auto_redirect(self):
        for options in ((),('--summary','never'),('--summary','auto')):
            result=self.check(options);self.assertEqual((result.returncode,result.stdout,result.stderr),(0,b'',b''))
    def test_redirected_match_and_expected_nonzero(self):
        for options,command in (([],['/bin/true']),(['--expect-exit','7'],[PYTHON,'-c','raise SystemExit(7)'])):
            result=self.check(['--summary','always',*options],command)
            self.assertEqual((result.returncode,result.stdout,result.stderr),(0,b'',b'\ngoose-check: matched\n'))
    def test_checker_verdict_not_child_exit_is_summarized(self):
        result=self.check(['--summary','always'],[PYTHON,'-c','raise SystemExit(7)'])
        self.assertEqual(result.returncode,1);self.assertEqual(result.stdout,b'')
        self.assertIn(b'exit mismatch',result.stderr);self.assertTrue(result.stderr.endswith(b'\ngoose-check: check failed\n'))
        result=self.check(['--summary','always'],['/missing/checker-program'])
        self.assertEqual(result.returncode,127);self.assertTrue(result.stderr.endswith(b'\ngoose-check: check failed\n'))
    def test_checked_stream_and_unterminated_live_diagnostics(self):
        code='import os;os.write(2,b"unterminated diagnostic")'
        result=self.check(['--summary','always'],[PYTHON,'-c',code])
        self.assertEqual(result.stderr,b'unterminated diagnostic\ngoose-check: matched\n')
        path=self.root/'expected';path.write_bytes(b'unterminated diagnostic')
        result=self.check(['--summary','always','--stderr',path],[PYTHON,'-c',code])
        self.assertEqual(result.returncode,0);self.assertEqual(result.stderr,b'\ngoose-check: matched\n')
    def terminal(self,env=None):
        master,slave=pty.openpty();attrs=termios.tcgetattr(slave);attrs[1]&=~termios.OPOST;termios.tcsetattr(slave,termios.TCSANOW,attrs)
        fcntl.ioctl(slave,termios.TIOCSWINSZ,struct.pack('HHHH',24,80,0,0));proc=None;output=bytearray()
        try:
            proc=subprocess.Popen([TOOL,'--summary','auto','--','/bin/true'],stdout=subprocess.PIPE,stderr=slave,env={**ENV,**(env or {})});os.close(slave);slave=-1
            deadline=time.monotonic()+15
            while time.monotonic()<deadline:
                if select.select([master],[],[],.1)[0]:
                    try: data=os.read(master,65536)
                    except OSError as error:
                        if error.errno==errno.EIO: break
                        raise
                    if not data: break
                    output.extend(data)
            stdout,_=proc.communicate(timeout=2);self.assertEqual((proc.returncode,stdout),(0,b''));return bytes(output)
        finally:
            if proc and proc.poll() is None: proc.kill();proc.communicate()
            os.close(master)
            if slave>=0: os.close(slave)
    def test_terminal_color_and_environment_policies(self):
        self.assertEqual(self.terminal(),b'\n\x1b[32mgoose-check: matched\x1b[0m\n')
        for env in ({'TERM':'dumb'},{'NO_COLOR':'1'},{'TERM':''}):
            self.assertEqual(self.terminal(env),b'\ngoose-check: matched\n')
    def test_bad_option_values_fail_before_launch(self):
        marker=self.root/'launched'
        for options in (['--summary','yes'],['--summary','always','--summary','never'],['--summary']):
            result=self.check(options,[PYTHON,'-c',f'from pathlib import Path;Path({str(marker)!r}).touch()'])
            self.assertEqual(result.returncode,2);self.assertFalse(marker.exists());self.assertNotIn(b'matched',result.stderr)
    def test_broken_summary_sink_preserves_success(self):
        read,write=os.pipe();os.close(read)
        try:
            result=subprocess.run([TOOL,'--summary','always','--','/bin/true'],stdout=subprocess.PIPE,stderr=write,env=ENV,timeout=10)
            self.assertEqual((result.returncode,result.stdout),(0,b''))
        finally: os.close(write)
    def test_parent_cancellation_has_no_completion_summary(self):
        marker=self.root/'ready';proc=subprocess.Popen([TOOL,'--summary','always','--',PYTHON,str(ROOT/'tests/child.py'),'hold',str(marker)],stdout=subprocess.PIPE,stderr=subprocess.PIPE,env=ENV,start_new_session=True)
        pidfd=None
        try:
            deadline=time.monotonic()+10
            while not marker.exists():
                if time.monotonic()>deadline: self.fail('child readiness timeout')
                time.sleep(.005)
            pidfd=os.pidfd_open(int(marker.read_text()))
            proc.send_signal(signal.SIGINT);stdout,stderr=proc.communicate(timeout=10)
            self.assertEqual((proc.returncode,stdout),(130,b''));self.assertNotIn(b'goose-check: matched',stderr);self.assertNotIn(b'goose-check: check failed',stderr)
            self.assertTrue(select.select([pidfd],[],[],0)[0])
        finally:
            if proc.poll() is None: os.killpg(proc.pid,signal.SIGKILL);proc.communicate()
            if pidfd is not None: os.close(pidfd)

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--tool',required=True);args,rest=parser.parse_known_args();TOOL=str(Path(args.tool).resolve())
    unittest.main(argv=[sys.argv[0],*rest])

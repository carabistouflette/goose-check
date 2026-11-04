#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Create a content-addressed compiler identity for native cache correctness."""
import argparse
import hashlib
from pathlib import Path
import shutil

root = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--cc', required=True)
parser.add_argument('--sanitize', action='store_true')
parser.add_argument('--faults', action='store_true')
a = parser.parse_args()
found = shutil.which(a.cc)
if not found:
    parser.error('compiler executable not found')
compiler = Path(found).resolve()
extra = []
if a.sanitize:
    extra = ['-fsanitize=address,undefined', '-fno-omit-frame-pointer', '-O1', '-g', '-U_FORTIFY_SOURCE', '-D_FORTIFY_SOURCE=3']
link = ['-no-pie'] if a.sanitize else []
if a.faults:
    source = (root/'tests/faults.c').read_bytes()
    frozen = root / '.build' / ('faults-' + hashlib.sha256(source).hexdigest() + '.c')
    frozen.parent.mkdir(exist_ok=True)
    frozen.write_bytes(source)
    link += [str(frozen), '-Wl,--wrap=syscall,--wrap=kill,--wrap=waitpid,--wrap=clock_gettime,--wrap=gc_recover,--wrap=gc_guard_begin']
body = ('#!/usr/bin/env python3\nimport os,sys\n'
        f'compiler={str(compiler)!r}\nextra={extra!r}\nlink={link!r}\n'
        'args=sys.argv[1:]\n'
        'if "--version" not in args:\n'
        '    args=extra+args+(link if "-c" not in args else [])\n'
        'os.execv(compiler,[compiler]+args)\n')
# Goose identifies CC by its path/style/version. Wrapper contents/environment
# alone are insufficient: freeze compiler, instrumentation and fixture identities.
digest = hashlib.sha256(Path(__file__).read_bytes()+compiler.read_bytes()+body.encode()).hexdigest()
path = root / '.build' / ('cc-' + digest + '.py')
path.parent.mkdir(exist_ok=True)
path.write_text(body)
path.chmod(0o700)
print(path)

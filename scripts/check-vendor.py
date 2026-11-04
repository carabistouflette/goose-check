#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Verify bundled source bytes against the reviewed dependency inventory."""
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parent.parent / 'vendor'
pins = json.loads((root / 'pins.json').read_text())
expected = {'pins.json'}
for name, entry in pins.items():
    revision = entry['revision']
    if len(revision) != 40 or any(c not in '0123456789abcdef' for c in revision):
        raise SystemExit(f'invalid pinned revision: {name}')
    for path, digest in entry['sha256'].items():
        relative = Path(name) / path
        if relative.is_absolute() or '..' in relative.parts:
            raise SystemExit('unsafe inventory path')
        actual = root / relative
        if actual.is_symlink() or not actual.is_file() or hashlib.sha256(actual.read_bytes()).hexdigest() != digest:
            raise SystemExit(f'vendored source mismatch: {relative}')
        expected.add(relative.as_posix())
actual = {p.relative_to(root).as_posix() for p in root.rglob('*') if p.is_file() or p.is_symlink()}
if actual != expected:
    raise SystemExit(f'vendor inventory differs: {sorted(actual ^ expected)}')
print('vendored source identities match pinned inventory')

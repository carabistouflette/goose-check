#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Trusted child modes for the standalone CLI integration tests."""
import os
from pathlib import Path
import signal
import sys
import time

mode = sys.argv[1]
if mode == 'echo':
    while chunk := os.read(0, 16384):
        sys.stdout.buffer.write(chunk)
    sys.stdout.buffer.flush()
elif mode == 'output':
    sys.stdout.buffer.write(b'x' * int(sys.argv[2]))
elif mode == 'stderr':
    size = int(sys.argv[2])
    sys.stderr.buffer.write((bytes(range(256)) * 4096)[:size])
elif mode == 'dual':
    remaining = int(sys.argv[2])
    data = bytes(range(256)) * 64
    while remaining:
        chunk = data[:min(remaining, len(data))]
        sys.stdout.buffer.write(chunk); sys.stdout.buffer.flush()
        sys.stderr.buffer.write(chunk); sys.stderr.buffer.flush()
        remaining -= len(chunk)
    while chunk := os.read(0, 16384):
        sys.stdout.buffer.write(chunk)
    sys.stdout.buffer.flush()
elif mode == 'exit':
    raise SystemExit(int(sys.argv[2]))
elif mode == 'args':
    import json
    sys.stdout.write(json.dumps(sys.argv[2:]))
elif mode == 'mark':
    Path(sys.argv[2]).write_text('launched')
elif mode == 'hold':
    signal.signal(signal.SIGINT, lambda *_: sys.exit(0))
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    os.write(2, b'diagnostic-ready\n')
    marker = Path(sys.argv[2])
    temporary = marker.with_name(marker.name + '.ready')
    temporary.write_text(str(os.getpid()))
    temporary.replace(marker)
    time.sleep(60)
else:
    raise SystemExit(99)

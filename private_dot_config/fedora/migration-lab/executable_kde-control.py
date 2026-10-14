#!/usr/bin/env python3
"""Private QMP console: screenshots, status, keystrokes, and stdin text (no logging)."""
import argparse
import json
import os
from pathlib import Path
import socket
import sys
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('action', choices=['status', 'screenshot', 'key', 'text', 'serial', 'shutdown'])
parser.add_argument('key', nargs='?')
args = parser.parse_args()
lab = Path(os.environ.get('XDG_DATA_HOME', str(Path.home() / '.local/share'))) / 'fedora-kde-rehearsal'
if args.action == 'serial':
    with socket.socket(socket.AF_UNIX) as serial:
        serial.connect(str(lab / 'run/serial.sock'))
        # Pace UART input and keep the connection open until QEMU consumes it.
        serial.settimeout(1)
        for byte in sys.stdin.buffer.read():
            serial.sendall(bytes([byte]))
            time.sleep(0.05)
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            try:
                if not serial.recv(8192):
                    break
            except socket.timeout:
                pass
    raise SystemExit(0)
with socket.socket(socket.AF_UNIX) as conn:
    conn.settimeout(20)
    conn.connect(str(lab / 'run/qmp.sock'))
    stream = conn.makefile('rwb', buffering=0)
    json.loads(stream.readline())
    def call(name, arguments=None):
        request = {'execute': name}
        if arguments is not None:
            request['arguments'] = arguments
        stream.write(json.dumps(request).encode() + b'\n')
        while True:
            result = json.loads(stream.readline())
            if 'error' in result:
                raise RuntimeError(result['error'])
            if 'return' in result:
                return result['return']
    call('qmp_capabilities')
    def key(code):
        call('human-monitor-command', {'command-line': f'sendkey {code} 1'})
        time.sleep(0.03)
    if args.action == 'key':
        if not args.key or any(c not in 'abcdefghijklmnopqrstuvwxyz0123456789_-' for c in args.key):
            parser.error('A QEMU key chord is required')
        key(args.key)
    elif args.action == 'text':
        codes = {' ': 'spc', '\n': 'ret', '/': 'slash', '.': 'dot', '-': 'minus', '_': 'shift-minus',
                 ':': 'shift-semicolon', ';': 'semicolon', "'": 'apostrophe', '"': 'shift-apostrophe',
                 '=': 'equal', '+': 'shift-equal', '$': 'shift-4', '|': 'shift-backslash',
                 '>': 'shift-dot', '<': 'shift-comma', '\\': 'backslash', '?': 'shift-slash',
                 '(': 'shift-9', ')': 'shift-0', '&': 'shift-7', '!': 'shift-1', '@': 'shift-2',
                 '[': 'bracket_left', ']': 'bracket_right', ',': 'comma', '~': 'shift-grave_accent'}
        value = sys.stdin.read()
        for c in value:
            if c in codes:
                key(codes[c])
            elif c.isascii() and c.isalnum():
                key(('shift-' if c.isupper() else '') + c.lower())
            else:
                raise ValueError('Unsupported character for private console')
    elif args.action == 'screenshot':
        path = lab / 'run/screenshot.ppm'
        call('screendump', {'filename': str(path)})
        print(path)
    elif args.action == 'shutdown':
        call('system_powerdown')
    else:
        print(json.dumps(call('query-status')))

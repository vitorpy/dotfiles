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
parser.add_argument('action', choices=['status', 'screenshot', 'key', 'text', 'serial', 'click', 'shutdown'])
parser.add_argument('key', nargs='?')
parser.add_argument('--cloud', action='store_true', help='Control the separate Cloud baseline instead')
args = parser.parse_args()
lab = Path(os.environ.get('XDG_DATA_HOME', str(Path.home() / '.local/share'))) / ('fedora-migration-lab' if args.cloud else 'fedora-kde-rehearsal')
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
        call('human-monitor-command', {'command-line': f'sendkey {code} 50'})
        time.sleep(0.15)
    if args.action == 'click':
        for device in call('query-mice'):
            if device['absolute'] and 'tablet' in device['name'].lower():
                call('human-monitor-command', {'command-line': f"mouse_set {device['index']}"})
                break
        x, y = (int(value) for value in args.key.split(','))
        capture = lab / 'run/input-size.ppm'
        call('screendump', {'filename': str(capture)})
        with capture.open('rb') as screen:
            if screen.readline().strip() != b'P6':
                raise RuntimeError('Unexpected screenshot format')
            width, height = map(int, screen.readline().split())
        capture.unlink()
        if not (0 <= x < width and 0 <= y < height):
            raise ValueError('Click is outside the current VM screen')
        call('input-send-event', {'events': [
            {'type': 'abs', 'data': {'axis': 'x', 'value': round(x * 32767 / (width - 1))}},
            {'type': 'abs', 'data': {'axis': 'y', 'value': round(y * 32767 / (height - 1))}}]})
        time.sleep(0.08)
        call('input-send-event', {'events': [{'type': 'btn', 'data': {'button': 'left', 'down': True}}]})
        time.sleep(0.08)
        call('input-send-event', {'events': [{'type': 'btn', 'data': {'button': 'left', 'down': False}}]})
    elif args.action == 'key':
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

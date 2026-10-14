#!/usr/bin/env python3
"""Interactive VM portal probe: opens a file dialog or a temporary screen-share chooser.

Run as the desktop user with its session bus. Select only the VM fixture/display.
A screen-share probe closes its session immediately after verifying the PipeWire FD.
"""
import argparse
import os
import struct
import subprocess
from pathlib import Path
import uuid
import gi

gi.require_version('Gio', '2.0')
from gi.repository import Gio, GLib

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('action', choices=['file', 'screencast'])
args = parser.parse_args()
bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
destination = 'org.freedesktop.portal.Desktop'
path = '/org/freedesktop/portal/desktop'


def request(interface, method, signature, arguments, options):
    token = 'migration_' + uuid.uuid4().hex
    options['handle_token'] = GLib.Variant('s', token)
    sender = bus.get_unique_name()[1:].replace('.', '_')
    expected = '/org/freedesktop/portal/desktop/request/' + sender + '/' + token
    loop = GLib.MainLoop()
    result = []
    def response(connection, sender, object_path, interface_name, signal_name, parameters):
        result.append(parameters.unpack())
        loop.quit()
    subscription = bus.signal_subscribe(destination, 'org.freedesktop.portal.Request', 'Response', expected,
                                        None, Gio.DBusSignalFlags.NONE, response)
    timer = GLib.timeout_add_seconds(180, lambda: (loop.quit(), False)[1])
    try:
        reply = bus.call_sync(destination, path, interface, method,
                              GLib.Variant(signature, (*arguments, options)), None,
                              Gio.DBusCallFlags.NONE, 15000, None).unpack()[0]
        if reply != expected:
            raise RuntimeError('Portal returned an unexpected request path')
        print(method + ': waiting for VM dialog response', flush=True)
        loop.run()
        if not result:
            raise RuntimeError('Portal request timed out')
        code, values = result[0]
        if code != 0:
            raise RuntimeError(method + ' returned response ' + str(code))
        return values
    finally:
        if GLib.MainContext.default().find_source_by_id(timer):
            GLib.source_remove(timer)
        bus.signal_unsubscribe(subscription)

if args.action == 'file':
    fixture = Path.home() / 'Documents/portal-smoke.txt'
    fixture.parent.mkdir(exist_ok=True)
    fixture.write_text('Public VM portal fixture\n')
    result = request('org.freedesktop.portal.FileChooser', 'OpenFile', '(ssa{sv})',
                     ('', 'Fedora migration portal test'),
                     {'current_file': GLib.Variant('ay', os.fsencode(fixture) + b'\0')})
    if result.get('uris') != [fixture.as_uri()]:
        raise SystemExit('The selected file was not the VM fixture')
    print('File chooser: selected VM fixture successfully', flush=True)
else:
    session = request('org.freedesktop.portal.ScreenCast', 'CreateSession', '(a{sv})', (),
                      {'session_handle_token': GLib.Variant('s', 'migration_' + uuid.uuid4().hex)})['session_handle']
    try:
        request('org.freedesktop.portal.ScreenCast', 'SelectSources', '(oa{sv})', (session,),
                {'types': GLib.Variant('u', 1), 'multiple': GLib.Variant('b', False),
                 'cursor_mode': GLib.Variant('u', 1), 'persist_mode': GLib.Variant('u', 0)})
        result = request('org.freedesktop.portal.ScreenCast', 'Start', '(osa{sv})', (session, ''), {})
        streams = result.get('streams', [])
        if not streams:
            raise RuntimeError('ScreenCast returned no streams')
        reply, descriptors = bus.call_with_unix_fd_list_sync(destination, path, 'org.freedesktop.portal.ScreenCast',
                        'OpenPipeWireRemote', GLib.Variant('(oa{sv})', (session, {})), None,
                        Gio.DBusCallFlags.NONE, 15000, None, None)
        fd = descriptors.get(reply.unpack()[0])
        os.fstat(fd)
        capture_dir = Path.home() / '.local/state/fedora-migration-lab'
        capture_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
        capture = capture_dir / 'portal-frame.png'
        try:
            subprocess.run(['gst-launch-1.0', '-q', 'pipewiresrc', 'fd=' + str(fd),
                            'path=' + str(streams[0][0]), 'num-buffers=1', '!', 'videoconvert',
                            '!', 'pngenc', '!', 'filesink', 'location=' + str(capture)],
                           check=True, timeout=30, pass_fds=(fd,), capture_output=True)
        except subprocess.CalledProcessError as error:
            (capture_dir / 'portal-capture.log').write_bytes(error.stderr)
            raise RuntimeError('Frame capture failed: ' + error.stderr.decode(errors='replace')) from error
        finally:
            os.close(fd)
        header = capture.read_bytes()[:24]
        if header[:8] != b'\x89PNG\r\n\x1a\n' or not all(struct.unpack('>II', header[16:24])):
            raise RuntimeError('Captured frame is not a valid nonempty PNG')
        print('ScreenCast: captured a VM frame through the portal PipeWire FD; closing session', flush=True)
    finally:
        bus.call_sync(destination, session, 'org.freedesktop.portal.Session', 'Close', None, None,
                      Gio.DBusCallFlags.NONE, 5000, None)

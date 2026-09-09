#!/usr/bin/env python3
"""Exercise semantic native UI control against only a disposable inbox."""
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parent.parent
BIN = ROOT / 'dist/AgentNotify.app/Contents/MacOS/AgentNotify'
checks = 0


def check(value, message):
    global checks
    assert value, message
    checks += 1


with tempfile.TemporaryDirectory(prefix='an-ui-', dir='/tmp') as tmp:
    env = {**os.environ, 'AGENTNOTIFY_STATE_DIR': tmp, 'AGENTNOTIFY_NO_LAUNCH': '1'}
    process = None

    def wait_socket(present=True):
        deadline = time.monotonic() + 8
        path = Path(tmp, 'notify.sock')
        while time.monotonic() < deadline:
            if path.exists() == present:
                return
            if process is not None and process.poll() is not None:
                raise AssertionError(process.stderr.read())
            time.sleep(.05)
        raise AssertionError('Interface service socket did not reach the expected state')

    def api(method, params=None):
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
            connection.settimeout(8)
            connection.connect(str(Path(tmp, 'notify.sock')))
            connection.sendall((json.dumps({'id': 'ui-test', 'method': method, 'params': params or {}}) + '\n').encode())
            result = json.loads(connection.makefile('r').readline())
            check(result.get('id') == 'ui-test', 'socket response identity')
            return result

    def ok(method, params=None):
        result = api(method, params)
        check(result['ok'], result)
        return result['data']

    try:
        # Handle the one-time shim offer headlessly so native UI checks never
        # open an unrelated setup sheet.
        process = subprocess.Popen([str(BIN), 'serve'], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        wait_socket()
        ok('dismissShimSetup')
        process.terminate(); process.communicate(timeout=8); wait_socket(False)

        process = subprocess.Popen([str(BIN), 'app'], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        wait_socket()
        initial = ok('uiState')
        check(initial['surface'] == 'hidden' and not initial['inbox']['visible'], 'native UI starts hidden')
        first = ok('send', {'title': 'Alpha build', 'message': 'First UI task', 'group': 'ui-alpha'})
        second = ok('send', {'title': 'Beta review', 'message': 'Second UI task', 'group': 'ui-beta'})
        deadline = time.monotonic() + 5
        arrival = None
        while time.monotonic() < deadline:
            arrival = ok('uiState')['arrival']
            if arrival['visible']:
                break
            time.sleep(.05)
        check(arrival and arrival['visible'], 'custom arrival is represented in UI state')
        ok('uiDismissArrival', {'id': arrival['id'], 'requestId': 'dismiss-arrival'})
        check(not ok('uiState')['arrival']['visible'], 'custom arrival dismisses without durable mutation')

        shown = ok('uiShow', {'surface': 'inbox', 'requestId': 'show-inbox'})
        check(shown['surface'] == 'inbox' and shown['inbox']['visible'], 'MCP/API shows native inbox')
        filtered = ok('uiSetView', {'filter': 'unread', 'query': 'Alpha', 'id': first['id'], 'details': 'expand', 'requestId': 'filter-alpha'})
        check(filtered['matchingCount'] == 1 and filtered['selection']['id'] == first['id'], 'search, filter, and exact selection apply together')
        check(ok('get', {'id': first['id']}).get('readAt') is None, 'interface selection does not imply reading')
        all_view = ok('uiSetView', {'filter': 'inbox', 'query': '', 'group': '', 'period': 'any', 'id': '', 'requestId': 'clear-view'})
        navigated = ok('uiNavigate', {'direction': 'first', 'requestId': 'first-row'})
        check(navigated['selection']['position'] == 1 and all_view['matchingCount'] == 2, 'semantic navigation follows current view order')

        records = ok('list', {'filter': 'inbox'})['items']
        references = [{'id': item['id'], 'expectedRevision': item['revision']} for item in records]
        batch = ok('statusBatch', {'items': references, 'state': 'read', 'requestId': 'mark-all-read'})
        check(batch['count'] == 2, 'atomic Mark All Read updates the exact visible snapshot')

        before_pin = ok('uiState')
        pin_params = {'pinned': True, 'expectedInstanceId': before_pin['instanceId'], 'expectedUIRevision': before_pin['uiRevision'], 'requestId': 'pin-once'}
        pinned = ok('uiSetPinned', pin_params)
        check(pinned['inbox']['pinned'] and pinned['inbox']['presentation'] == 'panel', 'pin converts the inbox to a persistent panel')
        replay = ok('uiSetPinned', pin_params)
        check(replay['uiRevision'] == pinned['uiRevision'], 'retried interface request is idempotent')
        stale = api('uiNavigate', {'direction': 'next', 'expectedUIRevision': before_pin['uiRevision'], 'requestId': 'stale-navigation'})
        check(not stale['ok'] and stale['error']['code'] == 'revision_conflict', 'stale relative navigation is rejected')

        preferences = ok('uiShow', {'surface': 'preferences', 'requestId': 'show-preferences'})
        check(preferences['preferencesVisible'], 'MCP/API shows native Preferences')
        closed = ok('uiClose', {'surface': 'all', 'requestId': 'close-all'})
        check(closed['surface'] == 'hidden' and not closed['arrival']['visible'], 'all native surfaces close semantically')
        print(f'{checks} native interface API checks passed; temporary app and state cleaned up.')
    finally:
        if process is not None and process.poll() is None:
            process.terminate()
            try:
                process.communicate(timeout=8)
            except subprocess.TimeoutExpired:
                process.kill(); process.communicate()

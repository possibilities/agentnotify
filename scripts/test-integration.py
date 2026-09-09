#!/usr/bin/env python3
"""Exercise actual CLI, socket, and MCP against only a disposable store."""
import concurrent.futures
import json
import os
from pathlib import Path
import signal
import socket
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parent.parent
BIN = ROOT / '.build/debug/agentnotify'
checks = 0


def check(value, message):
    global checks
    assert value, message
    checks += 1


with tempfile.TemporaryDirectory(prefix='an-', dir='/tmp') as tmp:
    env = {**os.environ, 'AGENTNOTIFY_STATE_DIR': tmp, 'AGENTNOTIFY_NO_LAUNCH': '1'}
    server = None
    children = []
    def start():
        global server
        server = subprocess.Popen([str(BIN), 'serve'], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        deadline = time.monotonic() + 8
        while time.monotonic() < deadline:
            if server.poll() is not None:
                raise AssertionError(server.stderr.read().decode())
            if Path(tmp, 'notify.sock').exists():
                return
            time.sleep(.05)
        raise AssertionError('Service did not become ready')
    def stop():
        server.terminate()
        server.communicate(timeout=8)
    def api(method, params=None):
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as conn:
            conn.settimeout(5)
            conn.connect(str(Path(tmp, 'notify.sock')))
            conn.sendall((json.dumps({'id': 'test', 'method': method, 'params': params or {}}) + '\n').encode())
            result = json.loads(conn.makefile('r').readline())
            check(result.get('id') == 'test', 'socket request/response correlation')
            return result
    def ok(method, params=None):
        result = api(method, params)
        check(result['ok'], result)
        return result['data']
    def cli(*args, input=None):
        return subprocess.run([str(BIN), *args], env=env, input=input, capture_output=True, text=True, timeout=12)
    def wait_for(predicate, seconds=4):
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            value = predicate()
            if value:
                return value
            time.sleep(.05)
        raise AssertionError('Condition did not become true')
    def group(name):
        return ok('list', {'filter': 'all', 'group': name})['items']
    try:
        start()
        check(Path(tmp).stat().st_mode & 0o777 == 0o700, 'private directory')
        check(Path(tmp, 'notify.sock').stat().st_mode & 0o777 == 0o600, 'private socket')
        second = cli('serve')
        check(second.returncode == 4 and 'already owns' in second.stderr, 'one service per store')
        check(cli('-version').stdout == 'terminal-notifier 3.1.0.\n', 'legacy version')
        check(cli('-list', 'missing').stdout == '', 'empty legacy listing')
        check(cli('-message', 'bad', '-timeout', '0').returncode == 2, 'bad timeout')
        check(cli('-message', '').returncode == 1, 'empty message')
        check(cli('-message', 'bad', '-in', '5m', '-action', 'Yes').returncode == 2, 'schedule interaction conflict')
        check(cli('-message', 'bad', '-open', '/tmp/no-scheme').returncode == 2, 'URL validation')
        piped = cli('-group', 'piped', input='Hello\nWorld\r\n')
        check(piped.returncode == 0 and piped.stdout == '', 'piped silent success')
        check(group('piped')[0]['message'] == 'Hello\nWorld', 'piped exact body')
        kept = ok('send', {'message': 'Keep on invalid replacement', 'group': 'atomic-old'})
        failed = cli('-remove', 'atomic-old', '-message', 'Invalid', '-open', '/invalid')
        check(failed.returncode == 2 and ok('get', {'id': kept['id']})['status'] == 'active', 'invalid replacement preserves old notification')
        replaced = cli('-remove', 'atomic-old', '-message', 'Valid', '-group', 'atomic-new')
        check(replaced.returncode == 0 and ok('get', {'id': kept['id']})['status'] == 'removed', 'remove plus send is atomic')
        scheduled = cli('-message', 'Later', '-group', 'scheduled', '-in', '1h')
        check(scheduled.returncode == 0 and scheduled.stdout == '', 'scheduled send')
        listing = cli('-list', 'PENDING')
        check(listing.stdout.startswith('GroupID\tTitle\tSubtitle\tMessage\tScheduled For\n'), 'legacy pending TSV header')
        # Concurrent action sets, literal result bytes, and response arbitration.
        prompts = []
        for name, action in [('choice-a', 'Ship'), ('choice-b', 'Hold')]:
            process = subprocess.Popen([str(BIN), '-message', name, '-group', name, '-action', action, '-action', 'Other', '-timeout', '8'], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            children.append(process)
            item = wait_for(lambda: next(iter(group(name)), None))
            prompts.append((process, item, action))
        for process, item, label in reversed(prompts):
            ok('respond', {'id': item['id'], 'kind': 'action', 'actionIndex': 0})
            out, err = process.communicate(timeout=5)
            check(process.returncode == 0 and out == label + '\n', 'concurrent prompt result identity')
        reply = subprocess.Popen([str(BIN), '-message', 'Reply', '-group', 'reply', '-reply', '', '-timeout', '8'], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        children.append(reply)
        item = wait_for(lambda: next(iter(group('reply')), None))
        ok('respond', {'id': item['id'], 'kind': 'reply', 'value': 'hello\n$not-shell'})
        out, _ = reply.communicate(timeout=5)
        check(out == 'hello\n$not-shell\n' and reply.returncode == 0, 'literal multiline reply')
        timeout = cli('-message', 'Timeout', '-group', 'timeout', '-action', 'Yes', '-timeout', '.2')
        check(timeout.stdout == '@TIMEOUT\n' and timeout.returncode == 6, 'legacy timeout output/status')
        check(group('timeout')[0]['status'] == 'active', 'timeout task retained')
        waiting = subprocess.Popen([str(BIN), '-message', 'Interrupt', '-group', 'interrupt', '-action', 'Yes'], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        children.append(waiting)
        wait_for(lambda: group('interrupt'))
        time.sleep(.2)
        waiting.send_signal(signal.SIGTERM)
        out, _ = waiting.communicate(timeout=5)
        check(waiting.returncode == 6 and out == '', 'signal interruption contract')
        killed = subprocess.Popen([str(BIN), '-message', 'Killed', '-group', 'killed', '-action', 'Yes'], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        children.append(killed)
        killed_item = wait_for(lambda: next(iter(group('killed')), None))
        killed.kill(); killed.communicate(timeout=5)
        wait_for(lambda: ok('get', {'id': killed_item['id']}).get('response', {}).get('kind') == 'interrupt', seconds=7)
        check(not ok('get', {'id': killed_item['id']})['presentable'], 'SIGKILL lease disables stale prompt')
        # Reading never executes; two responders cannot execute the callback twice.
        effect = str(Path(tmp, 'effect'))
        item = ok('send', {'message': 'Body effect', 'execute': f"printf x >> '{effect}'", 'requestId': 'body-send'})
        ok('status', {'id': item['id'], 'state': 'read'})
        check(not Path(effect).exists(), 'reading never executes callback')
        parameters = {'id': item['id'], 'kind': 'body', 'requestId': 'body-response'}
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            results = list(pool.map(lambda _: api('respond', parameters), range(4)))
        check(all(r['ok'] for r in results), 'safe idempotent response retries')
        wait_for(lambda: ok('get', {'id': item['id']}).get('response', {}).get('effect') == 'succeeded')
        check(Path(effect).read_text() == 'x', 'effect runs once')
        check(not api('respond', {'id': item['id'], 'kind': 'body'})['ok'], 'second independent response rejected')
        conflict = ok('send', {'message': 'revision'})
        ok('status', {'id': conflict['id'], 'state': 'read', 'expectedRevision': conflict['revision']})
        check(api('status', {'id': conflict['id'], 'state': 'done', 'expectedRevision': conflict['revision']})['error']['code'] == 'revision_conflict', 'stale writes rejected')
        for suffix, extra, kind, expected, code in [
            ('body', [], 'body', '@ACTIONCLICKED\n', 0),
            ('body-failure', ['-execute', '/usr/bin/false'], 'body', '', 5),
            ('close', [], 'close', '@CLOSED\n', 0),
        ]:
            process = subprocess.Popen([str(BIN), '-message', suffix, '-group', suffix, '-action', '@TIMEOUT', '-timeout', '8', *extra], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            children.append(process)
            notice = wait_for(lambda: next(iter(group(suffix)), None))
            ok('respond', {'id': notice['id'], 'kind': kind})
            out, _ = process.communicate(timeout=5)
            check(out == expected and process.returncode == code, 'legacy body/close result contract')
        # MCP discovery works without a separate implementation, then a real send/list.
        mcp = subprocess.Popen([str(BIN), 'mcp'], env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        children.append(mcp)
        def mcp_call(i, method, params=None):
            mcp.stdin.write(json.dumps({'jsonrpc': '2.0', 'id': i, 'method': method, 'params': params or {}}) + '\n'); mcp.stdin.flush()
            return json.loads(mcp.stdout.readline())
        check(mcp_call(1, 'initialize', {'protocolVersion': '2025-06-18'})['result']['serverInfo']['name'] == 'agentnotify', 'MCP initialize')
        tools = mcp_call(2, 'tools/list')['result']['tools']
        check({t['name'] for t in tools} == {'send','list','get','status','respond','remove','changes','diagnose','show','heartbeat'}, 'MCP parity catalog')
        result = mcp_call(3, 'tools/call', {'name': 'send', 'arguments': {'message': 'MCP notice', 'group': 'mcp'}})['result']
        check(not result['isError'] and result['structuredContent']['ok'], 'MCP send')
        bad = mcp_call(4, 'tools/call', {'name': 'send', 'arguments': {'message': False}})['result']
        check(bad['isError'], 'MCP validation parity')
        mcp.stdin.close(); mcp.wait(timeout=5)
        # Persisted state and resumable change stream survive a full service restart.
        before = ok('diagnose')
        first = ok('changes', {'after': 0, 'limit': 2})
        check(first['hasMore'] and len(first['changes']) == 2, 'change pagination')
        stop(); start()
        check(ok('diagnose')['total'] == before['total'], 'durable records after restart')
        check(ok('get', {'id': conflict['id']})['readAt'] is not None, 'durable read state')
        check(ok('changes', {'after': before['cursor']})['changes'] == [], 'stable change cursor')
        check(Path(effect).read_text() == 'x', 'no effect replay on restart')
        check(not api('send', {'message': 'x', 'invented': 1})['ok'], 'unknown fields refused')
        remove = cli('-remove', 'scheduled')
        check(remove.returncode == 0 and group('scheduled')[0]['status'] == 'removed', 'remove retains history')
        print(f'{checks} CLI/socket/MCP checks passed; temporary service and state cleaned up.')
    finally:
        for child in children:
            if child.poll() is None:
                child.terminate()
                try: child.wait(timeout=5)
                except subprocess.TimeoutExpired: child.kill(); child.wait()
        if server is not None and server.poll() is None:
            stop()

#!/usr/bin/env python3
"""Test the real guarded installer, with every destination under a temporary root."""
import os
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix='an-install-', dir='/tmp') as directory:
    target = Path(directory)
    env = {**os.environ, 'AGENTNOTIFY_INSTALL_ROOT': str(target)}
    binary_dir = target / '.local/bin'
    binary_dir.mkdir(parents=True)
    command = binary_dir / 'agentnotify'
    command.write_text('foreign command')
    def install(*args):
        return subprocess.run([str(ROOT/'scripts/install.sh'), '--install', *args], cwd=ROOT, env=env, capture_output=True, text=True, timeout=180)
    refused = install()
    assert refused.returncode != 0 and 'foreign command' in refused.stderr, refused.stderr
    assert command.read_text() == 'foreign command'
    command.unlink()
    first = install('--terminal-notifier')
    assert first.returncode == 0, first.stdout + first.stderr
    bundle = target / 'Applications/AgentNotify.app'
    metadata = plistlib.loads((bundle/'Contents/Info.plist').read_bytes())
    assert metadata['CFBundleIdentifier'] == 'io.arthack.agentnotify'
    assert metadata['LSUIElement'] is True
    revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    assert metadata['AgentNotifySourceRevision'] == revision
    assert command.resolve() == (bundle/'Contents/MacOS/AgentNotify').resolve()
    assert (binary_dir/'terminal-notifier').resolve() == command.resolve()
    version = subprocess.run([str(binary_dir/'terminal-notifier'), '-version'], capture_output=True, text=True, timeout=5)
    assert version.returncode == 0 and version.stdout == 'terminal-notifier 3.1.0.\n'
    state = target/'state'
    process = subprocess.Popen([str(command.resolve()), 'serve'], env={**env, 'AGENTNOTIFY_STATE_DIR': str(state)}, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        deadline = time.monotonic() + 5
        while not (state/'notify.sock').exists() and time.monotonic() < deadline:
            time.sleep(.05)
        assert process.poll() is None and (state/'notify.sock').exists()
        executable_before = command.resolve().stat()
        current = install()
        assert current.returncode == 0 and 'already current' in current.stdout, current.stdout + current.stderr
        executable_after = command.resolve().stat()
        assert (executable_after.st_ino, executable_after.st_mtime_ns) == (executable_before.st_ino, executable_before.st_mtime_ns)
        assert process.poll() is None, 'current-release convergence stopped the running service'
        # A missing/mismatched receipt must not falsely claim the release is current.
        (target/'.local/state/agentnotify-install/deployed-sha').write_text('older-revision\n')
        busy = install()
        assert busy.returncode != 0 and 'running' in busy.stderr, busy.stderr
        assert process.poll() is None, 'installer stopped the running service'
    finally:
        process.terminate(); process.communicate(timeout=5)
    # An existing agent session's MCP transport must survive an app update.
    mcp = subprocess.Popen([str(command), 'mcp'], env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    try:
        mcp.stdin.write(json.dumps({'jsonrpc': '2.0', 'id': 1, 'method': 'initialize', 'params': {'protocolVersion': '2025-06-18'}}) + '\n')
        mcp.stdin.flush()
        assert json.loads(mcp.stdout.readline())['result']['serverInfo']['name'] == 'agentnotify'
        executable_before = command.resolve().stat()
        again = install('--terminal-notifier')
        assert again.returncode == 0, again.stdout + again.stderr
        assert executable_before.st_ino != command.resolve().stat().st_ino, 'test did not replace the bundle'
        assert mcp.poll() is None, 'installer stopped an existing MCP client'
        mcp.stdin.write(json.dumps({'jsonrpc': '2.0', 'id': 2, 'method': 'tools/list'}) + '\n')
        mcp.stdin.flush()
        assert any(tool['name'] == 'send' for tool in json.loads(mcp.stdout.readline())['result']['tools'])
    finally:
        mcp.terminate(); mcp.communicate(timeout=5)
    assert (target/'.local/state/agentnotify-install/deployed-sha').read_text().strip() == subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    print('Installer checks passed: foreign-file preservation, clean install, legacy alias, unchanged running-app convergence, changed running-app refusal, live MCP client preservation across bundle replacement, signed revision and deployed-SHA receipt. All destinations were temporary.')

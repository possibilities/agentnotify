#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
mode="${1:---check}"
shift "$(( $# > 0 ? 1 : 0 ))"
compat=0
for argument in "$@"; do case "$argument" in --terminal-notifier) compat=1 ;; *) printf 'Unknown argument: %s\n' "$argument" >&2; exit 2 ;; esac; done
case "$mode" in --check|--install) ;; *) printf 'Usage: scripts/install.sh --check|--install [--terminal-notifier]\n' >&2; exit 2 ;; esac
[ "$(uname -s)" = Darwin ] || { printf 'macOS is required.\n' >&2; exit 1; }
[ "$(id -u)" -ne 0 ] || { printf 'Run as your account, not root.\n' >&2; exit 1; }
install_root="${AGENTNOTIFY_INSTALL_ROOT:-$HOME}"
app="$install_root/Applications/AgentNotify.app"
bin="$install_root/.local/bin"
if [ "$mode" = --check ]; then
    printf 'Build and install AgentNotify.app to %s; link %s/agentnotify. No launch or restart.\n' "$app" "$bin"
    if [ "$compat" = 1 ]; then printf 'Also link %s/terminal-notifier, refusing a foreign file.\n' "$bin"; fi
    exit 0
fi
[ -z "$(git -C "$repo_root" status --porcelain)" ] || { printf 'Refusing to install a dirty checkout. Build locally for previews; commit before installing.\n' >&2; exit 1; }
source_revision="$(git -C "$repo_root" rev-parse HEAD)"
receipt="$install_root/.local/state/agentnotify-install/deployed-sha"
# Refuse symlinked destinations and preserve an unrelated application/command.
for directory in "$install_root/Applications" "$install_root/.local" "$bin"; do
    [ ! -L "$directory" ] || { printf 'Refusing symlink directory: %s\n' "$directory" >&2; exit 1; }
done
if [ -e "$app" ] || [ -L "$app" ]; then
    [ ! -L "$app" ] && [ -d "$app" ] && [ "$(/usr/libexec/PlistBuddy -c 'Print :AgentNotifyInstaller' "$app/Contents/Info.plist" 2>/dev/null)" = agentnotify/scripts/install.sh ] || { printf 'Refusing foreign application: %s\n' "$app" >&2; exit 1; }
fi
for command_name in agentnotify $([ "$compat" = 1 ] && printf terminal-notifier); do
    target="$bin/$command_name"
    if [ -e "$target" ] || [ -L "$target" ]; then
        [ -L "$target" ] && [ "$(readlink "$target")" = "$app/Contents/MacOS/AgentNotify" ] || { printf 'Refusing foreign command: %s\n' "$target" >&2; exit 1; }
    fi
done
# Fleet convergence is safe while this exact installed release is running.
# Check the signed bundle as well as the receipt before skipping replacement.
if [ -x "$app/Contents/MacOS/AgentNotify" ] && [ -f "$receipt" ] \
    && [ "$(cat "$receipt")" = "$source_revision" ] \
    && [ "$(/usr/libexec/PlistBuddy -c 'Print :AgentNotifySourceRevision' "$app/Contents/Info.plist" 2>/dev/null)" = "$source_revision" ] \
    && codesign --verify --strict "$app" >/dev/null 2>&1; then
    mkdir -p "$bin"
    ln -sfn "$app/Contents/MacOS/AgentNotify" "$bin/agentnotify"
    if [ "$compat" = 1 ]; then ln -sfn "$app/Contents/MacOS/AgentNotify" "$bin/terminal-notifier"; fi
    printf 'AgentNotify is already current; left the app and any running process unchanged.\n'
    exit 0
fi
if [ -d "$app" ] && /usr/sbin/lsof -t "$app/Contents/MacOS/AgentNotify" >/dev/null 2>&1; then
    printf 'AgentNotify is running. Quit it before installation; the installer never restarts it.\n' >&2
    exit 1
fi
"$repo_root/scripts/build.sh"
mkdir -p "$install_root/Applications" "$bin"
staging="$(mktemp -d "$install_root/Applications/.agentnotify-install.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
cp -R "$repo_root/dist/AgentNotify.app" "$staging/AgentNotify.app"
if [ -d "$app" ]; then mv "$app" "$staging/previous.app"; fi
if ! mv "$staging/AgentNotify.app" "$app"; then
    if [ -d "$staging/previous.app" ]; then mv "$staging/previous.app" "$app"; fi
    exit 1
fi
ln -sfn "$app/Contents/MacOS/AgentNotify" "$bin/agentnotify"
if [ "$compat" = 1 ]; then ln -sfn "$app/Contents/MacOS/AgentNotify" "$bin/terminal-notifier"; fi
mkdir -p "$install_root/.local/state/agentnotify-install"
printf '%s\n' "$source_revision" > "$receipt"
printf 'Installed %s. Open it to enable system notifications.\n' "$app"

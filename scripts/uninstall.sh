#!/usr/bin/env bash
set -Eeuo pipefail

if (( $# != 0 )); then
  echo "Usage: scripts/uninstall.sh" >&2
  exit 2
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SOURCE="$ROOT/src/cli.ts"
TARGET="$HOME/.local/bin/agentnotify"
STATE_DIR="$HOME/.local/state/agentnotify"
RECEIPT="$STATE_DIR/deployed-sha"

fail() {
  printf 'agentnotify-uninstall: %s\n' "$1" >&2
  exit 1
}

owner_uid() {
  stat -c %u "$1" 2>/dev/null || stat -f %u "$1"
}

file_mode() {
  stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"
}

file_nlink() {
  stat -c %h "$1" 2>/dev/null || stat -f %l "$1"
}

for variable in \
  AGENTNOTIFY_INSTALL_BIN_DIR \
  AGENTNOTIFY_INSTALL_STATE_DIR \
  AGENTNOTIFY_INSTALL_DATA_DIR \
  AGENTNOTIFY_BUN \
  AGENTNOTIFY_LOG_DB \
  AGENTNOTIFY_DATA_DIR \
  XDG_STATE_HOME \
  XDG_DATA_HOME
do
  [[ -z "${!variable-}" ]] || fail "refusing inherited destination override: $variable"
done

for path in \
  "$HOME" \
  "$HOME/.local" \
  "$HOME/.local/bin" \
  "$HOME/.local/state" \
  "$STATE_DIR"
do
  [[ ! -L "$path" ]] || fail "refusing symlinked installation path: $path"
done

if [[ -L "$TARGET" && "$(readlink "$TARGET")" == "$SOURCE" ]]; then
  SHA="$(git -C "$ROOT" rev-parse --verify HEAD 2>/dev/null)" || fail "cannot determine source SHA"
  [[ "$SHA" =~ ^[0-9a-f]{40}$ ]] || fail "source SHA is malformed"
  if [[ -e "$RECEIPT" || -L "$RECEIPT" ]]; then
    [[ ! -L "$RECEIPT" && -f "$RECEIPT" ]] || fail "refusing unsafe deployed receipt: $RECEIPT"
    [[ "$(owner_uid "$RECEIPT")" == "$(id -u)" ]] || fail "refusing foreign deployed receipt: $RECEIPT"
    [[ "$(file_nlink "$RECEIPT")" == "1" ]] || fail "refusing hardlinked deployed receipt: $RECEIPT"
    [[ "$(file_mode "$RECEIPT")" == "600" ]] || fail "refusing deployed receipt with unsafe permissions: $RECEIPT"
    printf '%s\n' "$SHA" | cmp -s - "$RECEIPT" || fail "refusing deployed receipt that does not match this checkout: $RECEIPT"
  fi
  rm -f -- "$TARGET" "$RECEIPT"
  printf 'Removed owned agentnotify command and deployment receipt\n'
elif [[ -L "$TARGET" ]]; then
  printf 'agentnotify-uninstall: preserving symlink not owned by this checkout: %s\n' "$TARGET" >&2
elif [[ -e "$TARGET" ]]; then
  printf 'agentnotify-uninstall: preserving non-symlink: %s\n' "$TARGET" >&2
elif [[ -e "$RECEIPT" || -L "$RECEIPT" ]]; then
  printf 'agentnotify-uninstall: preserving uncorroborated deployment receipt: %s\n' "$RECEIPT" >&2
else
  printf 'agentnotify-uninstall: command is already absent\n'
fi

printf 'agentnotify-uninstall: data and configuration were preserved\n'

#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

if (( $# != 0 )); then
  echo "Usage: scripts/install.sh" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
SOURCE="$ROOT/src/cli.ts"
LOCAL_DIR="$HOME/.local"
BIN_DIR="$LOCAL_DIR/bin"
SHARE_DIR="$LOCAL_DIR/share"
DATA_DIR="$SHARE_DIR/agentnotify"
STATE_PARENT="$LOCAL_DIR/state"
STATE_DIR="$STATE_PARENT/agentnotify"
TARGET="$BIN_DIR/agentnotify"
RECEIPT="$STATE_DIR/deployed-sha"
EXPECTED_ORIGIN="https://github.com/possibilities/agentnotify.git"
TMP_PATH=""

cleanup() {
  if [[ -n "$TMP_PATH" ]]; then
    rm -f -- "$TMP_PATH"
  fi
}
trap cleanup EXIT

fail() {
  printf 'agentnotify-install: %s\n' "$1" >&2
  exit "${2:-1}"
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

validate_path() {
  local path="$1"
  local label="$2"
  local component current="" remainder platform

  [[ -n "$path" && "$path" == /* ]] || fail "refusing unsafe $label path (must be absolute): $path"
  [[ "$path" != "/" && "$path" != *//* && "$path" != */./* && "$path" != */../* && "$path" != */. && "$path" != */.. ]] || \
    fail "refusing unsafe $label path: $path"

  platform="$(uname -s)"
  remainder="${path#/}"
  while [[ -n "$remainder" ]]; do
    component="${remainder%%/*}"
    current="$current/$component"
    if [[ "$remainder" == */* ]]; then
      remainder="${remainder#*/}"
    else
      remainder=""
    fi

    # macOS exposes these stable lexical aliases into /private. Preserve normal
    # /tmp and /var paths while rejecting application-controlled symlinks below.
    if [[ "$platform" == "Darwin" ]]; then
      case "$current:$(readlink "$current" 2>/dev/null || true)" in
        /tmp:private/tmp|/tmp:/private/tmp|/var:private/var|/var:/private/var)
          continue
          ;;
      esac
    fi
    [[ ! -L "$current" ]] || fail "refusing symlinked $label path component: $current"
  done
}

validate_directory() {
  local dir="$1"
  local label="$2"
  local mode mode_value

  validate_path "$dir" "$label"
  [[ -d "$dir" ]] || fail "refusing non-directory $label path: $dir"
  [[ "$(owner_uid "$dir")" == "$(id -u)" ]] || fail "refusing foreign $label directory: $dir"
  mode="$(file_mode "$dir")"
  [[ "$mode" =~ ^[0-7]{3,4}$ ]] || fail "could not validate permissions for $label directory: $dir"
  mode_value=$((8#$mode))
  (( (mode_value & 0022) == 0 )) || fail "refusing unsafe writable $label directory: $dir"
}

ensure_directory() {
  local dir="$1"
  local label="$2"
  local create_mode="$3"

  validate_path "$dir" "$label"
  if [[ -e "$dir" ]]; then
    [[ -d "$dir" ]] || fail "refusing non-directory $label path: $dir"
  else
    mkdir -p -- "$dir"
    chmod "$create_mode" "$dir"
  fi
  validate_directory "$dir" "$label"
}

validate_safe_file() {
  local path="$1"
  local label="$2"
  local mode mode_value

  [[ ! -L "$path" && -f "$path" ]] || fail "refusing unsafe $label: $path"
  [[ "$(owner_uid "$path")" == "$(id -u)" ]] || fail "refusing foreign $label: $path"
  [[ "$(file_nlink "$path")" == "1" ]] || fail "refusing hardlinked $label: $path"
  mode="$(file_mode "$path")"
  [[ "$mode" =~ ^[0-7]{3,4}$ ]] || fail "could not validate permissions for $label: $path"
  mode_value=$((8#$mode))
  (( (mode_value & 07022) == 0 )) || fail "refusing unsafe permissions for $label: $path"
}

checkout_head() {
  local root="$1"
  local physical_root top sha

  [[ -d "$root/.git" || -f "$root/.git" ]] || return 1
  physical_root="$(cd "$root" && pwd -P)" || return 1
  top="$(git -C "$root" rev-parse --show-toplevel 2>/dev/null)" || return 1
  top="$(cd "$top" && pwd -P)" || return 1
  [[ "$top" == "$physical_root" ]] || return 1
  sha="$(git -C "$root" rev-parse --verify HEAD 2>/dev/null)" || return 1
  [[ "$sha" =~ ^[0-9a-f]{40}$ ]] || return 1
  printf '%s\n' "$sha"
}

normalized_origin() {
  local origin="$1"
  origin="${origin%/}"
  case "$origin" in
    https://github.com/possibilities/agentnotify|https://github.com/possibilities/agentnotify.git)
      printf '%s\n' "$EXPECTED_ORIGIN"
      ;;
    git@github.com:possibilities/agentnotify|git@github.com:possibilities/agentnotify.git|ssh://git@github.com/possibilities/agentnotify|ssh://git@github.com/possibilities/agentnotify.git)
      printf '%s\n' "$EXPECTED_ORIGIN"
      ;;
    *)
      printf '%s\n' "$origin"
      ;;
  esac
}

validate_managed_checkout() {
  local root="$1"
  local source="$root/src/cli.ts"
  local origin sha

  [[ "$root" == /* ]] || fail "refusing managed command with a non-absolute source root: $root"
  validate_path "$root" "source root"
  validate_directory "$root" "source root"
  validate_safe_file "$source" "agentnotify source command"
  [[ -x "$source" ]] || fail "refusing non-executable agentnotify source command: $source"
  sha="$(checkout_head "$root")" || fail "refusing agentnotify source outside an exact Git checkout: $root"
  origin="$(git -C "$root" remote get-url origin 2>/dev/null)" || fail "refusing agentnotify source without an origin: $root"
  [[ "$(normalized_origin "$origin")" == "$EXPECTED_ORIGIN" ]] || fail "refusing agentnotify source with foreign origin: $root"
  MANAGED_ROOT="$root"
  MANAGED_SHA="$sha"
}

classify_command() {
  local destination root
  MANAGED_KIND="absent"
  MANAGED_ROOT=""
  MANAGED_SHA=""

  if [[ ! -e "$TARGET" && ! -L "$TARGET" ]]; then
    return 0
  fi
  [[ -L "$TARGET" ]] || fail "refusing foreign command path: $TARGET"
  [[ "$(owner_uid "$TARGET")" == "$(id -u)" ]] || fail "refusing foreign command symlink: $TARGET"
  destination="$(readlink "$TARGET")"
  [[ "$destination" == /*/src/cli.ts ]] || fail "refusing foreign command symlink: $TARGET"
  root="${destination%/src/cli.ts}"
  [[ "$destination" == "$root/src/cli.ts" ]] || fail "refusing foreign command symlink: $TARGET"
  validate_managed_checkout "$root"
  MANAGED_KIND="source-link"
}

receipt_exists() {
  [[ -e "$RECEIPT" || -L "$RECEIPT" ]]
}

validate_receipt() {
  local expected_sha="${1:-}"
  local sha
  RECEIPT_SHA=""

  [[ ! -L "$RECEIPT" && -f "$RECEIPT" ]] || fail "refusing unsafe deployed receipt: $RECEIPT"
  [[ "$(owner_uid "$RECEIPT")" == "$(id -u)" ]] || fail "refusing foreign deployed receipt: $RECEIPT"
  [[ "$(file_nlink "$RECEIPT")" == "1" ]] || fail "refusing hardlinked deployed receipt: $RECEIPT"
  [[ "$(file_mode "$RECEIPT")" == "600" ]] || fail "refusing deployed receipt with unsafe permissions: $RECEIPT"
  IFS= read -r sha <"$RECEIPT" || fail "refusing malformed deployed receipt: $RECEIPT"
  [[ "$sha" =~ ^[0-9a-f]{40}$ ]] || fail "refusing malformed deployed receipt: $RECEIPT"
  printf '%s\n' "$sha" | cmp -s - "$RECEIPT" || fail "refusing malformed deployed receipt: $RECEIPT"
  if [[ -n "$expected_sha" && "$sha" != "$expected_sha" ]]; then
    fail "refusing deployed receipt that does not match the managed command: $RECEIPT"
  fi
  RECEIPT_SHA="$sha"
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

command -v bun >/dev/null 2>&1 || fail "Bun is required but was not found in PATH"
BUN_BIN="$(command -v bun)"
case "$BUN_BIN" in
  /*) ;;
  *) BUN_BIN="$(cd "$(dirname "$BUN_BIN")" && pwd -P)/$(basename "$BUN_BIN")" ;;
esac
[[ -x "$BUN_BIN" ]] || fail "Bun is not executable: $BUN_BIN"

validate_path "$SOURCE" "source command"
validate_managed_checkout "$ROOT"
DEPLOYED_SHA="$MANAGED_SHA"

EXPECTED_BUN="$({ AGENTNOTIFY_PACKAGE_JSON="$ROOT/package.json" "$BUN_BIN" -e '
  const manifest = JSON.parse(await Bun.file(process.env.AGENTNOTIFY_PACKAGE_JSON).text());
  const packageVersion = String(manifest.packageManager ?? "").match(/^bun@(.+)$/)?.[1];
  if (!packageVersion || manifest.engines?.bun !== packageVersion) process.exit(1);
  process.stdout.write(packageVersion);
'; } 2>/dev/null)" || fail "package.json must carry matching packageManager and engines.bun pins"
ACTUAL_BUN="$($BUN_BIN --version)"
[[ "$ACTUAL_BUN" == "$EXPECTED_BUN" ]] || fail "Bun $EXPECTED_BUN is required (found $ACTUAL_BUN at $BUN_BIN)"
EXPECTED_VERSION="$({ AGENTNOTIFY_PACKAGE_JSON="$ROOT/package.json" "$BUN_BIN" -e '
  const manifest = JSON.parse(await Bun.file(process.env.AGENTNOTIFY_PACKAGE_JSON).text());
  if (typeof manifest.version !== "string" || !manifest.version) process.exit(1);
  process.stdout.write(manifest.version);
'; } 2>/dev/null)" || fail "package.json must carry a version"

validate_directory "$HOME" "home"
ensure_directory "$LOCAL_DIR" "local" 755
ensure_directory "$BIN_DIR" "bin" 755
ensure_directory "$SHARE_DIR" "share" 755
ensure_directory "$DATA_DIR" "data" 700
ensure_directory "$STATE_PARENT" "state parent" 755
ensure_directory "$STATE_DIR" "state" 700
[[ "$(file_mode "$DATA_DIR")" == "700" ]] || fail "refusing non-private data directory: $DATA_DIR"
[[ "$(file_mode "$STATE_DIR")" == "700" ]] || fail "refusing non-private state directory: $STATE_DIR"

classify_command
if receipt_exists; then
  [[ "$MANAGED_KIND" != "absent" ]] || fail "refusing an uncorroborated deployed receipt: $RECEIPT"
  if [[ "$MANAGED_ROOT" == "$ROOT" && "$MANAGED_SHA" == "$DEPLOYED_SHA" ]]; then
    # Forward-repair a command link replaced by an interrupted install before
    # that install could publish its new receipt. The superseded receipt must
    # still identify history on the current repository's main line.
    validate_receipt
    git -C "$ROOT" merge-base --is-ancestor "$RECEIPT_SHA" "$DEPLOYED_SHA" 2>/dev/null || \
      fail "refusing foreign deployed receipt history: $RECEIPT"
  else
    validate_receipt "$MANAGED_SHA"
  fi
fi

(
  cd "$ROOT"
  "$BUN_BIN" install --frozen-lockfile
  "$BUN_BIN" run check
)

TMP_PATH="$BIN_DIR/.agentnotify-link.$$.$RANDOM"
[[ ! -e "$TMP_PATH" && ! -L "$TMP_PATH" ]] || fail "refusing unsafe temporary command path: $TMP_PATH"
ln -s -- "$SOURCE" "$TMP_PATH"
mv -f -- "$TMP_PATH" "$TARGET"
TMP_PATH=""

classify_command
[[ "$MANAGED_ROOT" == "$ROOT" && "$MANAGED_SHA" == "$DEPLOYED_SHA" ]] || fail "installed command failed verification: $TARGET"
ACTUAL_VERSION="$($TARGET --version)"
[[ "$ACTUAL_VERSION" == "$EXPECTED_VERSION" ]] || fail "installed command readiness check failed: $TARGET"

TMP_PATH="$(mktemp "$STATE_DIR/.deployed-sha.XXXXXX")"
chmod 0600 "$TMP_PATH"
printf '%s\n' "$DEPLOYED_SHA" >"$TMP_PATH"
[[ ! -L "$TMP_PATH" && -f "$TMP_PATH" ]] || fail "temporary deployed receipt is unsafe"
[[ "$(owner_uid "$TMP_PATH")" == "$(id -u)" && "$(file_nlink "$TMP_PATH")" == "1" && "$(file_mode "$TMP_PATH")" == "600" ]] || \
  fail "temporary deployed receipt failed verification"
printf '%s\n' "$DEPLOYED_SHA" | cmp -s - "$TMP_PATH" || fail "temporary deployed receipt failed content verification"
mv -f -- "$TMP_PATH" "$RECEIPT"
TMP_PATH=""
validate_receipt "$DEPLOYED_SHA"

printf 'Installed %s at %s\n' "$TARGET" "$DEPLOYED_SHA"

#!/usr/bin/env bash
set -Eeuo pipefail

if [ "$#" -ne 0 ]; then
  echo "Usage: scripts/uninstall.sh" >&2
  exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
owned_target="${repo_root}/src/cli.ts"
link="${HOME}/.local/bin/agentnotify"
if [ -L "${link}" ] && [ "$(readlink "${link}")" = "${owned_target}" ]; then
  rm -f "${link}"
  echo "uninstall: removed ${link}"
elif [ -L "${link}" ]; then
  echo "uninstall: preserving symlink not owned by this checkout: ${link}" >&2
elif [ -e "${link}" ]; then
  echo "uninstall: preserving non-symlink ${link}" >&2
else
  echo "uninstall: ${link} is already absent"
fi

echo "uninstall: data and configuration were preserved"

#!/usr/bin/env bash
set -Eeuo pipefail

trap 'echo "install: failed at line ${LINENO}" >&2' ERR
umask 077

if [ "$#" -ne 0 ]; then
  echo "Usage: scripts/install.sh" >&2
  exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cli_source="${repo_root}/src/cli.ts"
link_installer="${repo_root}/scripts/install-local-link.sh"

bun_bin="${AGENTNOTIFY_BUN:-}"
if [ -z "${bun_bin}" ]; then
  bun_bin="$(command -v bun 2>/dev/null || true)"
fi
if [ -z "${bun_bin}" ] || [ ! -x "${bun_bin}" ]; then
  echo "install: Bun is required" >&2
  exit 1
fi
case "${bun_bin}" in
  /*) ;;
  *) bun_bin="$(cd "$(dirname "${bun_bin}")" && pwd -P)/$(basename "${bun_bin}")" ;;
esac

expected_bun="$({ AGENTNOTIFY_PACKAGE_JSON="${repo_root}/package.json" "${bun_bin}" -e '
  const manifest = JSON.parse(await Bun.file(process.env.AGENTNOTIFY_PACKAGE_JSON).text());
  const packageVersion = String(manifest.packageManager ?? "").match(/^bun@(.+)$/)?.[1];
  if (!packageVersion || manifest.engines?.bun !== packageVersion) process.exit(1);
  process.stdout.write(packageVersion);
'; } 2>/dev/null)" || {
  echo "install: package.json must carry matching packageManager and engines.bun pins" >&2
  exit 1
}
actual_bun="$(${bun_bin} --version)"
if [ "${actual_bun}" != "${expected_bun}" ]; then
  echo "install: Bun ${expected_bun} is required (found ${actual_bun} at ${bun_bin})" >&2
  exit 1
fi

chmod 755 "${cli_source}" "${link_installer}"
echo "install: installing frozen dependencies"
( cd "${repo_root}" && "${bun_bin}" install --frozen-lockfile )
echo "install: running the complete check"
( cd "${repo_root}" && "${bun_bin}" run check )

"${link_installer}" "${cli_source}"

echo "install: agentnotify linked at ${HOME}/.local/bin/agentnotify"

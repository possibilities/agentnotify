#!/usr/bin/env bash
set -Eeuo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: install-local-link.sh SOURCE" >&2
  exit 2
fi

source_cli="$1"
case "${source_cli}" in
  /*) ;;
  *) echo "install-link: SOURCE must be absolute" >&2; exit 2 ;;
esac
if [ ! -f "${source_cli}" ]; then
  echo "install-link: missing CLI source ${source_cli}" >&2
  exit 1
fi

umask 077
local_dir="${HOME}/.local"
bin_dir="${local_dir}/bin"
share_dir="${local_dir}/share"
data_dir="${share_dir}/agentnotify"
state_parent="${local_dir}/state"
state_dir="${state_parent}/agentnotify"
link="${bin_dir}/agentnotify"
temporary=""
cleanup() {
  [ -z "${temporary}" ] || rm -f "${temporary}"
}
trap cleanup EXIT

for directory in \
  "${local_dir}" \
  "${bin_dir}" \
  "${share_dir}" \
  "${data_dir}" \
  "${state_parent}" \
  "${state_dir}"
do
  if [ -L "${directory}" ]; then
    echo "install-link: refusing symlinked directory ${directory}" >&2
    exit 1
  fi
done
mkdir -p "${bin_dir}" "${data_dir}" "${state_dir}"
chmod 755 "${bin_dir}"
chmod 700 "${data_dir}" "${state_dir}"

if [ -e "${link}" ] && [ ! -L "${link}" ]; then
  echo "install-link: refusing to replace non-symlink ${link}" >&2
  exit 1
fi

temporary="${bin_dir}/.agentnotify-link.${$}"
ln -s "${source_cli}" "${temporary}"
mv -f "${temporary}" "${link}"
temporary=""

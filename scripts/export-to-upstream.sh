#!/bin/bash

set -euo pipefail

upstream=${1:-}
if [[ -z $upstream || ! -f $upstream/cli/package.json || ! -d $upstream/cli/omarchy ]]; then
  echo "usage: $0 /path/to/stateset-icommerce" >&2
  exit 2
fi

plugin_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
plugin_version=$(node -p "require('$plugin_root/manifest.json').version")
cli_version=$(node -p "require('$upstream/cli/package.json').version")
if [[ $plugin_version != "$cli_version" ]]; then
  echo "version mismatch: plugin $plugin_version, CLI $cli_version" >&2
  exit 1
fi

for file in Model.js Panel.qml README.md Service.qml ServiceHost.js manifest.json; do
  cp "$plugin_root/$file" "$upstream/cli/omarchy/$file"
done

if ! git -C "$upstream" apply --reverse --check "$plugin_root/patches/status-schema-v1.patch" >/dev/null 2>&1; then
  git -C "$upstream" apply --check "$plugin_root/patches/status-schema-v1.patch"
  git -C "$upstream" apply "$plugin_root/patches/status-schema-v1.patch"
fi

node "$upstream/scripts/ci/check_omarchy_integration.mjs"
echo "Exported StateSet Omarchy plugin v$plugin_version to $upstream"

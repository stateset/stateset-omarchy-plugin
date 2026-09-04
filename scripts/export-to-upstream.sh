#!/bin/bash

set -euo pipefail

upstream=${1:-}
if [[ -z $upstream || ! -f $upstream/cli/package.json || ! -d $upstream/cli/omarchy ]]; then
  echo "usage: $0 /path/to/stateset-icommerce" >&2
  exit 2
fi

plugin_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
plugin_version=$(node -p "require('$plugin_root/manifest.json').version")
controller_version=$(tr -d '[:space:]' < "$plugin_root/upstream-version.txt")
contract_version=$(node -p "require('$plugin_root/contract.json').controllerVersion")
cli_version=$(node -p "require('$upstream/cli/package.json').version")
if [[ $controller_version != "$cli_version" || $contract_version != "$cli_version" ]]; then
  echo "controller mismatch: marker=$controller_version contract=$contract_version checkout=$cli_version" >&2
  exit 1
fi

for file in Model.js Panel.qml README.md Service.qml ServiceHost.js contract.json manifest.json; do
  cp "$plugin_root/$file" "$upstream/cli/omarchy/$file"
done
cp -a "$plugin_root/demo" "$upstream/cli/omarchy/"

# The standalone plugin can publish patch releases independently. The manifest
# stored in the CLI source tree must still match cli/package.json because the
# CLI packages that directory as its version-matched built-in integration.
node -e '
  const fs = require("node:fs")
  const file = process.argv[1]
  const version = process.argv[2]
  const manifest = JSON.parse(fs.readFileSync(file, "utf8"))
  manifest.version = version
  fs.writeFileSync(file, JSON.stringify(manifest, null, 2) + "\n")
' "$upstream/cli/omarchy/manifest.json" "$controller_version"

if ! git -C "$upstream" apply --reverse --check "$plugin_root/patches/status-schema-v1.patch" >/dev/null 2>&1; then
  git -C "$upstream" apply --check "$plugin_root/patches/status-schema-v1.patch"
  git -C "$upstream" apply "$plugin_root/patches/status-schema-v1.patch"
fi

node "$upstream/scripts/ci/check_omarchy_integration.mjs"
echo "Exported StateSet Omarchy plugin v$plugin_version for CLI v$controller_version to $upstream"

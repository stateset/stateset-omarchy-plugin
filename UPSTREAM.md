# Upstream handoff

The publishable QML files originate in `cli/omarchy` of the main iCommerce
repository. This mirror contains changes that must land there before the next
CLI release.

From this repository, export the runtime files into a clean checkout whose CLI
version matches `manifest.json`:

```bash
./scripts/export-to-upstream.sh /path/to/stateset-icommerce
```

The exporter also applies `patches/status-schema-v1.patch`, which adds the
explicit schema version, exact controller version, and allowlisted capability
handshake to `stateset-omarchy status --json`, and runs the upstream Omarchy
integration checker. Review the resulting upstream diff, run the upstream CLI
unit tests, and submit it through the main repository's normal review process.

`upstream-version.txt` records the exact CLI release used by this plugin. It is
deliberately separate from the plugin's own semantic version so standalone
patch releases do not trigger automated downgrade PRs. Release synchronization
updates both the generated runtime and this compatibility marker together. The
exporter rewrites only the copied upstream manifest version to that CLI release,
as required by the upstream packaging invariant.

The deterministic `demo/` harness is copied upstream with the runtime so CLI
release packaging can reproduce the same fictional states and screenshots.
Repository-only Node and QML test infrastructure remains owned by this mirror.

Do not release a later CLI version until the preserved mirror tests pass against
its generated plugin. This prevents release synchronization from silently
dropping security or operator-experience improvements.

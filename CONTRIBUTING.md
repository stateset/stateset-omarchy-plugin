# Contributing

Thanks for improving the StateSet iCommerce surface for Omarchy.

## Source ownership

Runtime plugin files are generated from `cli/omarchy` in the
[`stateset-icommerce`](https://github.com/stateset/stateset-icommerce) repository.
Changes to `Model.js`, `Panel.qml`, `Service.qml`, `ServiceHost.js`,
`manifest.json`, or the runtime sections of `README.md` should also be proposed
upstream so that a later release synchronization does not revert them.

This standalone repository owns its `test/` directory, GitHub workflows, and
this contributor guide, architecture notes, preview assets, upstream handoff,
and patch material. Release synchronization preserves those files.

## Local checks

Use Node.js 20.20 or newer and an Omarchy Quattro installation:

```bash
node --test
omarchy plugin validate .
git diff --check
```

CI additionally parses both QML entry points with Qt 6's `qmlformat` and runs
`qmllint` against a pinned Omarchy checkout. `test/process-boundary.test.js`
executes the real timeout/head pipeline against a deterministic fixture; keep
that test aligned with any polling-command change.

For live testing, copy the complete checkout to
`~/.config/omarchy/plugins/com.stateset.icommerce`; Omarchy intentionally
rejects symlinked plugin trees. Validate that copy, enable it, and restart the
shell when changing the shared service. Keep the Git-managed production
installation separate from this development copy.

## Runtime boundaries

Keep status parsing fail-closed and bounded. New controller output must be
normalized to a fixed schema in `Model.js` before it reaches QML. Do not add
runtime package downloads, dynamic shell fragments, credentials, database
writes, or model-provided command arguments. Operator actions must remain in
the explicit command allowlist and open visibly in a terminal.

Keep scheduling and lifecycle decisions in pure `Model.js` helpers where
possible. IPC must distinguish unknown, stale, and current state rather than
coercing probe failures into apparently valid values.

Any new setting belongs in both `barWidget.defaults` and `barWidget.schema`.
Add focused model or security regression tests for every behavior change.

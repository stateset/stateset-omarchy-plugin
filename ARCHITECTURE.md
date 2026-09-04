# Architecture

StateSet iCommerce is a two-entry Omarchy plugin with one deliberately narrow
controller boundary.

## Runtime flow

1. `Service.qml` polls the installed `stateset-omarchy` controller through a
   fixed, time-limited command and caps output before it reaches QML.
2. `Model.js` validates the JSON envelope, accepts the current status schema
   (plus legacy unversioned responses), normalizes every displayed field, and
   classifies failures.
3. `Panel.qml` renders the shared service snapshot. It can retain stale data for
   context, but never reports stale data as healthy or enables store actions.
4. Operator actions resolve through an exact action-to-command map and open in
   a visible floating terminal. No controller output can become a command.

`ServiceHost.js` contains the small compatibility lookup used to find the
plugin's shared service from the Omarchy bar host. A local fallback keeps the
panel loadable while a service is starting, without fabricating readiness.

## Trust boundaries

- The plugin does not open the commerce database or read provider credentials.
- Status and MCP lifecycle probes have fixed commands, deadlines, and output
  limits. Parsed strings and counts are sanitized and bounded.
- Commerce changes stay preview-only unless the separately installed
  controller has governed apply configured by the operator.
- Desktop notifications are derived only from normalized numeric deltas. They
  honor Omarchy Do Not Disturb, per-signal settings, and a cooldown.
- Controller schema versions fail closed when newer than this plugin supports.

## Ownership and releases

The canonical runtime source is `cli/omarchy` in `stateset-icommerce`. This
standalone repository adds validation, fixtures, preview assets, and release
automation. `scripts/export-to-upstream.sh` copies the runtime back to an
upstream checkout and applies the companion schema patch; `UPSTREAM.md`
documents that handoff. Scheduled release synchronization always opens a PR and
must pass both repositories' integration checks before it can be reviewed.

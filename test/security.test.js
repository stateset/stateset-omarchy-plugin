const test = require('node:test')
const assert = require('node:assert/strict')
const fs = require('node:fs')

const service = fs.readFileSync('Service.qml', 'utf8')
const panel = fs.readFileSync('Panel.qml', 'utf8')
const validationWorkflow = fs.readFileSync('.github/workflows/validate.yml', 'utf8')

test('status polling has a fixed command boundary and bounded streams', () => {
  assert.match(service, /command: \["\/usr\/bin\/bash", "-c", "set -o pipefail; \{ \/usr\/bin\/timeout --signal=TERM --kill-after=1s 8s stateset-omarchy status --json; \} 2>&1 \| \/usr\/bin\/head -c 65537"\]/)
  assert.doesNotMatch(service, /\bnpx\b|curl|wget/)
  assert.match(service, /Model\.MAX_OUTPUT_CHARS/)
  assert.match(service, /Model\.MAX_ERROR_CHARS/)
})

test('notifications use a fixed executable, policy controls, and Omarchy quiet mode', () => {
  assert.match(service, /"\/usr\/bin\/notify-send"/)
  assert.match(service, /Model\.pendingNotificationSummary\(pending\)/)
  assert.match(service, /firstPartyServiceFor\("omarchy\.notifications"\)/)
  assert.match(service, /notificationsQuiet/)
  assert.match(service, /Model\.cooldownRemainingMs/)
})

test('operator commands remain behind an exact action map', () => {
  assert.match(panel, /actionCommands: \(\{/)
  assert.match(panel, /dashboard: "stateset-omarchy dashboard"/)
  assert.match(panel, /serviceLogs: "\/usr\/bin\/journalctl --user -u stateset-icommerce-mcp\.service -n 100 --no-pager"/)
  assert.match(panel, /typeof controller !== "string"/)
  assert.doesNotMatch(panel, /\bnpx\b|curl|wget/)
})

test('IPC exposes standard panel aliases and explicit stale-state metadata', () => {
  assert.match(panel, /function show\(\): void \{ root\.open\(\) \}/)
  assert.match(panel, /function hide\(\): void \{ root\.close\(\) \}/)
  assert.match(panel, /stale: !service\.ready && service\.hasSnapshot/)
  assert.match(panel, /signalsComplete: service\.signalsComplete/)
  assert.match(panel, /statusSchemaVersion: service\.statusSchemaVersion/)
  assert.match(panel, /installed: service\.mcpInstalled/)
  assert.match(panel, /known: service\.mcpStatusKnown/)
  assert.match(panel, /effectiveRefreshIntervalSec: Model\.retryIntervalSeconds/)
  assert.match(panel, /notifications: \{ pending: Model\.normalizeNotificationDelta/)
  assert.match(panel, /snapshotRestored: service\.snapshotRestored/)
  assert.match(panel, /capabilitiesKnown: service\.capabilitiesKnown/)
})

test('last-good snapshots are bounded, normalized, and never restore readiness', () => {
  assert.match(service, /snapshotStatePath/)
  assert.match(service, /Model\.parseSnapshotState\(text, Date\.now\(\)\)/)
  assert.match(service, /ready = false/)
  assert.match(service, /snapshotRestored = true/)
  assert.match(service, /Model\.createSnapshotState\(value, savedAt\)/)
})

test('explicit controller capabilities gate every operator action', () => {
  for (const capability of ['attention', 'remediate', 'dashboard', 'agent', 'backup', 'doctor', 'agent-config', 'mcp-service']) {
    assert.match(panel, new RegExp(`supportsCapability\\("${capability}"\\)`))
  }
  assert.match(service, /!supportsCapability\("mcp-service"\)/)
})

test('QML analysis fails on every locally analyzable warning', () => {
  assert.match(validationWorkflow, /qmllint --max-warnings 0/)
  assert.doesNotMatch(validationWorkflow, /--max-warnings 10000/)
  assert.match(validationWorkflow, /qmltestrunner/)
})

test('failed polling backs off and unknown MCP state cannot trigger a lifecycle command', () => {
  assert.match(service, /consecutiveFailures \+= 1/)
  assert.match(service, /Model\.retryIntervalSeconds\(refreshIntervalSec, consecutiveFailures\)/)
  assert.match(panel, /if \(!service\.mcpStatusKnown\) service\.refreshService\(\)/)
  assert.match(panel, /root\.operational && !service\.mcpRefreshing/)
})

test('MCP lifecycle actions use a bounded direct process instead of a shell', () => {
  assert.match(service, /Model\.serviceActionCommand\(action\)/)
  assert.match(service, /serviceActionProcess\.command = command/)
  assert.match(service, /actionDeadline/)
  assert.match(service, /actionClearTimer\.stop\(\)/)
  assert.match(service, /Model\.MAX_ERROR_CHARS/)
  assert.doesNotMatch(panel, /serviceStart:|serviceStop:|serviceRestart:|serviceInstall:/)
  assert.match(panel, /confirmationAction === "stop"/)
  assert.match(panel, /confirmationAction === "restart"/)
})

test('MCP logs stay visible for recovery while mutations remain gated', () => {
  assert.match(panel, /visible: service\.mcpStatusKnown && service\.mcpInstalled\s+&& service\.supportsCapability\("mcp-service"\)/)
  assert.match(panel, /enabled: root\.operational && !service\.mcpRefreshing && !service\.actionRunning/)
  assert.match(panel, /if \(service\.mcpStatusKnown && service\.mcpInstalled\s+&& service\.supportsCapability\("mcp-service"\)\) indexes\.push\(9\)/)
})

test('notification deltas are persisted and delivered after quiet mode', () => {
  assert.match(service, /notificationStatePath/)
  assert.match(service, /"\/usr\/bin\/install", "-d", "-m", "700"/)
  assert.match(service, /atomicWrites: true/)
  assert.match(service, /Model\.mergePendingNotifications/)
  assert.match(service, /onDoNotDisturbChanged/)
})

test('interactive controls expose accessibility roles, names, and press actions', () => {
  assert.match(panel, /Accessible\.role: Accessible\.Button/)
  assert.match(panel, /Accessible\.role: Accessible\.StaticText/)
  assert.match(panel, /Accessible\.name:/)
  assert.match(panel, /Accessible\.description:/)
  assert.match(panel, /Accessible\.onPressAction:/)
})

test('panel provides scrolling and keyboard-driven action navigation', () => {
  assert.match(panel, /Flickable \{/)
  assert.match(panel, /ScrollBar\.vertical: ScrollBar/)
  assert.match(panel, /onMoveRequested: function\(dx, dy\)/)
  assert.match(panel, /onActivateRequested: root\.activateCursor\(\)/)
  assert.match(panel, /root\.launch\("doctor"\)/)
  assert.match(panel, /root\.launch\("configureAgents"\)/)
  assert.match(panel, /text === "g" \|\| text === "G"/)
})

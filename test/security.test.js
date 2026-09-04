const test = require('node:test')
const assert = require('node:assert/strict')
const fs = require('node:fs')

const service = fs.readFileSync('Service.qml', 'utf8')
const panel = fs.readFileSync('Panel.qml', 'utf8')

test('status polling has a fixed command boundary and bounded streams', () => {
  assert.match(service, /command: \["\/usr\/bin\/bash", "-c", "set -o pipefail; \{ \/usr\/bin\/timeout --signal=TERM --kill-after=1s 8s stateset-omarchy status --json; \} 2>&1 \| \/usr\/bin\/head -c 65537"\]/)
  assert.doesNotMatch(service, /\bnpx\b|curl|wget/)
  assert.match(service, /Model\.MAX_OUTPUT_CHARS/)
  assert.match(service, /Model\.MAX_ERROR_CHARS/)
})

test('notifications use a fixed executable, policy controls, and Omarchy quiet mode', () => {
  assert.match(service, /"\/usr\/bin\/notify-send"/)
  assert.match(service, /Model\.notificationSummary\(alerts, notificationAlerts\)/)
  assert.match(service, /firstPartyServiceFor\("omarchy\.notifications"\)/)
  assert.match(service, /!notificationsQuiet/)
  assert.match(service, /Model\.cooldownElapsed/)
})

test('operator commands remain behind an exact action map', () => {
  assert.match(panel, /actionCommands: \(\{/)
  assert.match(panel, /dashboard: "stateset-omarchy dashboard"/)
  assert.match(panel, /serviceRestart: "stateset-omarchy service restart"/)
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
  assert.match(panel, /mcp: \{ installed: service\.mcpInstalled/)
})

test('panel provides scrolling and keyboard-driven action navigation', () => {
  assert.match(panel, /Flickable \{/)
  assert.match(panel, /ScrollBar\.vertical: ScrollBar/)
  assert.match(panel, /onMoveRequested: function\(dx, dy\)/)
  assert.match(panel, /onActivateRequested: root\.activateCursor\(\)/)
})

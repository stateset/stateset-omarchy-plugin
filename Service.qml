import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

Item {
  id: root

  property var shell: null
  property var settings: ({})
  property bool refreshing: false
  property bool ready: false
  property bool configured: false
  property string dbPath: ""
  property string mode: "preview"
  property string message: "Discovering store"
  property string lastError: ""
  property string failureKind: ""
  property int statusSchemaVersion: 0
  property double sizeBytes: 0
  property var counts: ({ orders: 0, customers: 0, products: 0, returns: 0, payments: 0 })
  property var alerts: ({ pendingOrders: 0, failedPayments: 0, pendingReturns: 0, lowStock: 0, total: 0 })
  property bool signalsComplete: true
  property var unavailableSignals: []
  property bool hasAlertBaseline: false
  property bool hasSnapshot: false
  property date lastUpdated: new Date(0)
  property date lastAttempt: new Date(0)
  property date nextRefreshAt: new Date(0)
  property int consecutiveFailures: 0
  property bool mcpInstalled: false
  property bool mcpActive: false
  property bool mcpStatusKnown: false
  property string mcpState: "unknown"
  property bool mcpRefreshing: false
  property string mcpLastError: ""
  property date mcpLastUpdated: new Date(0)
  property string _stdout: ""
  property string _stderr: ""
  property bool _stdoutTruncated: false
  property bool _timedOut: false
  property string _serviceOutput: ""
  property bool _serviceTruncated: false
  property double lastNotificationAt: 0

  readonly property int refreshIntervalSec: {
    var value = parseInt(String(settings && settings.refreshIntervalSec || 120), 10)
    if (!isFinite(value)) value = 120
    return Math.max(30, Math.min(1800, value))
  }
  readonly property bool notificationsEnabled: settings && settings.notifications !== false
  readonly property int notificationCooldownMin: {
    var value = parseInt(String(settings && settings.notificationCooldownMin || 15), 10)
    if (!isFinite(value)) value = 15
    return Math.max(1, Math.min(240, value))
  }
  readonly property var notificationService: shell && typeof shell.firstPartyServiceFor === "function"
    ? shell.firstPartyServiceFor("omarchy.notifications") : null
  readonly property bool notificationsQuiet: notificationService
    ? notificationService.doNotDisturb === true : false

  function refresh() {
    if (refreshing || statusProcess.running) return
    refreshTimer.stop()
    refreshing = true
    _stdout = ""
    _stderr = ""
    _stdoutTruncated = false
    _timedOut = false
    lastAttempt = new Date()
    statusProcess.running = true
  }

  function appendStdout(data) {
    var result = Model.appendBounded(_stdout, data, Model.MAX_OUTPUT_CHARS)
    _stdout = result.text
    _stdoutTruncated = _stdoutTruncated || result.truncated
  }

  function appendStderr(data) {
    _stderr = Model.appendBounded(_stderr, data, Model.MAX_ERROR_CHARS).text
  }

  function fail(messageText, kind) {
    ready = false
    failureKind = kind || "controller-error"
    lastError = Model.safeText(messageText, 240, "StateSet controller failed")
    message = lastError
    consecutiveFailures += 1
    scheduleRefresh()
  }

  function scheduleRefresh() {
    var delay = Model.retryIntervalSeconds(refreshIntervalSec, consecutiveFailures)
    nextRefreshAt = new Date(Date.now() + delay * 1000)
    refreshTimer.interval = delay * 1000
    refreshTimer.restart()
  }

  function refreshService() {
    if (serviceStatusProcess.running) return
    _serviceOutput = ""
    _serviceTruncated = false
    mcpRefreshing = true
    serviceStatusProcess.running = true
  }

  function appendServiceOutput(data) {
    var result = Model.appendBounded(_serviceOutput, data, Model.MAX_ERROR_CHARS)
    _serviceOutput = result.text
    _serviceTruncated = _serviceTruncated || result.truncated
  }

  function finishService(exitCode) {
    mcpRefreshing = false
    if (exitCode !== 0 || _serviceTruncated) {
      mcpStatusKnown = false
      mcpActive = false
      mcpLastError = Model.safeText(_serviceOutput, 160, "Unable to read MCP service status")
      mcpState = "unknown"
      return
    }
    try {
      var value = Model.parseServiceStatusJson(_serviceOutput)
      mcpInstalled = value.installed
      mcpActive = value.active
      mcpStatusKnown = true
      mcpState = value.state
      mcpLastError = ""
      mcpLastUpdated = new Date()
    } catch (error) {
      mcpStatusKnown = false
      mcpActive = false
      mcpLastError = "Invalid MCP service response"
      mcpState = "unknown"
    }
  }

  function refreshIfStale() {
    var updated = lastUpdated instanceof Date ? lastUpdated.getTime() : 0
    if (updated <= 0 || Date.now() - updated >= refreshIntervalSec * 1000) refresh()
  }

  function finish(exitCode) {
    refreshing = false
    statusDeadline.stop()
    killDeadline.stop()
    var failure = Model.classifyFailure(exitCode, _stderr || _stdout, _timedOut, _stdoutTruncated)
    if (failure === "timeout") {
      fail("StateSet controller timed out", failure)
      return
    }
    if (failure === "oversized-response") {
      fail("StateSet controller response exceeded 64 KiB", failure)
      return
    }
    if (exitCode !== 0) {
      fail(_stderr || _stdout || "StateSet controller is unavailable; install @stateset/cli first", failure)
      return
    }
    try {
      var value = Model.parseStatusJson(_stdout)
      ready = value.ok
      statusSchemaVersion = value.schemaVersion
      configured = value.configured
      dbPath = value.dbPath
      mode = value.mode
      message = value.message
      sizeBytes = value.sizeBytes
      counts = value.counts
      signalsComplete = value.signalsComplete
      unavailableSignals = value.unavailableSignals
      var nextAlerts = Model.normalizeAlerts(value.alerts)
      var notificationAlerts = Model.notificationCandidate(alerts, nextAlerts, {
        failedPayments: settings && settings.notifyFailedPayments !== false,
        lowStock: settings && settings.notifyLowStock !== false,
        pendingReturns: settings && settings.notifyPendingReturns !== false
      })
      var notificationNow = Date.now()
      if (value.ok && notificationsEnabled && !notificationsQuiet
          && Model.cooldownElapsed(lastNotificationAt, notificationNow, notificationCooldownMin)
          && Model.shouldNotify(alerts, notificationAlerts, hasAlertBaseline)) {
        Quickshell.execDetached([
          "/usr/bin/notify-send", "--app-name", "StateSet iCommerce", "--urgency", notificationAlerts.failedPayments > alerts.failedPayments ? "critical" : "normal",
          "Commerce needs attention", Model.notificationSummary(alerts, notificationAlerts)
        ])
        lastNotificationAt = notificationNow
      }
      alerts = nextAlerts
      hasAlertBaseline = true
      hasSnapshot = true
      failureKind = ready ? "" : (configured ? "store-unavailable" : "not-configured")
      lastError = ready ? "" : message
      lastUpdated = new Date()
      consecutiveFailures = ready ? 0 : consecutiveFailures + 1
      scheduleRefresh()
      refreshService()
    } catch (error) {
      var incompatible = String(error).indexOf("Unsupported status schema version") >= 0
      fail(incompatible ? "StateSet controller uses an unsupported status schema" : "Invalid response from stateset-omarchy",
        incompatible ? "incompatible-controller" : "invalid-response")
    }
  }

  Timer {
    id: refreshTimer
    interval: root.refreshIntervalSec * 1000
    repeat: false
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    interval: 300000
    repeat: true
    running: root.hasSnapshot
    onTriggered: root.refreshService()
  }

  Timer {
    id: statusDeadline
    interval: 10000
    repeat: false
    onTriggered: {
      if (!statusProcess.running) return
      root._timedOut = true
      statusProcess.running = false
      killDeadline.restart()
    }
  }

  Timer {
    id: killDeadline
    interval: 1000
    repeat: false
    onTriggered: statusProcess.signal(9)
  }

  Process {
    id: statusProcess
    running: false
    command: ["/usr/bin/bash", "-c", "set -o pipefail; { /usr/bin/timeout --signal=TERM --kill-after=1s 8s stateset-omarchy status --json; } 2>&1 | /usr/bin/head -c 65537"]
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(data) { root.appendStdout(data) }
    }
    stderr: SplitParser {
      splitMarker: ""
      onRead: function(data) { root.appendStderr(data) }
    }
    onStarted: statusDeadline.restart()
    onExited: function(exitCode) {
      root.finish(exitCode)
    }
  }


  Process {
    id: serviceStatusProcess
    running: false
    command: ["/usr/bin/bash", "-c", "set -o pipefail; { /usr/bin/timeout --signal=TERM --kill-after=1s 5s stateset-omarchy service status --json; } 2>&1 | /usr/bin/head -c 4097"]
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(data) { root.appendServiceOutput(data) }
    }
    stderr: SplitParser {
      splitMarker: ""
      onRead: function(data) { root.appendServiceOutput(data) }
    }
    onExited: function(exitCode) { root.finishService(exitCode) }
  }
}

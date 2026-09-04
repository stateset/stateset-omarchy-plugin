import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import "../.."
import "../../Model.js" as Model

TestCase {
  name: "StateSetService"

  property var service: null

  QtObject {
    id: notificationService
    property bool doNotDisturb: false
  }

  QtObject {
    id: shellStub
    function firstPartyServiceFor(pluginId) {
      return pluginId === "omarchy.notifications" ? notificationService : null
    }
  }

  Component {
    id: serviceComponent
    Service {}
  }

  function init() {
    Quickshell.reset()
    ProcessRegistry.processes = []
    notificationService.doNotDisturb = false
    service = serviceComponent.createObject(this, { shell: shellStub })
    verify(service !== null)
    service.loadNotificationState("")
  }

  function cleanup() {
    service.destroy()
    service = null
  }

  function findProcess(predicate) {
    for (var index = 0; index < ProcessRegistry.processes.length; index += 1) {
      var process = ProcessRegistry.processes[index]
      if (predicate(process)) return process
    }
    return null
  }

  function statusProcess() {
    return findProcess(function(process) {
      return process.command.length >= 3
        && process.command[0] === "/usr/bin/bash"
        && String(process.command[2]).indexOf(" status --json") >= 0
        && String(process.command[2]).indexOf(" service status") < 0
    })
  }

  function lifecycleProcess() {
    return findProcess(function(process) {
      return process.command.length >= 7
        && process.command[0] === "/usr/bin/timeout"
        && process.command[4] === "stateset-omarchy"
        && process.command[5] === "service"
        && process.command[6] !== "status"
    })
  }

  function statusJson(alerts) {
    return JSON.stringify({
      schemaVersion: 1,
      controllerVersion: "1.30.0",
      capabilities: ["status", "dashboard", "agent", "attention", "remediate", "backup", "doctor", "agent-config", "mcp-service"],
      ok: true,
      configured: true,
      message: "Store ready",
      counts: { orders: 8, customers: 4, products: 6, returns: 1, payments: 7 },
      alerts: alerts || {}
    })
  }

  function completeStatus(alerts) {
    var process = statusProcess()
    verify(process !== null)
    process.complete(0, statusJson(alerts), "")
  }

  function test_first_snapshot_establishes_baseline_without_notification() {
    completeStatus({ failedPayments: 2 })
    compare(service.ready, true)
    compare(service.hasAlertBaseline, true)
    compare(service.controllerVersion, "1.30.0")
    compare(service.capabilitiesKnown, true)
    verify(service.supportsCapability("backup"))
    compare(Quickshell.detachedCommands.length, 0)
  }

  function test_dnd_queues_and_later_delivers_a_coalesced_notification() {
    completeStatus({ failedPayments: 1 })
    notificationService.doNotDisturb = true
    service.refresh()
    completeStatus({ failedPayments: 3, lowStock: 2 })
    compare(service.pendingNotifications.failedPayments, 2)
    compare(service.pendingNotifications.lowStock, 2)
    compare(Quickshell.detachedCommands.length, 0)

    notificationService.doNotDisturb = false
    compare(Quickshell.detachedCommands.length, 1)
    verify(String(Quickshell.detachedCommands[0][6]).indexOf("+2 failed payments") >= 0)
    compare(service.pendingNotifications.failedPayments, 0)
  }

  function test_persisted_notification_is_reconciled_before_delivery() {
    service.pendingNotifications = { failedPayments: 4, pendingReturns: 0, lowStock: 0 }
    service.notificationSnapshotReady = false
    service.deliverPendingNotifications()
    compare(Quickshell.detachedCommands.length, 0)

    completeStatus({ failedPayments: 0 })
    compare(service.pendingNotifications.failedPayments, 0)
    compare(Quickshell.detachedCommands.length, 0)
  }

  function test_disabled_signal_is_removed_before_delayed_delivery() {
    completeStatus({ failedPayments: 1 })
    notificationService.doNotDisturb = true
    service.refresh()
    completeStatus({ failedPayments: 3, lowStock: 2 })
    compare(service.pendingNotifications.failedPayments, 2)
    compare(service.pendingNotifications.lowStock, 2)

    service.settings = { notifyFailedPayments: false, notifyLowStock: true }
    compare(service.pendingNotifications.failedPayments, 0)
    compare(service.pendingNotifications.lowStock, 2)
    notificationService.doNotDisturb = false
    compare(Quickshell.detachedCommands.length, 1)
    verify(String(Quickshell.detachedCommands[0][6]).indexOf("failed payment") < 0)
    verify(String(Quickshell.detachedCommands[0][6]).indexOf("+2 low-stock SKUs") >= 0)
  }

  function test_direct_lifecycle_action_updates_mcp_state_and_feedback() {
    service.ready = true
    service.configured = true
    verify(service.runServiceAction("start"))
    var process = lifecycleProcess()
    verify(process !== null)
    compare(process.command, [
      "/usr/bin/timeout", "--signal=TERM", "--kill-after=1s", "10s",
      "stateset-omarchy", "service", "start", "--json"
    ])
    process.complete(0, '{"installed":true,"active":true,"state":"active"}', "")
    compare(service.actionRunning, false)
    compare(service.actionStatus, "MCP service started")
    compare(service.mcpActive, true)
    compare(service.mcpStatusKnown, true)
  }

  function test_unknown_or_unconfigured_actions_fail_closed() {
    compare(service.runServiceAction("remove"), false)
    compare(lifecycleProcess(), null)
    compare(service.runServiceAction("install"), false)
    compare(service.actionError, "Configure a readable store before installing MCP")
  }

  function test_missing_explicit_capability_disables_mcp_actions() {
    service.ready = true
    service.configured = true
    service.capabilitiesKnown = true
    service.capabilities = ["status", "backup"]
    compare(service.runServiceAction("start"), false)
    compare(lifecycleProcess(), null)
  }

  function test_fresh_snapshot_restores_data_without_enabling_actions() {
    var restored = serviceComponent.createObject(this, { shell: shellStub })
    verify(restored !== null)
    var now = Date.now()
    var state = Model.createSnapshotState(JSON.parse(statusJson({ failedPayments: 2 })), now)
    restored.loadSnapshotState(JSON.stringify(state))
    compare(restored.hasSnapshot, true)
    compare(restored.snapshotRestored, true)
    compare(restored.ready, false)
    compare(restored.configured, true)
    compare(restored.counts.orders, 8)
    compare(restored.alerts.failedPayments, 2)
    compare(restored.controllerVersion, "1.30.0")
    compare(restored.runServiceAction("start"), false)
    restored.destroy()
  }

  function test_lifecycle_failure_surfaces_bounded_cli_feedback() {
    service.ready = true
    service.configured = true
    verify(service.runServiceAction("restart"))
    var process = lifecycleProcess()
    verify(process !== null)
    process.complete(1, "", "Permission denied")
    compare(service.actionRunning, false)
    compare(service.actionError, "Permission denied")
    compare(service.actionStatus, "Permission denied")
  }

  function test_missing_controller_finishes_lifecycle_action() {
    service.ready = true
    service.configured = true
    verify(service.runServiceAction("start"))
    var process = lifecycleProcess()
    verify(process !== null)
    process.complete(127, "", "stateset-omarchy: command not found")
    compare(service.actionRunning, false)
    compare(service.actionError, "stateset-omarchy: command not found")
  }

  function test_lifecycle_timeout_has_specific_feedback() {
    service.ready = true
    service.configured = true
    verify(service.runServiceAction("restart"))
    var process = lifecycleProcess()
    verify(process !== null)
    process.complete(124, "", "")
    compare(service.actionRunning, false)
    compare(service.actionError, "MCP service action timed out")
  }
}

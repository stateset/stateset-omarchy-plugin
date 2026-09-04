import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "ServiceHost.js" as ServiceHost

Panel {
  id: root
  moduleName: "com.stateset.icommerce"
  ipcTarget: "com.stateset.icommerce"
  manageIpc: false

  QtObject {
    id: fallbackService
    property var settings: ({})
    property bool refreshing: false
    property bool ready: false
    property bool configured: false
    property string dbPath: ""
    property string mode: "preview"
    property string message: "Starting StateSet"
    property string lastError: ""
    property string failureKind: ""
    property int statusSchemaVersion: 0
    property double sizeBytes: 0
    property bool hasSnapshot: false
    property date lastUpdated: new Date(0)
    property date lastAttempt: new Date(0)
    property date nextRefreshAt: new Date(0)
    property int consecutiveFailures: 0
    property int refreshIntervalSec: 120
    property var counts: ({ orders: 0, customers: 0, products: 0, returns: 0, payments: 0 })
    property var alerts: ({ pendingOrders: 0, failedPayments: 0, pendingReturns: 0, lowStock: 0, total: 0 })
    property bool signalsComplete: true
    property var unavailableSignals: []
    property bool mcpInstalled: false
    property bool mcpActive: false
    property bool mcpStatusKnown: false
    property string mcpState: "unknown"
    property bool mcpRefreshing: false
    property string mcpLastError: ""
    property date mcpLastUpdated: new Date(0)
    function refresh() {}
    function refreshIfStale() {}
    function refreshService() {}
  }

  readonly property var hostedService: {
    var _ = bar && bar.shell ? bar.shell._services : null
    return ServiceHost.hostedService(bar)
  }
  readonly property var service: hostedService !== null ? hostedService : fallbackService
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var actionCommands: ({
    agent: "stateset-omarchy agent",
    attention: "stateset-omarchy attention",
    backup: "stateset-omarchy backup",
    configureAgents: "stateset-omarchy configure --agent all",
    dashboard: "stateset-omarchy dashboard",
    doctor: "stateset-omarchy doctor",
    remediate: "stateset-omarchy remediate",
    serviceInstall: "stateset-omarchy service install",
    serviceLogs: "/usr/bin/journalctl --user -u stateset-icommerce-mcp.service -n 100 --no-pager",
    serviceRestart: "stateset-omarchy service restart",
    serviceStart: "stateset-omarchy service start",
    serviceStatus: "stateset-omarchy service status",
    serviceStop: "stateset-omarchy service stop"
  })
  readonly property bool operational: service.ready && service.configured
  readonly property string recoveryText: {
    var text = ""
    if (service.failureKind === "controller-missing") text = "Install @stateset/cli@1.30.0, then refresh."
    else if (service.failureKind === "incompatible-controller") text = "Update the StateSet CLI to the version in manifest.json."
    else if (service.failureKind === "timeout") text = "The controller did not answer within 8 seconds."
    else if (service.failureKind === "not-configured") text = "Run stateset-omarchy install inside a store project."
    else if (service.failureKind === "store-unavailable") text = "The configured commerce store is not readable."
    else text = service.hasSnapshot ? "Showing the last valid snapshot." : "Check the controller and store configuration."
    var retry = Model.retryCountdownLabel(service.nextRefreshAt, nowMs)
    return retry ? text + " " + retry + "." : text
  }
  property double nowMs: Date.now()
  property bool cursorActive: false
  property int actionIndex: -1

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function launch(action) {
    var controller = actionCommands[action]
    if (!bar || typeof controller !== "string" || controller === "") return
    bar.run("omarchy-launch-floating-terminal-with-presentation '" + controller + "'")
    close()
  }

  function mcpToggleAction() {
    if (!service.mcpStatusKnown) return ""
    if (!service.mcpInstalled) return "serviceInstall"
    return service.mcpActive ? "serviceStop" : "serviceStart"
  }

  function triggerMcpAction() {
    if (!service.mcpStatusKnown) service.refreshService()
    else launch(mcpToggleAction())
  }

  function availableActions() {
    var indexes = []
    if (operational && (service.alerts.total || 0) > 0) indexes.push(0, 1)
    if (operational) indexes.push(2, 3, 4)
    if ((service.ready || !service.refreshing) && service.failureKind !== "controller-missing") indexes.push(5)
    if (operational) indexes.push(6, 7)
    if (operational && service.mcpStatusKnown && service.mcpInstalled) indexes.push(8)
    if (service.mcpStatusKnown && service.mcpInstalled) indexes.push(9)
    return indexes
  }

  function setCursor(index) {
    cursorActive = true
    actionIndex = index
    scrollActionIntoView()
  }

  function moveCursor(dx, dy) {
    var indexes = availableActions()
    if (indexes.length === 0) return
    var direction = dy !== 0 ? dy : dx
    var position = indexes.indexOf(actionIndex)
    if (position < 0) position = direction < 0 ? 0 : -1
    position = (position + (direction < 0 ? -1 : 1) + indexes.length) % indexes.length
    setCursor(indexes[position])
  }

  function activateCursor() {
    if (actionIndex === 7 && availableActions().indexOf(7) >= 0) {
      triggerMcpAction()
      return
    }
    var actions = ["attention", "remediate", "dashboard", "agent", "backup", "doctor", "configureAgents", mcpToggleAction(), "serviceRestart", "serviceLogs"]
    if (availableActions().indexOf(actionIndex) >= 0) launch(actions[actionIndex])
  }

  function actionItem(index) {
    if (index === 0) return reviewButton
    if (index === 1) return resolveButton
    if (index === 2) return dashboardButton
    if (index === 3) return agentButton
    if (index === 4) return backupButton
    if (index === 5) return service.ready ? doctorButton : recoveryDoctorButton
    if (index === 6) return agentsButton
    if (index === 7) return mcpButton
    if (index === 8) return restartButton
    if (index === 9) return logsButton
    return null
  }

  function scrollActionIntoView() {
    Qt.callLater(function() {
      var item = actionItem(actionIndex)
      if (!item || !panelFlick) return
      var point = item.mapToItem(panelFlick.contentItem, 0, 0)
      var margin = Style.space(8)
      if (point.y < panelFlick.contentY + margin) panelFlick.contentY = Math.max(0, point.y - margin)
      else if (point.y + item.height > panelFlick.contentY + panelFlick.height - margin) {
        panelFlick.contentY = Math.min(panelFlick.contentHeight - panelFlick.height,
          point.y + item.height + margin - panelFlick.height)
      }
    })
  }

  onOpenedChanged: if (opened) {
    cursorActive = false
    actionIndex = -1
    panelFlick.contentY = 0
    service.refreshIfStale()
    service.refreshService()
  }

  Timer {
    interval: 30000
    repeat: true
    running: root.opened
    triggeredOnStart: true
    onTriggered: root.nowMs = Date.now()
  }

  Binding {
    target: root.hostedService
    property: "settings"
    value: root.settings
    when: root.hostedService !== null
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { service.refresh(); return "ok" }
    function status(): string {
      return JSON.stringify({
        ready: service.ready,
        configured: service.configured,
        refreshing: service.refreshing,
        failureKind: service.failureKind,
        statusSchemaVersion: service.statusSchemaVersion,
        hasSnapshot: service.hasSnapshot,
        stale: !service.ready && service.hasSnapshot,
        mode: service.mode,
        dbPath: service.dbPath,
        sizeBytes: service.sizeBytes,
        counts: service.counts,
        alerts: service.alerts,
        signalsComplete: service.signalsComplete,
        unavailableSignals: service.unavailableSignals,
        mcp: {
          installed: service.mcpInstalled,
          active: service.mcpActive,
          known: service.mcpStatusKnown,
          state: service.mcpState,
          error: service.mcpLastError,
          lastUpdated: service.mcpLastUpdated instanceof Date && service.mcpLastUpdated.getTime() > 0 ? service.mcpLastUpdated.toISOString() : null
        },
        lastUpdated: service.lastUpdated instanceof Date && service.lastUpdated.getTime() > 0 ? service.lastUpdated.toISOString() : null,
        lastAttempt: service.lastAttempt instanceof Date && service.lastAttempt.getTime() > 0 ? service.lastAttempt.toISOString() : null,
        nextRefreshAt: service.nextRefreshAt instanceof Date && service.nextRefreshAt.getTime() > 0 ? service.nextRefreshAt.toISOString() : null,
        consecutiveFailures: service.consecutiveFailures,
        effectiveRefreshIntervalSec: Model.retryIntervalSeconds(service.refreshIntervalSec, service.consecutiveFailures),
        error: service.lastError
      })
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: service.refreshing && !service.hasSnapshot ? "󰑓" : !service.ready ? "󰅖" : !service.configured ? "󰒓" : !service.signalsComplete || (service.alerts.total || 0) > 0 ? "󰀪" : "󰆼"
    foreground: !service.ready || (service.alerts.failedPayments || 0) > 0 ? root.urgent : root.foreground
    tooltipText: service.refreshing ? "Refreshing StateSet Commerce" : (!service.signalsComplete ? "Some operational signals unavailable · " : "") + ((service.alerts.total || 0) > 0 ? (service.alerts.total + " items need attention · ") : "") + service.message
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton || buttonCode === Qt.MiddleButton) service.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(390))
    contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) { root.moveCursor(dx, dy) }
      onActivateRequested: root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (text === "r" || text === "R") service.refresh()
        else if (text === "d" || text === "D") { if (root.operational) root.launch("dashboard") }
        else if (text === "a" || text === "A") { if (root.operational) root.launch("agent") }
        else if (text === "b" || text === "B") { if (root.operational) root.launch("backup") }
        else if (text === "c" || text === "C") {
          if (service.failureKind !== "controller-missing") root.launch("doctor")
        }
        else if (text === "g" || text === "G") { if (root.operational) root.launch("configureAgents") }
        else if (text === "m" || text === "M") { if (root.operational) root.triggerMcpAction() }
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        ColumnLayout {
          id: content
          width: panelFlick.width
          spacing: Style.space(12)

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(10)

          Text {
            text: "󰆼"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.display
          }
          ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.space(2)
            Text {
              text: "StateSet Commerce"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }
            Text {
              Layout.fillWidth: true
              text: service.message
              textFormat: Text.PlainText
              color: service.ready ? root.dim : root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideMiddle
            }
          }
          PanelActionButton {
            iconText: service.refreshing ? "󰑓" : "󰑐"
            foreground: root.foreground
            fontFamily: root.fontFamily
            enabled: !service.refreshing
            onClicked: service.refresh()
          }
        }

        PanelSeparator { foreground: root.foreground }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(8)
          Text {
            Layout.fillWidth: true
            text: service.dbPath || "Run stateset-omarchy install inside a store project"
            textFormat: Text.PlainText
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideMiddle
          }
          Text {
            text: (service.sizeBytes > 0 ? Model.formatBytes(service.sizeBytes) + " · " : "") + Model.freshnessLabel(service.lastUpdated, root.nowMs)
            textFormat: Text.PlainText
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        Rectangle {
          visible: !service.ready && !service.refreshing
          Layout.fillWidth: true
          implicitHeight: unavailableRow.implicitHeight + Style.space(18)
          radius: Style.cornerRadius
          color: Color.popups.background
          border.color: root.urgent
          border.width: 1

          RowLayout {
            id: unavailableRow
            anchors.fill: parent
            anchors.margins: Style.space(9)
            spacing: Style.space(8)
            Text {
              Layout.fillWidth: true
              text: root.recoveryText
              textFormat: Text.PlainText
              wrapMode: Text.WordWrap
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
            Button {
              id: recoveryDoctorButton
              visible: service.failureKind !== "controller-missing"
              text: "DOCTOR"
              bordered: true
              foreground: root.foreground
              background: Color.popups.background
              accent: root.urgent
              fontFamily: root.fontFamily
              hasCursor: root.cursorActive && root.actionIndex === 5
              onHovered: function(on) { if (on) root.setCursor(5) }
              onClicked: root.launch("doctor")
            }
          }
        }

        Rectangle {
          visible: service.ready && !service.signalsComplete
          Layout.fillWidth: true
          implicitHeight: partialSignals.implicitHeight + Style.space(18)
          radius: Style.cornerRadius
          color: Color.popups.background
          border.color: Color.accent
          border.width: 1

          RowLayout {
            id: partialSignals
            anchors.fill: parent
            anchors.margins: Style.space(9)
            spacing: Style.space(8)
            Text {
              text: "󰀪"
              color: Color.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
            }
            ColumnLayout {
              Layout.fillWidth: true
              spacing: 0
              Text {
                text: "PARTIAL OPERATIONAL DATA"
                textFormat: Text.PlainText
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
              }
              Text {
                Layout.fillWidth: true
                text: "Unavailable: " + (service.unavailableSignals || []).map(function(signal) {
                  return ({ orders: "orders", payments: "payments", pendingReturns: "returns", lowStockItems: "inventory" })[signal] || signal
                }).join(", ")
                textFormat: Text.PlainText
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }
            }
          }
        }

        Rectangle {
          visible: (service.alerts.total || 0) > 0
          Layout.fillWidth: true
          implicitHeight: attentionRow.implicitHeight + Style.space(18)
          radius: Style.cornerRadius
          color: Color.popups.background
          border.color: (service.alerts.failedPayments || 0) > 0 ? root.urgent : Color.accent
          border.width: 1

          RowLayout {
            id: attentionRow
            anchors.fill: parent
            anchors.margins: Style.space(9)
            spacing: Style.space(8)
            Text {
              text: (service.alerts.failedPayments || 0) > 0 ? "󰅖" : "󰀪"
              color: (service.alerts.failedPayments || 0) > 0 ? root.urgent : Color.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
            }
            ColumnLayout {
              Layout.fillWidth: true
              spacing: 0
              Text {
                text: Model.attentionHeadline(service.alerts)
                textFormat: Text.PlainText
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
              }
              Text {
                Layout.fillWidth: true
                text: Model.attentionSummary(service.alerts)
                textFormat: Text.PlainText
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }
            }
            ColumnLayout {
              spacing: Style.space(4)
              Button {
                id: reviewButton
                text: "REVIEW"
                bordered: true
                foreground: root.foreground
                background: Color.popups.background
                accent: Color.accent
                fontFamily: root.fontFamily
                enabled: root.operational
                hasCursor: root.cursorActive && root.actionIndex === 0
                onHovered: function(on) { if (on) root.setCursor(0) }
                onClicked: root.launch("attention")
              }
              Button {
                id: resolveButton
                text: "RESOLVE"
                bordered: true
                foreground: root.foreground
                background: Color.popups.background
                accent: root.urgent
                fontFamily: root.fontFamily
                enabled: root.operational
                hasCursor: root.cursorActive && root.actionIndex === 1
                onHovered: function(on) { if (on) root.setCursor(1) }
                onClicked: root.launch("remediate")
              }
            }
          }
        }

        Rectangle {
          Layout.fillWidth: true
          implicitHeight: metrics.implicitHeight + Style.space(18)
          radius: Style.cornerRadius
          color: Color.popups.background
          border.color: service.mode === "preview" ? Color.accent : root.urgent
          border.width: 1
          RowLayout {
            id: metrics
            anchors.fill: parent
            anchors.margins: Style.space(9)
            Repeater {
              model: [
                { label: "ORDERS", value: service.counts.orders || 0 },
                { label: "CUSTOMERS", value: service.counts.customers || 0 },
                { label: "PRODUCTS", value: service.counts.products || 0 },
                { label: "RETURNS", value: service.counts.returns || 0 },
                { label: "PAYMENTS", value: service.counts.payments || 0 }
              ]
              ColumnLayout {
                id: metric
                required property var modelData
                Layout.fillWidth: true
                spacing: 0
                Text {
                  id: metricValue
                  Layout.alignment: Qt.AlignHCenter
                  text: Model.formatCount(metric.modelData.value)
                  textFormat: Text.PlainText
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  font.bold: true
                  MouseArea {
                    id: metricHover
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton
                  }
                  PanelToolTip {
                    visible: metricHover.containsMouse
                    text: metric.modelData.label + ": " + Model.formatExactCount(metric.modelData.value)
                  }
                }
                Text {
                  Layout.alignment: Qt.AlignHCenter
                  text: metric.modelData.label
                  textFormat: Text.PlainText
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }
          }
        }

        Text {
          Layout.fillWidth: true
          text: !service.ready ? "STATUS UNAVAILABLE · ACTIONS PAUSED" : service.mode === "preview" ? "PREVIEW ONLY · WRITES REQUIRE EXPLICIT APPLY" : "GOVERNED APPLY · OPERATOR POLICY ACTIVE"
          textFormat: Text.PlainText
          color: !service.ready || service.mode !== "preview" ? root.urgent : Color.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignHCenter
          font.bold: true
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(8)
          Button {
            id: dashboardButton
            Layout.fillWidth: true
            text: "DASHBOARD"
            bordered: true
            foreground: root.foreground
            background: Color.popups.background
            accent: Color.accent
            fontFamily: root.fontFamily
            enabled: root.operational
            hasCursor: root.cursorActive && root.actionIndex === 2
            onHovered: function(on) { if (on) root.setCursor(2) }
            onClicked: root.launch("dashboard")
          }
          Button {
            id: agentButton
            Layout.fillWidth: true
            text: "AGENT"
            bordered: true
            foreground: root.foreground
            background: Color.popups.background
            accent: Color.accent
            fontFamily: root.fontFamily
            enabled: root.operational
            hasCursor: root.cursorActive && root.actionIndex === 3
            onHovered: function(on) { if (on) root.setCursor(3) }
            onClicked: root.launch("agent")
          }
          Button {
            id: backupButton
            Layout.fillWidth: true
            text: "BACKUP"
            bordered: true
            foreground: root.foreground
            background: Color.popups.background
            accent: Color.accent
            fontFamily: root.fontFamily
            enabled: root.operational
            hasCursor: root.cursorActive && root.actionIndex === 4
            onHovered: function(on) { if (on) root.setCursor(4) }
            onClicked: root.launch("backup")
          }
        }

        RowLayout {
          visible: service.ready
          Layout.fillWidth: true
          spacing: Style.space(8)
          Button {
            id: doctorButton
            Layout.fillWidth: true
            text: "DOCTOR"
            bordered: true
            foreground: root.foreground
            background: Color.popups.background
            accent: Color.accent
            fontFamily: root.fontFamily
            hasCursor: root.cursorActive && root.actionIndex === 5
            onHovered: function(on) { if (on) root.setCursor(5) }
            onClicked: root.launch("doctor")
          }
          Button {
            id: agentsButton
            Layout.fillWidth: true
            text: "AGENTS"
            bordered: true
            foreground: root.foreground
            background: Color.popups.background
            accent: Color.accent
            fontFamily: root.fontFamily
            enabled: root.operational
            hasCursor: root.cursorActive && root.actionIndex === 6
            onHovered: function(on) { if (on) root.setCursor(6) }
            onClicked: root.launch("configureAgents")
          }
          Button {
            id: mcpButton
            Layout.fillWidth: true
            text: service.mcpRefreshing ? "MCP…" : !service.mcpStatusKnown ? "CHECK MCP" : !service.mcpInstalled ? "INSTALL MCP" : service.mcpActive ? "STOP MCP" : "START MCP"
            tooltipText: service.mcpLastError || ("MCP service: " + service.mcpState)
            bordered: true
            foreground: root.foreground
            background: Color.popups.background
            accent: Color.accent
            fontFamily: root.fontFamily
            enabled: root.operational && !service.mcpRefreshing
            hasCursor: root.cursorActive && root.actionIndex === 7
            onHovered: function(on) { if (on) root.setCursor(7) }
            onClicked: root.triggerMcpAction()
          }
        }

        RowLayout {
          visible: service.ready && service.mcpStatusKnown && service.mcpInstalled
          Layout.fillWidth: true
          spacing: Style.space(8)
          Button {
            id: restartButton
            Layout.fillWidth: true
            text: "RESTART MCP"
            tooltipText: "Restart the local MCP service"
            bordered: true
            foreground: root.foreground
            background: Color.popups.background
            accent: Color.accent
            fontFamily: root.fontFamily
            enabled: root.operational
            hasCursor: root.cursorActive && root.actionIndex === 8
            onHovered: function(on) { if (on) root.setCursor(8) }
            onClicked: root.launch("serviceRestart")
          }
          Button {
            id: logsButton
            Layout.fillWidth: true
            text: "MCP LOGS"
            tooltipText: "Show the latest 100 local MCP service log lines"
            bordered: true
            foreground: root.foreground
            background: Color.popups.background
            accent: Color.accent
            fontFamily: root.fontFamily
            hasCursor: root.cursorActive && root.actionIndex === 9
            onHovered: function(on) { if (on) root.setCursor(9) }
            onClicked: root.launch("serviceLogs")
          }
        }
        }
      }
    }
  }
}

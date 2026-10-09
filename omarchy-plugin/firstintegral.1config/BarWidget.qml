import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

// Bar face for 1config. The ring only. The percent stays in the tooltip
// and in the panel. Data lives in Service.qml.
BarWidget {
  id: root
  moduleName: "firstintegral.1config"

  readonly property var service: bar && bar.shell ? bar.shell.serviceFor("firstintegral.1config") : null
  readonly property bool alarming: service ? service.alarming === true : false
  readonly property bool brainFault: service && service.brain && String(service.brain.verdict || "") === "fault"
  readonly property bool failed: service ? service.state === "error" : false
  readonly property color normalForeground: bar ? bar.barForeground : Color.foreground
  readonly property color paint: root.failed && !(service && service.ready)
    ? Color.urgent
    : ((root.alarming || root.brainFault) ? Color.accent : root.normalForeground)

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (root.service) root.service.refresh()
    var panel = panelLoader.item
    if (!panel) return
    // Set the page here. Panel.open() is not the only way the shell shows
    // the card, and a derived function does not always replace the base one.
    panel.mode = "vitals"
    panel.showQuiet = false
    if (panel.controller) panel.controller.show()
    else panel.open()
  }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() {
    if (root.opened) root.close()
    else root.open()
  }
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "firstintegral.1config"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function refresh(): void { if (root.service) root.service.refresh() }
    function refreshLimits(): void { if (root.service) root.service.refreshLimits() }
    function isOpen(): bool { return root.opened }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    foreground: root.paint
    text: ""
    labelVisible: false
    hasVisualContent: true
    fixedWidth: root.vertical ? -1 : Style.bar.iconSlot
    fixedHeight: root.vertical ? Style.bar.iconSlot : -1
    horizontalMargin: 0
    tooltipText: root.service ? root.service.tooltipText() : "1config"
    onPressed: function(b) {
      if (b === Qt.RightButton) {
        if (root.service) root.service.refresh()
      } else root.togglePanel()
    }

    Loader {
      id: barMark
      anchors.centerIn: parent
      width: Style.bar.iconCanvas
      height: width
      source: Qt.resolvedUrl("RingMark.qml")
      onLoaded: {
        item.width = Qt.binding(function() { return barMark.width })
        item.height = Qt.binding(function() { return barMark.height })
        item.color = Qt.binding(function() { return root.paint })
        item.family = button.fontFamily
      }
    }
  }

  Rectangle {
    id: pulseDot
    readonly property bool armed: (root.alarming || root.brainFault) && !root.vertical
    visible: armed && opacity > 0
    width: Math.max(3, Style.space(4))
    height: width
    radius: width / 2
    color: Color.accent
    anchors.left: parent.right
    anchors.leftMargin: -button.scaledHorizontalMargin + Style.space(1)
    anchors.top: parent.top
    anchors.topMargin: Math.round(parent.height * 0.22)
    opacity: 0

    SequentialAnimation {
      id: pulseAnim
      NumberAnimation { target: pulseDot; property: "opacity"; to: 0.95; duration: 450; easing.type: Easing.OutCubic }
      NumberAnimation { target: pulseDot; property: "opacity"; to: 0.0; duration: 1300; easing.type: Easing.InOutSine }
    }
    Timer {
      interval: 6000
      repeat: true
      running: pulseDot.armed
      triggeredOnStart: true
      onTriggered: pulseAnim.restart()
      onRunningChanged: if (!running) { pulseAnim.stop(); pulseDot.opacity = 0 }
    }
  }
}

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

// Bar face for 1config. Shows the hottest plan percentage, or today's token
// total when no plan figure is on disk. Data lives in Service.qml.
BarWidget {
  id: root
  moduleName: "firstintegral.1config"

  readonly property var service: bar && bar.shell ? bar.shell.serviceFor("firstintegral.1config") : null
  readonly property string label: service ? service.barLabel : "…"
  readonly property bool alarming: service ? service.alarming === true : false
  readonly property bool failed: service ? service.state === "error" : false
  readonly property color normalForeground: bar ? bar.barForeground : Color.foreground
  readonly property color paint: root.failed && !(service && service.ready)
    ? Color.urgent
    : (root.alarming ? Color.accent : root.normalForeground)

  readonly property var verticalLines: root.vertical ? ["1c", root.label] : []

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (root.service) root.service.refresh()
    if (panelLoader.item) panelLoader.item.open()
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
    text: root.vertical ? "" : "1c " + root.label
    labelVisible: !root.vertical
    hasVisualContent: root.vertical ? root.verticalLines.length > 0 : true
    fixedHeight: root.vertical ? root.verticalLines.length * Style.bar.iconSlot : -1
    horizontalMargin: 8.5
    tooltipText: root.service ? root.service.tooltipText() : "1config"
    onPressed: function(b) {
      if (b === Qt.RightButton) {
        if (root.service) root.service.refresh()
      } else root.togglePanel()
    }

    Column {
      visible: root.vertical
      anchors.fill: parent
      Repeater {
        model: root.verticalLines
        OpticalGlyph {
          required property string modelData
          width: button.width
          height: Style.bar.iconSlot
          text: modelData
          fontFamily: button.fontFamily
          fontSize: button.fontSize
          color: root.paint
        }
      }
    }
  }

  Rectangle {
    id: pulseDot
    readonly property bool armed: root.alarming && !root.vertical
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

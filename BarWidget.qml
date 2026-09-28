import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Sprites.js" as Sprites

// Bar widget: a little pixel T-rex. Left click opens the runner under it;
// right click toggles the high score beside the icon.
BarWidget {
  id: root
  moduleName: "io.github.saikomantisu.dino"

  readonly property real gameScale: Math.max(0.5, Math.min(3, Number(setting("scale", 1)) || 1))
  readonly property bool showHighScore: setting("showHighScore", false) === true

  readonly property real iconSize: Math.round(Style.bar.iconCanvas)

  // ---- panel plumbing. Bar.findPanelWidget requires open/close/opened on the
  //      bar-widget root, so the widget stands in for the panel it hosts.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("store" in target) target.store = store
    if ("gameScale" in target) target.gameScale = root.gameScale
  }

  function toggleHighScore() {
    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    entry.showHighScore = !root.showHighScore
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()
  onGameScaleChanged: injectPanel()

  Store { id: store }

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
    target: "io.github.saikomantisu.dino"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function highscore(): string { return String(store.highScore) }
    function resetHighscore(): void { store.resetHighScore() }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: true
    horizontalMargin: 7
    fixedWidth: root.vertical ? -1 : Math.round(content.implicitWidth + Style.spaceReal(7) * 2)
    fixedHeight: root.vertical ? Math.round(content.implicitHeight + Style.spaceReal(4) * 2) : -1
    tooltipText: store.highScore > 0
      ? "Dino · high score " + store.highScore
      : "Dino · press space to start"

    onPressed: function(b) {
      if (b === Qt.RightButton) root.toggleHighScore()
      else root.togglePanel()
    }

    Row {
      id: content
      anchors.centerIn: parent
      spacing: Style.space(5)

      Canvas {
        id: icon
        width: root.iconSize
        height: root.iconSize
        anchors.verticalCenter: parent.verticalCenter
        antialiasing: false
        smooth: false

        property color ink: root.bar ? root.bar.barForeground : Color.foreground
        onInkChanged: requestPaint()
        onWidthChanged: requestPaint()

        onPaint: {
          var ctx = getContext("2d")
          ctx.reset()
          var sp = Sprites.sprites.icon
          var px = Math.max(1, Math.floor(Math.min(width / sp.cols, height / sp.rows)))
          var ox = Math.round((width - sp.cols * px) / 2)
          var oy = Math.round((height - sp.rows * px) / 2)
          ctx.fillStyle = "rgba(" + Math.round(ink.r * 255) + "," + Math.round(ink.g * 255) + "," + Math.round(ink.b * 255) + "," + ink.a + ")"
          for (var i = 0; i < sp.runs.length; i++) {
            var r = sp.runs[i]
            var x0 = Math.round(ox + r.x * px), y0 = Math.round(oy + r.y * px)
            ctx.fillRect(x0, y0, Math.round(ox + (r.x + r.w) * px) - x0, Math.round(oy + (r.y + 1) * px) - y0)
          }
        }
      }

      Text {
        visible: root.showHighScore && !root.vertical
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: String(store.highScore)
        color: icon.ink
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.bodySmall
        renderType: Text.NativeRendering
      }
    }
  }
}

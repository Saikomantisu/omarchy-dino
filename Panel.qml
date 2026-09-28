import QtQuick
import qs.Commons
import qs.Ui
import "Engine.js" as Engine
import "Sprites.js" as Sprites

// The game: a popup under the bar icon holding the runner canvas, the score
// line, and a one-line key hint. The bar widget owns the high-score store and
// the IPC target; this panel owns the run in progress.
//
// Closing the panel mid-run pauses it rather than ending it, so a click away
// to answer a message does not cost the run.
Panel {
  id: root
  moduleName: "io.github.saikomantisu.dino"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var store: null
  property real gameScale: 1

  readonly property var barIdentity: hostWidget || root

  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property color bg: Color.popups.background
  readonly property string family: bar ? bar.fontFamily : Style.font.family

  readonly property int gameWidth: Math.round(Engine.WIDTH * gameScale)
  readonly property int gameHeight: Math.round(Engine.HEIGHT * gameScale)

  property var game: Engine.create()
  // Bumped once per frame: the game state is a plain JS object, so the score
  // labels bind to this to know when to re-read it.
  property int tick: 0

  readonly property real night: { tick; return game.night }
  readonly property color ink: Qt.tint(fg, Qt.rgba(bg.r, bg.g, bg.b, night))
  readonly property color paper: Qt.tint(bg, Qt.rgba(fg.r, fg.g, fg.b, night))

  function pad(n) {
    var s = String(Math.max(0, Math.floor(n)))
    while (s.length < 5) s = "0" + s
    return s
  }

  function cssColor(c, alpha) {
    return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + ","
      + Math.round(c.b * 255) + "," + (alpha === undefined ? c.a : alpha) + ")"
  }

  function syncHighScore() {
    if (store && game.phase !== "playing") game.highScore = store.highScore
  }

  function pressAction(action) {
    syncHighScore()
    Engine.press(game, action)
    tick++
  }

  function releaseAction(action) {
    Engine.release(game, action)
  }

  function togglePause() {
    if (game.phase === "playing") Engine.pause(game)
    else if (game.phase === "paused") game.phase = "playing"
    tick++
  }

  function frame(seconds) {
    var result = Engine.step(game, seconds * 60)
    if (result === "crashed" && store) {
      store.submit(game.score)
      game.highScore = store.highScore
    }
    tick++
    canvas.requestPaint()
  }

  // ---- lifecycle -------------------------------------------------------

  function open() { root.controller.show() }
  function close() { root.controller.hide() }
  function toggle() { if (root.opened) root.close(); else root.open() }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  onOpenedChanged: {
    if (opened) {
      syncHighScore()
      canvas.requestPaint()
    } else {
      Engine.pause(game)
      Engine.release(game, "jump")
      Engine.release(game, "duck")
      tick++
    }
  }

  Connections {
    target: root.store
    function onHighScoreChanged() { root.syncHighScore(); root.tick++ }
  }

  implicitWidth: 0
  implicitHeight: 0

  FrameAnimation {
    running: root.opened
    onTriggered: root.frame(frameTime)
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keys
    contentWidth: panel.fittedContentWidth(root.gameWidth + panel.padding * 2)
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    Item {
      id: keys
      anchors.fill: parent
      focus: true

      function actionFor(event) {
        switch (event.key) {
        case Qt.Key_Space:
        case Qt.Key_Up:
        case Qt.Key_W:
        case Qt.Key_K:
          return "jump"
        case Qt.Key_Down:
        case Qt.Key_S:
        case Qt.Key_J:
          return "duck"
        }
        return ""
      }

      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        event.accepted = true
        if (event.key === Qt.Key_Escape || event.key === Qt.Key_Q) { root.close(); return }
        if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
          root.switchPanel((event.modifiers & Qt.ShiftModifier) || event.key === Qt.Key_Backtab ? -1 : 1)
          return
        }
        if (event.key === Qt.Key_P) { if (!event.isAutoRepeat) root.togglePause(); return }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          if (!event.isAutoRepeat && root.game.phase !== "playing") root.pressAction("jump")
          return
        }
        var action = actionFor(event)
        if (action === "") { event.accepted = false; return }
        // Holding Space keeps hopping, as in Chrome, but the synthetic release
        // that comes with each repeat must not cut the current jump short.
        if (event.isAutoRepeat && action === "duck") return
        root.pressAction(action)
      }
      Keys.onReleased: function(event) {
        var action = actionFor(event)
        if (action === "" || event.isAutoRepeat) return
        event.accepted = true
        root.releaseAction(action)
      }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(6)

        Item {
          id: stage
          width: parent.width
          height: Math.round(width * Engine.HEIGHT / Engine.WIDTH)
          clip: true

          Rectangle {
            anchors.fill: parent
            radius: Style.space(4)
            color: root.paper
            opacity: root.night
          }

          Canvas {
            id: canvas
            anchors.fill: parent
            antialiasing: false
            smooth: false
            renderStrategy: Canvas.Cooperative

            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()

            onPaint: {
              var ctx = getContext("2d")
              ctx.reset()
              ctx.clearRect(0, 0, width, height)

              var g = root.game
              var s = width / Engine.WIDTH
              var P = Sprites.PIXEL

              function box(x, y, w, h) {
                var x0 = Math.round(x * s), y0 = Math.round(y * s)
                ctx.fillRect(x0, y0, Math.max(1, Math.round((x + w) * s) - x0), Math.max(1, Math.round((y + h) * s) - y0))
              }
              function sprite(sp, x, y) {
                for (var i = 0; i < sp.runs.length; i++) {
                  var r = sp.runs[i]
                  box(x + r.x * P, y + r.y * P, r.w * P, P)
                }
              }

              // Clouds sit behind everything, faint.
              ctx.fillStyle = root.cssColor(root.ink, 0.28)
              for (var c = 0; c < g.clouds.length; c++) sprite(Sprites.sprites.cloud, g.clouds[c].x, g.clouds[c].y)

              // Night sky gets a handful of stars.
              if (g.night > 0) {
                ctx.fillStyle = root.cssColor(root.ink, 0.6 * g.night)
                for (var st = 0; st < 7; st++) {
                  var sx = ((st * 97 + 40) - g.frames * 0.05 * (st % 3 + 1)) % Engine.WIDTH
                  if (sx < 0) sx += Engine.WIDTH
                  box(sx, 12 + (st * 37) % 60, P, P)
                }
              }

              ctx.fillStyle = root.cssColor(root.ink, 1)

              // Horizon line, with a few bumps and the pebbles below it.
              box(0, Engine.GROUND_Y - 3, Engine.WIDTH, 1)
              for (var p = 0; p < g.pebbles.length; p++) {
                var pb = g.pebbles[p]
                if (pb.bump) box(pb.x, Engine.GROUND_Y - 5, 6, 2)
                box(pb.x, pb.y, pb.w, 1)
              }

              for (var o = 0; o < g.obstacles.length; o++) {
                var ob = g.obstacles[o]
                var osp = Engine.obstacleSprite(ob, g.frames)
                for (var n = 0; n < ob.size; n++)
                  sprite(osp, ob.x + n * (osp.width + P), ob.bottom - osp.height)
              }

              var dsp = Engine.dinoSprite(g)
              sprite(dsp, Engine.DINO_X, g.dino.y - dsp.height)
            }
          }

          // Score line, top right: HI 00123  00045
          Row {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: Math.round(6 * root.gameScale)
            anchors.rightMargin: Math.round(10 * root.gameScale)
            spacing: Math.round(10 * root.gameScale)

            Text {
              visible: { root.tick; return root.game.highScore > 0 }
              textFormat: Text.PlainText
              text: { root.tick; return "HI " + root.pad(root.game.highScore) }
              color: root.ink
              opacity: 0.6
              font.family: root.family
              font.pixelSize: Math.round(11 * root.gameScale)
              font.bold: true
            }

            Text {
              textFormat: Text.PlainText
              text: { root.tick; return root.pad(root.game.score) }
              color: root.ink
              // Every hundred points the score blinks, as in Chrome.
              opacity: { root.tick; return root.game.flash > 0 && Math.floor(root.game.flash / 12) % 2 === 1 ? 0 : 1 }
              font.family: root.family
              font.pixelSize: Math.round(11 * root.gameScale)
              font.bold: true
            }
          }

          // Centre message: start prompt, pause, or game over.
          Column {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -Math.round(18 * root.gameScale)
            spacing: Math.round(4 * root.gameScale)
            visible: { root.tick; return root.game.phase !== "playing" }

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              textFormat: Text.PlainText
              text: {
                root.tick
                var phase = root.game.phase
                if (phase === "over") return "G A M E   O V E R"
                if (phase === "paused") return "P A U S E D"
                return ""
              }
              visible: text !== ""
              color: root.ink
              font.family: root.family
              font.pixelSize: Math.round(13 * root.gameScale)
              font.bold: true
            }

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              textFormat: Text.PlainText
              text: {
                root.tick
                var g = root.game
                if (g.phase === "over")
                  return g.newHighScore ? "New high score! · space to play again" : "space to play again"
                if (g.phase === "paused") return "space to resume"
                return "press space to start"
              }
              color: root.ink
              opacity: { root.tick; return root.game.phase === "over" && root.game.overFrames < 30 ? 0 : 0.7 }
              font.family: root.family
              font.pixelSize: Math.round(9 * root.gameScale)
            }
          }

          MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            onPressed: { keys.forceActiveFocus(); root.pressAction("jump") }
            onReleased: root.releaseAction("jump")
          }
        }

        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          textFormat: Text.PlainText
          text: "space / ↑ jump   ·   ↓ duck   ·   p pause   ·   esc close"
          color: root.fg
          opacity: 0.45
          font.family: root.family
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }
  }
}

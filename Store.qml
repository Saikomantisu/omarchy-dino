import QtQuick
import Quickshell
import Quickshell.Io

// High score and a lifetime tally. The shell never opens the score file
// itself: bin/dino-scores does every read and write, refusing symlinks,
// foreign or oversized files, and replacing the file atomically through a
// private temporary file. One store lives per bar instance; each re-reads the
// file when its panel opens, so a record set on one monitor shows on the rest.
Item {
  id: root

  readonly property string helper: String(Qt.resolvedUrl("bin/dino-scores")).replace(/^file:\/\//, "")

  property int highScore: 0
  property int runs: 0
  property var queue: []

  function adopt(text) {
    var data = null
    try { data = JSON.parse(text) } catch (e) { return }
    if (!data || typeof data !== "object") return
    highScore = Math.max(0, Math.floor(Number(data.highScore) || 0))
    runs = Math.max(0, Math.floor(Number(data.runs) || 0))
  }

  function run(args) {
    queue.push(["python3", helper].concat(args))
    if (!proc.running) next()
  }

  function next() {
    if (queue.length === 0) return
    proc.command = queue.shift()
    proc.running = true
  }

  function refresh() { run(["read"]) }

  // Shown straight away; the helper's answer confirms it.
  function submit(score) {
    score = Math.max(0, Math.floor(Number(score) || 0))
    if (score > highScore) highScore = score
    runs += 1
    run(["submit", String(score)])
  }

  function resetHighScore() {
    highScore = 0
    run(["reset"])
  }

  Process {
    id: proc
    stdout: StdioCollector { id: out; waitForEnd: true }
    stderr: StdioCollector {
      onStreamFinished: if (text.trim() !== "") console.warn("dino: " + text.trim())
    }
    onExited: function(code) {
      if (code === 0) root.adopt(out.text)
      root.next()
    }
  }

  Component.onCompleted: refresh()
}

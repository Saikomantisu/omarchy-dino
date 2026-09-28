import QtQuick
import Quickshell
import Quickshell.Io

// High score and a lifetime tally, kept in a small JSON file. One of these
// lives per bar instance; they all watch the same file, so a record set on one
// monitor shows up on the others.
Item {
  id: root

  readonly property string directory: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/omarchy-dino"
  readonly property string path: directory + "/scores.json"

  property int highScore: 0
  property int runs: 0
  property bool directoryReady: false

  function adopt(text) {
    var data = {}
    try { data = JSON.parse(text || "{}") || {} } catch (e) { data = {} }
    highScore = Math.max(0, Math.floor(Number(data.highScore) || 0))
    runs = Math.max(0, Math.floor(Number(data.runs) || 0))
  }

  function persist() {
    if (!directoryReady) return
    file.setText(JSON.stringify({ highScore: highScore, runs: runs }, null, 2) + "\n")
  }

  // Returns true when the run set a new record.
  function submit(score) {
    runs += 1
    var record = score > highScore
    if (record) highScore = score
    persist()
    return record
  }

  function resetHighScore() {
    highScore = 0
    persist()
  }

  FileView {
    id: file
    path: root.directoryReady ? root.path : ""
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.adopt(text())
    onLoadFailed: root.adopt("")
    onFileChanged: reload()
  }

  // FileView can't create the directory it writes into.
  Process {
    id: ensureDirectory
    command: ["mkdir", "-p", root.directory]
    onExited: root.directoryReady = true
  }

  Component.onCompleted: ensureDirectory.running = true
}

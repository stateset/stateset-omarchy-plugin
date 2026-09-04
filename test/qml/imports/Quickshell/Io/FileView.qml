import QtQml

QtObject {
  property string path: ""
  property bool watchChanges: false
  property bool atomicWrites: false
  property bool printErrors: false
  property string contents: ""

  signal loaded()
  signal loadFailed()

  function text() { return contents }
  function setText(value) { contents = String(value) }
  function reload() {}
}

const test = require('node:test')
const assert = require('node:assert/strict')
const fs = require('node:fs')

const manifest = JSON.parse(fs.readFileSync('manifest.json', 'utf8'))
const controllerVersion = fs.readFileSync('upstream-version.txt', 'utf8').trim()
const readme = fs.readFileSync('README.md', 'utf8')
const panel = fs.readFileSync('Panel.qml', 'utf8')

test('plugin and controller compatibility versions stay explicit and aligned', () => {
  assert.match(manifest.version, /^\d+\.\d+\.\d+$/)
  assert.match(controllerVersion, /^\d+\.\d+\.\d+$/)
  assert.equal(manifest.version.split('.').slice(0, 2).join('.'), controllerVersion.split('.').slice(0, 2).join('.'))
  assert.match(readme, new RegExp(`@stateset/cli@${controllerVersion.replaceAll('.', '\\.')}`))
  assert.match(panel, new RegExp(`@stateset/cli@${controllerVersion.replaceAll('.', '\\.')}`))
})

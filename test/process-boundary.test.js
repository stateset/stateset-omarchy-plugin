const test = require('node:test')
const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')
const { spawnSync } = require('node:child_process')

const fixtureDir = path.resolve(__dirname, 'fixtures')
const serviceQml = fs.readFileSync(path.resolve(__dirname, '..', 'Service.qml'), 'utf8')
const commandMatch = serviceQml.match(/command: \["\/usr\/bin\/bash", "-c", "([^"]*stateset-omarchy status --json[^"]*)"\]/)
assert.ok(commandMatch, 'status command must remain statically discoverable')
const statusCommand = commandMatch[1]

function run(scenario, command = statusCommand) {
  return spawnSync('/usr/bin/bash', ['-c', command], {
    encoding: 'utf8',
    env: {
      ...process.env,
      PATH: `${fixtureDir}:${process.env.PATH}`,
      STATESET_FIXTURE_SCENARIO: scenario
    }
  })
}

test('fixed status pipeline returns healthy JSON', () => {
  const result = run('healthy')
  assert.equal(result.status, 0)
  assert.equal(JSON.parse(result.stdout).ok, true)
})

test('fixed status pipeline preserves controller failures', () => {
  const result = run('error')
  assert.equal(result.status, 3)
  assert.match(result.stdout, /fixture controller failed/)
})

test('fixed status pipeline caps producer output at the overflow sentinel', () => {
  const result = run('oversized')
  assert.equal(result.stdout.length, 65537)
  assert.notEqual(result.status, 0)
})

test('fixed status pipeline enforces its producer deadline', () => {
  const fastTimeout = statusCommand.replace('8s stateset-omarchy', '0.1s stateset-omarchy')
  const result = run('timeout', fastTimeout)
  assert.equal(result.status, 124)
})

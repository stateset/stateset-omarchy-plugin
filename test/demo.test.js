const test = require('node:test')
const assert = require('node:assert/strict')
const { mkdtempSync, rmSync } = require('node:fs')
const { tmpdir } = require('node:os')
const path = require('node:path')
const { spawnSync } = require('node:child_process')
const Model = require('../Model.js')

const cli = path.resolve('demo/bin/stateset-omarchy')

function run(args, scenario, stateDir) {
  return spawnSync(cli, args, {
    encoding: 'utf8',
    env: {
      ...process.env,
      STATESET_DEMO_SCENARIO: scenario || 'healthy',
      STATESET_DEMO_STATE_DIR: stateDir
    }
  })
}

test('demo scenarios follow the production status contract', () => {
  for (const scenario of ['healthy', 'attention', 'empty', 'partial', 'governed', 'unavailable']) {
    const result = run(['status', '--json'], scenario, tmpdir())
    assert.equal(result.status, 0, result.stderr)
    const status = Model.parseStatusJson(result.stdout)
    assert.equal(status.schemaVersion, 1)
    assert.equal(status.controllerVersion, '1.30.0')
    assert.equal(status.capabilitiesKnown, true)
    assert.ok(status.capabilities.includes('mcp-service'))
    assert.equal(status.ok, scenario !== 'unavailable')
  }
})

test('demo controller reproduces missing and oversized failure boundaries', () => {
  const missing = run(['status', '--json'], 'controller-missing', tmpdir())
  assert.equal(missing.status, 127)
  assert.match(missing.stderr, /command not found/)

  const oversized = run(['status', '--json'], 'oversized', tmpdir())
  assert.ok(oversized.stdout.length > Model.MAX_OUTPUT_CHARS)
})

test('demo MCP lifecycle state survives separate commands', () => {
  const stateDir = mkdtempSync(path.join(tmpdir(), 'stateset-demo-test-'))
  try {
    const stop = run(['service', 'stop', '--json'], 'healthy', stateDir)
    assert.equal(stop.status, 0, stop.stderr)
    assert.deepEqual(Model.parseServiceStatusJson(stop.stdout), {
      installed: true,
      active: false,
      state: 'inactive'
    })
    const start = run(['service', 'start', '--json'], 'healthy', stateDir)
    assert.equal(start.status, 0, start.stderr)
    assert.equal(Model.parseServiceStatusJson(start.stdout).active, true)
  } finally {
    rmSync(stateDir, { recursive: true, force: true })
  }
})

test('native MCP action boundary executes the controller and exits if it disappears', () => {
  const stateDir = mkdtempSync(path.join(tmpdir(), 'stateset-demo-action-'))
  const emptyPath = mkdtempSync(path.join(tmpdir(), 'stateset-empty-path-'))
  const command = Model.serviceActionCommand('stop')
  try {
    const success = spawnSync(command[0], command.slice(1), {
      encoding: 'utf8',
      timeout: 2000,
      env: {
        ...process.env,
        PATH: `${path.dirname(cli)}:${process.env.PATH}`,
        STATESET_DEMO_STATE_DIR: stateDir
      }
    })
    assert.equal(success.status, 0, success.stderr)
    assert.equal(Model.parseServiceStatusJson(success.stdout).active, false)

    const missing = spawnSync(command[0], command.slice(1), {
      encoding: 'utf8',
      timeout: 2000,
      env: { ...process.env, PATH: emptyPath }
    })
    assert.equal(missing.status, 127)
    assert.match(missing.stderr, /failed to run command/)
  } finally {
    rmSync(stateDir, { recursive: true, force: true })
    rmSync(emptyPath, { recursive: true, force: true })
  }
})

test('demo controller rejects commands outside the plugin contract', () => {
  const result = run(['service', 'remove'], 'healthy', tmpdir())
  assert.notEqual(result.status, 0)
  assert.match(result.stderr, /Unsupported demo service action/)
})

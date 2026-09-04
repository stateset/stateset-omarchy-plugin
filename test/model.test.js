const test = require('node:test')
const assert = require('node:assert/strict')
const Model = require('../Model.js')

test('normalizes a valid status without trusting extra fields', () => {
  const status = Model.parseStatusJson(JSON.stringify({
    ok: true,
    configured: true,
    dbPath: '/tmp/store.db',
    mode: 'governed-apply',
    message: 'Store ready',
    sizeBytes: 1536,
    counts: { orders: '12', customers: 3.9, products: -1, returns: Infinity },
    alerts: { pendingOrders: 2, failedPayments: 1, pendingReturns: 0, lowStock: 4 },
    ignored: 'value'
  }))

  assert.deepEqual(status, {
    ok: true,
    schemaVersion: 0,
    configured: true,
    dbPath: '/tmp/store.db',
    mode: 'governed-apply',
    message: 'Store ready',
    controllerVersion: '',
    capabilitiesKnown: false,
    capabilities: [],
    sizeBytes: 1536,
    counts: { orders: 12, customers: 3, products: 0, returns: 0, payments: 0 },
    alerts: { pendingOrders: 2, failedPayments: 1, pendingReturns: 0, lowStock: 4, total: 7 },
    signalsComplete: true,
    unavailableSignals: []
  })
})

test('normalizes partial operational signal health to known unique values', () => {
  const status = Model.parseStatusJson(JSON.stringify({
    ok: true,
    signalsComplete: true,
    unavailableSignals: ['payments', 'unknown', 'payments', 'lowStockItems']
  }))

  assert.equal(status.signalsComplete, false)
  assert.deepEqual(status.unavailableSignals, ['payments', 'lowStockItems'])
  assert.deepEqual(
    Model.normalizeUnavailableSignals(['orders', {}, 'pendingReturns', 'orders']),
    ['orders', 'pendingReturns']
  )
})

test('accepts the current status schema and rejects incompatible versions', () => {
  assert.equal(Model.parseStatusJson('{"schemaVersion":1,"ok":true}').schemaVersion, 1)
  assert.throws(() => Model.parseStatusJson('{"schemaVersion":2,"ok":true}'), /Unsupported status schema/)
  assert.equal(Model.controllerVersionCompatible('1.30.0'), true)
  assert.equal(Model.controllerVersionCompatible('1.30.9-beta.1'), true)
  assert.equal(Model.controllerVersionCompatible('1.31.0'), false)
  assert.equal(Model.controllerVersionCompatible('garbage'), false)
  assert.throws(
    () => Model.parseStatusJson('{"schemaVersion":1,"controllerVersion":"2.0.0","ok":true}'),
    /Unsupported controller version/
  )
})

test('normalizes an explicit controller capability handshake', () => {
  const status = Model.parseStatusJson(JSON.stringify({
    schemaVersion: 1,
    controllerVersion: '1.30.4',
    capabilities: ['status', 'mcp-service', 'unknown', 'status'],
    ok: true
  }))
  assert.equal(status.controllerVersion, '1.30.4')
  assert.equal(status.capabilitiesKnown, true)
  assert.deepEqual(status.capabilities, ['status', 'mcp-service'])
})

test('normalizes MCP service status', () => {
  assert.deepEqual(Model.parseServiceStatusJson('{"installed":true,"active":true,"state":"active"}'), {
    installed: true,
    active: true,
    state: 'active'
  })
  assert.deepEqual(Model.normalizeServiceStatus({ installed: true, active: 'yes', state: 'invented' }), {
    installed: true,
    active: false,
    state: 'unknown'
  })
  assert.deepEqual(Model.parseServiceStatusJson('{"installed":false,"active":true,"state":"active"}'), {
    installed: false,
    active: false,
    state: 'not-installed'
  })
  assert.deepEqual(Model.parseServiceStatusJson('{"installed":true,"active":true,"state":"failed"}'), {
    installed: true,
    active: false,
    state: 'failed'
  })
})

test('classifies controller failures for tailored recovery', () => {
  assert.equal(Model.classifyFailure(124, '', false, false), 'timeout')
  assert.equal(Model.classifyFailure(1, '', false, true), 'oversized-response')
  assert.equal(Model.classifyFailure(127, '', false, false), 'controller-missing')
  assert.equal(Model.classifyFailure(1, 'bash: stateset-omarchy: command not found', false, false), 'controller-missing')
  assert.equal(Model.classifyFailure(1, 'database is locked', false, false), 'controller-error')
  assert.equal(Model.classifyFailure(0, '', false, false), 'invalid-response')
})

test('fails closed on invalid status envelopes', () => {
  assert.throws(() => Model.parseStatusJson(''), /size is invalid/)
  assert.throws(() => Model.parseStatusJson('[]'), /must be an object/)
  assert.throws(() => Model.parseStatusJson('{"x":'), /malformed/)
  assert.throws(() => Model.parseStatusJson('['.repeat(9) + '0' + ']'.repeat(9)), /deeply nested|too many arrays/)
  assert.throws(() => Model.parseStatusJson(' '.repeat(Model.MAX_OUTPUT_CHARS + 1)), /size is invalid/)
})

test('sanitizes controller text for display', () => {
  assert.equal(Model.safeText('  bad\n<b>&\u202epath  ', 160), 'bad ‹b›＆ path')
  assert.equal(Model.safeText('abc', 0, 'fallback'), 'fallback')
  assert.equal(Model.safeText(null, 10, 'fallback'), 'fallback')
})

test('bounds streamed output without growing after truncation', () => {
  assert.deepEqual(Model.appendBounded('ab', 'cdef', 4), { text: 'abcd', truncated: true })
  assert.deepEqual(Model.appendBounded('abcd', 'x', 4), { text: 'abcd', truncated: true })
  assert.deepEqual(Model.appendBounded('', 0, 4), { text: '0', truncated: false })
})

test('formats large metric counts for a narrow panel', () => {
  assert.equal(Model.formatCount(999), '999')
  assert.equal(Model.formatCount(1200), '1.2K')
  assert.equal(Model.formatCount(999999), '999K')
  assert.equal(Model.formatCount(1250000), '1.2M')
  assert.equal(Model.formatCount(999999999), '999M')
  assert.equal(Model.formatExactCount(0), '0')
  assert.equal(Model.formatExactCount(1250000), '1,250,000')
})

test('formats bounded store sizes', () => {
  assert.equal(Model.formatBytes(0), '0 B')
  assert.equal(Model.formatBytes(1536), '1.5 KiB')
  assert.equal(Model.formatBytes(12 * 1024 * 1024), '12 MiB')
  assert.equal(Model.formatBytes(-1), '0 B')
})

test('describes snapshot freshness', () => {
  const now = new Date('2026-09-04T12:00:00Z')
  assert.equal(Model.freshnessLabel(new Date(0), now), 'Not updated yet')
  assert.equal(Model.freshnessLabel(new Date('2026-09-04T11:59:55Z'), now), 'Updated just now')
  assert.equal(Model.freshnessLabel(new Date('2026-09-04T11:57:00Z'), now), 'Updated 3m ago')
  assert.equal(Model.freshnessLabel(new Date('2026-09-04T09:00:00Z'), now), 'Updated 3h ago')
})

test('notifies only after a baseline and only for exceptional increases', () => {
  const before = { pendingOrders: 10, failedPayments: 1, pendingReturns: 2, lowStock: 3 }
  assert.equal(Model.shouldNotify(before, { ...before, pendingOrders: 11 }, true), false)
  assert.equal(Model.shouldNotify(before, { ...before, failedPayments: 2 }, false), false)
  assert.equal(Model.shouldNotify(before, { ...before, failedPayments: 3, lowStock: 4 }, true), true)
  assert.equal(
    Model.notificationSummary(before, { ...before, failedPayments: 3, lowStock: 4 }),
    '+2 failed payments · +1 low-stock SKU'
  )
})

test('applies per-signal notification policy and cooldowns', () => {
  const before = { pendingOrders: 10, failedPayments: 1, pendingReturns: 2, lowStock: 3 }
  const after = { pendingOrders: 11, failedPayments: 2, pendingReturns: 4, lowStock: 8 }
  assert.deepEqual(Model.notificationCandidate(before, after, {
    failedPayments: true,
    pendingReturns: false,
    lowStock: false
  }), {
    pendingOrders: 10,
    failedPayments: 2,
    pendingReturns: 2,
    lowStock: 3
  })
  assert.equal(Model.cooldownElapsed(0, 1000, 15), true)
  assert.equal(Model.cooldownElapsed(1000, 1000 + 14 * 60000, 15), false)
  assert.equal(Model.cooldownElapsed(1000, 1000 + 15 * 60000, 15), true)
  assert.equal(Model.cooldownRemainingMs(1000, 1000 + 14 * 60000, 15), 60000)
  assert.equal(Model.cooldownRemainingMs(9999999999999, 1000, 15), 15 * 60000)
})

test('coalesces exceptional alerts until they can be delivered', () => {
  const before = { failedPayments: 1, pendingReturns: 0, lowStock: 3 }
  const after = { failedPayments: 3, pendingReturns: 1, lowStock: 5 }
  const delta = Model.notificationDelta(before, after, {
    failedPayments: true,
    pendingReturns: true,
    lowStock: false
  })
  assert.deepEqual(delta, { failedPayments: 2, pendingReturns: 1, lowStock: 0 })
  assert.deepEqual(
    Model.filterNotificationDelta(
      { failedPayments: 2, pendingReturns: 1, lowStock: 4 },
      { failedPayments: false, pendingReturns: true, lowStock: false }
    ),
    { failedPayments: 0, pendingReturns: 1, lowStock: 0 }
  )
  const pending = Model.mergePendingNotifications(
    { failedPayments: 1, pendingReturns: 0, lowStock: 2 }, delta, after
  )
  assert.deepEqual(pending, { failedPayments: 3, pendingReturns: 1, lowStock: 2 })
  assert.equal(Model.hasPendingNotifications(pending), true)
  assert.equal(
    Model.pendingNotificationSummary(pending),
    '+3 failed payments · +2 low-stock SKUs · +1 pending return'
  )
  assert.deepEqual(
    Model.mergePendingNotifications(pending, {}, { failedPayments: 0, pendingReturns: 1, lowStock: 0 }),
    { failedPayments: 0, pendingReturns: 1, lowStock: 0 }
  )
})

test('loads persisted notification state defensively', () => {
  assert.deepEqual(Model.parseNotificationState(''), {
    lastNotificationAt: 0,
    pending: { failedPayments: 0, pendingReturns: 0, lowStock: 0 }
  })
  assert.deepEqual(Model.parseNotificationState('{"lastNotificationAt":500,"pending":{"failedPayments":2}}'), {
    lastNotificationAt: 500,
    pending: { failedPayments: 2, pendingReturns: 0, lowStock: 0 }
  })
  assert.equal(Model.parseNotificationState('{bad').lastNotificationAt, 0)
  assert.equal(Model.parseNotificationState('{"version":2,"lastNotificationAt":500}').lastNotificationAt, 0)
})

test('persists only fresh normalized healthy snapshots', () => {
  const now = Date.parse('2026-09-04T12:00:00Z')
  const state = Model.createSnapshotState({
    schemaVersion: 1,
    controllerVersion: '1.30.0',
    capabilities: ['status', 'backup', 'untrusted'],
    ok: true,
    configured: true,
    dbPath: '/tmp/store.db',
    counts: { orders: 12.9 },
    alerts: { failedPayments: 2 },
    ignored: 'secret'
  }, now)
  assert.equal(state.version, 1)
  assert.equal(state.snapshot.counts.orders, 12)
  assert.deepEqual(state.snapshot.capabilities, ['status', 'backup'])
  assert.equal('ignored' in state.snapshot, false)

  const restored = Model.parseSnapshotState(JSON.stringify(state), now + 1000)
  assert.equal(restored.ok, true)
  assert.equal(restored.snapshot.dbPath, '/tmp/store.db')
  assert.equal(restored.snapshot.alerts.failedPayments, 2)
  assert.equal(Model.parseSnapshotState(JSON.stringify(state), now + Model.SNAPSHOT_MAX_AGE_MS + 1).ok, false)
  assert.equal(Model.parseSnapshotState(JSON.stringify({ ...state, version: 2 }), now).ok, false)
  assert.equal(Model.createSnapshotState({ ok: false, configured: true }, now), null)
})

test('builds only allowlisted direct MCP lifecycle commands', () => {
  assert.deepEqual(Model.serviceActionCommand('start'), [
    '/usr/bin/timeout', '--signal=TERM', '--kill-after=1s', '10s',
    'stateset-omarchy', 'service', 'start', '--json'
  ])
  assert.deepEqual(Model.serviceActionCommand('install'), [
    '/usr/bin/timeout', '--signal=TERM', '--kill-after=1s', '10s',
    'stateset-omarchy', 'service', 'install'
  ])
  assert.deepEqual(Model.serviceActionCommand('remove'), [])
  assert.equal(Model.serviceActionLabel('restart', true), 'MCP service restarted')
})

test('backs off failed polling without exceeding thirty minutes', () => {
  assert.equal(Model.retryIntervalSeconds(120, 0), 120)
  assert.equal(Model.retryIntervalSeconds(120, 1), 120)
  assert.equal(Model.retryIntervalSeconds(120, 2), 240)
  assert.equal(Model.retryIntervalSeconds(120, 5), 1800)
  assert.equal(Model.retryIntervalSeconds(1, 2), 60)
  assert.equal(Model.retryIntervalSeconds(3600, 4), 1800)
})

test('formats the next retry as a short countdown', () => {
  const now = new Date('2026-09-04T12:00:00Z')
  assert.equal(Model.retryCountdownLabel(new Date(0), now), '')
  assert.equal(Model.retryCountdownLabel(new Date('2026-09-04T12:00:01Z'), now), 'Retrying now')
  assert.equal(Model.retryCountdownLabel(new Date('2026-09-04T12:00:42Z'), now), 'Retrying in 42s')
  assert.equal(Model.retryCountdownLabel(new Date('2026-09-04T12:02:01Z'), now), 'Retrying in 3m')
})

test('builds a readable attention summary with singular forms', () => {
  assert.equal(
    Model.attentionSummary({ failedPayments: 1, lowStock: 2, pendingReturns: 1, pendingOrders: 3 }),
    '1 failed payment · 2 low-stock SKUs · 1 pending return · 3 pending orders'
  )
  assert.equal(Model.attentionHeadline({ failedPayments: 1 }), '1 NEEDS ATTENTION')
  assert.equal(Model.attentionHeadline({ failedPayments: 2 }), '2 NEED ATTENTION')
})

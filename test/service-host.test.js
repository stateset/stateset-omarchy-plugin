const test = require('node:test')
const assert = require('node:assert/strict')
const { hostedService } = require('../ServiceHost.js')

test('returns the registered singleton service', () => {
  const service = { ready: true }
  assert.equal(hostedService({ shell: { serviceFor: id => id === 'com.stateset.icommerce' ? service : null } }), service)
})

test('fails safely when the shell service API is unavailable', () => {
  assert.equal(hostedService(null), null)
  assert.equal(hostedService({}), null)
  assert.equal(hostedService({ shell: {} }), null)
})

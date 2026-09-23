const { test } = require('node:test');
const assert = require('node:assert/strict');
const { toRows, overallStatus } = require('../public/status');

test('maps successful info calls to "up" rows with a short commit', () => {
  const rows = toRows([{ name: 'orders-api', info: { version: '1.2.0', commit: 'abcdef123456' } }]);
  assert.deepEqual(rows, [{ name: 'orders-api', version: '1.2.0', commit: 'abcdef1', status: 'up' }]);
});

test('maps failed calls to "down" rows', () => {
  const rows = toRows([{ name: 'inventory-svc', error: new Error('502') }]);
  assert.equal(rows[0].status, 'down');
  assert.equal(rows[0].version, '-');
});

test('overall status is healthy only when every service is up', () => {
  assert.equal(overallStatus([{ status: 'up' }, { status: 'up' }]), 'healthy');
  assert.equal(overallStatus([{ status: 'up' }, { status: 'down' }]), 'degraded');
  assert.equal(overallStatus([]), 'unknown');
});

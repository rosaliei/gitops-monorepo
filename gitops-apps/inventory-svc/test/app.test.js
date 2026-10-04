const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { createServer } = require('../src/app');

let server;
let base;

before(async () => {
  server = createServer();
  await new Promise((resolve) => server.listen(0, resolve));
  base = `http://127.0.0.1:${server.address().port}`;
});

after(() => server.close());

test('health probes respond', async () => {
  assert.deepEqual(await (await fetch(`${base}/healthz`)).json(), { status: 'ok' });
  assert.deepEqual(await (await fetch(`${base}/readyz`)).json(), { status: 'ready' });
});

test('info reports service, version and environment', async () => {
  const body = await (await fetch(`${base}/api/info`)).json();
  assert.equal(body.service, 'inventory-svc');
  assert.ok('version' in body && 'environment' in body && 'commit' in body);
});

test('lists items and returns one by sku', async () => {
  const items = await (await fetch(`${base}/api/items`)).json();
  assert.equal(items.length, 3);
  const tea = await (await fetch(`${base}/api/items/sku-tea`)).json();
  assert.equal(tea.quantity, 7);
});

test('unknown sku returns 404', async () => {
  assert.equal((await fetch(`${base}/api/items/sku-nope`)).status, 404);
});

test('metrics are exposed', async () => {
  await fetch(`${base}/healthz`);
  const text = await (await fetch(`${base}/metrics`)).text();
  assert.match(text, /http_requests_total\{method="GET",route="\/healthz",status="200"\}/);
  assert.match(text, /app_build_info/);
});

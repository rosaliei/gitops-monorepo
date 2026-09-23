// inventory-svc: a tiny stock service used to demo CI/CD and GitOps.
//
// Endpoints
//   GET /healthz          liveness probe
//   GET /readyz           readiness probe
//   GET /metrics          Prometheus metrics
//   GET /api/info         which version is running where
//   GET /api/items        list stock
//   GET /api/items/:sku   one item (404 if unknown)

const http = require('node:http');
const client = require('prom-client');

const SERVICE = 'inventory-svc';
const VERSION = process.env.APP_VERSION || 'dev';
const COMMIT = process.env.GIT_SHA || 'local';
const ENVIRONMENT = process.env.APP_ENV || 'local';

const STOCK = {
  'sku-coffee': { sku: 'sku-coffee', name: 'Coffee beans', quantity: 42 },
  'sku-tea': { sku: 'sku-tea', name: 'Green tea', quantity: 7 },
  'sku-mug': { sku: 'sku-mug', name: 'Mug', quantity: 0 },
};

function createServer() {
  const registry = new client.Registry();
  const requests = new client.Counter({
    name: 'http_requests_total',
    help: 'HTTP requests',
    labelNames: ['method', 'route', 'status'],
    registers: [registry],
  });
  const latency = new client.Histogram({
    name: 'http_request_duration_seconds',
    help: 'HTTP request latency',
    labelNames: ['method', 'route'],
    registers: [registry],
  });
  new client.Gauge({
    name: 'app_build_info',
    help: 'Build information',
    labelNames: ['service', 'version', 'commit'],
    registers: [registry],
  }).set({ service: SERVICE, version: VERSION, commit: COMMIT }, 1);

  const routes = [
    ['/healthz', () => [200, { status: 'ok' }]],
    ['/readyz', () => [200, { status: 'ready' }]],
    ['/api/info', () => [200, { service: SERVICE, version: VERSION, commit: COMMIT, environment: ENVIRONMENT }]],
    ['/api/items', () => [200, Object.values(STOCK)]],
    [/^\/api\/items\/([\w-]+)$/, (m) => (STOCK[m[1]] ? [200, STOCK[m[1]]] : [404, { error: 'not found' }])],
  ];

  return http.createServer(async (req, res) => {
    const path = new URL(req.url, 'http://localhost').pathname;

    if (path === '/metrics') {
      res.writeHead(200, { 'Content-Type': registry.contentType });
      return res.end(await registry.metrics());
    }

    const stop = latency.startTimer();
    let status = 404;
    let body = { error: 'not found' };
    let route = 'unmatched';
    for (const [pattern, handler] of routes) {
      const match = typeof pattern === 'string' ? (path === pattern ? [path] : null) : path.match(pattern);
      if (req.method === 'GET' && match) {
        [status, body] = handler(match);
        route = typeof pattern === 'string' ? pattern : '/api/items/:sku';
        break;
      }
    }
    stop({ method: req.method, route });
    requests.inc({ method: req.method, route, status });
    res.writeHead(status, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(body));
  });
}

module.exports = { createServer, STOCK };

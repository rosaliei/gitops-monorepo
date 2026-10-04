const { createServer } = require('./app');

const port = Number(process.env.PORT || 8080);
const server = createServer().listen(port, () => console.log(`inventory-svc listening on :${port}`));

// Let Kubernetes stop the pod cleanly.
process.on('SIGTERM', () => server.close(() => process.exit(0)));

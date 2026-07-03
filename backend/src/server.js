// Network entrypoint. Binds the Express app to PORT (default 8080, as required
// by the assessment) and wires graceful shutdown so Kubernetes rolling updates
// drain cleanly instead of dropping in-flight requests.
const createApp = require('./app');

const PORT = parseInt(process.env.PORT || '8080', 10);
const app = createApp();

const server = app.listen(PORT, () => {
  console.log(`backend listening on port ${PORT}`);
});

// SIGTERM is what Kubernetes sends before killing a pod. Closing the server
// lets existing connections finish within the pod's terminationGracePeriod.
function shutdown(signal) {
  console.log(`received ${signal}, shutting down gracefully`);
  server.close(() => process.exit(0));
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));

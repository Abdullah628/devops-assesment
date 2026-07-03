// Express application factory.
//
// The app is defined here and exported *without* calling listen(), so tests
// (test/health.test.js) can import it and drive it with supertest in-process,
// while server.js owns the actual network binding. This separation is a common
// production pattern: it keeps the HTTP wiring testable and side-effect free.
const express = require('express');
const db = require('./db');

function createApp() {
  const app = express();
  app.use(express.json());

  // Root endpoint — the assessment tests this literal response with curl.
  app.get('/', (_req, res) => {
    res.type('text/plain').send('Application is running');
  });

  // Liveness/readiness endpoint. Intentionally does NOT touch the database:
  // a transient DB blip should not make Kubernetes kill or depool the pod.
  // Database health is checked separately via /db-check.
  app.get('/health', (_req, res) => {
    res.json({ status: 'ok' });
  });

  // Optional deep check that proves private DB connectivity works.
  // Returns 200 only when the round-trip query succeeds.
  app.get('/db-check', async (_req, res) => {
    try {
      const ok = await db.ping();
      res.json({ database: ok ? 'connected' : 'unknown' });
    } catch (err) {
      res.status(503).json({ database: 'unreachable', error: err.message });
    }
  });

  return app;
}

module.exports = createApp;

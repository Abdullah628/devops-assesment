// Lazy PostgreSQL connection pool.
//
// The pool is only created the first time it is needed. This keeps the app
// (and its /health check) working even when no database is configured — which
// is exactly what we want in local dev, in CI, and for the Kubernetes liveness
// probe, none of which should be coupled to database availability.
//
// Connection details come exclusively from environment variables. Non-secret
// values (host, port, name, user) are injected via a ConfigMap in Kubernetes;
// the password comes from a Secret. Nothing is ever hardcoded here.
const { Pool } = require('pg');

let pool;

function getPool() {
  if (!pool) {
    pool = new Pool({
      host: process.env.DB_HOST || 'localhost',
      port: parseInt(process.env.DB_PORT || '5432', 10),
      database: process.env.DB_NAME || 'appdb',
      user: process.env.DB_USER || 'appuser',
      password: process.env.DB_PASSWORD || '',
      // Fail fast instead of hanging if the DB is unreachable (e.g. a broken
      // private endpoint). Surfaces problems quickly in troubleshooting.
      connectionTimeoutMillis: 3000,
      max: 5,
    });
  }
  return pool;
}

// Runs a trivial round-trip query. Used by the /db-check route to prove
// private connectivity end-to-end without exposing any data.
async function ping() {
  const client = await getPool().connect();
  try {
    const result = await client.query('SELECT 1 AS ok');
    return result.rows[0].ok === 1;
  } finally {
    client.release();
  }
}

module.exports = { getPool, ping };

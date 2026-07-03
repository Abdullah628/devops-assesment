// Minimal vanilla JS. Calls the backend through the /api prefix, which Nginx
// proxies to the backend Service. Using a relative /api path (rather than a
// hardcoded backend URL) means the same static bundle works unchanged in
// docker-compose and in Kubernetes — the proxy target is configured in the
// infrastructure layer, not baked into the frontend.
async function check(path, badgeId) {
  const badge = document.getElementById(badgeId);
  try {
    const res = await fetch(path);
    const text = await res.text();
    if (res.ok) {
      badge.textContent = 'OK';
      badge.className = 'badge ok';
    } else {
      badge.textContent = `HTTP ${res.status}`;
      badge.className = 'badge error';
    }
    return { path, ok: res.ok, status: res.status, body: text };
  } catch (err) {
    badge.textContent = 'unreachable';
    badge.className = 'badge error';
    return { path, ok: false, error: err.message };
  }
}

async function main() {
  const results = await Promise.all([
    check('/api/', 'root-status'),
    check('/api/health', 'health-status'),
  ]);
  document.getElementById('output').textContent = JSON.stringify(results, null, 2);
}

main();

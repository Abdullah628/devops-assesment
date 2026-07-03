// In-process API tests. These run in CI (npm test) with no database and no
// network binding required, because app.js exports the app without listen().
const request = require('supertest');
const createApp = require('../src/app');

const app = createApp();

describe('backend API', () => {
  test('GET / returns the running message', async () => {
    const res = await request(app).get('/');
    expect(res.status).toBe(200);
    expect(res.text).toBe('Application is running');
  });

  test('GET /health returns ok status as JSON', async () => {
    const res = await request(app).get('/health');
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ status: 'ok' });
  });
});

const test = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const { allowed, createGateway } = require('./public_api_gateway');

test('allow only routes used by the Android test app', () => {
  assert.equal(allowed('POST', '/api/auth/login'), true);
  assert.equal(allowed('POST', '/api/auth/register'), false);
  assert.equal(allowed('GET', '/api/mobile/news/sync?since=1'), true);
  assert.equal(allowed('GET', '/api/forecast/market'), true);
  assert.equal(allowed('GET', '/api/forecast/BTCUSDT'), false);
  assert.equal(allowed('POST', '/api/payments/123/cancel'), true);
  for (const path of ['/api/admin/db/overview', '/swagger-ui/index.html', '/v3/api-docs',
    '/h2-console', '/api/news/diagnostics', '/api/admin/../stocks', '/api/%61dmin/db/overview']) {
    assert.equal(allowed('GET', path), false, path);
  }
  assert.equal(allowed('POST', '/actuator/health'), false);
});

test('gateway denies internals and strips spoofed forwarding headers', async () => {
  const backend = http.createServer((req, res) => {
    res.setHeader('content-type', 'application/json');
    res.end(JSON.stringify({ path: req.url, fakeIp: req.headers['x-forwarded-for'] || null }));
  });
  await new Promise(resolve => backend.listen(0, '127.0.0.1', resolve));
  const { server } = createGateway({ upstreamPort: backend.address().port, port: 0 });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const base = `http://127.0.0.1:${server.address().port}`;
  try {
    const blocked = await fetch(`${base}/api/admin/db/overview`);
    assert.equal(blocked.status, 404);
    const ok = await fetch(`${base}/api/stocks`, { headers: { 'x-forwarded-for': '8.8.8.8' } });
    assert.equal(ok.status, 200);
    assert.deepEqual(await ok.json(), { path: '/api/stocks', fakeIp: null });
    const auth = await fetch(`${base}/api/auth/login`, {
      method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ email: 'test@example.com', password: 'test' }),
    });
    assert.equal(auth.status, 200);
  } finally {
    await new Promise(resolve => server.close(resolve));
    await new Promise(resolve => backend.close(resolve));
  }
});

test('registration is opt-in and bounded without opening admin routes', async () => {
  const backend = http.createServer((req, res) => {
    res.setHeader('content-type', 'application/json');
    res.end(JSON.stringify({ path: req.url }));
  });
  await new Promise(resolve => backend.listen(0, '127.0.0.1', resolve));
  const disabled = createGateway({ upstreamPort: backend.address().port, registrationEnabled: false });
  const enabled = createGateway({ upstreamPort: backend.address().port, registrationEnabled: true });
  await Promise.all([disabled, enabled].map(({ server }) =>
    new Promise(resolve => server.listen(0, '127.0.0.1', resolve))));
  const request = (gateway) => fetch(`http://127.0.0.1:${gateway.server.address().port}/api/auth/register`, {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ email: 'new@example.com', password: 'test-password' }),
  });
  try {
    assert.equal((await request(disabled)).status, 404);
    for (let attempt = 0; attempt < 10; attempt++) {
      assert.equal((await request(enabled)).status, 200);
    }
    assert.equal((await request(enabled)).status, 429);
    assert.equal((await fetch(`http://127.0.0.1:${enabled.server.address().port}/api/admin/users`)).status, 404);
  } finally {
    await Promise.all([disabled, enabled].map(({ server }) =>
      new Promise(resolve => server.close(resolve))));
    await new Promise(resolve => backend.close(resolve));
  }
});

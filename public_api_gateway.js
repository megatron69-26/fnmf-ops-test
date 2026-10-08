// Minimal, fail-closed HTTP gateway for the FNMF test Android client.
// The tunnel must target this listener, never the Spring Boot port directly.
const http = require('node:http');

const routes = [
  ['POST', /^\/api\/auth\/login$/],
  ['GET', /^\/api\/auth\/me$/],
  ['GET', /^\/api\/market\/(?:candles|prices)$/],
  ['GET', /^\/api\/mobile\/news\/sync$/],
  ['GET', /^\/api\/news\/sync$/],
  ['POST', /^\/api\/news\/refresh$/],
  ['GET', /^\/api\/trade\/(?:portfolio|history)$/],
  ['POST', /^\/api\/trade\/order$/],
  ['GET', /^\/api\/forecast\/(?:market|[A-Za-z0-9_-]+)$/],
  ['POST', /^\/api\/forecast\/(?:refresh|market\/refresh)$/],
  ['GET', /^\/api\/refresh-quota\/status$/],
  ['GET', /^\/api\/watchlist$/],
  ['POST', /^\/api\/watchlist$/],
  ['DELETE', /^\/api\/watchlist\/[A-Za-z0-9_-]+$/],
  ['POST', /^\/api\/payments\/(?:deposits|withdrawals)$/],
  ['GET', /^\/api\/payments(?:\/[0-9]+)?$/],
  ['POST', /^\/api\/payments\/[0-9]+\/cancel$/],
  ['GET', /^\/api\/stocks(?:\/[A-Za-z0-9_-]+)?$/],
  ['GET', /^\/actuator\/health$/],
];

const forwardedHeaders = ['authorization', 'accept', 'content-type', 'user-agent', 'client-request-id'];

function allowed(method, rawUrl) {
  let url;
  try {
    url = new URL(rawUrl, 'http://localhost');
    if (url.origin !== 'http://localhost' || /%(?:2f|5c|2e|00)/i.test(rawUrl)) return false;
    if (decodeURIComponent(url.pathname) !== url.pathname) return false;
    if (rawUrl.includes('\\') || rawUrl.split('?')[0].split('/').some(part => part === '.' || part === '..')) return false;
  } catch {
    return false;
  }
  return routes.some(([verb, path]) => verb === method && path.test(url.pathname));
}

function jsonError(res, status, message) {
  res.writeHead(status, { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' });
  res.end(JSON.stringify({ error: message }));
}

function createGateway({ upstreamPort = 8083, port = 8084 } = {}) {
  const counters = new Map();
  let active = 0;
  function underLimit(key, max) {
    const now = Date.now();
    const windowStart = Math.floor(now / 60000);
    const current = counters.get(key);
    if (!current || current.windowStart !== windowStart) {
      counters.set(key, { windowStart, count: 1 });
      if (counters.size > 500) {
        for (const [entryKey, value] of counters) {
          if (value.windowStart !== windowStart) counters.delete(entryKey);
        }
      }
      return true;
    }
    current.count += 1;
    return current.count <= max;
  }

  const server = http.createServer(async (req, res) => {
    // New accounts must be provisioned explicitly for this small private test cohort.
    if (req.url?.split('?')[0] === '/api/auth/register' && process.env.FNMF_PUBLIC_REGISTRATION !== 'true') {
      return jsonError(res, 404, 'Not found');
    }
    if (req.method === 'POST' && req.url?.split('?')[0] === '/api/auth/register' && process.env.FNMF_PUBLIC_REGISTRATION === 'true') {
      // Reuse the same bounded auth path below, without opening any other route.
    } else if (!allowed(req.method, req.url)) return jsonError(res, 404, 'Not found');
    // Do not use X-Forwarded-For: a tunnel makes all origins appear local,
    // while trusting client-provided values would enable spoofing.
    if (!underLimit('all', 600)) return jsonError(res, 429, 'Too many requests');
    const authRoute = /^\/api\/auth\/(?:login|register)(?:\?|$)/.test(req.url);
    if (authRoute && !underLimit('auth', 30)) return jsonError(res, 429, 'Too many auth requests');
    if (active >= 12) return jsonError(res, 503, 'Gateway busy');

    const chunks = [];
    let size = 0;
    try {
      for await (const chunk of req) {
        size += chunk.length;
        if (size > 256 * 1024) return jsonError(res, 413, 'Request too large');
        chunks.push(chunk);
      }
    } catch {
      return jsonError(res, 400, 'Invalid request body');
    }
    const body = Buffer.concat(chunks);
    if (authRoute) {
      let email;
      try {
        const parsed = JSON.parse(body.toString('utf8'));
        email = typeof parsed.email === 'string' ? parsed.email.trim().toLowerCase() : '';
      } catch {
        return jsonError(res, 400, 'Invalid JSON');
      }
      // A per-account cap survives a shared tunnel IP. No credentials are logged.
      if (!email || email.length > 254 || !underLimit(`auth:${email}`, 10)) {
        return jsonError(res, 429, 'Too many auth requests');
      }
    }

    const headers = {};
    for (const key of forwardedHeaders) if (req.headers[key]) headers[key] = req.headers[key];
    headers.host = `127.0.0.1:${upstreamPort}`;
    headers['content-length'] = body.length;
    active += 1;
    let closed = false;
    const finish = () => {
      if (!closed) { closed = true; active -= 1; }
    };
    res.on('close', finish);
    const upstream = http.request({
      hostname: '127.0.0.1', port: upstreamPort, method: req.method, path: req.url,
      headers, timeout: 50000,
    }, (response) => {
      const replyHeaders = {};
      for (const key of ['content-type', 'cache-control', 'etag', 'last-modified']) {
        if (response.headers[key]) replyHeaders[key] = response.headers[key];
      }
      replyHeaders['cache-control'] = 'no-store';
      res.writeHead(response.statusCode || 502, replyHeaders);
      response.pipe(res);
      response.on('end', finish);
      response.on('error', () => { finish(); res.destroy(); });
    });
    upstream.on('timeout', () => upstream.destroy(new Error('timeout')));
    upstream.on('error', () => {
      finish();
      if (!res.headersSent) jsonError(res, 502, 'Backend unavailable');
      else res.destroy();
    });
    upstream.end(body);
  });
  server.requestTimeout = 55000;
  server.headersTimeout = 10000;
  server.maxConnections = 20;
  return { server, port };
}

if (require.main === module) {
  const { server, port } = createGateway();
  server.listen(port, '127.0.0.1', () => process.stdout.write(`FNMF public API gateway listening on 127.0.0.1:${port}\n`));
}

module.exports = { allowed, createGateway };

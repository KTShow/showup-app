// ============================================================
// Apple Push Notification service (APNs) sender for the iPhone app.
// ============================================================
// Token-based auth: a short JWT (ES256) signed with the .p8 key from
// developer.apple.com > Keys, sent over HTTP/2 to Apple. No dependencies.
//
// Env: APNS_KEY (the whole .p8 file, BEGIN/END lines included),
//      APNS_KEY_ID, APNS_TEAM_ID, optional APNS_BUNDLE_ID.
// TestFlight and App Store builds both use the production APNs host.
// ============================================================

const http2 = require('http2');
const crypto = require('crypto');

const HOST = 'https://api.push.apple.com';
const BUNDLE_ID = process.env.APNS_BUNDLE_ID || 'com.showuproom.app';

function configured() {
  return !!(process.env.APNS_KEY && process.env.APNS_KEY_ID && process.env.APNS_TEAM_ID);
}

const b64url = (buf) => Buffer.from(buf).toString('base64').replace(/=+$/, '').replace(/\+/g, '-').replace(/\//g, '_');

// Apple accepts a token for up to an hour; reuse it across warm invocations.
let _jwt = null, _jwtAt = 0;
function jwt() {
  const now = Math.floor(Date.now() / 1000);
  if (_jwt && now - _jwtAt < 50 * 60) return _jwt;
  const head = b64url(JSON.stringify({ alg: 'ES256', kid: process.env.APNS_KEY_ID }));
  const claims = b64url(JSON.stringify({ iss: process.env.APNS_TEAM_ID, iat: now }));
  // Vercel env values sometimes arrive with literal "\n" instead of newlines.
  const key = process.env.APNS_KEY.replace(/\\n/g, '\n');
  const sig = crypto.sign('sha256', Buffer.from(head + '.' + claims), { key, dsaEncoding: 'ieee-p1363' });
  _jwt = head + '.' + claims + '.' + b64url(sig);
  _jwtAt = now;
  return _jwt;
}

// Sends one alert per job over a single connection.
// jobs: [{ token, payload: {title, body, url, tag} }]
// Returns [{ token, status, reason }].
function sendApns(jobs) {
  if (!jobs.length) return Promise.resolve([]);
  return new Promise((resolve) => {
    const client = http2.connect(HOST);
    const results = [];
    let left = jobs.length;
    const done = (r) => { results.push(r); if (--left === 0) { client.close(); resolve(results); } };
    // A connection failure also errors/closes every open request, which
    // reports each one below -- this just keeps it from throwing.
    client.on('error', (e) => console.error('apns connection error', e.message));
    jobs.forEach((j) => {
      const body = JSON.stringify({
        aps: { alert: { title: j.payload.title, body: j.payload.body }, sound: 'default', 'thread-id': j.payload.tag || 'showup' },
        url: j.payload.url,
      });
      let req;
      try {
        req = client.request({
          ':method': 'POST',
          ':path': '/3/device/' + j.token,
          authorization: 'bearer ' + jwt(),
          'apns-topic': BUNDLE_ID,
          'apns-push-type': 'alert',
          'apns-priority': '10',
          'content-type': 'application/json',
        });
      } catch (e) {
        done({ token: j.token, status: 0, reason: e.message });
        return;
      }
      let status = 0, data = '', reported = false;
      const finish = (r) => { if (!reported) { reported = true; done(r); } };
      req.setTimeout(10000, () => req.close(http2.constants.NGHTTP2_CANCEL));
      req.on('response', (h) => { status = h[':status']; });
      req.on('data', (c) => { data += c; });
      req.on('error', (e) => finish({ token: j.token, status: 0, reason: e.message }));
      req.on('close', () => {
        let reason = '';
        try { reason = data ? JSON.parse(data).reason : ''; } catch (e) {}
        finish({ token: j.token, status, reason });
      });
      req.end(body);
    });
  });
}

// Short fingerprint of the key in use (a hash of its PUBLIC half -- safe to
// show) so a wrong/stale key in the env can be spotted.
function keyInfo() {
  if (!configured()) return null;
  try {
    const pub = crypto.createPublicKey(process.env.APNS_KEY.replace(/\\n/g, '\n')).export({ type: 'spki', format: 'der' });
    return { kid: process.env.APNS_KEY_ID, team: process.env.APNS_TEAM_ID, fp: crypto.createHash('sha256').update(pub).digest('hex').slice(0, 10) };
  } catch (e) {
    return { kid: process.env.APNS_KEY_ID, error: 'key unreadable: ' + e.message };
  }
}

module.exports = { sendApns, apnsConfigured: configured, apnsKeyInfo: keyInfo };

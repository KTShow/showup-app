// ============================================================
// webpush.js — zero-dependency Web Push sender
// ============================================================
// Implements the two standards a browser push needs, using only Node's
// built-in crypto (no npm, matching the rest of the repo):
//   * RFC 8291 / 8188 — payload encryption ("aes128gcm"), so only the
//     subscribed device can read the alert text.
//   * RFC 8292 — VAPID, a signed token proving the push comes from us.
// Files under api/_lib are helpers, not deployed as endpoints (Vercel skips
// underscore-prefixed paths).
// ============================================================

const crypto = require('crypto');

function b64url(buf) {
  return Buffer.from(buf).toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function fromB64url(str) {
  return Buffer.from(str.replace(/-/g, '+').replace(/_/g, '/'), 'base64');
}

// Encrypts `payload` for one subscription. `opts.salt` / `opts.asPrivate`
// exist only so the RFC 8291 test vector can be reproduced exactly.
function encrypt(payload, p256dh, authSecret, opts) {
  opts = opts || {};
  const uaPublic = fromB64url(p256dh);
  const auth = fromB64url(authSecret);

  const ecdh = crypto.createECDH('prime256v1');
  if (opts.asPrivate) ecdh.setPrivateKey(fromB64url(opts.asPrivate));
  else ecdh.generateKeys();
  const asPublic = ecdh.getPublicKey();
  const sharedSecret = ecdh.computeSecret(uaPublic);

  const keyInfo = Buffer.concat([Buffer.from('WebPush: info\0'), uaPublic, asPublic]);
  const ikm = Buffer.from(crypto.hkdfSync('sha256', sharedSecret, auth, keyInfo, 32));

  const salt = opts.salt ? fromB64url(opts.salt) : crypto.randomBytes(16);
  const cek = Buffer.from(crypto.hkdfSync('sha256', ikm, salt, Buffer.from('Content-Encoding: aes128gcm\0'), 16));
  const nonce = Buffer.from(crypto.hkdfSync('sha256', ikm, salt, Buffer.from('Content-Encoding: nonce\0'), 12));

  // Single record: plaintext + 0x02 "last record" delimiter.
  const plain = Buffer.concat([Buffer.from(payload, 'utf8'), Buffer.from([2])]);
  const cipher = crypto.createCipheriv('aes-128-gcm', cek, nonce);
  const body = Buffer.concat([cipher.update(plain), cipher.final(), cipher.getAuthTag()]);

  const rs = Buffer.alloc(4);
  rs.writeUInt32BE(4096, 0);
  const header = Buffer.concat([salt, rs, Buffer.from([asPublic.length]), asPublic]);
  return Buffer.concat([header, body]);
}

// VAPID keys: public = 65-byte uncompressed P-256 point, private = 32-byte
// scalar, both base64url (the format every web-push tool uses).
function vapidAuthHeader(endpoint, publicKey, privateKey, subject) {
  const pub = fromB64url(publicKey);
  const key = crypto.createPrivateKey({
    format: 'jwk',
    key: { kty: 'EC', crv: 'P-256', d: privateKey, x: b64url(pub.subarray(1, 33)), y: b64url(pub.subarray(33, 65)) },
  });
  const header = b64url(JSON.stringify({ typ: 'JWT', alg: 'ES256' }));
  const claims = b64url(JSON.stringify({
    aud: new URL(endpoint).origin,
    exp: Math.floor(Date.now() / 1000) + 12 * 60 * 60,
    sub: subject,
  }));
  const unsigned = header + '.' + claims;
  const sig = crypto.sign('sha256', Buffer.from(unsigned), { key, dsaEncoding: 'ieee-p1363' });
  return 'vapid t=' + unsigned + '.' + b64url(sig) + ', k=' + publicKey;
}

// Sends one push. Resolves to the push service's HTTP status; 404/410 mean
// the subscription is dead (app removed, permission revoked) and should be
// deleted by the caller.
async function sendPush(sub, payload, vapid) {
  const body = encrypt(JSON.stringify(payload), sub.p256dh, sub.auth);
  const res = await fetch(sub.endpoint, {
    method: 'POST',
    headers: {
      Authorization: vapidAuthHeader(sub.endpoint, vapid.publicKey, vapid.privateKey, vapid.subject),
      'Content-Encoding': 'aes128gcm',
      'Content-Type': 'application/octet-stream',
      TTL: '86400',
      Urgency: 'normal',
    },
    body,
  });
  return res.status;
}

module.exports = { encrypt, vapidAuthHeader, sendPush, b64url, fromB64url };

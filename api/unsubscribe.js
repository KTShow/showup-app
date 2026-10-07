// ============================================================
// /api/unsubscribe — "Stop these emails" link in the weekly recap
// ============================================================
// GET  ?u=<user id>&t=<token>  -> turns the recap off, shows a short page
// POST (same query)            -> one-click unsubscribe from mail apps
//                                 (List-Unsubscribe-Post header)
//
// The token is an HMAC of the user id keyed by the service-role key, so the
// link works without signing in but can't be forged for someone else.
// Must match unsubscribeUrl() in scripts/send-comment-digest.mjs.
// ============================================================

const crypto = require('crypto');

const SUPABASE_URL = process.env.SUPABASE_URL || 'https://sgnulweruogjfdddwboe.supabase.co';
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

function validToken(userId, token) {
  if (!/^[0-9a-f-]{36}$/i.test(userId || '') || !/^[0-9a-f]{32}$/.test(token || '')) return false;
  const want = crypto.createHmac('sha256', SERVICE_KEY).update('unsub:' + userId).digest('hex').slice(0, 32);
  return crypto.timingSafeEqual(Buffer.from(want), Buffer.from(token));
}

function page(title, msg) {
  return '<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
    + '<title>ShowUp</title></head><body style="margin:0;background:#FBF7F2;font-family:-apple-system,Segoe UI,Helvetica,Arial,sans-serif;color:#3A3A3A;">'
    + '<div style="max-width:440px;margin:60px auto;padding:28px 24px;background:#fff;border-radius:12px;text-align:center;">'
    + '<div style="font-size:22px;font-weight:800;color:#C4622D;margin-bottom:14px;">ShowUp</div>'
    + '<div style="font-size:18px;font-weight:700;margin-bottom:8px;">' + title + '</div>'
    + '<div style="font-size:15px;color:#6A6A6A;line-height:1.5;">' + msg + '</div>'
    + '<a href="/" style="display:inline-block;margin-top:20px;color:#C4622D;font-weight:700;text-decoration:none;">Open ShowUp &rsaquo;</a>'
    + '</div></body></html>';
}

module.exports = async (req, res) => {
  const { u, t } = req.query || {};
  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  if (!SERVICE_KEY || !validToken(u, t)) {
    return res.status(400).send(page('That link didn’t work', 'You can turn off the weekly recap in ShowUp under Settings → Notifications.'));
  }
  try {
    const r = await fetch(SUPABASE_URL + '/rest/v1/rpc/digest_unsubscribe', {
      method: 'POST',
      headers: { apikey: SERVICE_KEY, Authorization: 'Bearer ' + SERVICE_KEY, 'Content-Type': 'application/json' },
      body: JSON.stringify({ p_user_id: u }),
    });
    if (!r.ok) throw new Error(r.status + ' ' + (await r.text()));
  } catch (e) {
    console.error('/api/unsubscribe error', e);
    return res.status(500).send(page('Something went wrong', 'Please try the link again in a minute.'));
  }
  return res.status(200).send(page('You’re unsubscribed', 'No more weekly recap emails. You can turn them back on any time in Settings → Notifications.'));
};

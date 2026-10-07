// ============================================================
// /api/push — delivers pending phone/desktop alerts (Vercel function)
// ============================================================
// Two ways in, both POST:
//   * No body (or {}): "flush". The app calls this right after posting a
//     comment. Claims every notification row the database marked
//     push_pending (see sql/add_push_alerts.sql -> notify_show_comment) and
//     pushes each to its owner's subscribed devices. Needs no login: it can
//     only ever deliver rows the database already decided to send, and the
//     claim is atomic, so each row is pushed at most once.
//   * {"test": true} with the user's Supabase token as a Bearer header:
//     sends a "you're all set" alert to that user's own devices only.
//
// Env (Vercel > Project > Settings > Environment Variables):
//   SUPABASE_SERVICE_ROLE_KEY, VAPID_PRIVATE_KEY
// ============================================================

const { sendPush } = require('./_lib/webpush');

const SUPABASE_URL = process.env.SUPABASE_URL || 'https://sgnulweruogjfdddwboe.supabase.co';
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const VAPID = {
  publicKey: process.env.VAPID_PUBLIC_KEY || 'BG2kXjoiKVotzmcJ1T1NCl-FL3DC8fMdoCCpwmdVdeRaGRc9V9jN6ikRHurIOMC1Wio9ZmfqJQv_6vJdgtx2Y9w',
  privateKey: process.env.VAPID_PRIVATE_KEY,
  subject: 'mailto:admin@showuproom.com',
};

const SB_HEADERS = {
  apikey: SERVICE_KEY,
  Authorization: 'Bearer ' + SERVICE_KEY,
  'Content-Type': 'application/json',
};

async function sb(path, init) {
  const res = await fetch(SUPABASE_URL + path, Object.assign({ headers: SB_HEADERS }, init));
  if (!res.ok) throw new Error(path + ' -> ' + res.status + ' ' + (await res.text()));
  const text = await res.text();
  return text ? JSON.parse(text) : null;
}

async function subscriptionsFor(userIds) {
  if (!userIds.length) return [];
  return sb('/rest/v1/push_subscriptions?select=id,user_id,endpoint,p256dh,auth&user_id=in.(' + userIds.join(',') + ')');
}

// Push to every device; prune subscriptions the push service says are gone.
async function deliver(subs, payloadFor) {
  let sent = 0;
  await Promise.all(subs.map(async (s) => {
    try {
      const status = await sendPush(s, payloadFor(s), VAPID);
      if (status === 404 || status === 410) {
        await sb('/rest/v1/push_subscriptions?id=eq.' + s.id, { method: 'DELETE' });
      } else if (status >= 200 && status < 300) {
        sent++;
      } else {
        console.error('push failed', status, s.endpoint.slice(0, 40));
      }
    } catch (e) {
      console.error('push error', e.message);
    }
  }));
  return sent;
}

function payloadForNotification(n) {
  const icon = n.type === 'comment' ? '💬 '
    : n.type === 'lounge_reply' ? '☕ '
    : (n.type === 'new_season' || n.type === 'season_upcoming') ? '📺 ' : '';
  return {
    title: icon + (n.title || 'ShowUp'),
    body: n.body || '',
    url: '/?notif=' + n.id,
    tag: n.type + ':' + (n.title || '').toLowerCase(),
  };
}

async function flush() {
  const rows = (await sb('/rest/v1/rpc/claim_pending_pushes', { method: 'POST', body: '{}' })) || [];
  if (!rows.length) return { claimed: 0, sent: 0 };
  const byUser = {};
  rows.forEach((n) => { (byUser[n.user_id] = byUser[n.user_id] || []).push(n); });
  const subs = await subscriptionsFor(Object.keys(byUser));
  const jobs = [];
  subs.forEach((s) => byUser[s.user_id].forEach((n) => jobs.push(Object.assign({}, s, { _n: n }))));
  const sent = await deliver(jobs, (j) => payloadForNotification(j._n));
  return { claimed: rows.length, sent };
}

async function test(req) {
  const token = (req.headers.authorization || '').replace(/^Bearer\s+/i, '');
  if (!token) return { status: 401, body: { error: 'Not signed in' } };
  const res = await fetch(SUPABASE_URL + '/auth/v1/user', { headers: { apikey: SERVICE_KEY, Authorization: 'Bearer ' + token } });
  if (!res.ok) return { status: 401, body: { error: 'Not signed in' } };
  const user = await res.json();
  const subs = await subscriptionsFor([user.id]);
  const sent = await deliver(subs, () => ({
    title: "🔔 You're all set",
    body: "You'll get an alert when someone in your Living Room comments on a show, or a show you follow gets a new season.",
    url: '/',
    tag: 'test',
  }));
  return { status: 200, body: { sent } };
}

module.exports = async (req, res) => {
  if (req.method !== 'POST') return res.status(405).json({ error: 'POST only' });
  if (!SERVICE_KEY || !VAPID.privateKey) return res.status(500).json({ error: 'Push is not configured' });
  try {
    if (req.body && req.body.test) {
      const r = await test(req);
      return res.status(r.status).json(r.body);
    }
    return res.status(200).json(await flush());
  } catch (e) {
    console.error('/api/push error', e);
    return res.status(500).json({ error: 'Push failed' });
  }
};

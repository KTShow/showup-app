// ============================================================
// send-comment-digest.mjs — weekly email recap of comments
// ============================================================
// Runs Sundays from .github/workflows/send-comment-digest.yml (and can be run
// by hand with `node scripts/send-comment-digest.mjs` given the env vars).
//
// For people who DON'T get phone alerts: one email a week listing the
// comments their crowd made that they haven't seen in the app yet. Who and
// what come from get_comment_digest() (sql/add_comment_digest.sql); each
// emailed bell row is stamped via mark_digest_sent() so it never goes out
// twice. Sent through Resend from recap@showuproom.com.
//
// Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, RESEND_API_KEY
// Optional: ONLY_EMAIL=someone@x.com -- PREVIEW: send one recap to just that
//             account, built from its comment bell rows of the last 7 days
//             regardless of its settings / alerts / what it's seen, and stamp
//             nothing (so the real Sunday run is unaffected)
//           DRY_RUN=1 -- print what would be sent, send and stamp nothing
//
// Zero dependencies: Node 20+ global fetch + node:crypto.
// ============================================================

import { createHmac } from 'node:crypto';

const SUPABASE_URL = need('SUPABASE_URL');
const SERVICE_KEY = need('SUPABASE_SERVICE_ROLE_KEY');
const DRY_RUN = !!process.env.DRY_RUN;
const RESEND_KEY = DRY_RUN ? process.env.RESEND_API_KEY : need('RESEND_API_KEY');
const ONLY_EMAIL = (process.env.ONLY_EMAIL || '').trim().toLowerCase();

const SITE = 'https://showuproom.com';
const FROM = 'ShowUp <recap@showuproom.com>';
const REPLY_TO = 'admin@showuproom.com';

const SB_HEADERS = {
  apikey: SERVICE_KEY,
  Authorization: `Bearer ${SERVICE_KEY}`,
  'Content-Type': 'application/json',
};

function need(name) {
  const v = process.env[name];
  if (!v) {
    console.error(`Missing required env var: ${name}`);
    process.exit(1);
  }
  return v;
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function rpc(name, body) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${name}`, {
    method: 'POST', headers: SB_HEADERS, body: JSON.stringify(body || {}),
  });
  if (!res.ok) throw new Error(`${name} -> ${res.status} ${await res.text()}`);
  const text = await res.text();
  return text ? JSON.parse(text) : null;
}

// Must match api/unsubscribe.js.
function unsubscribeUrl(userId) {
  const t = createHmac('sha256', SERVICE_KEY).update('unsub:' + userId).digest('hex').slice(0, 32);
  return `${SITE}/api/unsubscribe?u=${userId}&t=${t}`;
}

const esc = (s) => String(s == null ? '' : s)
  .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

function subjectFor(items) {
  if (items.length === 1) {
    const who = (items[0].body || '').split(/:| and \d/)[0].trim();
    return who ? `${who} commented on ${items[0].title}` : `New comments on ${items[0].title}`;
  }
  const shows = new Set(items.map((i) => (i.title || '').toLowerCase())).size;
  return shows === 1 ? `New comments on ${items[0].title}` : `Your crowd talked about ${shows} shows this week`;
}

const MAX_SHOWS = 10;

// One entry per show (newest comment row wins; rows arrive newest-first),
// capped at MAX_SHOWS. Every row's id is still stamped as emailed.
function byShow(rows) {
  const seen = new Map();
  rows.forEach((it) => {
    const k = (it.title || '').toLowerCase();
    if (!seen.has(k)) seen.set(k, it);
  });
  return [...seen.values()];
}

function render(row) {
  const all = byShow(row.items);
  const items = all.slice(0, MAX_SHOWS);
  const more = all.length - items.length;
  const hi = row.first_name ? `Hi ${esc(row.first_name)},` : 'Hi,';
  const unsub = unsubscribeUrl(row.user_id);
  const blocks = items.map((it) => `
      <tr><td style="padding:14px 0;border-top:1px solid #eee;">
        <div style="font-size:16px;font-weight:700;color:#3A3A3A;">${esc(it.title)}</div>
        <div style="font-size:15px;color:#555;margin:4px 0 8px;line-height:1.45;">${esc(it.body)}</div>
        <a href="${SITE}/?notif=${it.id}" style="color:#C4622D;font-weight:700;text-decoration:none;font-size:14px;">Read &amp; reply &rsaquo;</a>
      </td></tr>`).join('') + (more > 0 ? `
      <tr><td style="padding:14px 0;border-top:1px solid #eee;font-size:15px;color:#555;">
        &hellip;and ${more} more ${more === 1 ? 'show' : 'shows'}. <a href="${SITE}/" style="color:#C4622D;font-weight:700;text-decoration:none;">Open ShowUp &rsaquo;</a>
      </td></tr>` : '');

  const html = `<!doctype html><html><body style="margin:0;background:#FBF7F2;font-family:-apple-system,Segoe UI,Helvetica,Arial,sans-serif;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#FBF7F2;"><tr><td align="center" style="padding:24px 16px;">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:520px;background:#fff;border-radius:12px;padding:24px;">
      <tr><td style="font-size:22px;font-weight:800;color:#C4622D;padding-bottom:12px;">ShowUp</td></tr>
      <tr><td style="font-size:16px;color:#3A3A3A;padding-bottom:8px;">${hi}</td></tr>
      <tr><td style="font-size:16px;color:#3A3A3A;padding-bottom:6px;">Here's what your crowd talked about this week:</td></tr>
      ${blocks}
      <tr><td style="padding-top:20px;font-size:12px;color:#999;line-height:1.5;border-top:1px solid #eee;">
        You get this weekly recap because phone alerts aren't turned on for your account.
        <a href="${unsub}" style="color:#999;">Stop these emails</a> &middot; or change it in ShowUp under Settings &rarr; Notifications.
      </td></tr>
    </table>
  </td></tr></table></body></html>`;

  const text = [
    row.first_name ? `Hi ${row.first_name},` : 'Hi,', '', "Here's what your crowd talked about this week:", '',
    ...items.flatMap((it) => [it.title, it.body || '', `${SITE}/?notif=${it.id}`, '']),
    ...(more > 0 ? [`...and ${more} more. ${SITE}/`, ''] : []),
    `Stop these emails: ${unsub}`,
  ].join('\n');

  return { subject: subjectFor(all), html, text, unsub };
}

async function send(row, msg) {
  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: { Authorization: `Bearer ${RESEND_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      from: FROM,
      to: [row.email],
      reply_to: REPLY_TO,
      subject: msg.subject,
      html: msg.html,
      text: msg.text,
      headers: {
        'List-Unsubscribe': `<${msg.unsub}>`,
        'List-Unsubscribe-Post': 'List-Unsubscribe=One-Click',
      },
    }),
  });
  if (!res.ok) throw new Error(`resend ${res.status} ${await res.text()}`);
}

async function get(path, base = '/rest/v1') {
  const res = await fetch(`${SUPABASE_URL}${base}${path}`, { headers: SB_HEADERS });
  if (!res.ok) throw new Error(`${path} -> ${res.status} ${await res.text()}`);
  return res.json();
}

async function previewRow(email) {
  let user = null;
  for (let page = 1; !user && page <= 20; page++) {
    const r = await get(`/admin/users?page=${page}&per_page=200`, '/auth/v1');
    const list = r.users || [];
    user = list.find((u) => (u.email || '').toLowerCase() === email);
    if (list.length < 200) break;
  }
  if (!user) { console.error(`No account with email ${email}`); return null; }
  const since = new Date(Date.now() - 7 * 864e5).toISOString();
  const items = await get(`/notifications?select=id,title,body&user_id=eq.${user.id}&type=eq.comment&created_at=gt.${since}&order=created_at.desc`);
  if (!items.length) { console.error('No comments for that account in the last 7 days'); return null; }
  const prof = await get(`/users?select=first_name&id=eq.${user.id}`);
  return { user_id: user.id, email: user.email, first_name: prof[0] && prof[0].first_name, items };
}

async function main() {
  let rows;
  if (ONLY_EMAIL) {
    const r = await previewRow(ONLY_EMAIL);
    rows = r ? [r] : [];
  } else {
    rows = (await rpc('get_comment_digest')) || [];
  }
  console.log(`${rows.length} recap(s) to send${DRY_RUN ? ' (dry run)' : ''}${ONLY_EMAIL ? ' (only ' + ONLY_EMAIL + ')' : ''}`);

  let sent = 0, failed = 0;
  for (const row of rows) {
    const msg = render(row);
    if (DRY_RUN) {
      console.log(`-> ${row.email}: "${msg.subject}" (${row.items.length} item(s))`);
      continue;
    }
    try {
      await send(row, msg);
      if (!ONLY_EMAIL) await rpc('mark_digest_sent', { p_ids: row.items.map((i) => i.id) });
      sent++;
    } catch (e) {
      failed++;
      console.error(`failed for ${row.user_id}: ${e.message}`);
    }
    await sleep(600); // Resend's default limit is 2 requests/second
  }
  console.log(`sent ${sent}, failed ${failed}`);
  if (failed && !sent) process.exit(1);
}

main().catch((e) => { console.error(e); process.exit(1); });

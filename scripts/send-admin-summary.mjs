// ============================================================
// send-admin-summary.mjs — Monday numbers email for ShowUp admins
// ============================================================
// Runs Mondays from .github/workflows/send-admin-summary.yml (or by hand).
// Headline numbers only -- no names or emails in anyone's inbox; the
// details are in the app under Settings > Admin > Members. Data comes from
// _admin_members() (sql/add_admin_members.sql). Sent to every users.is_admin
// account through Resend.
//
// Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, RESEND_API_KEY
// Optional: DRY_RUN=1 -- print the email, send nothing
// ============================================================

const SUPABASE_URL = need('SUPABASE_URL');
const SERVICE_KEY = need('SUPABASE_SERVICE_ROLE_KEY');
const DRY_RUN = !!process.env.DRY_RUN;
const RESEND_KEY = DRY_RUN ? process.env.RESEND_API_KEY : need('RESEND_API_KEY');

const SITE = 'https://showuproom.com';
const FROM = 'ShowUp <recap@showuproom.com>';

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

async function sb(path, init) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, Object.assign({ headers: SB_HEADERS }, init));
  if (!res.ok) throw new Error(`${path} -> ${res.status} ${await res.text()}`);
  return res.json();
}

const days = (d) => (d ? (Date.now() - new Date(d).getTime()) / 864e5 : Infinity);
const pct = (n, of) => (of ? Math.round((n * 100) / of) : 0);

function summarize(all) {
  const newer = all.filter((m) => days(m.joined) < 7);
  const prior = all.filter((m) => days(m.joined) >= 7);
  const n = {
    total: all.length,
    newThisWeek: newer.length,
    newWith3: newer.filter((m) => m.shows >= 3).length,
    active: all.filter((m) => days(m.last_visit) < 7).length,
    activePrior: prior.filter((m) => days(m.last_visit) < 7).length,
    alerts: all.filter((m) => m.alerts_on).length,
    installed: all.filter((m) => m.uses_app || m.home_screen).length,
    app: all.filter((m) => m.uses_app).length,
    quiet: all.filter((m) => days(m.last_visit) >= 14).length,
  };
  return n;
}

function render(n) {
  const rows = [
    ['Members', `${n.total}`],
    ['New this week', `${n.newThisWeek}` + (n.newThisWeek ? ` (${n.newWith3} added 3+ shows)` : '')],
    ['Active this week', `${n.active} (${pct(n.active, n.total)}%)`],
    ['Alerts on', `${n.alerts} (${pct(n.alerts, n.total)}%)`],
    ['iPhone app or Home Screen', `${n.installed} (${pct(n.installed, n.total)}%), ${n.app} on the iPhone app`],
    ['Not in for 2+ weeks', `${n.quiet}`],
  ];
  const html = `<!doctype html><html><body style="margin:0;background:#FBF7F2;font-family:-apple-system,Segoe UI,Helvetica,Arial,sans-serif;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#FBF7F2;"><tr><td align="center" style="padding:24px 16px;">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:520px;background:#fff;border-radius:12px;padding:24px;">
      <tr><td colspan="2" style="font-size:22px;font-weight:800;color:#C4622D;padding-bottom:4px;">ShowUp</td></tr>
      <tr><td colspan="2" style="font-size:16px;color:#3A3A3A;padding-bottom:14px;">Your Monday numbers</td></tr>
      ${rows.map(([k, v]) => `<tr><td style="padding:9px 0;border-top:1px solid #eee;font-size:15px;color:#555;">${k}</td><td align="right" style="padding:9px 0;border-top:1px solid #eee;font-size:15px;font-weight:700;color:#3A3A3A;">${v}</td></tr>`).join('')}
      <tr><td colspan="2" style="padding-top:18px;font-size:14px;color:#555;line-height:1.5;">
        Names and details: <a href="${SITE}/" style="color:#C4622D;font-weight:700;text-decoration:none;">ShowUp</a> &rarr; Settings &rarr; Admin &rarr; Members.
        "iPhone app or Home Screen" fills in as people visit, since the app started recording it on Oct 27.
      </td></tr>
    </table>
  </td></tr></table></body></html>`;
  const text = ['ShowUp: your Monday numbers', '', ...rows.map(([k, v]) => `${k}: ${v}`), '',
    `Names and details: ${SITE} > Settings > Admin > Members`].join('\n');
  return { subject: `ShowUp this week: ${n.active} active, ${n.newThisWeek} new`, html, text };
}

async function adminEmails() {
  const admins = await sb('users?select=email&is_admin=is.true');
  return admins.map((a) => a.email).filter(Boolean);
}

async function main() {
  const all = (await sb('rpc/_admin_members', { method: 'POST', body: '{}' })) || [];
  const msg = render(summarize(all));
  const to = await adminEmails();
  console.log(`${all.length} members; sending to ${to.length} admin(s)${DRY_RUN ? ' (dry run)' : ''}`);
  if (DRY_RUN) { console.log(msg.subject + '\n\n' + msg.text); return; }
  if (!to.length) { console.error('No admin emails found'); process.exit(1); }
  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: { Authorization: `Bearer ${RESEND_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ from: FROM, to, subject: msg.subject, html: msg.html, text: msg.text }),
  });
  if (!res.ok) throw new Error(`resend ${res.status} ${await res.text()}`);
  console.log('sent');
}

main().catch((e) => { console.error(e); process.exit(1); });

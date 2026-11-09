// ============================================================
// send-login-code.mjs — admin backup when someone's login code email
// never shows up (e.g. AT&T / bellsouth.net hiding it)
// ============================================================
// Run by hand from .github/workflows/send-login-code.yml. Makes a fresh
// sign-in code for an EXISTING account (no email goes to that person) and
// emails it to admin@showuproom.com, so an admin can text it to them.
// The code is never printed to the GitHub log (repo collaborators can read it).
//
// The person should already be on the "enter your code" screen: each new code
// replaces the older ones, so this one has to be the newest.
//
// Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, RESEND_API_KEY, TARGET_EMAIL
// ============================================================

const SUPABASE_URL = need('SUPABASE_URL');
const SERVICE_KEY = need('SUPABASE_SERVICE_ROLE_KEY');
const RESEND_KEY = need('RESEND_API_KEY');
const TARGET = need('TARGET_EMAIL').trim().toLowerCase();

const FROM = 'ShowUp <recap@showuproom.com>';
const ADMIN_TO = 'admin@showuproom.com';

function need(name) {
  const v = process.env[name];
  if (!v || !v.trim()) {
    console.error(`Missing required value: ${name}`);
    process.exit(1);
  }
  return v;
}

const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

async function main() {
  // Existing accounts only -- never create one from here.
  const lookup = await fetch(`${SUPABASE_URL}/rest/v1/users?select=id,first_name&email=ilike.${encodeURIComponent(TARGET)}`, {
    headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}` },
  });
  if (!lookup.ok) throw new Error(`user lookup -> ${lookup.status} ${await lookup.text()}`);
  const rows = await lookup.json();
  if (!rows.length) {
    console.error(`No ShowUp account found for ${TARGET}. Check the spelling. Nothing was sent.`);
    process.exit(1);
  }
  const first = rows[0].first_name || TARGET;

  // Admin "generate link" makes the same kind of code the app emails, without sending anything.
  const gen = await fetch(`${SUPABASE_URL}/auth/v1/admin/generate_link`, {
    method: 'POST',
    headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ type: 'magiclink', email: TARGET }),
  });
  if (!gen.ok) throw new Error(`generate_link -> ${gen.status} ${await gen.text()}`);
  const data = await gen.json();
  const code = data.email_otp || (data.properties && data.properties.email_otp);
  if (!code) throw new Error('Supabase did not return a code.');

  const html = `<div style="font-family:-apple-system,Segoe UI,Arial,sans-serif;font-size:16px;color:#2b2b2b;">
<p>Here is a ShowUp sign-in code for <b>${esc(first)}</b> (${esc(TARGET)}):</p>
<p style="font-size:32px;font-weight:700;letter-spacing:4px;margin:16px 0;">${esc(code)}</p>
<p>Text it to them. They type it on the "enter your code" screen in the app.</p>
<p style="color:#777;font-size:14px;">It works for 24 hours, or until they ask the app for another code. If they tap "send code" again, run the job again.</p>
</div>`;

  const send = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: { Authorization: `Bearer ${RESEND_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ from: FROM, to: [ADMIN_TO], subject: `Sign-in code for ${first}`, html }),
  });
  if (!send.ok) throw new Error(`Resend -> ${send.status} ${await send.text()}`);

  console.log(`Done. A sign-in code for ${first} was emailed to ${ADMIN_TO}.`);
}

main().catch((e) => {
  console.error('Failed:', e.message);
  process.exit(1);
});

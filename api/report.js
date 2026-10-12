// ============================================================
// /api/report — email admin@showuproom.com when someone files a report
// ============================================================
// POST {report_id} with the reporter's Supabase token as a Bearer header.
// The report itself is already saved by submit_report() (see
// sql/add_report_block_filter.sql); this only sends the heads-up email so
// reports get a timely response (Apple guideline 1.2). If email isn't set
// up (no RESEND_API_KEY on Vercel) it quietly does nothing -- reports are
// still visible in Settings > Admin > Reports.
//
// Env (Vercel): SUPABASE_SERVICE_ROLE_KEY, RESEND_API_KEY
// ============================================================

const SUPABASE_URL = process.env.SUPABASE_URL || 'https://sgnulweruogjfdddwboe.supabase.co';
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const RESEND_KEY = process.env.RESEND_API_KEY;

const REASONS = { spam: 'Spam', harassment: 'Harassment or bullying', hate: 'Hate speech', sexual: 'Sexual content', other: 'Something else' };
const esc = (s) => String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

async function sb(path) {
  const res = await fetch(SUPABASE_URL + path, { headers: { apikey: SERVICE_KEY, Authorization: 'Bearer ' + SERVICE_KEY } });
  if (!res.ok) throw new Error(path + ' -> ' + res.status);
  return res.json();
}

module.exports = async (req, res) => {
  if (req.method !== 'POST') return res.status(405).json({ error: 'POST only' });
  if (!SERVICE_KEY) return res.status(500).json({ error: 'Not configured' });
  const token = (req.headers.authorization || '').replace(/^Bearer\s+/i, '');
  const id = req.body && req.body.report_id;
  if (!token || !/^[0-9a-f-]{36}$/i.test(id || '')) return res.status(400).json({ error: 'Bad request' });

  try {
    const ures = await fetch(SUPABASE_URL + '/auth/v1/user', { headers: { apikey: SERVICE_KEY, Authorization: 'Bearer ' + token } });
    if (!ures.ok) return res.status(401).json({ error: 'Not signed in' });
    const user = await ures.json();

    const rows = await sb('/rest/v1/reports?select=*&id=eq.' + id);
    const r = rows[0];
    if (!r || r.reporter_id !== user.id) return res.status(404).json({ error: 'Not found' });
    if (!RESEND_KEY) return res.status(200).json({ emailed: false });

    const ids = [r.reporter_id, r.target_user_id].filter(Boolean).join(',');
    const people = ids ? await sb('/rest/v1/users?select=id,first_name,last_initial&id=in.(' + ids + ')') : [];
    const nameOf = (uid) => { const u = people.find((p) => p.id === uid); return u ? (u.first_name + ' ' + (u.last_initial || '')).trim() : 'Unknown'; };
    const what = r.target_type === 'user' ? 'a person' : r.target_type === 'comment' ? 'a comment' : 'a Lounge post';

    const html = '<div style="font-family:-apple-system,Segoe UI,Helvetica,Arial,sans-serif;font-size:15px;color:#3A3A3A;">'
      + '<p><b>New ShowUp report:</b> ' + esc(REASONS[r.reason] || r.reason) + '</p>'
      + '<p>' + esc(nameOf(r.reporter_id)) + ' reported ' + what + ' by <b>' + esc(nameOf(r.target_user_id)) + '</b>.</p>'
      + (r.content_snapshot ? '<p style="background:#FBF7F2;padding:10px 12px;border-radius:8px;">&ldquo;' + esc(r.content_snapshot) + '&rdquo;</p>' : '')
      + (r.note ? '<p>Note: ' + esc(r.note) + '</p>' : '')
      + '<p>Review it in ShowUp: Settings &gt; Admin &gt; Reports. Apple expects a response within 24 hours.</p></div>';

    const send = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { Authorization: 'Bearer ' + RESEND_KEY, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        from: 'ShowUp <reports@showuproom.com>',
        to: ['admin@showuproom.com'],
        subject: 'ShowUp report: ' + (REASONS[r.reason] || r.reason) + ' (' + what + ')',
        html,
      }),
    });
    if (!send.ok) { console.error('resend', send.status, await send.text()); return res.status(200).json({ emailed: false }); }
    return res.status(200).json({ emailed: true });
  } catch (e) {
    console.error('/api/report error', e);
    return res.status(500).json({ error: 'Failed' });
  }
};

// ============================================================
// refresh-platforms.mjs — weekly "did this show change services?" check
// ============================================================
// Runs weekly from .github/workflows/refresh-platforms.yml (or by hand with
// the env vars set; DRY_RUN=1 logs what it would change without writing).
//
// A show's service is saved once, when someone adds it. Shows move between
// services, so once a week this:
//   1. Pulls every show row with a tmdb_id and a real service name.
//   2. For each distinct (tmdb_id, media_type), asks TMDB where it streams
//      in the US (subscription / free / with-ads; NOT buy/rent).
//   3. For each saved service on that show:
//        - still listed by TMDB           -> leave it alone (respects people
//                                            who chose one of several, e.g.
//                                            a bundle), clear any pending move
//        - TMDB lists nothing we know     -> leave it alone (data gap, or the
//                                            show left streaming entirely)
//        - not listed, TMDB has service Y -> first time: remember it in
//                                            platform_moves. Same move seen on
//                                            a check 6+ days later: switch
//                                            every copy saved as X to Y.
//                                            (APPLY_NOW=1: switch right away.)
// Also: anyone who has checked services in Settings > My services gets
// their copies moved onto one of those when the show streams there and
// the saved service isn't one of theirs (right away, no two-week wait --
// both services are currently listed, so there's no flip-flop to guard).
// Moved shows likewise land on one of the person's own services.
// Also: shows saved as None (or blank) get a service filled in, once, when
// TMDB now lists one -- preferring the person's own services. If they set
// it back to None, shows.platform_filled_at keeps us from refilling it.
// Quiet by design: no notifications. 'None', 'Other', blank and typed-in
// services are never touched, nor is PBS Passport (see PROTECTED).
//
// Zero dependencies: Node 20+ global fetch, Supabase REST, TMDB REST.
// ============================================================

const SUPABASE_URL = need('SUPABASE_URL');
const SERVICE_KEY = need('SUPABASE_SERVICE_ROLE_KEY');
const TMDB_KEY = need('TMDB_API_KEY');
const DRY_RUN = process.env.DRY_RUN === '1';
// APPLY_NOW=1 skips the two-week wait (one-off catch-up runs, by hand).
const APPLY_NOW = process.env.APPLY_NOW === '1';
// Services people choose on purpose that TMDB rarely lists (e.g. British
// mysteries watched on PBS Passport). Never switched away from.
const PROTECTED = new Set(['PBS Passport']);
const CONFIRM_AFTER_MS = 6 * 86400000; // second sighting must be a later weekly run

const REST = `${SUPABASE_URL}/rest/v1`;
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

// --- provider name -> app service name. KEEP IN SYNC with PROVIDER_NAME_MAP /
// PROVIDER_KEYWORD_FALLBACK / mapProviderToPlatform in index.html.
const PROVIDER_NAME_MAP = {
  'acorn tv': 'Acorn TV',
  'amc plus': 'AMC+',
  'netflix': 'Netflix',
  'hulu': 'Hulu',
  'disney plus': 'Disney+',
  'amazon prime video': 'Amazon Prime',
  'amazon video': 'Amazon Prime',
  'apple tv plus': 'Apple TV+',
  'apple tv': 'Apple TV+',
  'max': 'HBO Max',
  'hbo max': 'HBO Max',
  'paramount plus': 'Paramount+',
  'paramount plus with showtime': 'Paramount+',
  'peacock': 'Peacock',
  'peacock premium': 'Peacock',
  'peacock premium plus': 'Peacock',
  'espn plus': 'ESPN+',
  'discovery plus': 'Discovery+',
  'showtime': 'Showtime',
  'showtime apple tv channel': 'Showtime',
  'starz': 'Starz',
  'starz apple tv channel': 'Starz',
  'pbs': 'PBS Passport',
  'pbs documentaries': 'PBS Passport',
  'pbs masterpiece': 'PBS Passport',
  'britbox': 'BritBox',
  'tubi': 'Tubi',
  'tubi tv': 'Tubi',
  'pluto tv': 'Pluto TV',
  // Amazon/Apple add-on channels whose names the keyword fallback misses.
  'apple tv amazon channel': 'Apple TV+',
  'acorntv amazon channel': 'Acorn TV',
  'acorntv': 'Acorn TV',
  // Local PBS station apps (where Passport lives).
  'thirteen': 'PBS Passport',
  'weta plus': 'PBS Passport',
  'kqed': 'PBS Passport',
};
const PROVIDER_KEYWORD_FALLBACK = [
  ['acorn tv', 'Acorn TV'], ['amc plus', 'AMC+'],
  ['netflix', 'Netflix'], ['hulu', 'Hulu'], ['disney plus', 'Disney+'],
  ['amazon prime video', 'Amazon Prime'], ['amazon video', 'Amazon Prime'],
  ['apple tv plus', 'Apple TV+'], ['hbo max', 'HBO Max'], ['max', 'HBO Max'],
  ['paramount plus', 'Paramount+'], ['peacock', 'Peacock'], ['espn plus', 'ESPN+'],
  ['discovery plus', 'Discovery+'], ['showtime', 'Showtime'], ['starz', 'Starz'],
  ['pbs', 'PBS Passport'], ['britbox', 'BritBox'], ['tubi', 'Tubi'], ['pluto tv', 'Pluto TV'],
];
// KEEP IN SYNC with POPULAR_PLATFORM_ORDER in index.html.
const POPULAR_ORDER = ['Netflix', 'Amazon Prime', 'Hulu', 'HBO Max', 'Disney+', 'Apple TV+', 'Peacock', 'Paramount+'];
const KNOWN_SERVICES = new Set(Object.values(PROVIDER_NAME_MAP));

export function mapProviderToPlatform(name) {
  if (!name) return null;
  const key = name.toLowerCase().replace(/\+/g, ' plus').replace(/\s+/g, ' ').trim();
  if (PROVIDER_NAME_MAP[key]) return PROVIDER_NAME_MAP[key];
  for (const [kw, svc] of PROVIDER_KEYWORD_FALLBACK) {
    if (new RegExp('\\b' + kw.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '\\b').test(key)) return svc;
  }
  return null;
}

// Ordered, de-duplicated app service names TMDB lists for the US. Sorted most-popular-first;
// the first one is the same pick the app makes when a show is added.
// Provider names we see but don't map to an app service, with how many
// shows list them -- logged at the end so we know what's worth adding.
export const unmapped = new Map();

export function servicesFromProviders(d) {
  const us = d && d.results && d.results.US;
  if (!us) return [];
  const out = [];
  const seen = new Set();
  for (const p of [...(us.flatrate || []), ...(us.free || []), ...(us.ads || [])]) {
    const svc = mapProviderToPlatform(p.provider_name);
    if (svc && !out.includes(svc)) out.push(svc);
    if (!svc && !seen.has(p.provider_name)) {
      seen.add(p.provider_name);
      unmapped.set(p.provider_name, (unmapped.get(p.provider_name) || 0) + 1);
    }
  }
  // Most widely held services first, so services[0] (the one a moved show
  // gets) matches the app's pickPopularPlatform(). Stable sort keeps TMDB's
  // order among the rest.
  const rank = (x) => { const i = POPULAR_ORDER.indexOf(x); return i === -1 ? POPULAR_ORDER.length : i; };
  return out.sort((a, b) => rank(a) - rank(b));
}

// What to do with one saved service, given TMDB's current list and any
// pending move from an earlier run. Pure, so it's easy to test.
//   -> { action: 'keep' | 'clear' | 'remember' | 'apply', to? }
export function decide(saved, services, pending, now = Date.now(), applyNow = false) {
  if (PROTECTED.has(saved)) return { action: pending ? 'clear' : 'keep' };
  if (!services.length) return { action: pending ? 'clear' : 'keep' };
  if (services.includes(saved)) return { action: pending ? 'clear' : 'keep' };
  const to = services[0];
  if (applyNow) return { action: 'apply', to };
  if (pending && pending.to_platform === to &&
      now - new Date(pending.first_seen).getTime() >= CONFIRM_AFTER_MS) {
    return { action: 'apply', to };
  }
  if (pending && pending.to_platform === to) return { action: 'keep' }; // still waiting
  return { action: 'remember', to }; // new or changed target: (re)start the clock
}

// The service a given person's copy should get: one they've checked in
// Settings > My services if the show is on any, else the most popular.
export function pickFor(services, mine) {
  const yours = services.filter((x) => mine.includes(x));
  return (yours.length ? yours : services)[0] || null;
}

// Saved service still streams the show, but the person has told us which
// services they have and this isn't one of them while another is: move
// their copy to theirs. Returns the new service or null.
export function relabelFor(saved, services, mine) {
  if (PROTECTED.has(saved) || !mine.length || mine.includes(saved)) return null;
  if (!services.includes(saved)) return null; // that's a move, handled by decide()
  const yours = services.filter((x) => mine.includes(x));
  return yours.length ? yours[0] : null;
}

async function sb(method, path, body, extraHeaders = {}) {
  const res = await fetch(`${REST}/${path}`, {
    method,
    headers: { ...SB_HEADERS, ...extraHeaders },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  if (!res.ok) throw new Error(`${method} ${path} -> ${res.status} ${await res.text()}`);
  return method === 'GET' ? res.json() : null;
}

// PostgREST caps rows per request, so page through.
async function sbGetAll(path) {
  const out = [];
  const size = 1000;
  for (let from = 0; ; from += size) {
    const res = await fetch(`${REST}/${path}`, {
      headers: { ...SB_HEADERS, Range: `${from}-${from + size - 1}` },
    });
    if (!res.ok) throw new Error(`GET ${path} -> ${res.status} ${await res.text()}`);
    const rows = await res.json();
    out.push(...rows);
    if (rows.length < size) return out;
  }
}

async function fetchProviders(tmdbId, mediaType) {
  const kind = mediaType === 'documentary' ? 'movie' : 'tv';
  const res = await fetch(
    `https://api.themoviedb.org/3/${kind}/${tmdbId}/watch/providers?api_key=${TMDB_KEY}`
  );
  if (res.status === 404) return null;
  if (!res.ok) throw new Error(`TMDB ${kind}/${tmdbId} -> ${res.status}`);
  return res.json();
}

const enc = encodeURIComponent;

async function main() {
  console.log(`[platforms] run start ${new Date().toISOString()}${DRY_RUN ? ' (DRY RUN)' : ''}${APPLY_NOW ? ' (APPLY NOW)' : ''}`);

  const shows = await sbGetAll('shows?select=id,user_id,title,tmdb_id,media_type,platform,platform_filled_at&tmdb_id=not.is.null&order=id');
  const userRows = await sbGetAll('users?select=id,my_services');
  const myServices = new Map(userRows.map((u) => [u.id, u.my_services || []]));
  const mineOf = (row) => myServices.get(row.user_id) || [];
  const pendingRows = await sbGetAll('platform_moves?select=tmdb_id,media_type,from_platform,to_platform,first_seen');
  const pendingMap = new Map(pendingRows.map((r) => [`${r.tmdb_id}|${r.media_type}|${r.from_platform}`, r]));

  // (tmdb_id|media_type) -> { title, saved: Map(service -> [rows]) }
  const groups = new Map();
  for (const s of shows) {
    const blank = !s.platform || s.platform === 'None';
    // Blank/None gets filled in ONCE (platform_filled_at); if the person sets
    // it back to None, we leave it. 'Other' and typed-in names: never.
    if (blank ? s.platform_filled_at : !KNOWN_SERVICES.has(s.platform)) continue;
    const mt = s.media_type || 'tv';
    const k = `${s.tmdb_id}|${mt}`;
    if (!groups.has(k)) groups.set(k, { tmdbId: s.tmdb_id, mt, title: s.title, saved: new Map(), blank: [] });
    const g = groups.get(k);
    if (blank) { g.blank.push(s); continue; }
    if (!g.saved.has(s.platform)) g.saved.set(s.platform, []);
    g.saved.get(s.platform).push(s);
  }
  console.log(`[platforms] ${shows.length} show rows, ${groups.size} distinct shows to check`);

  let remembered = 0, applied = 0, rowsChanged = 0, cleared = 0, relabeled = 0, filled = 0, errors = 0;

  // Set a batch of rows to their new services, grouped so it's one PATCH
  // per target. pick(row) -> new service (or null = leave alone).
  async function patchRows(rows, pick, extra = {}) {
    const byTarget = new Map();
    for (const r of rows) {
      const to = pick(r);
      if (!to || to === r.platform) continue;
      if (!byTarget.has(to)) byTarget.set(to, []);
      byTarget.get(to).push(r.id);
    }
    let n = 0;
    for (const [to, ids] of byTarget) {
      n += ids.length;
      if (!DRY_RUN) await sb('PATCH', `shows?id=in.(${ids.join(',')})`, { platform: to, ...extra }, { Prefer: 'return=minimal' });
    }
    return { n, targets: [...byTarget.keys()] };
  }

  for (const g of groups.values()) {
    let services;
    try {
      const d = await fetchProviders(g.tmdbId, g.mt);
      if (!d) continue;
      services = servicesFromProviders(d);
    } catch (e) {
      errors++;
      console.error(`[platforms] ${g.title}: ${e.message}`);
      await sleep(500);
      continue;
    }

    if (g.blank.length && services.length) {
      try {
        const { n, targets } = await patchRows(g.blank, (r) => pickFor(services, mineOf(r)),
          { platform_filled_at: new Date().toISOString() });
        if (n) {
          filled += n;
          console.log(`[platforms] filled in None: ${g.title} -> ${targets.join('/')} (${n} copies)`);
        }
      } catch (e) {
        errors++;
        console.error(`[platforms] ${g.title} (None): ${e.message}`);
      }
    }

    for (const [saved, rows] of g.saved) {
      const count = rows.length;
      const pk = `${g.tmdbId}|${g.mt}|${saved}`;
      const pending = pendingMap.get(pk);
      const { action, to } = decide(saved, services, pending, Date.now(), APPLY_NOW);
      const pkFilter = `tmdb_id=eq.${g.tmdbId}&media_type=eq.${enc(g.mt)}&from_platform=eq.${enc(saved)}`;
      try {
        if (action === 'clear') {
          cleared++;
          if (!DRY_RUN) await sb('DELETE', `platform_moves?${pkFilter}`);
        }
        if (action === 'keep' || action === 'clear') {
          const { n, targets } = await patchRows(rows, (r) => relabelFor(saved, services, mineOf(r)));
          if (n) {
            relabeled += n;
            console.log(`[platforms] to their services: ${g.title} ${saved} -> ${targets.join('/')} (${n} copies)`);
          }
        } else if (action === 'remember') {
          remembered++;
          console.log(`[platforms] maybe moved: ${g.title} ${saved} -> ${to} (${count} copies; confirm next week)`);
          if (!DRY_RUN) {
            await sb('POST', 'platform_moves?on_conflict=tmdb_id,media_type,from_platform',
              { tmdb_id: g.tmdbId, media_type: g.mt, from_platform: saved, to_platform: to, first_seen: new Date().toISOString() },
              { Prefer: 'resolution=merge-duplicates,return=minimal' });
          }
        } else if (action === 'apply') {
          applied++;
          const { n, targets } = await patchRows(rows, (r) => pickFor(services, mineOf(r)));
          rowsChanged += n;
          console.log(`[platforms] MOVED: ${g.title} ${saved} -> ${targets.join('/') || to} (${n} copies)`);
          if (!DRY_RUN) await sb('DELETE', `platform_moves?${pkFilter}`);
        }
      } catch (e) {
        errors++;
        console.error(`[platforms] ${g.title} (${saved}): ${e.message}`);
      }
    }
    await sleep(60); // stay well under TMDB's rate limit
  }

  console.log(`[platforms] done: ${applied} moves applied (${rowsChanged} rows), ${remembered} pending, ${cleared} cleared, ${relabeled} moved to people's own services, ${filled} None filled in, ${errors} errors`);
  const top = [...unmapped].sort((a, b) => b[1] - a[1]).slice(0, 25);
  console.log(`[platforms] services we don't track (shows listing them): ${top.map(([n, c]) => `${n} ${c}`).join(' | ')}`);
  if (errors && errors >= groups.size / 2) process.exit(1); // something systemic, fail the run
}

if (process.argv[1]?.endsWith('refresh-platforms.mjs')) {
  main().catch((e) => {
    console.error(e);
    process.exit(1);
  });
}

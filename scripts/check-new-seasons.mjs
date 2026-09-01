// ============================================================
// check-new-seasons.mjs — scheduled new-season checker
// ============================================================
// Runs daily from .github/workflows/check-new-seasons.yml (and can be run
// by hand with `node scripts/check-new-seasons.mjs` given the env vars).
//
// What it does, once per run:
//   1. Pulls every show anyone is Currently Watching, plus every show in
//      Waiting for New Season.
//   2. For each DISTINCT tmdb_id, asks TMDB how many seasons have actually
//      aired (air_date present and in the past — never counts a season TMDB
//      created the moment it was announced).
//   3. Upserts that into tracked_seasons (one shared row per show).
//   4. Per user's copy of the show:
//        - no stored number_of_seasons  -> set the baseline, do NOT notify
//        - released count went up        -> set new_season_available = true
//                                           and insert a notification
//        - otherwise                     -> nothing
//
// Zero dependencies: Node 20+ global fetch, Supabase REST, TMDB REST.
// The dedup unique index on notifications means re-running is always safe.
// ============================================================

const SUPABASE_URL = need('SUPABASE_URL');
const SERVICE_KEY = need('SUPABASE_SERVICE_ROLE_KEY');
const TMDB_KEY = need('TMDB_API_KEY');

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

// --- released-season count: the one definition used everywhere -------------
// A season counts only if it has a real air date that has already passed.
// season_number 0 is TMDB's "Specials" bucket and never counts.
function releasedSeasons(tmdb) {
  const today = new Date();
  return (tmdb.seasons || [])
    .filter((s) => s.season_number > 0 && s.air_date && new Date(s.air_date) <= today)
    .sort((a, b) => new Date(a.air_date) - new Date(b.air_date));
}

async function sbGet(path) {
  const res = await fetch(`${REST}/${path}`, { headers: SB_HEADERS });
  if (!res.ok) throw new Error(`GET ${path} -> ${res.status} ${await res.text()}`);
  return res.json();
}

async function sbPatch(path, body) {
  const res = await fetch(`${REST}/${path}`, {
    method: 'PATCH',
    headers: SB_HEADERS,
    body: JSON.stringify(body),
  });
  if (!res.ok) throw new Error(`PATCH ${path} -> ${res.status} ${await res.text()}`);
}

async function sbUpsert(path, body, { ignoreDuplicates = false } = {}) {
  const res = await fetch(`${REST}/${path}`, {
    method: 'POST',
    headers: {
      ...SB_HEADERS,
      Prefer: ignoreDuplicates
        ? 'resolution=ignore-duplicates,return=minimal'
        : 'resolution=merge-duplicates,return=minimal',
    },
    body: JSON.stringify(body),
  });
  if (!res.ok) throw new Error(`POST ${path} -> ${res.status} ${await res.text()}`);
}

async function fetchTmdb(tmdbId) {
  const res = await fetch(
    `https://api.themoviedb.org/3/tv/${tmdbId}?api_key=${TMDB_KEY}`
  );
  if (res.status === 404) return null; // dead / bad id — skip quietly
  if (!res.ok) throw new Error(`TMDB ${tmdbId} -> ${res.status}`);
  return res.json();
}

async function main() {
  const startedAt = new Date();
  console.log(`[new-seasons] run start ${startedAt.toISOString()}`);

  // 1. Candidate shows: Currently Watching + Waiting for New Season, with a tmdb_id.
  const shows = await sbGet(
    'shows?select=id,user_id,title,tmdb_id,status,waiting_for_season,number_of_seasons,new_season_available' +
      '&tmdb_id=not.is.null' +
      '&or=(status.eq.watching,and(status.eq.watchlist,waiting_for_season.is.true))'
  );
  console.log(`[new-seasons] ${shows.length} candidate show rows`);

  // 2. Existing registry, so we can tell a real change from a no-op.
  const registryRows = await sbGet('tracked_seasons?select=tmdb_id,released_season_count');
  const registry = new Map(registryRows.map((r) => [r.tmdb_id, r.released_season_count]));

  // Group candidate rows by tmdb_id.
  const byTmdb = new Map();
  for (const s of shows) {
    if (!byTmdb.has(s.tmdb_id)) byTmdb.set(s.tmdb_id, []);
    byTmdb.get(s.tmdb_id).push(s);
  }
  const tmdbIds = [...byTmdb.keys()];
  console.log(`[new-seasons] ${tmdbIds.length} distinct shows to check`);

  let checked = 0,
    baselined = 0,
    notified = 0,
    skipped = 0,
    errors = 0;

  for (const tmdbId of tmdbIds) {
    let tmdb;
    try {
      tmdb = await fetchTmdb(tmdbId);
    } catch (e) {
      console.error(`[new-seasons] TMDB error for ${tmdbId}: ${e.message}`);
      errors++;
      await sleep(300);
      continue;
    }
    if (!tmdb) {
      skipped++;
      continue;
    }

    const released = releasedSeasons(tmdb);
    const count = released.length;
    const latest = released[released.length - 1];
    checked++;

    // 3. Upsert the shared registry row.
    const prevCount = registry.get(tmdbId);
    const changed = prevCount == null || count !== prevCount;
    try {
      await sbUpsert('tracked_seasons', {
        tmdb_id: tmdbId,
        title: tmdb.name || null,
        released_season_count: count,
        latest_season_number: latest ? latest.season_number : null,
        latest_season_air_date: latest ? latest.air_date : null,
        last_checked_at: new Date().toISOString(),
        ...(changed ? { last_change_at: new Date().toISOString() } : {}),
      });
    } catch (e) {
      console.error(`[new-seasons] registry upsert failed for ${tmdbId}: ${e.message}`);
      errors++;
    }

    // 4. Reconcile each user's copy of the show.
    for (const s of byTmdb.get(tmdbId)) {
      try {
        if (s.number_of_seasons == null) {
          await sbPatch(`shows?id=eq.${s.id}`, { number_of_seasons: count });
          baselined++;
          continue;
        }
        if (count <= s.number_of_seasons) continue;

        await sbPatch(`shows?id=eq.${s.id}`, {
          number_of_seasons: count,
          new_season_available: true,
        });
        await sbUpsert(
          'notifications',
          {
            user_id: s.user_id,
            type: 'new_season',
            title: s.title,
            body: latest
              ? `Season ${latest.season_number} is out`
              : 'A new season is out',
            show_id: s.id,
            tmdb_id: tmdbId,
            season_count: count,
            season_number: latest ? latest.season_number : null,
          },
          { ignoreDuplicates: true }
        );
        notified++;
        console.log(`[new-seasons] notified user ${s.user_id} -> ${s.title} (S${latest ? latest.season_number : '?'})`);
      } catch (e) {
        console.error(`[new-seasons] reconcile failed for show ${s.id}: ${e.message}`);
        errors++;
      }
    }

    await sleep(120); // be polite to TMDB
  }

  console.log(
    `[new-seasons] done: checked=${checked} baselined=${baselined} notified=${notified} skipped=${skipped} errors=${errors}`
  );
  if (errors > 0) process.exitCode = 1;
}

main().catch((e) => {
  console.error('[new-seasons] fatal:', e);
  process.exit(1);
});

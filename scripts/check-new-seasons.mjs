// ============================================================
// check-new-seasons.mjs — scheduled new-season checker
// ============================================================
// Runs daily from .github/workflows/check-new-seasons.yml (and can be run
// by hand with `node scripts/check-new-seasons.mjs` given the env vars).
//
// What it does, once per run:
//   1. Pulls every show anyone has in Currently Watching or My List
//      (My List includes the "Waiting for New Season" subset).
//   2. For each DISTINCT tmdb_id, asks TMDB:
//        - how many seasons have actually aired (air_date present and in the
//          past — never counts a season TMDB created when it was announced)
//        - whether a not-yet-aired season has a confirmed premiere date
//          (tmdb.next_episode_to_air only)
//   3. Upserts the aired count into tracked_seasons (one shared row per show).
//   4. Per user's copy of the show:
//        - confirmed premiere date for a season they haven't seen ->
//          'season_upcoming' notification ("Season 3 premieres Nov 9"),
//          no card badge (it isn't out yet)
//        - no stored number_of_seasons -> set the baseline, do NOT notify
//        - aired count went up -> set new_season_available = true and insert
//          a 'new_season' notification ("Season 3 is out")
//        - otherwise -> nothing
//
// A user can get both notifications for one season: the dated heads-up
// ~2-3 weeks out, then the "it's out" on air day.
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

// --- upcoming season: a confirmed premiere date for a season not yet aired -
// Uses ONLY tmdb.next_episode_to_air, TMDB's "this is genuinely scheduled
// next" field. Far-out dates in tmdb.seasons[] are routinely placeholders or
// shift around, so they're deliberately ignored -- we'd rather give ~2-3
// weeks of reliable notice than a month of maybe-wrong notice.
function upcomingSeason(tmdb, releasedCount) {
  const nx = tmdb.next_episode_to_air;
  if (!nx || !nx.air_date) return null;
  if (nx.season_number == null || nx.season_number <= releasedCount) return null;
  if (new Date(nx.air_date) <= new Date()) return null;
  return { season_number: nx.season_number, air_date: nx.air_date };
}

function fmtDate(iso) {
  const d = new Date(iso + 'T00:00:00Z');
  return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric', timeZone: 'UTC' });
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

  // 1. Candidate shows: everything in Currently Watching or My List, with a
  //    tmdb_id. (My List = status 'watchlist', which includes the "Waiting
  //    for New Season" subset.)
  const shows = await sbGet(
    'shows?select=id,user_id,title,tmdb_id,status,number_of_seasons,new_season_available' +
      '&tmdb_id=not.is.null' +
      '&status=in.(watching,watchlist)'
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
    headsups = 0,
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
    const upcoming = upcomingSeason(tmdb, count);
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
        // 4a. Dated heads-up for a not-yet-aired season the user hasn't seen.
        //     Independent of the baseline/new_season logic below; the dedup
        //     index keeps it to one per user per season. No card badge.
        const seenCount = s.number_of_seasons == null ? count : s.number_of_seasons;
        if (upcoming && upcoming.season_number > seenCount) {
          await sbUpsert(
            'notifications',
            {
              user_id: s.user_id,
              type: 'season_upcoming',
              title: s.title,
              body: `Season ${upcoming.season_number} premieres ${fmtDate(upcoming.air_date)}`,
              show_id: s.id,
              tmdb_id: tmdbId,
              season_count: upcoming.season_number,
              season_number: upcoming.season_number,
            },
            { ignoreDuplicates: true }
          );
          headsups++;
        }

        // 4b. Baseline / new-season-is-out.
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
    `[new-seasons] done: checked=${checked} baselined=${baselined} notified=${notified} headsups=${headsups} skipped=${skipped} errors=${errors}`
  );
  if (errors > 0) process.exitCode = 1;
}

main().catch((e) => {
  console.error('[new-seasons] fatal:', e);
  process.exit(1);
});

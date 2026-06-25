# ShowUp — Claude Code Project Guide

## What This Project Is
ShowUp is a social TV show tracking web app. Users track what they're watching, rate shows with "remotes" (1–5), and share their viewing with friends in a "Living Room." Think letterboxd for TV, but social and cozy.

## Tech Stack
- Single HTML file app — no build step, no npm, no framework
- Supabase (auth via OTP magic link + 6-digit code, Postgres DB)
- Deployed at: https://showup-app-zeta.vercel.app
- Supabase URL: https://sgnulweruogjfdddwboe.supabase.co

## Key Files
- `index.html` — the entire app (~2400 lines, HTML + CSS + JS all inline)
- `invite 0528.html` — standalone invite landing page
- `privacy 0528.html` — privacy policy
- `showup-pitch 0527.html` — pitch/landing page
- `vercel.json` — Vercel routing (handles /join/:username rewrites)
- `supabase.js` — dead file, not imported

## App Structure
4 tabs: **Watching**, **My List** (watchlist), **Binged** (watched), **Living Room**

Screens: login → onboard → tellmore → app → profile → settings

## Database Tables
- `users` — profile, room theme, username, psychographic data
- `shows` — status: watching/watchlist/watched/dnf, hidden, rating
- `reactions` — text reactions users post on friends' shows
- `top5_shows` — each user's ranked top 5 of all time
- `living_rooms` — one per user
- `living_room_members` — friend connections (status: pending/active)
- `sessions` — session tracking

## Core Features (all working)
- Add/move shows across Watching / My List / Binged tabs
- Rate shows 1–5 "remotes" (custom SVG remote control icons)
- Mark shows as DNF (Didn't Finish) — shown with red badge
- Hide shows from friends
- Friend Living Rooms — see what friends are watching, react to their shows
- Friends Favorites — group rankings based on friend ratings
- Top 5 all-time shows visible to friends
- Room themes: cabin, coastal, formal, mancave, modern, tuscany, worldcup
- Invite friends via /join/:username share link
- Psychographic profile (Tell Us More screen — career, hobbies, watch habits)

## Invite Flow (how it works)
1. User shares their link: `https://showup-app-zeta.vercel.app/join/<username>`
2. Vercel rewrites `/join/:username` → serves index.html
3. `PENDING_INVITER` is parsed from the URL path on page load
4. **New user**: invite banner shows → they complete onboarding → `connectViaInvite(PENDING_INVITER)` is called → DB connection created via `connect_via_invite` RPC
5. **Existing user**: invite banner shows on DOMContentLoaded, BUT `connectViaInvite` is NOT called — this is a known gap to fix

## Known Issues / In Progress
- **Invite flow for existing users**: When an already-logged-in user visits a `/join/` link, the banner shows but the connection is never created. Need to call `connectViaInvite(PENDING_INVITER)` inside `loadUserIntoState` when `PENDING_INVITER` is set.
- **Living Room + invite flow for beta**: Active discussion — the next session's focus

## Critical Code Notes
- `bootstrap()` reads localStorage directly (never calls `getSession()`) — avoids Supabase PKCE init deadlock
- `onAuthStateChange` callback must be synchronous — uses `setTimeout(fn, 0)` defer to avoid deadlock
- `getFriendsWithShows()` does bidirectional lookup (people in my room + rooms I've joined)
- Many `_OLD` suffixed functions exist as dead code — ignore them
- Auth uses OTP (6-digit code) with PKCE bypass workaround

## User
- Tracey — non-technical founder/builder
- Works on Windows 11, uses Claude Code via desktop app
- Plain English explanations preferred, show the full picture before making changes

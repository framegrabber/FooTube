# Spec: browser-inbox

Module `browser-inbox` of FooTube's self-hosted sync (capability map: `SYNC.md`; background: `docs/ideas/cloudflare-sync.md`). Spans both repos: the Worker side in `FooTubeSyncBackend`, folding into Watch Later in FooTubeCore. Depends on `sync-backend` and `sync-client`. This file is the single source of the inbox Contract; `FooTubeSyncBackend/SPEC.md` links here.

Written overnight on 2026-10-26 without the owner's review of this file; see **Decisions to review**.

## Objective
While browsing YouTube on a laptop or phone, I click a bookmark and the video lands in FooTube's Watch Later on every Apple TV of the household.

**Stories:**
1. As a viewer on youtube.com (watch page, `youtu.be` link, Shorts), I click the "→ FooTube" bookmark; a small tab says "Added to Watch Later" and closes itself after 2 s.
2. As a viewer, the next time FooTube syncs on any Apple TV, the video is first in Watch Later with its title and thumbnail.
3. As a builder, I create the bookmark by running one command in `FooTubeSyncBackend` and pasting its output as a bookmark URL.
4. As the household, a leaked bookmark lets a stranger add videos to Watch Later and nothing else.

## Contract (additions to `FooTubeSyncBackend/SPEC.md`)
**Second secret:** `INBOX_TOKEN` (at least 64 characters, `openssl rand -base64 48`), separate from `SYNC_TOKEN`. Missing or short → inbox routes return `500 not_configured`; store routes are unaffected.

| Route | Auth | Request | Responses |
|---|---|---|---|
| `GET /add?v=<id>&t=<title>` | none | from the bookmarklet, token in the URL fragment | `200` HTML page (below); no data is read or written by this request |
| `POST /v1/inbox` | `Bearer INBOX_TOKEN` or `SYNC_TOKEN` | `{"videoID": "<11 chars [A-Za-z0-9_-]>", "title": "<≤ 200 chars>"?}`, `application/json`, ≤ 1 KiB | `201` added, `200` already in the inbox (same `videoID`, title updated), `400 invalid_video_id`, `409 inbox_full` (100 items), `401`, `411`/`413`/`415` as for stores |
| `GET /v1/inbox` | `Bearer SYNC_TOKEN` only | — | `200 {"items":[{"seq": n, "videoID", "title"?, "addedAt"}]}` oldest first |
| `DELETE /v1/inbox?through=<seq>` | `Bearer SYNC_TOKEN` only | — | `204`; removes items with `seq ≤ through` (idempotent) |

`INBOX_TOKEN` on any other route → `401`. No CORS headers anywhere: the `/add` page posts to its own origin.

**`/add` page:** static HTML with an inline script allowed by a hash-based CSP (`default-src 'none'; script-src 'sha256-…'; style-src 'sha256-…'; connect-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'`), `Referrer-Policy: no-referrer`, `Cache-Control: no-store`. The script reads the token from `location.hash`, immediately removes it with `history.replaceState`, posts `{videoID, title}`, shows the result in English and German (by `navigator.language`) and calls `window.close()` after 2 s on success.

**D1:** migration `0002_inbox.sql`: `inbox(seq INTEGER PRIMARY KEY AUTOINCREMENT, video_id TEXT UNIQUE NOT NULL, title TEXT, added_at TEXT NOT NULL)`.

**Bookmarklet:** `npm run bookmarklet` prints `javascript:` code with the Worker URL and `INBOX_TOKEN` filled in from `.env.deployed` (or `--url`/`--token`). It extracts the ID from `youtube.com/watch?v=`, `youtube.com/shorts/<id>`, `youtu.be/<id>` and `m.youtube.com`, takes the title from `document.title` without the " - YouTube" suffix, and opens `<worker>/add?v=<id>&t=<title>#<token>` in a new tab. On other pages it shows `alert("Not a YouTube video")`. The token is never sent as a query parameter, so it doesn't appear in Worker logs.

## Client (FooTubeCore + app)
- During each Watch Later sync round, after a successful `PUT` (or when nothing needed pushing): `GET /v1/inbox`; each item not already live in Watch Later becomes an entry with `addedAt` = `changedAt` = the item's `addedAt`, `video` = a `VideoSummary` with the ID, the title (or the ID if none) and the standard `i.ytimg.com` thumbnail; the merged Watch Later is pushed; then `DELETE /v1/inbox?through=<last seq>`. If two devices fold the same items, the Watch Later merge deduplicates them by video ID.
- When an inbox-created entry is shown, the app fills in channel and duration from the catalog when it next plays or opens it (existing summary refresh paths); no extra requests at fold time.
- Only the Worker's configured URL is contacted; nothing new to configure in the app.

## Tech Stack, Commands, Structure, Style
As `FooTubeSyncBackend/SPEC.md` and `SPEC-sync-client.md`. New files: `FooTubeSyncBackend/src/inbox.ts`, `src/addPage.ts`, `migrations/0002_inbox.sql`, `scripts/bookmarklet.mjs`, tests `test/inbox.test.ts`; FooTubeCore `SyncClient` inbox calls, `SyncInbox.swift` (folding), tests.

## Testing Strategy
- Worker: every row of the table; token separation (inbox token rejected on store routes and `GET`/`DELETE` inbox); duplicate `videoID`; cap of 100; `/add` response headers (CSP with the right hashes, no-referrer, no-store) and that `/add` never touches D1.
- Bookmarklet: unit test of the ID extraction on the URL shapes above plus non-YouTube URLs (the extraction function is shared with the generator and tested in Node).
- Client: folding with the fake Worker: new item, item already live, item removed earlier (re-added, since the inbox add is newer), two devices folding at once, `DELETE` failing (items folded again next time, no duplicates).
- Manual: bookmark in Safari and Chrome on youtube.com → video in Watch Later on the Simulator after foregrounding.

## Boundaries
- **Always:** keep the inbox token add-only; test the CSP hash against the served script.
- **Ask first:** letting the inbox token read anything; CORS; any third-party script or font on `/add`.
- **Never:** accept a token in the query string; log tokens, titles or video IDs.

## Success Criteria
1. Clicking the bookmark on a YouTube watch page adds the video; it appears first in Watch Later on two Simulators after they sync.
2. With only the inbox token, `GET`/`PUT` stores and `GET`/`DELETE` inbox return `401`.
3. The `/add` page passes with a strict CSP (no console CSP violations in Safari and Chrome) and the token is gone from the address bar after load.
4. `scripts/check.sh` (both repos) exits 0.

## Not Doing
- Share-sheet extension or Shortcut on iPhone: belongs to `ios-app`.
- Adding to anything but Watch Later (subscribe, play now on a TV): later, if wanted.
- A browser extension: a bookmarklet needs no store, no review, no updates.

## Decisions to review
- **Token in the fragment of a page on the Worker's origin**, not an in-page `fetch` from youtube.com: YouTube's CSP likely blocks cross-origin requests from bookmarklets [unverified; checked during implementation], and the fragment never reaches server logs.
- **Title passed from the page** so Watch Later shows something useful before the catalog fills in details.
- **Inbox cap 100**, idempotent per video ID.

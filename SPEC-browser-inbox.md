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
| `GET /add` | none | from the bookmarklet; video ID, title and token only in the URL fragment (`#v=<id>&t=<title>&k=<token>`) | `200` HTML page (below); no data is read or written by this request |
| `POST /v1/inbox` | `Bearer INBOX_TOKEN` or `SYNC_TOKEN` | `{"videoID": "<11 chars [A-Za-z0-9_-]>", "title": "<≤ 200 chars>"?}`, `application/json`, ≤ 1 KiB | `201` added, `200` already in the inbox (same `videoID`, title updated), `400 invalid_video_id`, `409 inbox_full` (100 items), `429 rate_limited` with `Retry-After: 60` (more than 20 per 60 s per credential type, checked after auth and before the body; approximate, per Cloudflare location), `401`, `411`/`413`/`415` as for stores |
| `GET /v1/inbox` | `Bearer SYNC_TOKEN` only | — | `200 {"items":[{"seq": n, "videoID", "title"?, "addedAt"}]}` oldest first |
| `DELETE /v1/inbox?through=<seq>` | `Bearer SYNC_TOKEN` only | — | `204`; removes items with `seq ≤ through` (idempotent) |

`INBOX_TOKEN` on any other route → `401`. No CORS headers anywhere: the `/add` page posts to its own origin.

**`/add` page:** static HTML with an inline script allowed by a hash-based CSP (`default-src 'none'; script-src 'sha256-…'; style-src 'sha256-…'; connect-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'`), `Referrer-Policy: no-referrer`, `Cache-Control: no-store`. The script reads the token from `location.hash`, immediately removes it with `history.replaceState`, posts `{videoID, title}`, shows the result in English and German (by `navigator.language`) and calls `window.close()` after 2 s on success.

**D1:** migration `0002_inbox.sql`: `inbox(seq INTEGER PRIMARY KEY AUTOINCREMENT, video_id TEXT UNIQUE NOT NULL, title TEXT, added_at TEXT NOT NULL)`.

**Bookmarklet:** `npm run bookmarklet` writes `javascript:` code with the Worker URL and `INBOX_TOKEN` filled in from `.env.deployed` (or `--url`/`--token`) to the gitignored `.bookmarklet.txt`. It extracts the ID from `youtube.com/watch?v=`, `youtube.com/shorts/<id>`, `youtu.be/<id>` and `m.youtube.com`, takes the title from `document.title` without the " - YouTube" suffix and the `(n) ` notification prefix, and opens `<worker>/add#v=<id>&t=<title>&k=<token>` in a new tab. On other pages it shows `alert("Not a YouTube video")`. Nothing is sent in the path or query, so neither the token nor the video ID or title reaches Worker logs; the page removes the fragment before posting.

**As implemented** (choices this spec left open, recorded in `FooTubeSyncBackend/SPEC.md` → Browser inbox): malformed JSON → `400 invalid_video_id`; titles trimmed, cut to 200 characters, dropped if empty; a repeat without a title keeps the stored one; `201`/`200` have empty bodies; `DELETE` without a valid `through` → `400 invalid_request`; `Cache-Control: no-store` on `GET /v1/inbox`; Workers invocation logs and traces are off, only the Worker's own allowlisted log line remains.

## Client (FooTubeCore + app)
- During each Watch Later sync round, after a successful `PUT` (or when nothing needed pushing): `GET /v1/inbox`; each item not already live in Watch Later, and not removed there at or after the item's `addedAt`, becomes an entry with `addedAt` = the item's `addedAt` (order) and `changedAt` = the time of folding (with the item's `addedAt` the push round would take the entry for one pruned elsewhere, changed before `lastSyncAt` and missing on the Worker, and drop it), `video` = a `VideoSummary` with the ID, the title (or the ID if none) and the standard `i.ytimg.com` thumbnail; the merged Watch Later is pushed; then `DELETE /v1/inbox?through=<last seq>`. `500 not_configured` (no `INBOX_TOKEN`) and `404` (a Worker from before the inbox) on `GET /v1/inbox` mean "no inbox": the round continues normally. If two devices fold the same items, the Watch Later merge deduplicates them by video ID.
- The client doesn't trust the Worker's title rule: it applies its own (`UntrustedText.title`, shared with `footube://` links): control (`Cc`) and format (`Cf`, including bidi overrides and zero-width characters) characters dropped (line breaks and tabs become spaces), trimmed, cut to 200 Unicode scalars; an empty result counts as no title.
- An inbox response with more than 100 items (the Worker's cap) is rejected without folding anything; the round fails like any unreadable response.
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
- **Token in the fragment of a page on the Worker's origin**, not an in-page `fetch` from youtube.com (which would need CORS on the Worker). This does not keep the token from the page's scripts: the bookmarklet's code, token included, runs inside the page it is clicked on, so YouTube's scripts (or any other site's, if clicked elsewhere) can read it. Accepted risk (owner, 2026-10-29): the inbox token can only add videos to Watch Later and fill the inbox, and `POST /v1/inbox` is rate-limited to 20 per minute; the README says to click it only on youtube.com and to rotate `INBOX_TOKEN` if it was clicked elsewhere or leaked.
- **Video ID and title in the fragment too** (changed during implementation), so no inbox data appears in any URL the Worker or Cloudflare logs.
- **Title passed from the page** so Watch Later shows something useful before the catalog fills in details.
- **Inbox cap 100**, idempotent per video ID.

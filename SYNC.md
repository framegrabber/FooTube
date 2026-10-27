# Capability Map: Self-hosted sync

Index of the sync initiative. Background and decisions: `docs/ideas/cloudflare-sync.md`. Module ids are fixed; specs and tasks refer to them.

| Module id | Responsibility | Repo | Spec | Depends on |
|---|---|---|---|---|
| `sync-backend` | Cloudflare Worker + D1: `GET`/`PUT /v1/stores/:name`, version check, bearer auth, deploy steps. Owns the app–Worker contract. | FooTubeSyncBackend | `FooTubeSyncBackend/SPEC.md` | — |
| `sync-client` | FooTubeCore: v2 stores with deletion markers, v1 migration, merge rules, `lastSyncAt`, `SyncEngine`. tvOS: launch-argument config, sync on foreground and after changes, status in Settings. | FooTube | `SPEC-sync-client.md` | `sync-backend` |
| `ios-app` | iPhone/iPad target on FooTubeCore, synced through `sync-client`; watching and collecting (Shortcut to the inbox, `footube://`) | FooTube | `SPEC-ios-app.md` (questions answered 2026-10-27) | `sync-client`, `browser-inbox` |
| `browser-inbox` | Add-only inbox token, `/add` page, `/v1/inbox`, bookmarklet; apps fold inbox entries into Watch Later | both | `SPEC-browser-inbox.md` | `sync-backend`, `sync-client` |

Build order: `sync-backend` → `sync-client` → `browser-inbox` → `ios-app`. Changed overnight 2026-10-26 from the approved `… → ios-app → browser-inbox` (owner to confirm): the two don't depend on each other, and `ios-app` waits on open questions in its spec.

The contract lives only in `FooTubeSyncBackend/SPEC.md` (section "Contract"). FooTube links to it; FooTubeCore pins it with responses recorded from `wrangler dev`.

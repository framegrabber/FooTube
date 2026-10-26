# Capability Map: Self-hosted sync

Index of the sync initiative. Background and decisions: `docs/ideas/cloudflare-sync.md`. Module ids are fixed; specs and tasks refer to them.

| Module id | Responsibility | Repo | Spec | Depends on |
|---|---|---|---|---|
| `sync-backend` | Cloudflare Worker + D1: `GET`/`PUT /v1/stores/:name`, version check, bearer auth, deploy steps. Owns the app–Worker contract. | FooTubeSyncBackend | `FooTubeSyncBackend/SPEC.md` | — |
| `sync-client` | FooTubeCore: v2 stores with deletion markers, v1 migration, merge rules, `lastSyncAt`, `SyncEngine`. tvOS: build-time config, sync on foreground and after changes, status in Settings. | FooTube | `SPEC-sync-client.md` (not yet written) | `sync-backend` |
| `ios-app` | iPhone/iPad target on FooTubeCore, synced through `sync-client` | FooTube | written when next | `sync-client` |
| `browser-inbox` | Add-only inbox token, `/add` page, `/v1/inbox`, bookmarklet; apps fold inbox entries into Watch Later | both | written when next | `sync-backend`, `sync-client` |

Build order: `sync-backend` → `sync-client` → `ios-app` → `browser-inbox`.

The contract lives only in `FooTubeSyncBackend/SPEC.md` (section "Contract"). FooTube links to it; FooTubeCore pins it with responses recorded from `wrangler dev`.

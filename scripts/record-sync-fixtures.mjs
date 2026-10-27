#!/usr/bin/env node
// Records the sync Worker's responses into Packages/FooTubeCore/Tests/FooTubeCoreTests/Fixtures/sync/,
// which SyncClientTests replay through a URLProtocol stub.
//
// Run against a fresh `wrangler dev` of ../FooTubeSyncBackend (the Example expects `subscriptions`
// and `watchLater` never written, so use an empty --persist-to directory):
//   FOOTUBE_SYNC_TEST_URL=http://localhost:8790 FOOTUBE_SYNC_TEST_TOKEN=<dev token> node scripts/record-sync-fixtures.mjs
// Optional FOOTUBE_SYNC_UNCONFIGURED_URL: a second `wrangler dev` whose SYNC_TOKEN is too short, for
// the `not_configured` response. Records status, ETag, Content-Type, WWW-Authenticate and bodies;
// never the token or the Authorization header.
import { execFileSync } from "node:child_process";
import { writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const base = process.env.FOOTUBE_SYNC_TEST_URL;
const token = process.env.FOOTUBE_SYNC_TEST_TOKEN;
const unconfigured = process.env.FOOTUBE_SYNC_UNCONFIGURED_URL;
if (!base || !token) {
  console.error("Set FOOTUBE_SYNC_TEST_URL and FOOTUBE_SYNC_TEST_TOKEN (wrangler dev only).");
  process.exit(1);
}
if (!["localhost", "127.0.0.1"].includes(new URL(base).hostname)) {
  console.error("FOOTUBE_SYNC_TEST_URL must be a local wrangler dev (localhost or 127.0.0.1).");
  process.exit(1);
}

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const out = join(root, "Packages/FooTubeCore/Tests/FooTubeCoreTests/Fixtures/sync");
let backend = "unknown commit";
try {
  backend = execFileSync("git", ["-C", join(root, "../FooTubeSyncBackend"), "rev-parse", "--short", "HEAD"]).toString().trim();
} catch {
  backend = "commit not found";
}
const source = `wrangler dev of FooTubeSyncBackend ${backend}, recorded ${new Date().toISOString()} by scripts/record-sync-fixtures.mjs`;

const documentA = '{"format":1,"entries":[{"id":"UCsXVk37bltHxD1rDPwtNM8Q","name":"Kurzgesagt – In a Nutshell","changedAt":"2026-10-26T21:00:00.000Z"}]}';
const documentB = '{"format":1,"entries":[{"id":"UCsXVk37bltHxD1rDPwtNM8Q","name":"Kurzgesagt – In a Nutshell","changedAt":"2026-10-26T21:00:00.000Z"},{"id":"UCBJycsmduvYEL83R_U4JriQ","name":"Marques Brownlee","changedAt":"2026-10-26T21:05:00.000Z"}]}';
const documentC = '{"format":1,"entries":[{"id":"UCsXVk37bltHxD1rDPwtNM8Q","name":"Kurzgesagt – In a Nutshell","changedAt":"2026-10-26T21:00:00.000Z","removedAt":"2026-10-26T21:06:00.000Z"}]}';
const recordedRequestHeaders = ["content-type", "if-match", "if-none-match"];
const recordedResponseHeaders = ["etag", "content-type", "www-authenticate"];

async function exchange(name, { method = "GET", store = "subscriptions", headers = {}, body, auth = token, url = base }) {
  const init = { method, headers: { ...headers } };
  if (auth) init.headers.authorization = `Bearer ${auth}`;
  if (body instanceof ReadableStream) {
    init.body = body;
    init.duplex = "half";
  } else if (body !== undefined) {
    init.body = body;
  }
  const response = await fetch(`${url}/v1/stores/${store}`, init);
  const text = await response.text();
  const pick = (source, names) =>
    Object.fromEntries(names.flatMap((key) => (source[key] === undefined ? [] : [[key, source[key]]])));
  const requestHeaders = pick(Object.fromEntries(Object.entries(init.headers).map(([k, v]) => [k.toLowerCase(), v])), recordedRequestHeaders);
  const responseHeaders = pick(Object.fromEntries(response.headers), recordedResponseHeaders);
  const bodyBytes = typeof body === "string" ? Buffer.byteLength(body) : 0;
  console.log(`${name}: ${method} ${store} → ${response.status} ${responseHeaders.etag ?? ""}`);
  return {
    name,
    request: {
      method,
      path: `/v1/stores/${store}`,
      headers: requestHeaders,
      ...(typeof body === "string" && bodyBytes <= 4096 ? { body } : {}),
      bodyBytes,
    },
    response: { status: response.status, headers: responseHeaders, body: text },
  };
}

const json = { "content-type": "application/json" };
const example = [];
example.push(await exchange("get-never-written", {}));
example.push(await exchange("put-create", { method: "PUT", headers: { ...json, "if-none-match": "*" }, body: documentA }));
const first = example.at(-1).response.headers.etag;
example.push(await exchange("put-replace", { method: "PUT", headers: { ...json, "if-match": first }, body: documentB }));
const second = example.at(-1).response.headers.etag;
example.push(await exchange("put-replace-stale", { method: "PUT", headers: { ...json, "if-match": first }, body: documentC }));
example.push(await exchange("get-written", {}));

const errors = [];
errors.push(await exchange("get-unauthorized", { auth: "wrong-token" }));
errors.push(await exchange("put-unauthorized", { method: "PUT", headers: { ...json, "if-match": second }, body: documentC, auth: "wrong-token" }));
errors.push(await exchange("put-create-existing", { method: "PUT", headers: { ...json, "if-none-match": "*" }, body: documentC }));
errors.push(await exchange("put-replace-never-written", { method: "PUT", store: "watchLater", headers: { ...json, "if-match": first }, body: '{"format":1,"entries":[]}' }));
errors.push(await exchange("put-no-precondition", { method: "PUT", headers: json, body: documentC }));
const chunked = new ReadableStream({
  start(controller) {
    controller.enqueue(new TextEncoder().encode(documentC));
    controller.close();
  },
});
errors.push(await exchange("put-no-length", { method: "PUT", headers: { ...json, "if-match": second }, body: chunked }));
errors.push(await exchange("put-too-large", { method: "PUT", headers: { ...json, "if-match": second }, body: "x".repeat(1024 * 1024 + 1) }));
errors.push(await exchange("put-wrong-type", { method: "PUT", headers: { "content-type": "text/plain", "if-match": second }, body: documentC }));
errors.push(await exchange("delete-not-allowed", { method: "DELETE" }));
if (unconfigured) {
  errors.push(await exchange("get-not-configured", { url: unconfigured }));
}

const write = (file, exchanges) =>
  writeFileSync(join(out, file), `${JSON.stringify({ source, exchanges }, null, 2)}\n`);
write("example.json", example);
write("errors.json", errors);
console.log(`Wrote ${out}/example.json and errors.json`);

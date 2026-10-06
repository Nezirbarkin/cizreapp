// deno test _shared/live_token_test.ts
//
// `live-token` Edge Function istek mantığı — ağsız (sahte JWT çözümü ve sahte
// yetki kararı). `node:assert` hem Deno'da hem Node'da çalışır.

import assert from "node:assert/strict";
import { inflateSync } from "node:zlib";
import {
  handleLiveTokenRequest,
  LIVE_TOKEN_TTL_SECONDS,
  type LiveTokenDeps,
  type LiveTokenGrant,
  randomViewerUid,
} from "./live_token.ts";

const APP_ID = "970CA35de60c44645bbae8a215061b33";
const APP_CERT = "5CFd2fd1755d40ecb72977518be15d3b";
const SESSION = "0b6f5a3e-8d0c-4c55-9a55-2f3e1c0a7b11";
const CHANNEL = "cz_0123456789abcdef0123456789abcdef";

type Call = { sessionId: string; role: string; userId: string | null };

function deps(overrides: Partial<LiveTokenDeps> = {}, grant?: (c: Call) => LiveTokenGrant) {
  const calls: Call[] = [];
  const d: LiveTokenDeps = {
    appId: APP_ID,
    appCertificate: APP_CERT,
    userIdFromJwt: (jwt) => Promise.resolve(jwt === "user-jwt" ? "user-1" : null),
    grant: (sessionId, role, userId) => {
      const call = { sessionId, role, userId };
      calls.push(call);
      return Promise.resolve(grant ? grant(call) : { ok: true, channel: CHANNEL, host_uid: 1 });
    },
    randomViewerUid: () => 424242,
    ...overrides,
  };
  return { d, calls };
}

function post(body: unknown, jwt?: string, method = "POST"): Request {
  const headers: Record<string, string> = { "content-type": "application/json" };
  if (jwt) headers.authorization = `Bearer ${jwt}`;
  return new Request("https://x.test/functions/v1/live-token", {
    method,
    headers,
    body: method === "POST" ? JSON.stringify(body) : undefined,
  });
}

/** Anahtardaki uid ve ayrıcalık sayısı (imza bölümünü atlayarak). */
function tokenFacts(token: string) {
  const bytes = new Uint8Array(inflateSync(Uint8Array.from(atob(token.slice(3)), (c) => c.charCodeAt(0))));
  let pos = 0;
  const u16 = () => (pos += 2, bytes[pos - 2] | (bytes[pos - 1] << 8));
  const skip = (n: number) => (pos += n);
  const str = () => {
    const n = u16();
    const s = new TextDecoder().decode(bytes.slice(pos, pos + n));
    pos += n;
    return s;
  };
  skip(u16()); // imza
  const appId = str();
  skip(12); // issueTs, expire, salt
  const expire = bytes[pos - 8] | (bytes[pos - 7] << 8) | (bytes[pos - 6] << 16) | (bytes[pos - 5] << 24);
  skip(2); // servis sayısı
  skip(2); // servis türü
  const privileges = u16();
  skip(privileges * 6);
  const channel = str();
  const uid = str();
  return { appId, expire, privileges, channel, uid };
}

Deno.test("satıcı: uid 1, yayın ayrıcalıkları, App ID döner", async () => {
  const { d, calls } = deps();
  const res = await handleLiveTokenRequest(post({ session_id: SESSION, role: "host" }, "user-jwt"), d);
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.ok, true);
  assert.equal(body.app_id, APP_ID);
  assert.equal(body.uid, 1);
  assert.equal(body.host_uid, 1);
  assert.equal(body.channel, CHANNEL);
  assert.equal(body.expires_in, LIVE_TOKEN_TTL_SECONDS);
  assert.deepEqual(calls, [{ sessionId: SESSION, role: "host", userId: "user-1" }]);
  const facts = tokenFacts(body.token);
  assert.deepEqual(facts, { appId: APP_ID, expire: 3600, privileges: 4, channel: CHANNEL, uid: "1" });
  assert.equal(JSON.stringify(body).includes(APP_CERT), false, "sertifika asla dönmez");
});

Deno.test("izleyici: rastgele uid, yalnız katılma; misafir (anon anahtarı) kullanıcısız sorulur", async () => {
  const { d, calls } = deps();
  const res = await handleLiveTokenRequest(post({ session_id: SESSION, role: "viewer" }, "anon-key"), d);
  const body = await res.json();
  assert.equal(body.ok, true);
  assert.equal(body.uid, 424242);
  assert.equal(body.host_uid, 1);
  assert.equal(calls[0].userId, null);
  const facts = tokenFacts(body.token);
  assert.equal(facts.privileges, 1);
  assert.equal(facts.uid, "424242");
});

Deno.test("yetki kararı reddederse anahtar üretilmez; kod aynen iletilir", async () => {
  for (const error of ["NOT_LIVE", "ENDED", "FORBIDDEN", "AUTH_REQUIRED", "NOT_FOUND", "SHOP_INACTIVE"]) {
    const { d } = deps({}, () => ({ ok: false, error }));
    const res = await handleLiveTokenRequest(post({ session_id: SESSION, role: "viewer" }), d);
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.deepEqual(body, { ok: false, error });
  }
});

Deno.test("Agora ayarı yoksa ya da sertifikasızsa LIVE_NOT_CONFIGURED; karar sorulmaz", async () => {
  for (const cfg of [{ appId: undefined }, { appCertificate: undefined }, { appCertificate: "" }, { appId: "bad" }]) {
    const { d, calls } = deps(cfg);
    const body = await (await handleLiveTokenRequest(post({ session_id: SESSION, role: "host" }, "user-jwt"), d)).json();
    assert.deepEqual(body, { ok: false, error: "LIVE_NOT_CONFIGURED" });
    assert.equal(calls.length, 0);
  }
});

Deno.test("hatalı istek: rol/kimlik/metot", async () => {
  const { d, calls } = deps();
  for (const body of [{ session_id: SESSION, role: "admin" }, { session_id: "x", role: "viewer" }, {}, null]) {
    const res = await handleLiveTokenRequest(post(body), d);
    assert.equal(res.status, 400);
  }
  assert.equal((await handleLiveTokenRequest(post(null, undefined, "GET"), d)).status, 405);
  assert.equal((await handleLiveTokenRequest(new Request("https://x.test", { method: "OPTIONS" }), d)).status, 204);
  assert.equal(calls.length, 0);
});

Deno.test("hız sınırı: kullanıcıya göre, misafirde IP'ye göre", async () => {
  const keys: string[] = [];
  const { d } = deps({ rateLimited: (k) => (keys.push(k), true) });
  const res = await handleLiveTokenRequest(post({ session_id: SESSION, role: "viewer" }, "user-jwt"), d);
  assert.equal(res.status, 429);
  const guest = new Request("https://x.test", {
    method: "POST",
    headers: { "x-forwarded-for": "203.0.113.9, 10.0.0.1" },
    body: JSON.stringify({ session_id: SESSION, role: "viewer" }),
  });
  await handleLiveTokenRequest(guest, d);
  assert.deepEqual(keys, ["user-1", "ip:203.0.113.9"]);
});

Deno.test("izleyici uid aralığı satıcınınkiyle çakışmaz", () => {
  for (let i = 0; i < 1000; i++) {
    const uid = randomViewerUid();
    assert.ok(uid >= 100000 && uid < 0x7fffffff);
  }
});

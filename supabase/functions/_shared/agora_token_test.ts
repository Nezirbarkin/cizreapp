// deno test _shared/agora_token_test.ts
//
// Bilinen cevaplar resmi `agora-token@2.0.6` paketinin AccessToken2 +
// ServiceRtc (RtcTokenBuilder2 ile aynı ayrıcalıklar) çıktısıdır; sabit
// issueTs/salt ile üretildi. Ayrıca aynı paketin `verifySignature`'ı rastgele
// tuzlu 50 anahtarı doğruladı (Görev 3.4). `node:assert` hem Deno'da hem
// Node'da çalışır.

import assert from "node:assert/strict";
import { inflateSync } from "node:zlib";
import { AgoraTokenError, buildRtcToken, randomSalt, type RtcTokenInput } from "./agora_token.ts";

const APP_ID = "970CA35de60c44645bbae8a215061b33";
const APP_CERT = "5CFd2fd1755d40ecb72977518be15d3b";

const base: RtcTokenInput = {
  appId: APP_ID,
  appCertificate: APP_CERT,
  channelName: "7d72365eb983485397e3e3f9d460bdda",
  uid: 2882341273,
  role: "subscriber",
  tokenExpireSeconds: 600,
  issueTs: 1111111,
  salt: 1,
};

async function errorOf(input: RtcTokenInput): Promise<string> {
  try {
    await buildRtcToken(input);
  } catch (e) {
    if (e instanceof AgoraTokenError) return e.message;
    throw e;
  }
  return "NO_ERROR";
}

/** Anahtarın içeriğini çözer: imza + imzalanan bilgi alanları. */
function decode(token: string) {
  assert.equal(token.slice(0, 3), "007");
  const bytes = new Uint8Array(inflateSync(Uint8Array.from(atob(token.slice(3)), (c) => c.charCodeAt(0))));
  let pos = 0;
  const u16 = () => {
    const v = bytes[pos] | (bytes[pos + 1] << 8);
    pos += 2;
    return v;
  };
  const u32 = () => {
    const v = (bytes[pos] | (bytes[pos + 1] << 8) | (bytes[pos + 2] << 16) | (bytes[pos + 3] << 24)) >>> 0;
    pos += 4;
    return v;
  };
  const str = () => {
    const n = u16();
    const s = new TextDecoder().decode(bytes.slice(pos, pos + n));
    pos += n;
    return s;
  };
  const signatureLength = u16();
  pos += signatureLength;
  const appId = str();
  const issueTs = u32();
  const expire = u32();
  const salt = u32();
  const services = u16();
  const serviceType = u16();
  const privileges: Record<number, number> = {};
  const privilegeCount = u16();
  for (let i = 0; i < privilegeCount; i++) {
    const key = u16();
    privileges[key] = u32();
  }
  const channel = str();
  const uid = str();
  return { signatureLength, appId, issueTs, expire, salt, services, serviceType, privileges, channel, uid, rest: bytes.length - pos };
}

Deno.test("resmi paketle bayt bayt aynı: izleyici", async () => {
  assert.equal(
    await buildRtcToken(base),
    "007eJxTYCjvdzbWfdRvW3iNTXtGaMYq8Zvu4vrm1kpuTqeXPfxxS1CBwdLcwNnR2DQl1cwg2cTEzMQ0KSkx1SLRyNDUwMwwydjY/YsAQwQTAwMjAwhDIAgoMJinmBsZm5mmJllaGJtYmBpbmqcapxqnWaaYmBkkpaQkcjEYWVgYGZsYGpkbAwC2/CKh",
  );
});

Deno.test("resmi paketle bayt bayt aynı: yayıncı (ayrıcalık süresiyle)", async () => {
  assert.equal(
    await buildRtcToken({ ...base, role: "publisher", privilegeExpireSeconds: 600 }),
    "007eJxTYDhuGCT90E3Yo2+N3efJV5hX1K1MZAqae/Sa8UP9VXvOhfArMFiaGzg7GpumpJoZJJuYmJmYJiUlplokGhmaGpgZJhkbu38RYIhgYmBgZABhRgYWBkYwnwlMMoNJFjCpwGCeYm5kbGaammRpYWxiYWpsaZ5qnGqcZpliYmaQlJKSyMVgZGFhZGxiaGRuDACosyXL",
  );
});

Deno.test("resmi paketle bayt bayt aynı: CizreApp kanal biçimi, satıcı uid 1", async () => {
  assert.equal(
    await buildRtcToken({
      ...base,
      channelName: "cz_0123456789abcdef0123456789abcdef",
      uid: 1,
      role: "publisher",
      tokenExpireSeconds: 3600,
      issueTs: 1790000000,
      salt: 99999999,
    }),
    "007eJxTYOB+dt5IKZz7wvSQpmetm+OUG47zHmtlv5H1ZerLBr0Xy9oVGCzNDZwdjU1TUs0Mkk1MzExMk5ISUy0SjQxNDcwMk4yNG6w3ZgnwMTD8f/CVlZGBkYGFgZEBBJjAJDOYZAGTygzJVfEGhkbGJqZm5haWiUnJKalp6HxGBkMA/8UoIQ==",
  );
});

Deno.test("izleyici yalnız katılır; yayıncı ses/görüntü/veri yayınlar", async () => {
  const viewer = decode(await buildRtcToken({ ...base, issueTs: undefined, salt: undefined }));
  assert.deepEqual(viewer.privileges, { 1: 0 });
  assert.equal(viewer.appId, APP_ID);
  assert.equal(viewer.channel, base.channelName);
  assert.equal(viewer.uid, "2882341273");
  assert.equal(viewer.expire, 600);
  assert.equal(viewer.services, 1);
  assert.equal(viewer.serviceType, 1);
  assert.equal(viewer.signatureLength, 32);
  assert.equal(viewer.rest, 0);
  assert.ok(Math.abs(viewer.issueTs - Math.floor(Date.now() / 1000)) <= 5, "issueTs şimdi");
  assert.ok(viewer.salt >= 1 && viewer.salt <= 99999999);

  const host = decode(await buildRtcToken({ ...base, role: "publisher", uid: 1 }));
  assert.deepEqual(host.privileges, { 1: 0, 2: 0, 3: 0, 4: 0 });
  assert.equal(host.uid, "1");

  const anyUid = decode(await buildRtcToken({ ...base, uid: 0 }));
  assert.equal(anyUid.uid, "", "uid 0 → boş metin (resmi paketteki gibi)");
});

Deno.test("geçersiz girdiler anahtar üretmez", async () => {
  assert.equal(await errorOf({ ...base, appId: "" }), "INVALID_APP_ID");
  assert.equal(await errorOf({ ...base, appId: "x".repeat(32) }), "INVALID_APP_ID");
  assert.equal(await errorOf({ ...base, appCertificate: APP_CERT.slice(1) }), "INVALID_APP_CERTIFICATE");
  assert.equal(await errorOf({ ...base, channelName: "" }), "INVALID_CHANNEL");
  assert.equal(await errorOf({ ...base, channelName: "c".repeat(65) }), "INVALID_CHANNEL");
  assert.equal(await errorOf({ ...base, uid: -1 }), "INVALID_UID");
  assert.equal(await errorOf({ ...base, uid: 2 ** 32 }), "INVALID_UID");
  assert.equal(await errorOf({ ...base, uid: 1.5 }), "INVALID_UID");
  assert.equal(await errorOf({ ...base, tokenExpireSeconds: 0 }), "INVALID_EXPIRE");
  assert.equal(await errorOf({ ...base, salt: 0 }), "INVALID_SALT");
});

Deno.test("tuz aralığı 1..99999999", () => {
  for (let i = 0; i < 1000; i++) {
    const salt = randomSalt();
    assert.ok(Number.isInteger(salt) && salt >= 1 && salt <= 99999999);
  }
});

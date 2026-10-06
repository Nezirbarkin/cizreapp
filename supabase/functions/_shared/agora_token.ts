// Agora RTC erişim anahtarı (AccessToken2, "007" sürümü) üretimi.
//
// Bağımlılıksızdır: yalnız Web Crypto (HMAC-SHA256), CompressionStream (zlib)
// ve btoa kullanır; Deno'da (Edge Function) ve Node'da aynen çalışır.
// Resmi `agora-token` npm paketindeki `RtcTokenBuilder2.buildTokenWithUid`
// ile BAYT BAYT aynı çıktıyı verir — bilinen cevap testleri
// `agora_token_test.ts`'te (değerler resmi paketle üretildi).
//
// Biçim: "007" + base64(zlib(imza_uzunluklu + imzalanan_bilgi)).
// imzalanan_bilgi = appId, issueTs, expire, salt, servis sayısı, RTC servisi
// (tür=1, ayrıcalık haritası, kanal adı, uid metni). Tamsayılar küçük-uçlu,
// metin/bayt dizileri 2 baytlık uzunluk önekiyle yazılır.

/** RTC servis türü ve ayrıcalık kimlikleri (Agora AccessToken2). */
export const RTC_SERVICE_TYPE = 1;
export const RTC_PRIVILEGE = {
  joinChannel: 1,
  publishAudio: 2,
  publishVideo: 3,
  publishData: 4,
} as const;

/** publisher = yayıncı (satıcı), subscriber = izleyici (yalnız katılır). */
export type RtcRole = "publisher" | "subscriber";

export interface RtcTokenInput {
  appId: string;
  appCertificate: string;
  channelName: string;
  /** 0 = kanaldaki her uid (kullanmayın); aksi halde 1..2^32-1. */
  uid: number;
  role: RtcRole;
  /** Anahtarın geçerlilik süresi, üretimden itibaren saniye. */
  tokenExpireSeconds: number;
  /** Ayrıcalıkların süresi (saniye); 0 = anahtar süresi geçerli. */
  privilegeExpireSeconds?: number;
  /** Yalnız testler için sabitlenir. */
  issueTs?: number;
  /** Yalnız testler için sabitlenir (1..99999999). */
  salt?: number;
}

export class AgoraTokenError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "AgoraTokenError";
  }
}

const HEX32 = /^[0-9a-fA-F]{32}$/;
const UINT32_MAX = 0xffffffff;
const encoder = new TextEncoder();

class ByteWriter {
  private parts: number[] = [];

  uint16(v: number): this {
    this.parts.push(v & 0xff, (v >>> 8) & 0xff);
    return this;
  }

  uint32(v: number): this {
    this.parts.push(v & 0xff, (v >>> 8) & 0xff, (v >>> 16) & 0xff, (v >>> 24) & 0xff);
    return this;
  }

  bytes(b: Uint8Array): this {
    if (b.length > 0xffff) throw new AgoraTokenError("FIELD_TOO_LONG");
    this.uint16(b.length);
    for (const x of b) this.parts.push(x);
    return this;
  }

  string(s: string): this {
    return this.bytes(encoder.encode(s));
  }

  raw(b: Uint8Array): this {
    for (const x of b) this.parts.push(x);
    return this;
  }

  build(): Uint8Array {
    return Uint8Array.from(this.parts);
  }
}

async function hmacSha256(key: Uint8Array, message: Uint8Array): Promise<Uint8Array> {
  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    key,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return new Uint8Array(await crypto.subtle.sign("HMAC", cryptoKey, message));
}

/** zlib (RFC 1950) sıkıştırma — Node `zlib.deflateSync` ile aynı biçim. */
async function zlibDeflate(data: Uint8Array): Promise<Uint8Array> {
  const stream = new Blob([data]).stream().pipeThrough(new CompressionStream("deflate"));
  return new Uint8Array(await new Response(stream).arrayBuffer());
}

function toBase64(bytes: Uint8Array): string {
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary);
}

function assertUint32(value: number, code: string, min = 0): void {
  if (!Number.isInteger(value) || value < min || value > UINT32_MAX) {
    throw new AgoraTokenError(code);
  }
}

/** Rastgele tuz (resmi paketteki gibi 1..99999999). */
export function randomSalt(): number {
  const buf = new Uint32Array(1);
  crypto.getRandomValues(buf);
  return (buf[0] % 99999999) + 1;
}

/**
 * Bir RTC kanalı için Agora erişim anahtarı üretir.
 * Yayıncı: katılma + ses/görüntü/veri yayınlama; izleyici: yalnız katılma.
 */
export async function buildRtcToken(input: RtcTokenInput): Promise<string> {
  const { appId, appCertificate, channelName, uid, role } = input;
  if (!HEX32.test(appId)) throw new AgoraTokenError("INVALID_APP_ID");
  if (!HEX32.test(appCertificate)) throw new AgoraTokenError("INVALID_APP_CERTIFICATE");
  const channelBytes = encoder.encode(channelName);
  if (channelBytes.length === 0 || channelBytes.length > 64) {
    throw new AgoraTokenError("INVALID_CHANNEL");
  }
  assertUint32(uid, "INVALID_UID");
  assertUint32(input.tokenExpireSeconds, "INVALID_EXPIRE", 1);
  const privilegeExpire = input.privilegeExpireSeconds ?? 0;
  assertUint32(privilegeExpire, "INVALID_EXPIRE");
  const issueTs = input.issueTs ?? Math.floor(Date.now() / 1000);
  assertUint32(issueTs, "INVALID_ISSUE_TS", 1);
  const salt = input.salt ?? randomSalt();
  assertUint32(salt, "INVALID_SALT", 1);

  // Ayrıcalık haritası anahtar sırasıyla (TreeMap) yazılır.
  const privileges: number[] = [RTC_PRIVILEGE.joinChannel];
  if (role === "publisher") {
    privileges.push(
      RTC_PRIVILEGE.publishAudio,
      RTC_PRIVILEGE.publishVideo,
      RTC_PRIVILEGE.publishData,
    );
  }
  const service = new ByteWriter().uint16(RTC_SERVICE_TYPE).uint16(privileges.length);
  for (const privilege of privileges) service.uint16(privilege).uint32(privilegeExpire);
  service.string(channelName).string(uid === 0 ? "" : String(uid));

  const signingInfo = new ByteWriter()
    .string(appId)
    .uint32(issueTs)
    .uint32(input.tokenExpireSeconds)
    .uint32(salt)
    .uint16(1)
    .raw(service.build())
    .build();

  // İmza anahtarı: HMAC(issueTs, sertifika) → HMAC(salt, …)
  let signingKey = await hmacSha256(
    new ByteWriter().uint32(issueTs).build(),
    encoder.encode(appCertificate),
  );
  signingKey = await hmacSha256(new ByteWriter().uint32(salt).build(), signingKey);
  const signature = await hmacSha256(signingKey, signingInfo);

  const content = new ByteWriter().bytes(signature).raw(signingInfo).build();
  return "007" + toBase64(await zlibDeflate(content));
}

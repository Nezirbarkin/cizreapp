import {
  base64UrlDecode,
  derEcdsaToRaw,
  hmacSha256Base64Url,
  timingSafeEqual,
} from "./crypto.ts";

const encoder = new TextEncoder();
const REQUIRED = [
  "ad_network",
  "ad_unit",
  "custom_data",
  "reward_amount",
  "reward_item",
  "timestamp",
  "transaction_id",
];
const keyCache = new Map<string, { key: CryptoKey; expiresAt: number }>();

export interface ParsedSsv {
  signedData: string;
  signature: string;
  keyId: string;
  values: Record<string, string>;
}

export function parseRawSsvQuery(url: string): ParsedSsv {
  const raw = new URL(url).search.slice(1);
  if (!raw || raw.length > 8192 || raw.includes("#")) {
    throw new Error("INVALID_QUERY");
  }
  const marker = "&signature=";
  const signatureAt = raw.indexOf(marker);
  if (signatureAt <= 0 || raw.indexOf(marker, signatureAt + 1) !== -1) {
    throw new Error("INVALID_SIGNATURE_POSITION");
  }
  const signedData = raw.slice(0, signatureAt);
  const unsigned = raw.slice(signatureAt + 1);
  const pairs = unsigned.split("&");
  if (
    pairs.length !== 2 || !pairs[0].startsWith("signature=") ||
    !pairs[1].startsWith("key_id=")
  ) {
    throw new Error("INVALID_UNSIGNED_PARAMETERS");
  }
  const signature = decodeComponent(pairs[0].slice("signature=".length));
  const keyId = decodeComponent(pairs[1].slice("key_id=".length));
  if (!signature || !/^[0-9]{1,100}$/u.test(keyId)) {
    throw new Error("INVALID_SIGNATURE_METADATA");
  }

  const values: Record<string, string> = {};
  for (const pair of signedData.split("&")) {
    const equals = pair.indexOf("=");
    if (equals <= 0) throw new Error("INVALID_SIGNED_PARAMETER");
    const name = decodeComponent(pair.slice(0, equals));
    if (name in values || name === "signature" || name === "key_id") {
      throw new Error("DUPLICATE_PARAMETER");
    }
    values[name] = decodeComponent(pair.slice(equals + 1));
  }
  for (const name of REQUIRED) {
    if (!values[name]) throw new Error(`MISSING_FIELD:${name}`);
  }
  if (values.user_id === undefined) values.user_id = "";
  return { signedData, signature, keyId, values };
}

function decodeComponent(value: string): string {
  try {
    return decodeURIComponent(value.replaceAll("+", "%20"));
  } catch {
    throw new Error("INVALID_PERCENT_ENCODING");
  }
}

export function validateTimestamp(
  timestampMs: string,
  nowMs: number,
  maxAgeMs: number,
  futureSkewMs: number,
): Date {
  if (!/^\d{10,16}$/u.test(timestampMs)) throw new Error("INVALID_TIMESTAMP");
  const value = Number(timestampMs);
  if (
    !Number.isSafeInteger(value) || value < nowMs - maxAgeMs ||
    value > nowMs + futureSkewMs
  ) {
    throw new Error("TIMESTAMP_REJECTED");
  }
  return new Date(value);
}

export async function verifyCustomData(
  customData: string,
  secret: string,
): Promise<{ sessionId: string; nonce: string }> {
  const match =
    /^v1\.([0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12})\.([A-Za-z0-9_-]{43})\.([A-Za-z0-9_-]{43})$/iu
      .exec(customData);
  if (!match) throw new Error("INVALID_CUSTOM_DATA");
  const expected = await hmacSha256Base64Url(
    secret,
    `v1.${match[1]}.${match[2]}`,
  );
  if (!timingSafeEqual(expected, match[3])) {
    throw new Error("INVALID_CUSTOM_DATA_MAC");
  }
  return { sessionId: match[1], nonce: match[2] };
}

export async function verifySsvSignature(
  parsed: ParsedSsv,
  keyUrl: string,
  ttlMs: number,
  fetcher: typeof fetch = fetch,
): Promise<boolean> {
  let key = await getKey(parsed.keyId, keyUrl, ttlMs, false, fetcher);
  let valid = await verifyWithKey(key, parsed);
  if (!valid) {
    keyCache.delete(parsed.keyId);
    key = await getKey(parsed.keyId, keyUrl, ttlMs, true, fetcher);
    valid = await verifyWithKey(key, parsed);
  }
  return valid;
}

async function verifyWithKey(
  key: CryptoKey,
  parsed: ParsedSsv,
): Promise<boolean> {
  const der = base64UrlDecode(parsed.signature);
  const raw = derEcdsaToRaw(der);
  return await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    ownedBuffer(raw),
    encoder.encode(parsed.signedData),
  );
}

// TypeScript 6 correctly models a generic Uint8Array as potentially backed by
// SharedArrayBuffer, while WebCrypto accepts an ArrayBuffer-backed view. Copying
// also prevents a caller from mutating signature bytes during verification.
function ownedBuffer(bytes: Uint8Array): ArrayBuffer {
  const copy = new Uint8Array(bytes.byteLength);
  copy.set(bytes);
  return copy.buffer;
}

async function getKey(
  keyId: string,
  keyUrl: string,
  ttlMs: number,
  force: boolean,
  fetcher: typeof fetch,
): Promise<CryptoKey> {
  const cached = keyCache.get(keyId);
  if (!force && cached && cached.expiresAt > Date.now()) return cached.key;
  const response = await fetcher(keyUrl, {
    headers: { Accept: "application/json" },
    signal: AbortSignal.timeout(5000),
  });
  if (!response.ok) throw new Error("KEY_FETCH_FAILED");
  const payload = await response.json();
  if (!payload || !Array.isArray(payload.keys)) {
    throw new Error("INVALID_KEY_RESPONSE");
  }
  let requested: CryptoKey | null = null;
  for (const item of payload.keys) {
    const id = String(item.keyId ?? item.key_id ?? "");
    const pem = item.pem;
    if (!/^\d{1,100}$/u.test(id) || typeof pem !== "string") continue;
    const key = await importPem(pem);
    keyCache.set(id, { key, expiresAt: Date.now() + ttlMs });
    if (id === keyId) requested = key;
  }
  if (!requested) throw new Error("UNKNOWN_KEY_ID");
  return requested;
}

async function importPem(pem: string): Promise<CryptoKey> {
  const content = pem.replace(
    /-----BEGIN PUBLIC KEY-----|-----END PUBLIC KEY-----|\s/gu,
    "",
  );
  const binary = Uint8Array.from(atob(content), (char) => char.charCodeAt(0));
  return await crypto.subtle.importKey(
    "spki",
    binary,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["verify"],
  );
}

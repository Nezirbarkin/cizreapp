const encoder = new TextEncoder();

export function base64UrlEncode(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(
    /=+$/u,
    "",
  );
}

export function base64UrlDecode(value: string): Uint8Array {
  if (!/^[A-Za-z0-9_-]+={0,2}$/u.test(value)) {
    throw new Error("INVALID_BASE64URL");
  }
  const normalized = value.replaceAll("-", "+").replaceAll("_", "/");
  const padded = normalized + "=".repeat((4 - normalized.length % 4) % 4);
  const binary = atob(padded);
  return Uint8Array.from(binary, (char) => char.charCodeAt(0));
}

export function randomOpaqueToken(byteLength = 32): string {
  const bytes = new Uint8Array(byteLength);
  crypto.getRandomValues(bytes);
  return base64UrlEncode(bytes);
}

export async function sha256Hex(value: string): Promise<string> {
  return hex(
    new Uint8Array(
      await crypto.subtle.digest("SHA-256", encoder.encode(value)),
    ),
  );
}

export async function hmacSha256Hex(
  secret: string,
  value: string,
): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return hex(
    new Uint8Array(
      await crypto.subtle.sign("HMAC", key, encoder.encode(value)),
    ),
  );
}

export async function hmacSha256Base64Url(
  secret: string,
  value: string,
): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return base64UrlEncode(
    new Uint8Array(
      await crypto.subtle.sign("HMAC", key, encoder.encode(value)),
    ),
  );
}

export function timingSafeEqual(a: string, b: string): boolean {
  const left = encoder.encode(a);
  const right = encoder.encode(b);
  if (left.length !== right.length) return false;
  let difference = 0;
  for (let i = 0; i < left.length; i++) difference |= left[i] ^ right[i];
  return difference === 0;
}

function hex(bytes: Uint8Array): string {
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join(
    "",
  );
}

function readDerLength(bytes: Uint8Array, offset: number): [number, number] {
  const first = bytes[offset];
  if (first < 0x80) return [first, offset + 1];
  const count = first & 0x7f;
  if (count < 1 || count > 2 || offset + count >= bytes.length) {
    throw new Error("INVALID_DER_LENGTH");
  }
  let length = 0;
  for (let i = 0; i < count; i++) {
    length = (length << 8) | bytes[offset + 1 + i];
  }
  return [length, offset + 1 + count];
}

/** Converts an ASN.1 DER ECDSA P-256 signature to WebCrypto's 64-byte r||s form. */
export function derEcdsaToRaw(
  signature: Uint8Array,
  componentSize = 32,
): Uint8Array {
  if (signature.length === componentSize * 2) return signature;
  let offset = 0;
  if (signature[offset++] !== 0x30) throw new Error("INVALID_DER_SEQUENCE");
  const [sequenceLength, sequenceStart] = readDerLength(signature, offset);
  offset = sequenceStart;
  if (
    offset + sequenceLength !== signature.length || signature[offset++] !== 0x02
  ) {
    throw new Error("INVALID_DER_SEQUENCE");
  }
  const [rLength, rStart] = readDerLength(signature, offset);
  offset = rStart;
  const r = signature.slice(offset, offset + rLength);
  offset += rLength;
  if (signature[offset++] !== 0x02) throw new Error("INVALID_DER_INTEGER");
  const [sLength, sStart] = readDerLength(signature, offset);
  offset = sStart;
  const s = signature.slice(offset, offset + sLength);
  offset += sLength;
  if (offset !== signature.length) throw new Error("INVALID_DER_TRAILING_DATA");
  const raw = new Uint8Array(componentSize * 2);
  copyInteger(r, raw, 0, componentSize);
  copyInteger(s, raw, componentSize, componentSize);
  return raw;
}

function copyInteger(
  integer: Uint8Array,
  output: Uint8Array,
  offset: number,
  size: number,
): void {
  if (integer.length === 0 || (integer[0] & 0x80) !== 0) {
    throw new Error("INVALID_DER_INTEGER");
  }
  let value = integer;
  if (value.length > 1 && value[0] === 0) {
    // DER requires exactly one sign-padding byte when the unsigned ECDSA
    // component starts with a high bit. Reject redundant/non-canonical zeros.
    if ((value[1] & 0x80) === 0) throw new Error("INVALID_DER_INTEGER");
    value = value.slice(1);
  }
  if (value.length > size) throw new Error("INVALID_DER_INTEGER");
  output.set(value, offset + size - value.length);
}

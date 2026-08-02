import {
  assertEquals,
  assertRejects,
  assertThrows,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  type ParsedSsv,
  parseRawSsvQuery,
  validateTimestamp,
  verifyCustomData,
  verifySsvSignature,
} from "./admob_ssv.ts";
import {
  base64UrlEncode,
  derEcdsaToRaw,
  hmacSha256Base64Url,
} from "./crypto.ts";

Deno.test("raw SSV canonical signed bytes signature parametresinden önce korunur", () => {
  const signed =
    "ad_network=5450213213286189855&ad_unit=unit%2Fone&custom_data=x&reward_amount=1&reward_item=point&timestamp=1720000000000&transaction_id=tx";
  const parsed = parseRawSsvQuery(
    `https://example.test/callback?${signed}&signature=MEUCIQ&key_id=123`,
  );
  assertEquals(parsed.signedData, signed);
  assertEquals(parsed.values.ad_unit, "unit/one");
});

Deno.test("canonical parser duplicate ve yanlış unsigned sıra için fail-closed", () => {
  const signed =
    "ad_network=a&ad_unit=u&custom_data=x&reward_amount=1&reward_item=p&timestamp=1720000000000&transaction_id=t";
  assertThrows(() =>
    parseRawSsvQuery(
      `https://x.test/?${signed}&ad_unit=evil&signature=s&key_id=1`,
    )
  );
  assertThrows(() =>
    parseRawSsvQuery(`https://x.test/?${signed}&key_id=1&signature=s`)
  );
});

Deno.test("timestamp replay ve future pencereleri reddedilir", () => {
  const now = 2_000_000_000_000;
  assertEquals(
    validateTimestamp(String(now - 1000), now, 5000, 500).getTime(),
    now - 1000,
  );
  assertThrows(() => validateTimestamp(String(now - 5001), now, 5000, 500));
  assertThrows(() => validateTimestamp(String(now + 501), now, 5000, 500));
});

Deno.test("custom data MAC session ve nonce bağını doğrular", async () => {
  const secret = "x".repeat(32);
  const session = "550e8400-e29b-41d4-a716-446655440000";
  const nonce = "a".repeat(43);
  const prefix = `v1.${session}.${nonce}`;
  const custom = `${prefix}.${await hmacSha256Base64Url(secret, prefix)}`;
  assertEquals(await verifyCustomData(custom, secret), {
    sessionId: session,
    nonce,
  });
  await assertRejects(() =>
    verifyCustomData(`${custom.slice(0, -1)}A`, secret)
  );
});

Deno.test("DER P-256 ECDSA imzası 64-byte raw r||s biçimine çevrilir", () => {
  const der = Uint8Array.from([0x30, 0x06, 0x02, 0x01, 0x01, 0x02, 0x01, 0x02]);
  const raw = derEcdsaToRaw(der);
  assertEquals(raw.length, 64);
  assertEquals(raw[31], 1);
  assertEquals(raw[63], 2);
});

Deno.test("RFC 6979 P-256 SHA-256 DER vektörü doğrulanır ve key cache kullanılır", async () => {
  const vector = await rfc6979Vector("6979001");
  let fetchCount = 0;
  const fetcher: typeof fetch = () => {
    fetchCount++;
    return Promise.resolve(keyResponse(vector.keyId, vector.pem));
  };

  assertEquals(
    await verifySsvSignature(
      vector.parsed,
      "https://keys.test",
      60_000,
      fetcher,
    ),
    true,
  );
  assertEquals(
    await verifySsvSignature(
      vector.parsed,
      "https://keys.test",
      60_000,
      fetcher,
    ),
    true,
  );
  assertEquals(fetchCount, 1);
});

Deno.test("aynı key id rotasyonunda başarısız doğrulama anahtarı yeniler", async () => {
  const vector = await rfc6979Vector("6979002");
  const wrongKey = await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["sign", "verify"],
  );
  const wrongPem = pem(
    await crypto.subtle.exportKey("spki", wrongKey.publicKey),
  );
  let fetchCount = 0;
  const fetcher: typeof fetch = () => {
    fetchCount++;
    return Promise.resolve(
      keyResponse(vector.keyId, fetchCount === 1 ? wrongPem : vector.pem),
    );
  };

  assertEquals(
    await verifySsvSignature(
      vector.parsed,
      "https://keys.test",
      60_000,
      fetcher,
    ),
    true,
  );
  assertEquals(fetchCount, 2);
});

Deno.test("key fetch ve bilinmeyen key id fail-closed davranır", async () => {
  const vector = await rfc6979Vector("6979003");
  const failedFetch: typeof fetch = () =>
    Promise.resolve(new Response(null, { status: 503 }));
  await assertRejects(
    () =>
      verifySsvSignature(
        vector.parsed,
        "https://keys.test",
        60_000,
        failedFetch,
      ),
    Error,
    "KEY_FETCH_FAILED",
  );

  const unknownKey: typeof fetch = () =>
    Promise.resolve(keyResponse("9999999", vector.pem));
  await assertRejects(
    () =>
      verifySsvSignature(
        vector.parsed,
        "https://keys.test",
        60_000,
        unknownKey,
      ),
    Error,
    "UNKNOWN_KEY_ID",
  );
});

async function rfc6979Vector(
  keyId: string,
): Promise<{ keyId: string; pem: string; parsed: ParsedSsv }> {
  // RFC 6979 A.2.5: ECDSA P-256 / SHA-256, message "sample". Both
  // components require DER sign padding, which caught the production bug.
  const x = hex(
    "60FED4BA255A9D31C961EB74C6356D68C049B8923B61FA6CE669622E60F29FB6",
  );
  const y = hex(
    "7903FE1008B8BC99A41AE9E95628BC64F2F1B20C2D7E9F5177A3C294D4462299",
  );
  const r = hex(
    "EFD48B2AACB6A8FD1140DD9CD45E81D69D2C877B56AAF991C34D0EA84EAF3716",
  );
  const s = hex(
    "F7CB1C942D657C41D436C7A1B6E29F65F3E900DBB9AFF4064DC4AB2F843ACDA8",
  );
  const der = Uint8Array.from([
    0x30,
    0x46,
    0x02,
    0x21,
    0x00,
    ...r,
    0x02,
    0x21,
    0x00,
    ...s,
  ]);
  const publicKey = await crypto.subtle.importKey(
    "jwk",
    {
      kty: "EC",
      crv: "P-256",
      x: base64UrlEncode(x),
      y: base64UrlEncode(y),
      ext: true,
    },
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["verify"],
  );
  return {
    keyId,
    pem: pem(await crypto.subtle.exportKey("spki", publicKey)),
    parsed: {
      signedData: "sample",
      signature: base64UrlEncode(der),
      keyId,
      values: {},
    },
  };
}

function keyResponse(keyId: string, publicKeyPem: string): Response {
  return Response.json({ keys: [{ keyId, pem: publicKeyPem }] });
}

function pem(spki: ArrayBuffer): string {
  const encoded = btoa(String.fromCharCode(...new Uint8Array(spki)));
  return `-----BEGIN PUBLIC KEY-----\n${
    encoded.match(/.{1,64}/gu)?.join("\n")
  }\n-----END PUBLIC KEY-----`;
}

function hex(value: string): Uint8Array {
  return Uint8Array.from(
    value.match(/.{2}/gu) ?? [],
    (byte) => Number.parseInt(byte, 16),
  );
}

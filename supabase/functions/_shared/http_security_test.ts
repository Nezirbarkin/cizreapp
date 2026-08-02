import {
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { bearerToken, json, options } from "./http.ts";

Deno.test("reward session CORS preflight yalnız izinli yöntemi ilan eder", () => {
  const response = options("POST, OPTIONS");

  assertEquals(response.status, 204);
  assertEquals(response.headers.get("access-control-allow-origin"), "*");
  assertEquals(
    response.headers.get("access-control-allow-methods"),
    "POST, OPTIONS",
  );
  assertStringIncludes(
    response.headers.get("access-control-allow-headers") ?? "",
    "authorization",
  );
});

Deno.test("JSON hata yanıtı CORS ve Allow başlığını korur", async () => {
  const response = json({ error_code: "METHOD_NOT_ALLOWED" }, 405, {
    Allow: "GET",
  });

  assertEquals(response.status, 405);
  assertEquals(response.headers.get("allow"), "GET");
  assertEquals(response.headers.get("access-control-allow-origin"), "*");
  assertEquals(await response.json(), { error_code: "METHOD_NOT_ALLOWED" });
});

Deno.test("bearer ayrıştırıcı eksik ve geçersiz authorization için fail-closed", () => {
  assertEquals(bearerToken(new Request("https://example.test")), null);
  assertEquals(
    bearerToken(
      new Request("https://example.test", {
        headers: { authorization: "Basic secret" },
      }),
    ),
    null,
  );
  assertEquals(
    bearerToken(
      new Request("https://example.test", {
        headers: { authorization: "Bearer signed.jwt" },
      }),
    ),
    "signed.jwt",
  );
});

Deno.test("AdMob callback public, session endpoint JWT korumalıdır", async () => {
  const config = (await Deno.readTextFile(
    new URL("../../config.toml", import.meta.url),
  )).replaceAll("\r\n", "\n");

  assertStringIncludes(
    config,
    "[functions.admob-ssv-callback]\nverify_jwt = false",
  );
  assertStringIncludes(
    config,
    "[functions.admob-reward-session]\nverify_jwt = true",
  );
});

Deno.test("AdMob endpoint yöntem sözleşmeleri fail-closed kalır", async () => {
  const callback = await Deno.readTextFile(
    new URL("../admob-ssv-callback/index.ts", import.meta.url),
  );
  const session = await Deno.readTextFile(
    new URL("../admob-reward-session/index.ts", import.meta.url),
  );
  const legacy = await Deno.readTextFile(
    new URL("../grant-ad-reward/index.ts", import.meta.url),
  );

  assertStringIncludes(callback, 'if (req.method !== "GET")');
  assertStringIncludes(callback, 'Allow: "GET"');
  assertStringIncludes(session, 'if (req.method === "OPTIONS")');
  assertStringIncludes(session, 'if (req.method !== "POST")');
  assertStringIncludes(legacy, 'if (req.method === "OPTIONS")');
  assertStringIncludes(legacy, 'if (req.method !== "POST")');
  assertStringIncludes(legacy, "LEGACY_AD_REWARD_ENDPOINT_RETIRED");
  assertStringIncludes(legacy, "credit_created: false");
  assertEquals(legacy.includes(".rpc("), false);
  assertEquals(legacy.includes("user_balances"), false);
  assertEquals(legacy.includes("balance_transactions"), false);
});

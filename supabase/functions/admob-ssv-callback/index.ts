import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import {
  parseRawSsvQuery,
  validateTimestamp,
  verifyCustomData,
  verifySsvSignature,
} from "../_shared/admob_ssv.ts";
import { hmacSha256Hex } from "../_shared/crypto.ts";
import { json, requireEnv, safeErrorCode } from "../_shared/http.ts";

serve(async (req: Request) => {
  if (req.method !== "GET") {
    return json({ error_code: "METHOD_NOT_ALLOWED" }, 405, { Allow: "GET" });
  }
  try {
    const env = requireEnv([
      "SUPABASE_URL",
      "SUPABASE_SERVICE_ROLE_KEY",
      "ADMOB_SSV_MODE",
      "ADMOB_SSV_HASH_SECRET",
      "ADMOB_SSV_PUBLIC_KEY_URL",
      "ADMOB_SSV_KEY_CACHE_TTL_SECONDS",
      "ADMOB_SSV_MAX_AGE_SECONDS",
      "ADMOB_SSV_FUTURE_SKEW_SECONDS",
      "ADMOB_SSV_PRODUCTION_AD_UNITS",
      "ADMOB_SSV_TEST_AD_UNITS",
    ]);
    if (
      !new Set(["production", "test", "disabled"]).has(env.ADMOB_SSV_MODE) ||
      env.ADMOB_SSV_MODE === "disabled"
    ) {
      return json({ error_code: "SSV_DISABLED" }, 503);
    }
    if (
      env.ADMOB_SSV_HASH_SECRET.length < 32 ||
      !env.ADMOB_SSV_PUBLIC_KEY_URL.startsWith("https://")
    ) {
      throw new Error("INVALID_CONFIG");
    }
    const parsed = parseRawSsvQuery(req.url);
    if (parsed.values.ad_network !== "5450213213286189855") {
      throw new Error("INVALID_AD_NETWORK");
    }
    const allowed = new Set(
      (env.ADMOB_SSV_MODE === "production"
        ? env.ADMOB_SSV_PRODUCTION_AD_UNITS
        : env.ADMOB_SSV_TEST_AD_UNITS)
        .split(",").map((value) => value.trim()).filter(Boolean),
    );
    if (allowed.size === 0 || !allowed.has(parsed.values.ad_unit)) {
      throw new Error("AD_UNIT_NOT_ALLOWED");
    }
    const callbackDate = validateTimestamp(
      parsed.values.timestamp,
      Date.now(),
      positiveInt(env.ADMOB_SSV_MAX_AGE_SECONDS) * 1000,
      positiveInt(env.ADMOB_SSV_FUTURE_SKEW_SECONDS) * 1000,
    );
    const custom = await verifyCustomData(
      parsed.values.custom_data,
      env.ADMOB_SSV_HASH_SECRET,
    );
    const signatureValid = await verifySsvSignature(
      parsed,
      env.ADMOB_SSV_PUBLIC_KEY_URL,
      positiveInt(env.ADMOB_SSV_KEY_CACHE_TTL_SECONDS) * 1000,
    );
    if (!signatureValid) throw new Error("INVALID_SIGNATURE");

    // Test environment verifies the complete protocol but can never create economic credit.
    if (env.ADMOB_SSV_MODE === "test") {
      return new Response(null, { status: 204 });
    }
    const supabase = createClient(
      env.SUPABASE_URL,
      env.SUPABASE_SERVICE_ROLE_KEY,
      { auth: { persistSession: false } },
    );
    const transactionHash = await hmacSha256Hex(
      env.ADMOB_SSV_HASH_SECRET,
      parsed.values.transaction_id,
    );
    const customDataNonceHash = await hmacSha256Hex(
      env.ADMOB_SSV_HASH_SECRET,
      custom.nonce,
    );
    const providerUserHash = parsed.values.user_id
      ? await hmacSha256Hex(env.ADMOB_SSV_HASH_SECRET, parsed.values.user_id)
      : null;
    const { data, error } = await supabase.rpc("grant_verified_ad_points", {
      p_reward_session_id: custom.sessionId,
      // The SQL uniqueness contract is preserved with a deterministic HMAC;
      // the raw provider transaction identifier is never persisted.
      p_provider_transaction_id: transactionHash,
      p_provider_transaction_hash: transactionHash,
      p_ad_unit_id: parsed.values.ad_unit,
      p_signature_key_id: parsed.keyId,
      p_callback_timestamp: callbackDate.toISOString(),
      p_custom_data_nonce_hash: customDataNonceHash,
      p_provider_user_id_hash: providerUserHash,
    });
    if (error) throw new Error("GRANT_RPC_FAILED");
    return json({ status: "ok", duplicate: data?.duplicate === true }, 200, {
      "Cache-Control": "no-store",
    });
  } catch (error) {
    const code = safeErrorCode(error);
    console.error("admob_ssv_rejected", { code });
    const transient = code === "KEY_FETCH_FAILED" ||
      code === "GRANT_RPC_FAILED" || code.startsWith("MISSING_CONFIG:");
    return json({
      error_code: transient ? "TEMPORARY_VERIFICATION_FAILURE" : "SSV_REJECTED",
    }, transient ? 503 : 400);
  }
});

function positiveInt(value: string): number {
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed <= 0) {
    throw new Error("INVALID_CONFIG");
  }
  return parsed;
}

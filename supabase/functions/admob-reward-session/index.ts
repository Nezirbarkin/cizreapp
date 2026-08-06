import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import { hmacSha256Base64Url, hmacSha256Hex } from "./_shared/crypto.ts";
import {
  bearerToken,
  json,
  options,
  requireEnv,
  safeErrorCode,
} from "./_shared/http.ts";

serve(async (req: Request) => {
  if (req.method === "OPTIONS") return options("POST, OPTIONS");
  if (req.method !== "POST") {
    return json({ error_code: "METHOD_NOT_ALLOWED" }, 405, {
      Allow: "POST, OPTIONS",
    });
  }
  try {
    const env = requireEnv([
      "SUPABASE_URL",
      "SUPABASE_SERVICE_ROLE_KEY",
      "ADMOB_SSV_MODE",
      "ADMOB_SSV_HASH_SECRET",
    ]);
    if (
      !new Set(["production", "test", "disabled"]).has(env.ADMOB_SSV_MODE) ||
      env.ADMOB_SSV_MODE === "disabled"
    ) {
      return json({ error_code: "REWARD_SESSIONS_DISABLED" }, 503);
    }
    if (env.ADMOB_SSV_HASH_SECRET.length < 32) {
      throw new Error("INVALID_HASH_SECRET");
    }
    const token = bearerToken(req);
    if (!token) return json({ error_code: "UNAUTHORIZED" }, 401);
    const supabase = createClient(
      env.SUPABASE_URL,
      env.SUPABASE_SERVICE_ROLE_KEY,
      { auth: { persistSession: false } },
    );
    const { data: { user }, error: authError } = await supabase.auth.getUser(
      token,
    );
    if (authError || !user) return json({ error_code: "UNAUTHORIZED" }, 401);

    const body = await req.json().catch(() => ({}));
    const idempotencyKey = typeof body.idempotency_key === "string"
      ? body.idempotency_key.trim()
      : "";
    if (!/^[A-Za-z0-9_.:-]{8,200}$/u.test(idempotencyKey)) {
      return json({ error_code: "INVALID_IDEMPOTENCY_KEY" }, 400);
    }
    if (
      "user_id" in body || "reward" in body || "price" in body ||
      "amount" in body
    ) {
      return json({ error_code: "FORBIDDEN_CLIENT_FIELD" }, 400);
    }

    // Keyed deterministic nonce keeps retries on the DB idempotency key stable;
    // without the secret it remains computationally opaque and unpredictable.
    const nonce = await hmacSha256Base64Url(
      env.ADMOB_SSV_HASH_SECRET,
      `reward-session-nonce:v1:${user.id}:${idempotencyKey}`,
    );
    const nonceHash = await hmacSha256Hex(env.ADMOB_SSV_HASH_SECRET, nonce);
    const { data, error } = await supabase.rpc("create_ad_reward_session", {
      p_user_id: user.id,
      p_nonce_hash: nonceHash,
      p_client_idempotency_key: idempotencyKey,
      p_device_pseudonym_hash: null,
      p_network_pseudonym_hash: null,
    });
    if (error || !data?.reward_session_id) {
      throw new Error("SESSION_RPC_FAILED");
    }
    const prefix = `v1.${data.reward_session_id}.${nonce}`;
    const customData = `${prefix}.${await hmacSha256Base64Url(
      env.ADMOB_SSV_HASH_SECRET,
      prefix,
    )}`;
    return json(
      {
        reward_session_id: data.reward_session_id,
        custom_data: customData,
        status: data.status,
        expires_at: data.expires_at,
        policy_version: data.policy_version,
        environment: env.ADMOB_SSV_MODE,
      },
      201,
      { "Cache-Control": "no-store" },
    );
  } catch (error) {
    console.error("admob_reward_session_failed", {
      code: safeErrorCode(error),
    });
    return json({ error_code: "SESSION_UNAVAILABLE" }, 503);
  }
});

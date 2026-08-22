import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import { bearerToken, json, options, requireEnv } from "../_shared/http.ts";
import { sha256Hex } from "../_shared/crypto.ts";

// Profil özelliği (avatar/kapak dekorasyonu) satın alma — yalnızca PUAN ile.
// purchase_my_profile_feature_with_points RPC'si service_role-only olduğu
// için (bkz. 20260818000006 migration), bu Edge Function service-role
// anahtarını tutan tek meşru çağıran taraf. Kullanıcı kimliği her zaman
// doğrulanmış JWT'den alınır, client body'sinden asla güvenilmez.
serve(async (req: Request) => {
  if (req.method === "OPTIONS") return options("POST, OPTIONS");
  if (req.method !== "POST") {
    return json({ error_code: "METHOD_NOT_ALLOWED" }, 405, {
      Allow: "POST, OPTIONS",
    });
  }
  try {
    const env = requireEnv(["SUPABASE_URL", "SUPABASE_SERVICE_ROLE_KEY"]);
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
    if ("user_id" in body || "points" in body || "points_spent" in body) {
      return json({ error_code: "FORBIDDEN_CLIENT_FIELD" }, 400);
    }

    const featureId = String(body.feature_id ?? "");
    const plan = String(body.plan ?? "");
    const idempotency = String(
      req.headers.get("x-idempotency-key") ?? body.idempotency_key ?? "",
    ).trim();

    if (
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/iu.test(
        featureId,
      ) ||
      (plan !== "monthly" && plan !== "yearly") ||
      !/^[A-Za-z0-9_.:-]{8,160}$/u.test(idempotency)
    ) {
      return json({ error_code: "INVALID_INPUT" }, 400);
    }

    // Persisted ledger idempotency key sabit uzunlukta ve kullanıcıya göre
    // ad alanına ayrılmış olsun — smm-order-create'deki aynı desen.
    const serverKey = `profile-feature-purchase:${
      await sha256Hex(`${user.id}:${idempotency}`)
    }`;

    const { data, error: rpcError } = await supabase.rpc(
      "purchase_my_profile_feature_with_points",
      {
        p_user_id: user.id,
        p_feature_id: featureId,
        p_plan: plan,
        p_idempotency_key: serverKey,
      },
    );

    if (rpcError) {
      const message = rpcError.message ?? "";
      if (message.includes("INSUFFICIENT_POINTS")) {
        return json({ error_code: "INSUFFICIENT_POINTS" }, 402);
      }
      if (message.includes("REWARD_FEATURE_DISABLED")) {
        return json({ error_code: "REWARD_FEATURE_DISABLED" }, 503);
      }
      if (message.includes("satın alınabilir değildir")) {
        return json({ error_code: "FEATURE_NOT_PURCHASABLE" }, 404);
      }
      console.error("profile_feature_purchase_failed", {
        code: rpcError.code ?? "UNKNOWN",
      });
      return json({ error_code: "PURCHASE_FAILED" }, 400);
    }

    return json({ status: "success", ...(data as Record<string, unknown>) });
  } catch (error) {
    console.error("profile_feature_purchase_failed", {
      code: error instanceof Error ? error.message : "UNKNOWN",
    });
    return json({ error_code: "INTERNAL_ERROR" }, 500);
  }
});

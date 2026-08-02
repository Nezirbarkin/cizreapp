import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import {
  creditSellerOnce,
  cumulativeRefund,
  refundComposition,
  setReconciliation,
} from "../_shared/digital_orders.ts";
import { bearerToken, json, options, requireEnv } from "../_shared/http.ts";

const ALLOWED = new Set([
  "completed",
  "partial",
  "canceled",
  "refunded",
  "failed",
]);
serve(async (req: Request) => {
  if (req.method === "OPTIONS") return options("POST, OPTIONS");
  if (req.method !== "POST") {
    return json({ error_code: "METHOD_NOT_ALLOWED" }, 405);
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
    if ("price" in body || "refund_amount" in body || "composition" in body) {
      return json({ error_code: "FORBIDDEN_CLIENT_FIELD" }, 400);
    }
    const status = String(body.new_status ?? "");
    if (!body.digital_order_id || !ALLOWED.has(status)) {
      return json({ error_code: "INVALID_INPUT" }, 400);
    }
    const { data: order, error } = await supabase.from("digital_orders")
      .select(
        "id,user_id,product_id,provider_id,quantity,gross_total_try,status,seller_credited,external_order_id,reconciliation_status",
      )
      .eq("id", body.digital_order_id).single();
    if (error || !order) return json({ error_code: "NOT_FOUND" }, 404);
    const { data: profile } = await supabase.from("profiles").select("role").eq(
      "id",
      user.id,
    ).single();
    let authorized = profile?.role === "admin";
    if (!authorized) {
      const { data: provider } = await supabase.from("smm_providers").select(
        "owner_type,owner_id",
      ).eq("id", order.provider_id).single();
      const { data: shop } = await supabase.from("shops").select("id").eq(
        "owner_id",
        user.id,
      ).maybeSingle();
      authorized = provider?.owner_type === "seller" &&
        provider.owner_id === shop?.id;
    }
    if (!authorized) return json({ error_code: "FORBIDDEN" }, 403);
    if (["refunded", "canceled", "failed"].includes(order.status)) {
      return json({ error_code: "ORDER_CLOSED" }, 409);
    }

    const remains = Number(body.remains);
    if (
      status === "partial" &&
      (!Number.isInteger(remains) || remains < 0 || remains > order.quantity)
    ) {
      return json({ error_code: "INVALID_REMAINS" }, 400);
    }
    let refund: unknown = null;
    if (status === "canceled" || status === "refunded" || status === "failed") {
      // A privileged manual terminal decision is definitive, unlike network/provider ambiguity.
      refund = await refundComposition(
        supabase,
        order,
        status,
        Number(order.gross_total_try),
        `Yetkili manuel kesin ${status} kararı`,
        true,
      );
    } else if (status === "partial") {
      const cumulative = cumulativeRefund(
        Number(order.gross_total_try),
        order.quantity,
        remains,
        false,
      );
      await setReconciliation(supabase, order.id, "settled");
      if (cumulative > 0) {
        refund = await refundComposition(
          supabase,
          order,
          status,
          cumulative,
          "Yetkili manuel kesin kısmi teslim kararı",
          false,
        );
      }
      await creditSellerOnce(
        supabase,
        order,
        (order.quantity - remains) / order.quantity,
      );
    } else if (status === "completed") {
      await setReconciliation(supabase, order.id, "settled");
      await creditSellerOnce(supabase, order, 1);
    }
    // Economic side effects complete first. If this final status write fails,
    // a retry observes idempotent refund/seller-credit RPC results and can finish.
    const { error: statusError } = await supabase.from("digital_orders").update({
      status,
      remains: status === "partial" ? remains : null,
      updated_at: new Date().toISOString(),
    }).eq("id", order.id);
    if (statusError) throw new Error("ORDER_STATUS_UPDATE_FAILED");
    return json({ status: "success", new_status: status, refund });
  } catch (error) {
    console.error("smm_manual_status_failed", {
      code: error instanceof Error ? error.message : "UNKNOWN",
    });
    return json({ error_code: "INTERNAL_ERROR" }, 500);
  }
});

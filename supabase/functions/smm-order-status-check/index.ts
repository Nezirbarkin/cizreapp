import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import {
  creditSellerOnce,
  cumulativeRefund,
  mapProviderStatus,
  refundComposition,
  setReconciliation,
} from "../_shared/digital_orders.ts";
import { bearerToken, json, options, requireEnv } from "../_shared/http.ts";

serve(async (req: Request) => {
  if (req.method === "OPTIONS") return options("POST, OPTIONS");
  if (req.method !== "POST") {
    return json({ error_code: "METHOD_NOT_ALLOWED" }, 405);
  }
  try {
    const env = requireEnv([
      "SUPABASE_URL",
      "SUPABASE_SERVICE_ROLE_KEY",
      "CRON_SECRET",
    ]);
    const supabase = createClient(
      env.SUPABASE_URL,
      env.SUPABASE_SERVICE_ROLE_KEY,
      { auth: { persistSession: false } },
    );
    const isCron = req.headers.get("x-cron-secret") === env.CRON_SECRET;
    let userId: string | null = null;
    if (!isCron) {
      const token = bearerToken(req);
      if (!token) return json({ error_code: "UNAUTHORIZED" }, 401);
      const { data: { user }, error } = await supabase.auth.getUser(token);
      if (error || !user) return json({ error_code: "UNAUTHORIZED" }, 401);
      userId = user.id;
    }
    let query = supabase.from("digital_orders")
      .select(
        "id,user_id,product_id,provider_id,quantity,gross_total_try,status,seller_credited,external_order_id,reconciliation_status",
      )
      .in("status", ["pending", "in_progress"]).order("last_checked_at", {
        ascending: true,
        nullsFirst: true,
      }).limit(200);
    if (userId) query = query.eq("user_id", userId);
    const { data: orders, error } = await query;
    if (error) throw new Error("ORDER_FETCH_FAILED");
    let checked = 0, updated = 0, refunded = 0, reconciliationPending = 0;
    for (const order of orders ?? []) {
      if (!order.external_order_id) continue;
      const { data: provider } = await supabase.from("smm_providers").select(
        "api_url,api_key,is_active",
      ).eq("id", order.provider_id).single();
      if (!provider?.is_active) {
        await setReconciliation(supabase, order.id, "reconciliation_pending");
        reconciliationPending++;
        continue;
      }
      checked++;
      let response: Response;
      let result: unknown;
      try {
        response = await fetch(provider.api_url, {
          method: "POST",
          headers: { "Content-Type": "application/x-www-form-urlencoded" },
          body: new URLSearchParams({
            key: provider.api_key,
            action: "status",
            order: order.external_order_id,
          }),
          signal: AbortSignal.timeout(15_000),
        });
        result = JSON.parse(await response.text());
      } catch {
        await setReconciliation(supabase, order.id, "reconciliation_pending");
        reconciliationPending++;
        continue;
      }
      if (
        !response.ok || !isRecord(result) || result.error ||
        typeof result.status !== "string"
      ) {
        await setReconciliation(supabase, order.id, "reconciliation_pending");
        reconciliationPending++;
        continue;
      }
      const status = mapProviderStatus(result.status);
      const remains = result.remains == null ? null : Number(result.remains);
      const startCount = result.start_count == null
        ? null
        : Number(result.start_count);
      if (status === "canceled" || status === "refunded") {
        await refundComposition(
          supabase,
          order,
          status,
          Number(order.gross_total_try),
          `Sağlayıcı kesin ${status} sonucu`,
          true,
        );
        refunded++;
      } else if (
        status === "partial" && remains !== null && Number.isInteger(remains)
      ) {
        await setReconciliation(supabase, order.id, "settled");
        const cumulative = cumulativeRefund(
          Number(order.gross_total_try),
          order.quantity,
          remains,
          false,
        );
        if (cumulative > 0) {
          await refundComposition(
            supabase,
            order,
            status,
            cumulative,
            "Sağlayıcı kesin kısmi teslim sonucu",
            false,
          );
          refunded++;
        }
        await creditSellerOnce(
          supabase,
          order,
          (order.quantity - remains) / order.quantity,
        );
      } else if (status === "completed") {
        await setReconciliation(supabase, order.id, "settled");
        await creditSellerOnce(supabase, order, 1);
      } else await setReconciliation(supabase, order.id, "pending_provider");
      // Persist provider status only after economic mutations succeed. DB RPCs
      // make retries safe if this final state write fails.
      const { error: updateError } = await supabase.from("digital_orders").update({
        status,
        remains,
        start_count: startCount,
        last_checked_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      }).eq("id", order.id);
      if (updateError) throw new Error("ORDER_STATUS_UPDATE_FAILED");
      if (status !== order.status) updated++;
    }
    return json({
      status: "success",
      checked,
      updated,
      refunded,
      reconciliation_pending: reconciliationPending,
    });
  } catch (error) {
    console.error("smm_status_check_failed", {
      code: error instanceof Error ? error.message : "UNKNOWN",
    });
    return json({ error_code: "INTERNAL_ERROR" }, 500);
  }
});

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object";
}

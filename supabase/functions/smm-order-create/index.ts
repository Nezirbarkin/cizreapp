import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import {
  refundComposition,
  setReconciliation,
} from "../_shared/digital_orders.ts";
import { bearerToken, json, options, requireEnv } from "../_shared/http.ts";
import { sha256Hex } from "../_shared/crypto.ts";

interface OrderReservation {
  digital_order_id: string;
  provider_id: string;
  smm_service_id: string;
  gross_total_try: unknown;
  points_spent: unknown;
  points_discount_try: unknown;
  cash_paid_try: unknown;
  duplicate?: boolean;
}

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
    if (
      "price" in body || "total_price" in body || "composition" in body ||
      "user_id" in body
    ) {
      return json({ error_code: "FORBIDDEN_CLIENT_FIELD" }, 400);
    }
    const idempotency = String(
      req.headers.get("x-idempotency-key") ?? body.idempotency_key ?? "",
    ).trim();
    const quantity = Number(body.quantity);
    if (
      !/^[A-Za-z0-9_.:-]{8,160}$/u.test(idempotency) || !body.product_id ||
      typeof body.target_url !== "string" ||
      !Number.isInteger(quantity) || quantity <= 0
    ) return json({ error_code: "INVALID_INPUT" }, 400);
    // Keep the persisted key fixed-length and opaque. The client key may be up
    // to 160 chars, while DB/ledger idempotency keys are intentionally capped.
    const serverKey = `smm-create:${await sha256Hex(`${user.id}:${idempotency}`)}`;
    const { data, error: rpcError } = await supabase.rpc(
      "create_digital_order_with_points",
      {
        p_user_id: user.id,
        p_product_id: body.product_id,
        p_target_url: body.target_url,
        p_quantity: quantity,
        p_idempotency_key: serverKey,
        p_use_points: body.use_points !== false,
      },
    );
    if (rpcError || !isOrderReservation(data)) {
      return json({ error_code: "ORDER_RESERVATION_FAILED" }, 400);
    }
    const orderData = data;
    if (orderData.duplicate) {
      // The RPC deliberately returns no provider service/external id on the
      // duplicate branch. Never repeat an ambiguous non-idempotent provider add.
      const { data: existing } = await supabase.from("digital_orders")
        .select("external_order_id,status,reconciliation_status")
        .eq("id", orderData.digital_order_id).single();
      if (existing?.external_order_id) {
        return json({
          status: "success",
          digital_order_id: orderData.digital_order_id,
          external_order_id: existing.external_order_id,
          ...publicComposition(orderData),
          duplicate: true,
        });
      }
      await setReconciliation(
        supabase,
        orderData.digital_order_id,
        "reconciliation_pending",
      );
      return json({
        status: "reconciliation_pending",
        digital_order_id: orderData.digital_order_id,
        duplicate: true,
        refunded: false,
      }, 202);
    }

    const order = {
      id: orderData.digital_order_id,
      gross_total_try: Number(orderData.gross_total_try),
    };
    const { data: provider, error: providerError } = await supabase.from(
      "smm_providers",
    )
      .select("api_url, api_key, is_active").eq("id", orderData.provider_id)
      .single();
    if (providerError || !provider?.is_active) {
      await refundComposition(
        supabase,
        order,
        "failed",
        order.gross_total_try,
        "Sağlayıcı yapılandırması kesin olarak kullanılamıyor",
        true,
      );
      await supabase.from("digital_orders").update({
        status: "failed",
        error_message: "PROVIDER_UNAVAILABLE",
      }).eq("id", order.id);
      return json({ error_code: "PROVIDER_UNAVAILABLE", refunded: true }, 502);
    }
    let response: Response;
    let result: unknown;
    try {
      response = await fetch(provider.api_url, {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: new URLSearchParams({
          key: provider.api_key,
          action: "add",
          service: String(orderData.smm_service_id),
          link: body.target_url,
          quantity: String(quantity),
        }),
        signal: AbortSignal.timeout(15_000),
      });
      const text = await response.text();
      result = JSON.parse(text);
    } catch {
      await setReconciliation(supabase, order.id, "reconciliation_pending");
      return json({
        status: "reconciliation_pending",
        digital_order_id: order.id,
        refunded: false,
      }, 202);
    }
    if (!response.ok || !isRecord(result)) {
      await setReconciliation(supabase, order.id, "reconciliation_pending");
      return json({
        status: "reconciliation_pending",
        digital_order_id: order.id,
        refunded: false,
      }, 202);
    }
    if (result.error || !result.order) {
      await refundComposition(
        supabase,
        order,
        "failed",
        order.gross_total_try,
        "Sağlayıcı siparişi kesin olarak reddetti",
        true,
      );
      await supabase.from("digital_orders").update({
        status: "failed",
        error_message: "PROVIDER_REJECTED",
      }).eq("id", order.id);
      return json({ error_code: "PROVIDER_REJECTED", refunded: true }, 400);
    }
    await supabase.from("digital_orders").update({
      external_order_id: String(result.order),
      status: "in_progress",
      last_checked_at: new Date().toISOString(),
    }).eq("id", order.id);
    await setReconciliation(supabase, order.id, "pending_provider");
    return json({
      status: "success",
      digital_order_id: order.id,
      external_order_id: String(result.order),
      ...publicComposition(orderData),
    });
  } catch (error) {
    console.error("smm_order_create_failed", {
      code: error instanceof Error ? error.message : "UNKNOWN",
    });
    return json({ error_code: "INTERNAL_ERROR" }, 500);
  }
});

function publicComposition(data: OrderReservation) {
  return {
    gross_total_try: data.gross_total_try,
    points_spent: data.points_spent,
    points_discount_try: data.points_discount_try,
    cash_paid_try: data.cash_paid_try,
  };
}

function isOrderReservation(value: unknown): value is OrderReservation {
  return isRecord(value) && typeof value.digital_order_id === "string" &&
    typeof value.provider_id === "string" &&
    typeof value.smm_service_id === "string";
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object";
}

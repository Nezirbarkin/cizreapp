// Paket (sabit fiyat, manuel teslim) dijital siparişini kapatır.
//
// Paket siparişinde sağlayıcı yoktur (digital_orders.provider_id NULL,
// delivery_mode = 'manual'); satıcı teslimi kendisi yapar ve buradan:
//   * completed → mutabakat 'settled' + satıcıya bir kez net kazanç
//     (credit_digital_order_seller, mağazanın dijital komisyonu düşülür)
//   * canceled  → tam iade, puan puana / TL TL bakiyeye
//     (refund_digital_order_payment, kesin)
// Yetki: admin ya da ürünün mağaza sahibi. Kısmi teslim yoktur (adet = 1).
// Alıcı bildirimi DB tetikleyicisinden gelir (notify_manual_digital_order).
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import {
  creditSellerOnce,
  refundComposition,
  setReconciliation,
} from "../_shared/digital_orders.ts";
import { bearerToken, json, options, requireEnv } from "../_shared/http.ts";

const ALLOWED = new Set(["completed", "canceled"]);

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
        "id,user_id,product_id,provider_id,quantity,gross_total_try,status,seller_credited,external_order_id,reconciliation_status,delivery_mode",
      )
      .eq("id", body.digital_order_id).maybeSingle();
    if (error || !order) return json({ error_code: "NOT_FOUND" }, 404);
    if (order.delivery_mode !== "manual" || order.provider_id != null) {
      return json({ error_code: "NOT_PACKAGE_ORDER" }, 400);
    }

    const { data: profile } = await supabase.from("profiles").select("role").eq(
      "id",
      user.id,
    ).maybeSingle();
    let authorized = profile?.role === "admin";
    if (!authorized) {
      const { data: product } = await supabase.from("products").select(
        "shop_id",
      ).eq("id", order.product_id).maybeSingle();
      if (product?.shop_id) {
        const { data: shop } = await supabase.from("shops").select("owner_id")
          .eq("id", product.shop_id).maybeSingle();
        authorized = shop?.owner_id === user.id;
      }
    }
    if (!authorized) return json({ error_code: "FORBIDDEN" }, 403);

    // Aynı karar tekrar gelirse (ağ tekrarı) başarı döner; ters karar reddedilir.
    if (order.status === status) {
      return json({ status: "success", new_status: status, duplicate: true });
    }
    if (order.status !== "pending" && order.status !== "in_progress") {
      return json({ error_code: "ORDER_CLOSED" }, 409);
    }

    let refund: unknown = null;
    if (status === "canceled") {
      refund = await refundComposition(
        supabase,
        order,
        status,
        Number(order.gross_total_try),
        "Satıcı/yetkili paket siparişini iptal etti",
        true,
      );
    } else {
      await setReconciliation(supabase, order.id, "settled");
      await creditSellerOnce(supabase, order, 1);
    }
    // Ekonomik yan etkiler önce; bu son yazım düşerse tekrar deneme
    // idempotent RPC sonuçlarını görür ve tamamlar.
    const { error: statusError } = await supabase.from("digital_orders").update({
      status,
      updated_at: new Date().toISOString(),
    }).eq("id", order.id);
    if (statusError) throw new Error("ORDER_STATUS_UPDATE_FAILED");
    return json({ status: "success", new_status: status, refund });
  } catch (error) {
    console.error("digital_package_order_status_failed", {
      code: error instanceof Error ? error.message : "UNKNOWN",
    });
    return json({ error_code: "INTERNAL_ERROR" }, 500);
  }
});

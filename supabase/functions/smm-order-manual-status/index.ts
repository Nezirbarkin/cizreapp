import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import {
  creditSellerOnce,
  cumulativeRefund,
  refundComposition,
  setReconciliation,
} from "../_shared/digital_orders.ts";
import { bearerToken, json, options, requireEnv } from "../_shared/http.ts";

// Alıcı bildirimi DB tetikleyicisinden gelir (notify_digital_order_status,
// yönetici kazanç bildirimi notify_digital_order_seller_credit); burada
// notifications'a yazılmaz, yoksa çift bildirim olur.

const ALLOWED = new Set([
  "completed",
  "partial",
  "canceled",
  "refunded",
  "failed",
]);

// Yayındaki istemci (smm_service.dart) hata metnini `error` alanından
// gösterir; `error_code` makine içindir.
const ERROR_TEXT: Record<string, string> = {
  METHOD_NOT_ALLOWED: "Geçersiz istek.",
  UNAUTHORIZED: "Oturumunuz geçersiz, lütfen tekrar giriş yapın.",
  FORBIDDEN_CLIENT_FIELD: "Geçersiz istek.",
  INVALID_INPUT: "Geçerli bir sipariş ve durum seçin.",
  NOT_FOUND: "Sipariş bulunamadı.",
  USE_PACKAGE_ORDER_STATUS:
    "Paket siparişleri Dijital Siparişler'deki paket teslim düğmesiyle kapatılır.",
  FORBIDDEN: "Bu siparişi değiştirme yetkiniz yok.",
  ORDER_CLOSED: "Bu sipariş zaten kapanmış, durumu değiştirilemez.",
  SELLER_ALREADY_CREDITED:
    "Satıcıya kazancı aktarılmış siparişte iade veya kısmi teslim yapılamaz.",
  INVALID_REMAINS: "Kalan miktar 0 ile sipariş adedi arasında olmalı.",
  INTERNAL_ERROR: "Durum güncellenemedi.",
};

function fail(code: string, status: number): Response {
  return json({ error_code: code, error: ERROR_TEXT[code] }, status);
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") return options("POST, OPTIONS");
  if (req.method !== "POST") return fail("METHOD_NOT_ALLOWED", 405);
  try {
    const env = requireEnv(["SUPABASE_URL", "SUPABASE_SERVICE_ROLE_KEY"]);
    const token = bearerToken(req);
    if (!token) return fail("UNAUTHORIZED", 401);
    const supabase = createClient(
      env.SUPABASE_URL,
      env.SUPABASE_SERVICE_ROLE_KEY,
      { auth: { persistSession: false } },
    );
    const { data: { user }, error: authError } = await supabase.auth.getUser(
      token,
    );
    if (authError || !user) return fail("UNAUTHORIZED", 401);
    const body = await req.json().catch(() => ({}));
    if ("price" in body || "refund_amount" in body || "composition" in body) {
      return fail("FORBIDDEN_CLIENT_FIELD", 400);
    }
    const status = String(body.new_status ?? "");
    if (!body.digital_order_id || !ALLOWED.has(status)) {
      return fail("INVALID_INPUT", 400);
    }
    const { data: order, error } = await supabase.from("digital_orders")
      .select(
        "id,user_id,product_id,provider_id,quantity,gross_total_try,status,seller_credited,external_order_id,reconciliation_status",
      )
      .eq("id", body.digital_order_id).single();
    if (error || !order) return fail("NOT_FOUND", 404);
    const { data: profile } = await supabase.from("profiles").select("role").eq(
      "id",
      user.id,
    ).single();
    // Paket (manuel teslim) siparişleri yalnız digital-package-order-status
    // ile kapatılır; sağlayıcısı olmadığı için buradaki yetki/kısmi teslim
    // mantığı onlara uymaz.
    if (order.provider_id == null) return fail("USE_PACKAGE_ORDER_STATUS", 409);
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
    if (!authorized) return fail("FORBIDDEN", 403);
    if (["refunded", "canceled", "failed"].includes(order.status)) {
      return fail("ORDER_CLOSED", 409);
    }
    // refund_digital_order_payment kazancı aktarılmış siparişte iadeyi zaten
    // reddeder; önceden durmak hem anlaşılır hata verir hem de 'partial'
    // yolunda iade öncesi mutabakat yazımını önler. (Eski 07-13 sürümüyle
    // tamamlanmış siparişler de buraya düşer: seller_credited = true.)
    if (order.seller_credited && status !== "completed") {
      return fail("SELLER_ALREADY_CREDITED", 409);
    }

    const remains = Number(body.remains);
    if (
      status === "partial" &&
      (!Number.isInteger(remains) || remains < 0 || remains > order.quantity)
    ) {
      return fail("INVALID_REMAINS", 400);
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
    return fail("INTERNAL_ERROR", 500);
  }
});

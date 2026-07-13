// smm-order-manual-status Edge Function
// Admin veya provider'ı sahiplenen satıcı, bir dijital siparişin durumunu manuel değiştirebilir.
// completed/partial -> satıcıya kazanç kredisi (idempotent), canceled/refunded -> müşteriye tam iade.
// Deploy: supabase functions deploy smm-order-manual-status

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.38.4";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const ALLOWED_STATUSES = ["completed", "partial", "canceled", "refunded", "failed"];

interface DigitalOrderRow {
  id: string;
  user_id: string;
  product_id: string;
  quantity: number;
  total_price: number;
  status: string;
  seller_credited: boolean;
}

// Not: bu yardımcı fonksiyonlar smm-order-status-check/index.ts içinde de bilerek TEKRARLANIYOR.
// Supabase'in tekli-fonksiyon deploy modu (bazı CLI/Dashboard akışları) sibling `_shared/` klasörünü
// pakete dahil etmiyor ("Module not found _shared/...") - bu yüzden paylaşılan modül importu KULLANILMIYOR.

async function refundCustomer(
  supabase: any,
  order: DigitalOrderRow,
  amount: number,
  reason: string,
): Promise<void> {
  if (amount <= 0) return;
  await supabase.rpc("add_to_balance", {
    p_user_id: order.user_id,
    p_amount: amount,
    p_type: "refund",
    p_reference_type: "digital_order",
    p_reference_id: order.id,
    p_description: reason,
  });
}

async function notifyAdmins(
  supabase: any,
  title: string,
  content: string,
  data: Record<string, unknown>,
): Promise<void> {
  try {
    const { data: admins, error } = await supabase.from("profiles").select("id").eq("role", "admin");
    if (error || !admins || admins.length === 0) return;
    const rows = admins.map((a: { id: string }) => ({
      user_id: a.id,
      type: "digital_order_commission",
      title,
      content,
      data,
      is_read: false,
      created_at: new Date().toISOString(),
    }));
    await supabase.from("notifications").insert(rows);
  } catch (err) {
    console.error("❌ Admin bildirimi gönderilemedi:", (err as Error).message);
  }
}

async function notifyCustomer(
  supabase: any,
  userId: string,
  title: string,
  content: string,
  data: Record<string, unknown>,
): Promise<void> {
  try {
    await supabase.from("notifications").insert({
      user_id: userId,
      type: "digital_order_status",
      title,
      content,
      data,
      is_read: false,
      created_at: new Date().toISOString(),
    });
  } catch (err) {
    console.error("❌ Müşteri bildirimi gönderilemedi:", (err as Error).message);
  }
}

async function creditSellerIfNeeded(
  supabase: any,
  order: DigitalOrderRow,
  deliveredRatio: number,
): Promise<void> {
  if (order.seller_credited) return;

  const { data: product, error: productError } = await supabase
    .from("products")
    .select("shop_id, name")
    .eq("id", order.product_id)
    .single();
  if (productError || !product) {
    console.error(`❌ Satıcı kredisi: ürün bulunamadı (order ${order.id})`, productError?.message);
    return;
  }

  const { data: shop, error: shopError } = await supabase
    .from("shops")
    .select("owner_id, digital_commission_rate, name")
    .eq("id", product.shop_id)
    .single();
  if (shopError || !shop) {
    console.error(`❌ Satıcı kredisi: mağaza bulunamadı (order ${order.id})`, shopError?.message);
    return;
  }

  const grossAmount = Math.round(order.total_price * deliveredRatio * 100) / 100;
  if (grossAmount <= 0) return;

  // Dijital ürün komisyonu fiziksel siparişlerin commission_rate'inden AYRI tutulur.
  // Admin belirlemediyse (NULL) varsayılan %10 uygulanır.
  const commissionRate = shop.digital_commission_rate ?? 10;
  const commissionAmount = Math.round((grossAmount * commissionRate / 100) * 100) / 100;
  const netAmount = Math.round((grossAmount - commissionAmount) * 100) / 100;

  await supabase.rpc("add_to_balance", {
    p_user_id: shop.owner_id,
    p_amount: netAmount,
    p_type: "commission",
    p_reference_type: "digital_order",
    p_reference_id: order.id,
    p_description: `Dijital ürün satışı kazancı - ${product.name}`,
  });

  await supabase
    .from("digital_orders")
    .update({ seller_credited: true, commission_amount: commissionAmount, net_seller_amount: netAmount })
    .eq("id", order.id);

  await notifyAdmins(
    supabase,
    "Dijital Sipariş Kazancı",
    `${shop.name} mağazasına ${product.name} satışından ₺${netAmount.toFixed(2)} kazanç eklendi (komisyon: ₺${commissionAmount.toFixed(2)}).`,
    { digital_order_id: order.id, shop_id: product.shop_id },
  );
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const supabase = createClient(supabaseUrl, supabaseServiceKey);

  try {
    const authHeader = req.headers.get("authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    const { data: { user }, error: authError } = await supabase.auth.getUser(
      authHeader.replace("Bearer ", "")
    );
    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Geçersiz oturum" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const body = await req.json();
    const { digital_order_id, new_status, remains } = body;

    if (!digital_order_id || !new_status || !ALLOWED_STATUSES.includes(new_status)) {
      return new Response(JSON.stringify({ error: "digital_order_id ve geçerli bir new_status zorunludur" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    if (new_status === "partial" && (remains == null || remains < 0)) {
      return new Response(JSON.stringify({ error: "Kısmi durum için geçerli remains zorunludur" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const { data: order, error: orderError } = await supabase
      .from("digital_orders")
      .select("id, user_id, product_id, provider_id, quantity, total_price, status, seller_credited, external_order_id, start_count")
      .eq("id", digital_order_id)
      .single();
    if (orderError || !order) {
      console.error("❌ Sipariş sorgu hatası:", orderError?.message, orderError?.details);
      return new Response(JSON.stringify({
        error: "Sipariş bulunamadı",
        debug_detail: orderError?.message,
      }), {
        status: 404,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Yetki kontrolü: admin VEYA bu provider'ı sahiplenen satıcı
    const { data: profile } = await supabase.from("profiles").select("role").eq("id", user.id).single();
    const isAdmin = profile?.role === "admin";

    if (!isAdmin) {
      const { data: provider } = await supabase
        .from("smm_providers")
        .select("owner_type, owner_id")
        .eq("id", order.provider_id)
        .single();
      const { data: shop } = await supabase.from("shops").select("id").eq("owner_id", user.id).maybeSingle();
      const ownsProvider = provider?.owner_type === "seller" && shop && provider.owner_id === shop.id;
      if (!ownsProvider) {
        return new Response(JSON.stringify({ error: "Bu siparişi değiştirme yetkiniz yok" }), {
          status: 403,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }
    }

    if (order.status === "refunded" || order.status === "canceled" || order.status === "failed") {
      return new Response(JSON.stringify({ error: "Bu sipariş zaten kapanmış, durumu değiştirilemez" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Sağlayıcıdan gerçek başlangıç miktarını (start_count) çek - manuel durum değişikliğinde de
    // bu bilgi eksik kalmasın. Sorgu başarısız olursa manuel işlemi engellemez, sadece atlanır.
    let providerStartCount: number | null = order.start_count ?? null;
    if (order.external_order_id) {
      try {
        const { data: provider } = await supabase
          .from("smm_providers")
          .select("api_url, api_key")
          .eq("id", order.provider_id)
          .single();
        if (provider) {
          const res = await fetch(provider.api_url, {
            method: "POST",
            headers: { "Content-Type": "application/x-www-form-urlencoded" },
            body: new URLSearchParams({
              key: provider.api_key,
              action: "status",
              order: order.external_order_id,
            }),
          });
          const smmResult = await res.json();
          if (smmResult?.start_count != null) {
            providerStartCount = parseInt(smmResult.start_count, 10);
          }
        }
      } catch (err) {
        console.error(`❌ Başlangıç miktarı sağlayıcıdan alınamadı (order ${order.id}):`, (err as Error).message);
      }
    }

    const updatePayload: Record<string, unknown> = {
      status: new_status,
      start_count: providerStartCount,
      last_checked_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    };
    if (new_status === "partial") updatePayload.remains = remains;

    await supabase.from("digital_orders").update(updatePayload).eq("id", digital_order_id);

    let refundAmount = 0;
    if (new_status === "canceled" || new_status === "refunded") {
      refundAmount = order.total_price;
      await refundCustomer(supabase, order, refundAmount, "Sipariş manuel olarak iptal/iade edildi - otomatik iade");
      await notifyCustomer(
        supabase,
        order.user_id,
        "Dijital Siparişiniz İade Edildi",
        `Siparişiniz iptal/iade edildi ve bakiyenize ₺${refundAmount.toFixed(2)} eklendi.`,
        { digital_order_id, status: new_status },
      );
    } else if (new_status === "completed") {
      await creditSellerIfNeeded(supabase, order, 1);
      await notifyCustomer(
        supabase,
        order.user_id,
        "Dijital Siparişiniz Tamamlandı",
        "Siparişiniz tamamlandı olarak işaretlendi.",
        { digital_order_id, status: new_status },
      );
    } else if (new_status === "partial") {
      refundAmount = Math.round((order.total_price * remains / order.quantity) * 100) / 100;
      await refundCustomer(supabase, order, refundAmount, "Dijital sipariş kısmi teslim - fark iadesi");
      const deliveredRatio = (order.quantity - remains) / order.quantity;
      await creditSellerIfNeeded(supabase, order, deliveredRatio);
      await notifyCustomer(
        supabase,
        order.user_id,
        "Dijital Siparişiniz Kısmi Tamamlandı",
        `Siparişinizin bir kısmı tamamlandı, ₺${refundAmount.toFixed(2)} bakiyenize iade edildi.`,
        { digital_order_id, status: new_status },
      );
    }

    return new Response(JSON.stringify({ status: "success", new_status, refund_amount: refundAmount }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err: unknown) {
    const error = err as Error;
    console.error("❌ smm-order-manual-status error:", error.message);
    return new Response(JSON.stringify({ status: "error", error: error.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});

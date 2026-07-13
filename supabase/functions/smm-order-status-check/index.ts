// smm-order-status-check Edge Function
// Bekleyen dijital siparişlerin durumunu sağlayıcıdan sorgular, günceller, gerekirse otomatik iade eder.
// Deploy: supabase functions deploy smm-order-status-check
// Cron: Supabase Dashboard -> Cron -> */5 * * * * -> POST bu fonksiyona, header: x-cron-secret: <CRON_SECRET>

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.38.4";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

interface DigitalOrderRow {
  id: string;
  user_id: string;
  product_id: string;
  quantity: number;
  total_price: number;
  status: string;
  seller_credited: boolean;
}

// Not: bu yardımcı fonksiyonlar smm-order-manual-status/index.ts içinde de bilerek TEKRARLANIYOR.
// Supabase'in tekli-fonksiyon deploy modu sibling `_shared/` klasörünü pakete dahil etmiyor
// ("Module not found _shared/...") - bu yüzden paylaşılan modül importu KULLANILMIYOR.

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

function mapProviderStatus(raw: string): string {
  const s = (raw || "").toLowerCase();
  if (s.includes("progress") || s.includes("processing")) return "in_progress";
  if (s.includes("complete")) return "completed";
  if (s.includes("partial")) return "partial";
  if (s.includes("cancel")) return "canceled";
  if (s.includes("refund")) return "refunded";
  return "pending";
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const supabase = createClient(supabaseUrl, supabaseServiceKey);

  try {
    const cronSecret = req.headers.get("x-cron-secret");
    const expectedCronSecret = Deno.env.get("CRON_SECRET");
    const isCron = !!cronSecret && !!expectedCronSecret && cronSecret === expectedCronSecret;

    let userId: string | null = null;
    if (!isCron) {
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
      userId = user.id;
    }

    let query = supabase
      .from("digital_orders")
      .select("id, provider_id, product_id, quantity, total_price, external_order_id, status, user_id, seller_credited")
      .in("status", ["pending", "in_progress"])
      .order("last_checked_at", { ascending: true, nullsFirst: true })
      .limit(200);

    if (!isCron && userId) {
      query = query.eq("user_id", userId);
    }

    const { data: orders, error: fetchError } = await query;
    if (fetchError) {
      throw new Error(fetchError.message);
    }

    // Provider bilgilerini (api_url/api_key) ayrı sorguyla çek - embed/join kullanmıyoruz
    // çünkü PostgREST ilişki cache'i güncel olmayabilir ve embed sessizce null dönebilir.
    const providerIds = [...new Set((orders || []).map((o) => o.provider_id))];
    const providersById = new Map<string, { api_url: string; api_key: string }>();
    if (providerIds.length > 0) {
      const { data: providers, error: providersError } = await supabase
        .from("smm_providers")
        .select("id, api_url, api_key")
        .in("id", providerIds);
      if (providersError) throw new Error(providersError.message);
      for (const p of providers || []) {
        providersById.set(p.id, { api_url: p.api_url, api_key: p.api_key });
      }
    }

    let checked = 0;
    let updated = 0;
    let refunded = 0;
    const debugLog: any[] = [];

    for (const order of orders || []) {
      const provider = providersById.get(order.provider_id);
      if (!order.external_order_id || !provider) {
        debugLog.push({ order_id: order.id, skipped: true, reason: !order.external_order_id ? "no external_order_id" : "provider not found" });
        continue;
      }
      checked++;

      let smmResult: any;
      try {
        const res = await fetch(provider.api_url, {
          method: "POST",
          headers: { "Content-Type": "application/x-www-form-urlencoded" },
          body: new URLSearchParams({
            key: provider.api_key,
            action: "status",
            order: order.external_order_id,
          }),
        });
        smmResult = await res.json();
      } catch (err) {
        console.error(`❌ Durum sorgu hatası (order ${order.id}):`, (err as Error).message);
        debugLog.push({ order_id: order.id, fetchError: (err as Error).message });
        continue;
      }

      debugLog.push({ order_id: order.id, providerRawStatus: smmResult?.status, providerResponse: smmResult });

      if (!smmResult || smmResult.error) continue;

      const newStatus = mapProviderStatus(smmResult.status);
      const startCount = smmResult.start_count != null ? parseInt(smmResult.start_count, 10) : null;
      const remains = smmResult.remains != null ? parseInt(smmResult.remains, 10) : null;

      if (newStatus === order.status) {
        await supabase
          .from("digital_orders")
          .update({ last_checked_at: new Date().toISOString(), start_count: startCount, remains })
          .eq("id", order.id);
        continue;
      }

      await supabase
        .from("digital_orders")
        .update({
          status: newStatus,
          start_count: startCount,
          remains,
          last_checked_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        })
        .eq("id", order.id);
      updated++;

      if (newStatus === "canceled" || newStatus === "refunded") {
        try {
          await refundCustomer(
            supabase,
            order,
            order.total_price,
            `Dijital sipariş ${newStatus === "canceled" ? "iptal edildi" : "iade edildi"} - otomatik iade`,
          );
          refunded++;
        } catch (refundErr) {
          console.error(`❌ Otomatik iade başarısız (order ${order.id}):`, (refundErr as Error).message);
        }
        await notifyCustomer(
          supabase,
          order.user_id,
          "Dijital Siparişiniz İade Edildi",
          `Siparişiniz ${newStatus === "canceled" ? "iptal edildi" : "iade edildi"} ve bakiyenize ₺${order.total_price.toFixed(2)} eklendi.`,
          { digital_order_id: order.id, status: newStatus },
        );
      } else if (newStatus === "completed") {
        try {
          await creditSellerIfNeeded(supabase, order, 1);
        } catch (creditErr) {
          console.error(`❌ Satıcı kredisi başarısız (order ${order.id}):`, (creditErr as Error).message);
        }
        await notifyCustomer(
          supabase,
          order.user_id,
          "Dijital Siparişiniz Tamamlandı",
          "Siparişiniz sağlayıcı tarafından tamamlandı.",
          { digital_order_id: order.id, status: newStatus },
        );
      } else if (newStatus === "partial" && remains != null && remains > 0 && order.quantity > 0) {
        const refundAmount = Math.round((order.total_price * remains / order.quantity) * 100) / 100;
        try {
          await refundCustomer(supabase, order, refundAmount, "Dijital sipariş kısmi teslim - fark iadesi");
          refunded++;
        } catch (refundErr) {
          console.error(`❌ Kısmi iade başarısız (order ${order.id}):`, (refundErr as Error).message);
        }
        try {
          const deliveredRatio = (order.quantity - remains) / order.quantity;
          await creditSellerIfNeeded(supabase, order, deliveredRatio);
        } catch (creditErr) {
          console.error(`❌ Kısmi satıcı kredisi başarısız (order ${order.id}):`, (creditErr as Error).message);
        }
        await notifyCustomer(
          supabase,
          order.user_id,
          "Dijital Siparişiniz Kısmi Tamamlandı",
          `Siparişinizin bir kısmı tamamlandı, kalan tutar bakiyenize iade edildi.`,
          { digital_order_id: order.id, status: newStatus },
        );
      }
    }

    return new Response(JSON.stringify({
      status: "success",
      checked,
      updated,
      refunded,
      // Sadece manuel (kullanıcı JWT'si ile) çağrıda debug bilgisi dön - cron çağrısında gereksiz.
      debug: isCron ? undefined : debugLog,
    }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err: unknown) {
    const error = err as Error;
    console.error("❌ smm-order-status-check error:", error.message);
    return new Response(JSON.stringify({ status: "error", error: error.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});

// smm-sync-products Edge Function
// Sağlayıcıda bir servis kaldırılmış/değiştirilmişse, o servise bağlı dijital ürünü otomatik
// olarak satışa kapatır (is_available=false) ve müşteri ekranında görünmez olur. Servis
// sağlayıcıda tekrar mevcutsa ve önceden bu mekanizma yüzünden kapatılmışsa otomatik açar.
// Ayrıca servisin min/max miktar aralığı sağlayıcıda değiştiyse ürünün min_quantity/max_quantity
// alanlarını otomatik günceller; böylece müşteri ekranındaki miktar aralığı ve sunucu tarafı
// sipariş doğrulaması sağlayıcıyla uyumlu kalır.
// Deploy: supabase functions deploy smm-sync-products
// Cron: Supabase Dashboard -> Cron -> saatte bir -> POST bu fonksiyona, header: x-cron-secret: <CRON_SECRET>

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { getAdminClient } from "../_shared/client.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  const supabase = getAdminClient();

  try {
    const cronSecret = req.headers.get("x-cron-secret");
    const expectedCronSecret = Deno.env.get("CRON_SECRET");
    if (cronSecret !== expectedCronSecret) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const { data: providers, error: providersError } = await supabase
      .from("smm_providers")
      .select("id, api_url, api_key")
      .eq("is_active", true);
    if (providersError) throw new Error(providersError.message);

    let checkedProviders = 0;
    let disabled = 0;
    let reEnabled = 0;
    let rangeUpdated = 0;

    for (const provider of providers || []) {
      let services: any[];
      try {
        const res = await fetch(provider.api_url, {
          method: "POST",
          headers: { "Content-Type": "application/x-www-form-urlencoded" },
          body: new URLSearchParams({ key: provider.api_key, action: "services" }),
        });
        const json = await res.json();
        if (!Array.isArray(json)) continue;
        services = json;
      } catch (err) {
        console.error(`❌ Servis listesi alınamadı (provider ${provider.id}):`, (err as Error).message);
        continue;
      }
      checkedProviders++;

      const availableServiceIds = new Set(services.map((s: any) => String(s.service)));

      // Sağlayıcının bildirdiği miktar aralıkları (servis ID -> {min, max}).
      // API'ler min/max'i çoğu zaman string döndürdüğü için sayıya çevrilir.
      const serviceRanges = new Map<string, { min: number; max: number }>();
      for (const s of services) {
        const min = Number.parseInt(String(s.min ?? ""), 10);
        const max = Number.parseInt(String(s.max ?? ""), 10);
        if (!Number.isFinite(min) || !Number.isFinite(max)) continue;
        if (min <= 0 || max < min) continue;
        serviceRanges.set(String(s.service), { min, max });
      }

      const { data: products, error: productsError } = await supabase
        .from("products")
        .select("id, smm_service_id, is_available, smm_disabled_reason, min_quantity, max_quantity")
        .eq("smm_provider_id", provider.id)
        .eq("product_type", "digital");
      if (productsError) {
        console.error(`❌ Ürünler alınamadı (provider ${provider.id}):`, productsError.message);
        continue;
      }

      // Sağlayıcıya ait ürünleri toplu işle: disable/re-enable ID'lerini topla,
      // döngü sonunda iki toplu update gönder (ürün başına tek tek UPDATE yerine).
      const disableIds: string[] = [];
      const reEnableIds: string[] = [];
      // Aynı min/max aralığına düşen ürünler tek UPDATE'te toplanır: "min:max" -> ürün ID'leri
      const rangeUpdates = new Map<string, string[]>();

      for (const product of products || []) {
        const serviceId = String(product.smm_service_id);
        const stillExists = availableServiceIds.has(serviceId);

        if (!stillExists && product.is_available) {
          disableIds.push(product.id);
        } else if (stillExists && !product.is_available && product.smm_disabled_reason) {
          // Sadece bu mekanizmanın kapattığı ürünleri otomatik geri açar; satıcının
          // manuel kapattığı ürünlere (smm_disabled_reason boş) dokunulmaz.
          reEnableIds.push(product.id);
        }

        const range = serviceRanges.get(serviceId);
        if (range && (product.min_quantity !== range.min || product.max_quantity !== range.max)) {
          const key = `${range.min}:${range.max}`;
          const bucket = rangeUpdates.get(key);
          if (bucket) bucket.push(product.id);
          else rangeUpdates.set(key, [product.id]);
        }
      }

      if (disableIds.length > 0) {
        const { error: upErr } = await supabase
          .from("products")
          .update({
            is_available: false,
            smm_disabled_reason: "Sağlayıcıda bu servis artık mevcut değil",
          })
          .in("id", disableIds);
        if (upErr) {
          console.error(`❌ Toplu disable hatası (provider ${provider.id}):`, upErr.message);
        } else {
          disabled += disableIds.length;
        }
      }

      if (reEnableIds.length > 0) {
        const { error: upErr } = await supabase
          .from("products")
          .update({ is_available: true, smm_disabled_reason: null })
          .in("id", reEnableIds);
        if (upErr) {
          console.error(`❌ Toplu re-enable hatası (provider ${provider.id}):`, upErr.message);
        } else {
          reEnabled += reEnableIds.length;
        }
      }

      for (const [key, ids] of rangeUpdates) {
        const [min, max] = key.split(":").map((v) => Number.parseInt(v, 10));
        const { error: upErr } = await supabase
          .from("products")
          .update({ min_quantity: min, max_quantity: max })
          .in("id", ids);
        if (upErr) {
          console.error(`❌ Min/max güncelleme hatası (provider ${provider.id}):`, upErr.message);
        } else {
          rangeUpdated += ids.length;
        }
      }
    }

    return new Response(JSON.stringify({ status: "success", checkedProviders, disabled, reEnabled, rangeUpdated }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err: unknown) {
    const error = err as Error;
    console.error("❌ smm-sync-products error:", error.message);
    return new Response(JSON.stringify({ status: "error", error: error.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});

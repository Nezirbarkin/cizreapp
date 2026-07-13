// smm-sync-products Edge Function
// Sağlayıcıda bir servis kaldırılmış/değiştirilmişse, o servise bağlı dijital ürünü otomatik
// olarak satışa kapatır (is_available=false) ve müşteri ekranında görünmez olur. Servis
// sağlayıcıda tekrar mevcutsa ve önceden bu mekanizma yüzünden kapatılmışsa otomatik açar.
// Deploy: supabase functions deploy smm-sync-products
// Cron: Supabase Dashboard -> Cron -> saatte bir -> POST bu fonksiyona, header: x-cron-secret: <CRON_SECRET>

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.38.4";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

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

      const { data: products, error: productsError } = await supabase
        .from("products")
        .select("id, smm_service_id, is_available, smm_disabled_reason")
        .eq("smm_provider_id", provider.id)
        .eq("product_type", "digital");
      if (productsError) {
        console.error(`❌ Ürünler alınamadı (provider ${provider.id}):`, productsError.message);
        continue;
      }

      for (const product of products || []) {
        const stillExists = availableServiceIds.has(String(product.smm_service_id));

        if (!stillExists && product.is_available) {
          await supabase
            .from("products")
            .update({
              is_available: false,
              smm_disabled_reason: "Sağlayıcıda bu servis artık mevcut değil",
            })
            .eq("id", product.id);
          disabled++;
        } else if (stillExists && !product.is_available && product.smm_disabled_reason) {
          // Sadece bu mekanizmanın kapattığı ürünleri otomatik geri açar; satıcının
          // manuel kapattığı ürünlere (smm_disabled_reason boş) dokunulmaz.
          await supabase
            .from("products")
            .update({ is_available: true, smm_disabled_reason: null })
            .eq("id", product.id);
          reEnabled++;
        }
      }
    }

    return new Response(JSON.stringify({ status: "success", checkedProviders, disabled, reEnabled }), {
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

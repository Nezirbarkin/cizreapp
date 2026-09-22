// smm-sync-products Edge Function
//
// Sağlayıcının `services` listesini çeker ve o sağlayıcıya bağlı dijital ürünleri
// listeyle karşılaştırır. Şunlardan biri olursa ürün OTOMATİK "tükendi"
// (is_available=false) yapılır ve müşteri ekranından kalkar:
//
//   * servis ID'si sağlayıcıda artık yok            -> smm_disabled_kind = 'missing'
//   * ID var ama servisin adı değişmiş (ID başka    -> smm_disabled_kind = 'service_changed'
//     bir hizmete atanmış olabilir)
//   * sağlayıcının 1000 adet fiyatı değişmiş        -> smm_disabled_kind = 'price_changed'
//
// Karşılaştırma tabanı smm_product_baselines tablosundadır (satıcı hizmeti seçerken
// smm_set_product_baseline RPC'siyle yazılır; sağlayıcı fiyatı satıcının maliyeti olduğu
// için herkesçe okunabilen products tablosuna konmaz). Tabanı olmayan (eski) ürünler için
// ilk senkronda mevcut değerler taban olarak alınır, ürün kapatılmaz.
//
// 'missing' düzelirse (servis geri geldi, ad/fiyat aynı) ürün otomatik açılır.
// 'price_changed' / 'service_changed' otomatik AÇILMAZ: satıcı/admin ürünü elle açtığında
// products_smm_accept_on_reenable tetikleyicisi tabanı siler, bir sonraki senkron mevcut
// değerleri yeni taban alır (yeni durum kabul edilmiş olur).
//
// Ayrıca servisin min/max miktar aralığı değiştiyse ürünün min_quantity/max_quantity alanları
// güncellenir.
//
// Çağıranlar: cron (x-cron-secret) veya admin kullanıcı JWT'si ("Şimdi senkronize et" düğmesi).
// Deploy: supabase functions deploy smm-sync-products
// Cron: 10 dakikada bir — bkz. supabase/migrations/20260920000005_smm_sync_price_guard.sql

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { getAdminClient } from "../_shared/client.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });

// Ad karşılaştırması: büyük/küçük harf, boşluk ve noktalama farkları değişiklik sayılmaz.
const normName = (value: unknown) => String(value ?? "").toLowerCase().replace(/[^a-z0-9]+/g, "");

const RATE_EPSILON = 0.0001;

type ProviderService = { name: string; rate: number | null };
type DisableUpdate = { id: string; kind: "missing" | "service_changed" | "price_changed"; reason: string };

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  const supabase = getAdminClient();

  try {
    // --- Yetki: cron sırrı VEYA admin kullanıcı ---
    const cronSecret = req.headers.get("x-cron-secret");
    const expectedCronSecret = Deno.env.get("CRON_SECRET");
    let authorized = !!expectedCronSecret && cronSecret === expectedCronSecret;

    if (!authorized) {
      const authHeader = req.headers.get("authorization");
      if (authHeader) {
        const { data: { user } } = await supabase.auth.getUser(authHeader.replace("Bearer ", ""));
        if (user) {
          const { data: profile } = await supabase.from("profiles").select("role").eq("id", user.id).single();
          authorized = profile?.role === "admin";
        }
      }
    }
    if (!authorized) return json({ error: "Unauthorized" }, 401);

    const { data: providers, error: providersError } = await supabase
      .from("smm_providers")
      .select("id, api_url, api_key")
      .eq("is_active", true);
    if (providersError) throw new Error(providersError.message);

    let checkedProviders = 0;
    let disabledMissing = 0;
    let disabledServiceChanged = 0;
    let disabledPriceChanged = 0;
    let reEnabled = 0;
    let baselineAdopted = 0;
    let rangeUpdated = 0;

    for (const provider of providers || []) {
      let rawServices: any[];
      try {
        const res = await fetch(provider.api_url, {
          method: "POST",
          headers: { "Content-Type": "application/x-www-form-urlencoded" },
          body: new URLSearchParams({ key: provider.api_key, action: "services" }),
        });
        const parsed = await res.json();
        // Sağlayıcı hata döndürdüyse (dizi değil) HİÇBİR ürüne dokunulmaz: geçici bir API
        // sorunu yüzünden tüm ürünleri kapatmak felaket olurdu.
        if (!Array.isArray(parsed)) continue;
        rawServices = parsed;
      } catch (err) {
        console.error(`❌ Servis listesi alınamadı (provider ${provider.id}):`, (err as Error).message);
        continue;
      }
      checkedProviders++;

      // Boş liste de şüphelidir (sağlayıcı bakımda olabilir): hiçbir şey yapma.
      if (rawServices.length === 0) continue;

      const services = new Map<string, ProviderService>();
      // Sağlayıcının bildirdiği miktar aralıkları (servis ID -> {min, max}).
      // API'ler min/max'i çoğu zaman string döndürdüğü için sayıya çevrilir.
      const serviceRanges = new Map<string, { min: number; max: number }>();
      for (const s of rawServices) {
        const id = String(s.service);
        const rate = Number.parseFloat(String(s.rate ?? ""));
        services.set(id, { name: String(s.name ?? ""), rate: Number.isFinite(rate) ? rate : null });

        const min = Number.parseInt(String(s.min ?? ""), 10);
        const max = Number.parseInt(String(s.max ?? ""), 10);
        if (!Number.isFinite(min) || !Number.isFinite(max)) continue;
        if (min <= 0 || max < min) continue;
        serviceRanges.set(id, { min, max });
      }

      const { data: products, error: productsError } = await supabase
        .from("products")
        .select(
          "id, smm_service_id, is_available, smm_disabled_reason, smm_disabled_kind, " +
            "min_quantity, max_quantity",
        )
        .eq("smm_provider_id", provider.id)
        .eq("product_type", "digital");
      if (productsError) {
        console.error(`❌ Ürünler alınamadı (provider ${provider.id}):`, productsError.message);
        continue;
      }

      // Karşılaştırma tabanı: ayrı, istemciye kapalı tabloda (sağlayıcı fiyatı satıcının
      // maliyetidir, products'a yazılmaz).
      const baselines = new Map<string, { rate: number | null; name: string | null }>();
      const productIds = ((products || []) as any[]).map((p) => p.id);
      if (productIds.length > 0) {
        const { data: baselineRows, error: baselineError } = await supabase
          .from("smm_product_baselines")
          .select("product_id, provider_rate, service_name")
          .in("product_id", productIds);
        if (baselineError) {
          // Taban okunamazsa karşılaştırma yapılamaz; yanlış "değişti" kararı vermemek için atla.
          console.error(`❌ Tabanlar alınamadı (provider ${provider.id}):`, baselineError.message);
          continue;
        }
        for (const row of (baselineRows || []) as any[]) {
          baselines.set(row.product_id, {
            rate: row.provider_rate == null ? null : Number(row.provider_rate),
            name: row.service_name ?? null,
          });
        }
      }

      const disableUpdates: DisableUpdate[] = [];
      const reEnableIds: string[] = [];
      const baselineUpdates: { id: string; rate: number | null; name: string }[] = [];
      // Aynı min/max aralığına düşen ürünler tek UPDATE'te toplanır: "min:max" -> ürün ID'leri
      const rangeUpdates = new Map<string, string[]>();

      for (const product of (products || []) as any[]) {
        const serviceId = String(product.smm_service_id);
        const svc = services.get(serviceId);

        if (!svc) {
          // Servis listede yok. Açık ürün kapatılır; fiyat/servis değişimi yüzünden kapalı olan
          // ürünün nedeni "yok" olarak güncellenir. Zaten 'missing' ile kapalıysa ya da satıcı
          // elle kapattıysa (neden boş) dokunulmaz.
          const closedForOtherReason = !product.is_available &&
            product.smm_disabled_kind != null && product.smm_disabled_kind !== "missing";
          if (product.is_available || closedForOtherReason) {
            disableUpdates.push({
              id: product.id,
              kind: "missing",
              reason: "Sağlayıcıda bu servis artık mevcut değil",
            });
          }
          continue;
        }

        const base = baselines.get(product.id);
        const baseRate = base?.rate ?? null;
        const baseName = base?.name ?? null;

        const nameChanged = baseName != null && normName(baseName) !== normName(svc.name);
        const priceChanged = baseRate != null && svc.rate != null && Math.abs(baseRate - svc.rate) > RATE_EPSILON;

        if (nameChanged || priceChanged) {
          const kind: DisableUpdate["kind"] = nameChanged ? "service_changed" : "price_changed";
          // Aynı nedenle zaten kapalıysa tekrar yazma.
          if (product.is_available || product.smm_disabled_kind !== kind) {
            // Metin bilerek rakam/ad içermez: products herkesçe okunabilir.
            const reason = nameChanged
              ? "Sağlayıcıda bu servisin ID'si başka bir hizmete atanmış görünüyor"
              : "Sağlayıcı fiyatı değişti";
            disableUpdates.push({ id: product.id, kind, reason });
          }
        } else {
          // Değişiklik yok. 'missing' yüzünden kapanmış (ya da eski kayıtta tür yok) ürünü geri aç.
          // Satıcının manuel kapattığı (neden boş) ve fiyat/servis değişimi yüzünden kapanmış
          // ürünlere dokunulmaz.
          const closedByMissing = !product.is_available &&
            (product.smm_disabled_kind === "missing" ||
              (product.smm_disabled_kind == null && product.smm_disabled_reason));
          if (closedByMissing) reEnableIds.push(product.id);

          // Taban yoksa (eski ürün / kabul edilmiş değişiklik) mevcut değerleri taban al.
          if (baseRate == null || baseName == null) {
            baselineUpdates.push({ id: product.id, rate: svc.rate, name: svc.name });
          }
        }

        const range = serviceRanges.get(serviceId);
        if (range && (product.min_quantity !== range.min || product.max_quantity !== range.max)) {
          const key = `${range.min}:${range.max}`;
          const bucket = rangeUpdates.get(key);
          if (bucket) bucket.push(product.id);
          else rangeUpdates.set(key, [product.id]);
        }
      }

      // Kapatmalar: gerekçe ürün başına farklı olduğu için tek tek, ama paralel.
      for (let i = 0; i < disableUpdates.length; i += 10) {
        const chunk = disableUpdates.slice(i, i + 10);
        const results = await Promise.all(chunk.map((u) =>
          supabase
            .from("products")
            .update({ is_available: false, smm_disabled_reason: u.reason, smm_disabled_kind: u.kind })
            .eq("id", u.id)
        ));
        results.forEach((res, idx) => {
          if (res.error) {
            console.error(`❌ Kapatma hatası (ürün ${chunk[idx].id}):`, res.error.message);
            return;
          }
          if (chunk[idx].kind === "missing") disabledMissing++;
          else if (chunk[idx].kind === "service_changed") disabledServiceChanged++;
          else disabledPriceChanged++;
        });
      }

      if (reEnableIds.length > 0) {
        const { error: upErr } = await supabase
          .from("products")
          .update({ is_available: true, smm_disabled_reason: null, smm_disabled_kind: null })
          .in("id", reEnableIds);
        if (upErr) {
          console.error(`❌ Toplu re-enable hatası (provider ${provider.id}):`, upErr.message);
        } else {
          reEnabled += reEnableIds.length;
        }
      }

      if (baselineUpdates.length > 0) {
        const { error: baseErr } = await supabase
          .from("smm_product_baselines")
          .upsert(
            baselineUpdates.map((u) => ({
              product_id: u.id,
              provider_rate: u.rate,
              service_name: u.name,
              updated_at: new Date().toISOString(),
            })),
            { onConflict: "product_id" },
          );
        if (baseErr) {
          console.error(`❌ Taban yazma hatası (provider ${provider.id}):`, baseErr.message);
        } else {
          baselineAdopted += baselineUpdates.length;
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

    return json({
      status: "success",
      checkedProviders,
      disabled: disabledMissing + disabledServiceChanged + disabledPriceChanged,
      disabledMissing,
      disabledServiceChanged,
      disabledPriceChanged,
      reEnabled,
      baselineAdopted,
      rangeUpdated,
    });
  } catch (err: unknown) {
    const error = err as Error;
    console.error("❌ smm-sync-products error:", error.message);
    return json({ status: "error", error: error.message }, 500);
  }
});

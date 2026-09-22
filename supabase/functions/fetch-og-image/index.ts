// fetch-og-image Edge Function
// Satıcı / admin ürün görseli eklerken bir web sayfası linki yapıştırır; bu
// fonksiyon sayfadaki ana görseli (og:image, twitter:image, JSON-LD vb.) bulur,
// SUNUCUDA indirir ve baytlarını base64 olarak döner.
//
// Neden yalnızca link değil de bayt dönüyor: dış sitenin görsel URL'sini ürüne
// olduğu gibi kaydetmek kırılgandır (hotlink koruması, web'de CORS, ürün
// toptancıda silinince görselin kaybolması). İstemci baytları normal bir dosya
// gibi kendi bucket'ına yükler; böylece mevcut boyut/tür kontrolleri ve
// storage RLS aynen geçerli kalır.
//
// Yetki: yalnız admin veya mağaza sahibi (satıcı). Aksi halde bu uç nokta
// herkese açık bir "sunucudan istek at" aracına dönüşürdü.
//
// Deploy: supabase functions deploy fetch-og-image

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { getAdminClient } from "../_shared/client.ts";
import { bearerToken, json, options, safeErrorCode } from "../_shared/http.ts";
import {
  bytesToBase64,
  type DnsResolver,
  scrapeProductImage,
  ScrapeError,
} from "../_shared/og_image.ts";

// Deno.resolveDns bulunamazsa (ör. yetki yok) boş döner; assertPublicUrl bu
// durumda DNS_FAILED verir. Ad çözümü zaten çalışmıyorsa fetch de çalışmaz.
const resolveHost: DnsResolver = async (hostname) => {
  const addresses: string[] = [];
  for (const type of ["A", "AAAA"] as const) {
    try {
      addresses.push(...await Deno.resolveDns(hostname, type));
    } catch {
      // Bu kayıt türü yok / çözümlenemedi.
    }
  }
  return addresses;
};

// Isolate başına basit hız sınırı: kötüye kullanımı yavaşlatır, meşru kullanımı
// (birkaç ürün girişi) etkilemez. Isolate'lar arasında paylaşılmaz; amaç kaba bir
// fren.
const RATE_WINDOW_MS = 60_000;
const RATE_MAX = 20;
const hits = new Map<string, number[]>();

function rateLimited(userId: string): boolean {
  const now = Date.now();
  const recent = (hits.get(userId) ?? []).filter((t) => now - t < RATE_WINDOW_MS);
  if (recent.length >= RATE_MAX) {
    hits.set(userId, recent);
    return true;
  }
  recent.push(now);
  hits.set(userId, recent);
  if (hits.size > 500) {
    for (const [k, v] of hits) {
      if (v.every((t) => now - t >= RATE_WINDOW_MS)) hits.delete(k);
    }
  }
  return false;
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") return options("POST, OPTIONS");
  if (req.method !== "POST") {
    return json({ error_code: "METHOD_NOT_ALLOWED" }, 405, {
      Allow: "POST, OPTIONS",
    });
  }

  try {
    const token = bearerToken(req);
    if (!token) return json({ error_code: "UNAUTHORIZED" }, 401);

    const supabase = getAdminClient();
    const { data: { user }, error: authError } = await supabase.auth.getUser(
      token,
    );
    if (authError || !user) return json({ error_code: "UNAUTHORIZED" }, 401);

    const { data: profile } = await supabase
      .from("profiles")
      .select("role")
      .eq("id", user.id)
      .maybeSingle();
    let allowed = profile?.role === "admin";
    if (!allowed) {
      const { data: shop } = await supabase
        .from("shops")
        .select("id")
        .eq("owner_id", user.id)
        .maybeSingle();
      allowed = shop != null;
    }
    if (!allowed) return json({ error_code: "FORBIDDEN" }, 403);

    if (rateLimited(user.id)) {
      return json({
        ok: false,
        error: "RATE_LIMITED",
        message: "Çok fazla deneme yapıldı; bir dakika sonra tekrar deneyin",
      }, 429);
    }

    const body = await req.json().catch(() => ({}));

    try {
      const result = await scrapeProductImage(body?.url, {
        resolve: resolveHost,
      });
      return json({
        ok: true,
        image_url: result.imageUrl,
        page_url: result.pageUrl,
        title: result.title,
        content_type: result.mime,
        extension: result.ext,
        size: result.bytes.length,
        image_base64: bytesToBase64(result.bytes),
      });
    } catch (e) {
      // Beklenen hatalar (geçersiz link, görsel yok, site engelledi…) 200 ile
      // döner ki istemci mesajı doğrudan gösterebilsin.
      if (e instanceof ScrapeError) {
        return json({ ok: false, error: e.code, message: e.message });
      }
      throw e;
    }
  } catch (err) {
    console.error("fetch-og-image error:", err);
    return json({ ok: false, error: safeErrorCode(err) }, 500);
  }
});

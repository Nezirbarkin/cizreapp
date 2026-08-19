// route-distance Edge Function
// Alım→teslim arası gerçek en kısa yol mesafesini Google Directions ile
// hesaplar, road_distance_cache tablosuna yazar (sunucu otoritesi) ve
// istemciye önizleme için döndürür. create_package_request RPC'si bu
// önbelleği okuyarak ücreti hesaplar; böylece önizleme ile kesilen tutar
// tutarlı olur. İstemci mesafe gönderemez — Google çağrısı burada, sunucuda
// yapılır.
//
// Deploy: supabase functions deploy route-distance
// GCP: Google API key'in Directions API yetkisi açık olmalı.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { getAdminClient } from "../_shared/client.ts";

// Harici yön/mesafe API'leri için üst sınır. Sağlayıcı yavaşlarsa veya yanıt
// vermezse worker'ın platform wall-clock sınırına kadar takılı kalmasını önler;
// abort olunca OSRM yedeğine / no_route dönüşüne düşer.
const ROUTE_FETCH_TIMEOUT_MS = 8_000;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function round5(n: number): number {
  return Math.round(n * 1e5) / 1e5;
}

// OSRM demo router yedeği. Google Directions API GCP'de kapalıysa (REQUEST_DENIED)
// veya rota bulunamazsa gerçek yol mesafesi + polyline için çağrılır. Ücretsiz,
// key yok; geometries=polyline Google ile aynı encoded format döndürür. demo
// sunucusu production için güvenilir değildir (rate limit, SLA yok) ama Cizre
// ölçeğinde görsel rota + mesafe için yeterlidir.
// Koordinat sırası: lng,lat;lng,lat
async function fetchOsmRoute(
  pickupLat: number, pickupLng: number,
  deliveryLat: number, deliveryLng: number,
): Promise<{ distanceKm: number; durationS: number | null; polyline: string | null } | null> {
  try {
    const url =
      "https://router.project-osrm.org/route/v1/driving/" +
      `${pickupLng},${pickupLat};${deliveryLng},${deliveryLat}` +
      "?overview=full&geometries=polyline";
    const resp = await fetch(url, { method: "GET", signal: AbortSignal.timeout(ROUTE_FETCH_TIMEOUT_MS) });
    if (!resp.ok) return null;
    const data = await resp.json();
    if (data?.code !== "Ok" || !Array.isArray(data.routes) || data.routes.length === 0) {
      return null;
    }
    const meters = data.routes[0].distance;
    if (meters == null || meters <= 0) return null;
    return {
      distanceKm: Math.round((meters / 1000) * 1000) / 1000,
      durationS: data.routes[0].duration ?? null,
      polyline: data.routes[0].geometry ?? null,
    };
  } catch {
    return null;
  }
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const supabase = getAdminClient();

    const { data: { user }, error: authError } = await supabase.auth.getUser(
      authHeader.replace("Bearer ", "")
    );
    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Geçersiz oturum" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const body = await req.json().catch(() => ({}));
    const pickupLat = Number(body.pickup_lat);
    const pickupLng = Number(body.pickup_lng);
    const deliveryLat = Number(body.delivery_lat);
    const deliveryLng = Number(body.delivery_lng);

    if (![pickupLat, pickupLng, deliveryLat, deliveryLng].every((n) =>
      Number.isFinite(n)
    )) {
      return new Response(JSON.stringify({ error: "Geçersiz koordinat" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    if (
      pickupLat < -90 || pickupLat > 90 || deliveryLat < -90 || deliveryLat > 90 ||
      pickupLng < -180 || pickupLng > 180 || deliveryLng < -180 || deliveryLng > 180
    ) {
      return new Response(JSON.stringify({ error: "Koordinat aralık dışı" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // API key: önce app_about_settings (uygulamanın kullandığı key), sonra env.
    let apiKey = "";
    try {
      const { data, error } = await supabase
        .from("app_about_settings")
        .select("google_maps_api_key")
        .limit(1)
        .maybeSingle();
      if (!error && data?.google_maps_api_key) {
        apiKey = data.google_maps_api_key;
      }
    } catch (e) {
      console.warn("app_about_settings key okuma hatası:", e);
    }
    if (!apiKey) apiKey = Deno.env.get("GOOGLE_MAPS_API_KEY") ?? "";
    if (!apiKey) {
      return new Response(JSON.stringify({
        ok: false,
        error: "API key yok",
      }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // 1) Google Directions (birincil). Directions API GCP'de kapalıysa veya
    // rota yoksa OSRM yedeğine düşülür (aşağıda). Başarısızlıkta erken return
    // yok — değişkenler null kalır, OSRM denenir.
    let distanceKm: number | null = null;
    let durationS: number | null = null;
    let polylinePoints: string | null = null;
    let provider = "google";

    try {
      const url =
        "https://maps.googleapis.com/maps/api/directions/json" +
        `?origin=${pickupLat},${pickupLng}` +
        `&destination=${deliveryLat},${deliveryLng}` +
        `&mode=driving&key=${apiKey}`;
      const gResp = await fetch(url, { method: "GET", signal: AbortSignal.timeout(ROUTE_FETCH_TIMEOUT_MS) });
      if (gResp.ok) {
        const gData = await gResp.json();
        const routes = gData?.routes;
        if (Array.isArray(routes) && routes.length > 0) {
          const leg = routes[0]?.legs?.[0];
          const meters = leg?.distance?.value;
          if (meters != null && meters > 0) {
            distanceKm = Math.round((meters / 1000) * 1000) / 1000;
            durationS = leg?.duration?.value ?? null;
            polylinePoints = routes[0]?.overview_polyline?.points ?? null;
          }
        }
      }
    } catch (e) {
      console.warn("Google Directions hatası:", e);
    }

    // 2) Google başarısızsa (Directions API kapalı / no route) OSRM yedeği.
    //    Böylece önbelleğe gerçek yol mesafesi yine yazılır; RPC kuş uçuşuna
    //    düşmez. directions API ileride açılırsa Google otomatik önceliklenir.
    if (distanceKm == null) {
      const osrm = await fetchOsmRoute(pickupLat, pickupLng, deliveryLat, deliveryLng);
      if (osrm) {
        distanceKm = osrm.distanceKm;
        durationS = osrm.durationS;
        polylinePoints = osrm.polyline;
        provider = "osrm";
      }
    }

    if (distanceKm == null) {
      return new Response(JSON.stringify({
        ok: false,
        error: "no_route",
      }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Önbelleğe yaz (RPC bundan okuyacak). Koordinatları 5 ondalık yuvarla
    // — RPC aynı yuvarlamayı kullanır. Hem Google hem OSRM kaynağı yazılır.
    const pkLat = round5(pickupLat);
    const pkLng = round5(pickupLng);
    const dlLat = round5(deliveryLat);
    const dlLng = round5(deliveryLng);
    try {
      await supabase
        .from("road_distance_cache")
        .upsert(
          {
            pickup_lat: pkLat,
            pickup_lng: pkLng,
            delivery_lat: dlLat,
            delivery_lng: dlLng,
            distance_km: distanceKm,
            duration_s: durationS ?? null,
            fetched_at: new Date().toISOString(),
          },
          { onConflict: "pickup_lat,pickup_lng,delivery_lat,delivery_lng" }
        );
    } catch (e) {
      // Önbellek yazma başarısız olsa bile önizleme yine döner; RPC miss
      // durumunda Haversine kullanır.
      console.warn("road_distance_cache upsert hatası:", e);
    }

    return new Response(JSON.stringify({
      ok: true,
      distance_km: distanceKm,
      duration_s: durationS,
      polyline: polylinePoints,
      provider,
    }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err: unknown) {
    const error = err as Error;
    console.error("route-distance error:", error.message);
    return new Response(JSON.stringify({
      ok: false,
      error: error.message,
    }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
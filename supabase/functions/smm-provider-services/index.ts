// smm-provider-services Edge Function
// Sağlayıcının hizmet (service) listesini getirir (action=services) - api_key client'a hiç dönmez.
// Deploy: supabase functions deploy smm-provider-services

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.38.4";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
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
    const { provider_id } = body;
    if (!provider_id) {
      return new Response(JSON.stringify({ error: "provider_id zorunludur" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Kullanıcının bu provider'a erişimi var mı? (RLS ile aynı kural: admin veya provider sahibi satıcı)
    const { data: provider, error: providerError } = await supabase
      .from("smm_providers")
      .select("id, api_url, api_key, owner_type, owner_id")
      .eq("id", provider_id)
      .single();

    if (providerError || !provider) {
      return new Response(JSON.stringify({ error: "Sağlayıcı bulunamadı" }), {
        status: 404,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const { data: profile } = await supabase
      .from("profiles")
      .select("role")
      .eq("id", user.id)
      .single();
    const isAdmin = profile?.role === "admin";

    if (!isAdmin) {
      const { data: shop } = await supabase
        .from("shops")
        .select("id")
        .eq("owner_id", user.id)
        .maybeSingle();
      const ownsProvider = provider.owner_type === "seller" && shop && provider.owner_id === shop.id;
      if (!ownsProvider) {
        return new Response(JSON.stringify({ error: "Bu sağlayıcıya erişiminiz yok" }), {
          status: 403,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }
    }

    const res = await fetch(provider.api_url, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({ key: provider.api_key, action: "services" }),
    });
    const services = await res.json();

    if (!Array.isArray(services)) {
      return new Response(JSON.stringify({
        status: "error",
        error: services?.error || "Sağlayıcıdan servis listesi alınamadı",
      }), {
        status: 502,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Sadece ihtiyaç duyulan alanları dön; api_key hiçbir zaman response'a dahil edilmez.
    const mapped = services.map((s: any) => ({
      service: String(s.service),
      name: s.name,
      category: s.category,
      rate: s.rate != null ? parseFloat(s.rate) : null, // 1000 adet fiyatı
      min: s.min != null ? parseInt(s.min, 10) : null,
      max: s.max != null ? parseInt(s.max, 10) : null,
    }));

    return new Response(JSON.stringify({ status: "success", services: mapped }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err: unknown) {
    const error = err as Error;
    console.error("❌ smm-provider-services error:", error.message);
    return new Response(JSON.stringify({ status: "error", error: error.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});

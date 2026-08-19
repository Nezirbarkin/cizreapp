// get-seller-earnings Edge Function
// Satıcının kazanç özetini getirir
// Deploy: supabase functions deploy get-seller-earnings

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { getAdminClient } from "../_shared/client.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

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

    // Kullanıcıyı doğrula
    const { data: { user }, error: authError } = await supabase.auth.getUser(
      authHeader.replace("Bearer ", "")
    );

    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Geçersiz oturum" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Satıcı mı kontrol et
    const { data: profile } = await supabase
      .from("profiles")
      .select("role")
      .eq("id", user.id)
      .single();

    if (profile?.role !== "seller" && profile?.role !== "admin") {
      return new Response(JSON.stringify({ error: "Bu işlem için satıcı hesabı gerekli" }), {
        status: 403,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Özet DB tarafında tek aggregate sorgusuyla (tüm geçmişi çekmek yerine).
    const { data: summary, error: summaryError } = await supabase
      .rpc("get_seller_earnings_summary", { p_seller_id: user.id })
      .maybeSingle();

    if (summaryError) {
      throw summaryError;
    }

    const s = summary ?? {};

    // Son 10 kayıt liste için (limitli — tüm geçmiş değil).
    const { data: recentEarnings, error: recentError } = await supabase
      .from("seller_earnings")
      .select("*")
      .eq("seller_id", user.id)
      .order("created_at", { ascending: false })
      .limit(10);

    if (recentError) {
      throw recentError;
    }

    // Sistem ayarları
    const { data: settings } = await supabase
      .from("app_about_settings")
      .select("min_withdrawal_amount, withdrawal_fee_percent")
      .maybeSingle();

    return new Response(JSON.stringify({
      status: "success",
      earnings_summary: {
        total_orders: s.total_orders ?? 0,
        total_gross: s.total_gross ?? 0,
        total_commission: s.total_commission ?? 0,
        total_net: s.total_net ?? 0,
        pending_amount: s.pending_amount ?? 0,
        available_amount: s.available_amount ?? 0,
        withdrawn_amount: s.withdrawn_amount ?? 0,
        min_withdrawal: settings?.min_withdrawal_amount || 50,
        withdrawal_fee_percent: settings?.withdrawal_fee_percent || 2,
      },
      recent_earnings: recentEarnings ?? [],
    }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err: unknown) {
    const error = err as Error;
    console.error("❌ get-seller-earnings error:", error.message);

    return new Response(JSON.stringify({
      status: "error",
      error: error.message,
    }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});

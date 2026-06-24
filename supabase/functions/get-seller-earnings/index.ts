// get-seller-earnings Edge Function
// Satıcının kazanç özetini getirir
// Deploy: supabase functions deploy get-seller-earnings

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

  try {
    const authHeader = req.headers.get("authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

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

    // Kazanç özeti
    const { data: earnings, error: earningsError } = await supabase
      .from("seller_earnings")
      .select("*")
      .eq("seller_id", user.id)
      .order("created_at", { ascending: false });

    if (earningsError) {
      throw earningsError;
    }

    // Özet hesapla
    let totalGross = 0;
    let totalCommission = 0;
    let totalNet = 0;
    let pendingAmount = 0;
    let availableAmount = 0;
    let withdrawnAmount = 0;

    for (const earning of earnings || []) {
      const gross = parseFloat(earning.gross_amount || "0");
      const commission = parseFloat(earning.commission_amount || "0");
      const net = parseFloat(earning.net_amount || "0");

      totalGross += gross;
      totalCommission += commission;
      totalNet += net;

      switch (earning.status) {
        case "pending":
          pendingAmount += net;
          break;
        case "available":
          availableAmount += net;
          break;
        case "withdrawn":
          withdrawnAmount += net;
          break;
      }
    }

    // Sistem ayarları
    const { data: settings } = await supabase
      .from("app_about_settings")
      .select("min_withdrawal_amount, withdrawal_fee_percent")
      .maybeSingle();

    return new Response(JSON.stringify({
      status: "success",
      earnings_summary: {
        total_orders: earnings?.length || 0,
        total_gross: totalGross,
        total_commission: totalCommission,
        total_net: totalNet,
        pending_amount: pendingAmount,
        available_amount: availableAmount,
        withdrawn_amount: withdrawnAmount,
        min_withdrawal: settings?.min_withdrawal_amount || 50,
        withdrawal_fee_percent: settings?.withdrawal_fee_percent || 2,
      },
      recent_earnings: earnings?.slice(0, 10) || [],
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

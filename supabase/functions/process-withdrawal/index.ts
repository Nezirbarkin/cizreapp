// process-withdrawal Edge Function
// Admin çekim talebini işler (onaylar/reddeder)
// Deploy: supabase functions deploy process-withdrawal

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

    // Admin kontrolü
    const { data: profile } = await supabase
      .from("profiles")
      .select("role")
      .eq("id", user.id)
      .single();

    if (profile?.role !== "admin") {
      return new Response(JSON.stringify({ error: "Bu işlem için admin yetkisi gerekli" }), {
        status: 403,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const body = await req.json();
    const { withdrawal_id, action, notes } = body;

    if (!withdrawal_id || !action) {
      return new Response(JSON.stringify({ error: "withdrawal_id ve action zorunludur" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (!["approve", "reject", "process"].includes(action)) {
      return new Response(JSON.stringify({ error: "Geçersiz action. approve, reject veya process olmalı" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Çekim talebini bul
    const { data: withdrawal, error: withdrawalError } = await supabase
      .from("seller_withdrawals")
      .select("*")
      .eq("id", withdrawal_id)
      .single();

    if (withdrawalError || !withdrawal) {
      return new Response(JSON.stringify({ error: "Çekim talebi bulunamadı" }), {
        status: 404,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (withdrawal.status !== "pending") {
      return new Response(JSON.stringify({ error: "Bu çekim talebi zaten işlenmiş" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    let newStatus: string;
    let failureReason: string | null = null;

    switch (action) {
      case "approve":
      case "process":
        newStatus = "processing";
        break;
      case "reject":
        newStatus = "failed";
        failureReason = notes || "Admin tarafından reddedildi";
        break;
    }

    // Çekim talebini güncelle
    const { error: updateError } = await supabase
      .from("seller_withdrawals")
      .update({
        status: newStatus,
        admin_id: user.id,
        admin_notes: notes || null,
        processed_at: new Date().toISOString(),
        failure_reason: failureReason,
        updated_at: new Date().toISOString(),
      })
      .eq("id", withdrawal_id);

    if (updateError) {
      throw updateError;
    }

    // Eğer reddedildiyse, kazançları geri available yap
    if (action === "reject") {
      await supabase
        .from("seller_earnings")
        .update({
          status: "available",
          withdrawal_id: null,
          updated_at: new Date().toISOString(),
        })
        .eq("withdrawal_id", withdrawal_id)
        .eq("status", "withdrawn");
    }

    console.log("✅ Çekim işlendi:", {
      withdrawalId: withdrawal_id,
      action,
      newStatus,
      adminId: user.id,
    });

    return new Response(JSON.stringify({
      status: "success",
      withdrawal_id: withdrawal_id,
      new_status: newStatus,
      processed_at: new Date().toISOString(),
    }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err: unknown) {
    const error = err as Error;
    console.error("❌ process-withdrawal error:", error.message);

    return new Response(JSON.stringify({
      status: "error",
      error: error.message,
    }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});

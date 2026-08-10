// cancel-withdrawal Edge Function
// Satıcı kendi pending çekim talebini iptal eder
// Deploy: supabase functions deploy cancel-withdrawal

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
    // Auth kontrolü
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

    // Body'den payout_request_id al
    const body = await req.json();
    const { payout_request_id } = body;

    if (!payout_request_id) {
      return new Response(JSON.stringify({
        error: "payout_request_id zorunludur"
      }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Önce isteğin bu satıcıya ait olduğunu ve pending olduğunu kontrol et
    const { data: existingRequest, error: fetchError } = await supabase
      .from("payout_requests")
      .select("id, seller_id, status, amount")
      .eq("id", payout_request_id)
      .single();

    if (fetchError || !existingRequest) {
      return new Response(JSON.stringify({
        error: "Ödeme isteği bulunamadı"
      }), {
        status: 404,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (existingRequest.seller_id !== user.id) {
      return new Response(JSON.stringify({
        error: "Bu ödeme isteğini iptal etme yetkiniz yok"
      }), {
        status: 403,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (existingRequest.status !== "pending") {
      return new Response(JSON.stringify({
        error: `Bu istek zaten ${existingRequest.status} durumunda, iptal edilemez`
      }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Durumu cancelled olarak güncelle
    const { data: updated, error: updateError } = await supabase
      .from("payout_requests")
      .update({
        status: "cancelled",
        cancelled_at: new Date().toISOString(),
      })
      .eq("id", payout_request_id)
      .eq("status", "pending") // Double-check: race condition koruması
      .select()
      .single();

    if (updateError) {
      throw updateError;
    }

    if (!updated) {
      return new Response(JSON.stringify({
        error: "İstek iptal edilemedi (durum değişmiş olabilir)"
      }), {
        status: 409,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    return new Response(JSON.stringify({
      status: "success",
      message: "Ödeme isteği iptal edildi",
      payout_request: updated,
    }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err: unknown) {
    const error = err as Error;
    console.error("❌ cancel-withdrawal error:", error.message);

    return new Response(JSON.stringify({
      status: "error",
      error: error.message,
    }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});

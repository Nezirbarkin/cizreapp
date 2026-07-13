// smm-order-create Edge Function
// Dijital ürün (SMM panel) siparişi oluşturur: bakiye düşer, sağlayıcı API'sine iletir.
// Deploy: supabase functions deploy smm-order-create

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.38.4";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

async function smmRequest(apiUrl: string, params: Record<string, string>) {
  const res = await fetch(apiUrl, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams(params),
  });
  return await res.json();
}

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
    const { product_id, target_url, quantity } = body;

    if (!product_id || !target_url || !quantity) {
      return new Response(JSON.stringify({ error: "product_id, target_url ve quantity zorunludur" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Ürün doğrulama + atomik bakiye düşme + digital_orders insert (tek DB transaction).
    const { data: rows, error: rpcError } = await supabase.rpc("create_digital_order", {
      p_user_id: user.id,
      p_product_id: product_id,
      p_target_url: target_url,
      p_quantity: parseInt(quantity, 10),
    });

    if (rpcError) {
      const msg = rpcError.message || "Sipariş oluşturulamadı";
      const isInsufficient = /Insufficient balance/i.test(msg);
      return new Response(JSON.stringify({
        status: "error",
        error: isInsufficient ? "Yetersiz bakiye" : msg,
      }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const row = Array.isArray(rows) ? rows[0] : rows;
    const digitalOrderId = row?.digital_order_id;
    const providerId = row?.provider_id;
    const smmServiceId = row?.smm_service_id;
    const totalPrice = row?.total_price != null ? parseFloat(row.total_price) : null;
    const balanceAfter = row?.balance_after != null ? parseFloat(row.balance_after) : null;

    // Sağlayıcının api_url/api_key'ini SADECE service-role client ile oku, client'a asla dönme.
    const { data: provider, error: providerError } = await supabase
      .from("smm_providers")
      .select("api_url, api_key, is_active")
      .eq("id", providerId)
      .single();

    if (providerError || !provider || !provider.is_active) {
      await refundAndFail(supabase, user.id, digitalOrderId, totalPrice!, "Sağlayıcı bulunamadı veya devre dışı");
      return new Response(JSON.stringify({
        status: "error",
        error: "Sağlayıcı şu anda kullanılamıyor, bakiyeniz iade edildi",
      }), {
        status: 502,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    let smmResult: any;
    try {
      smmResult = await smmRequest(provider.api_url, {
        key: provider.api_key,
        action: "add",
        service: smmServiceId,
        link: target_url,
        quantity: String(quantity),
      });
    } catch (fetchErr) {
      await refundAndFail(supabase, user.id, digitalOrderId, totalPrice!, "Sağlayıcıya bağlanılamadı");
      return new Response(JSON.stringify({
        status: "error",
        error: "Sağlayıcıya bağlanılamadı, bakiyeniz iade edildi",
      }), {
        status: 502,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (!smmResult || smmResult.error || !smmResult.order) {
      const providerError = smmResult?.error || "Sağlayıcı siparişi kabul etmedi";
      await refundAndFail(supabase, user.id, digitalOrderId, totalPrice!, providerError);
      return new Response(JSON.stringify({
        status: "error",
        error: "Sağlayıcı siparişi kabul etmedi, bakiyeniz iade edildi",
        debug_detail: providerError,
      }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const { error: updateError } = await supabase
      .from("digital_orders")
      .update({
        external_order_id: String(smmResult.order),
        status: "in_progress",
        last_checked_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      })
      .eq("id", digitalOrderId);

    if (updateError) {
      console.error("❌ digital_orders güncellenemedi (sipariş sağlayıcıya iletildi):", updateError.message);
    }

    return new Response(JSON.stringify({
      status: "success",
      digital_order_id: digitalOrderId,
      external_order_id: smmResult.order,
      total_price: totalPrice,
      new_balance: balanceAfter,
    }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err: unknown) {
    const error = err as Error;
    console.error("❌ smm-order-create error:", error.message);
    return new Response(JSON.stringify({ status: "error", error: error.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});

async function refundAndFail(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  digitalOrderId: string,
  amount: number,
  reason: string,
) {
  try {
    await supabase.rpc("add_to_balance", {
      p_user_id: userId,
      p_amount: amount,
      p_type: "refund",
      p_reference_type: "digital_order",
      p_reference_id: digitalOrderId,
      p_description: `Dijital sipariş başarısız - otomatik iade: ${reason}`,
    });
  } catch (refundErr) {
    console.error("❌ Otomatik iade başarısız:", (refundErr as Error).message);
  }

  await supabase
    .from("digital_orders")
    .update({ status: "failed", error_message: reason, updated_at: new Date().toISOString() })
    .eq("id", digitalOrderId);
}

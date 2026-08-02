// refund-to-balance Edge Function
// Sipariş iptal/iade durumunda bakiyeye iade yapar
// Deploy: supabase functions deploy refund-to-balance
//
// @deprecated (2026-07-09) Bu edge function yeni iptal akışında KULLANILMIYOR.
// Yeni akış: müşteri iptal talebi açar → admin onaylar →
//   approve_cancellation_request RPC (DB) atomik olarak:
//     1) orders.status='cancelled', payment_status='refunded'
//     2) add_to_balance RPC ile bakiyeye iade (refund_amount > 0 ise)
//     3) restore_product_stock trigger
//     4) müşteriye notification
// Bu fonksiyon yalnızca ileriye dönük "admin manuel iade" senaryoları için
// bırakıldı. BalanceService.refundToBalance() yeni akışta çağrılmamalı.

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

    // Kullanıcıyı doğrula (admin veya sistem)
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

    const isAdmin = profile?.role === "admin";

    const body = await req.json();
    const { order_id, amount, reason, is_admin_refund } = body;

    if (!order_id || !amount) {
      return new Response(JSON.stringify({ error: "order_id ve amount zorunludur" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // ═══════════════════════════════════════════════════════════════════════
    // GÜVENLİK: Bu fonksiyon yalnızca admin manuel iade içindir (@deprecated
    // notuna göre). Non-admin yol kapatıldı — eski sürümde is_admin_refund
    // false iken herhangi bir authenticated kullanıcı kendi siparişi için
    // KULLANICI KONTROLLÜ herhangi bir tutarı iade alıp bakiyesini
    // şişirebiliyordu. Artık admin zorunlu + tutar sipariş totaliyle sınırlı.
    // ═══════════════════════════════════════════════════════════════════════
    if (!isAdmin) {
      return new Response(JSON.stringify({ error: "Bu işlem için admin yetkisi gerekli" }), {
        status: 403,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const amountNum = parseFloat(amount);
    if (isNaN(amountNum) || !isFinite(amountNum) || amountNum <= 0) {
      return new Response(JSON.stringify({ error: "Geçersiz iade tutarı (pozitif sayı olmalı)" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Siparişi bul (total + durum iade doğrulaması için gerekli)
    const { data: order, error: orderError } = await supabase
      .from("orders")
      .select("*, user_id, total, status, payment_status")
      .eq("id", order_id)
      .single();

    if (orderError || !order) {
      return new Response(JSON.stringify({ error: "Sipariş bulunamadı" }), {
        status: 404,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // İade tutarı sipariş totalini aşamaz (arbitrary balance inflation önle)
    const orderTotal = Number(order.total ?? 0);
    if (amountNum > orderTotal) {
      return new Response(JSON.stringify({
        error: `İade tutarı sipariş tutarını aşamaz (sipariş: ₺${orderTotal.toFixed(2)})`,
      }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // İade edilebilir durum kontrolü: iptal edilmiş veya ödenmiş siparişler.
    // Devam eden (pending/confirmed/preparing/on_the_way) siparişlere manuel
    // iade yapılmamalı — iptal akışı approve_cancellation_request RPC'sini
    // kullanmalı.
    const refundableStatus = ["cancelled", "delivered"];
    if (!refundableStatus.includes(order.status)) {
      return new Response(JSON.stringify({
        error: `Bu sipariş durumunda iade yapılamaz (mevcut: ${order.status}). İptal için onay akışını kullanın.`,
      }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Admin-only olduğu için hedef kullanıcı her zaman sipariş sahibi.
    const targetUserId = order.user_id;

    // Daha önce iade yapılmış mı kontrol et
    const { data: existingRefund } = await supabase
      .from("balance_transactions")
      .select("id, amount")
      .eq("reference_id", order_id)
      .eq("type", "refund")
      .eq("status", "completed")
      .maybeSingle();

    if (existingRefund) {
      return new Response(JSON.stringify({
        error: "Bu sipariş için zaten iade yapılmış",
        existing_refund_id: existingRefund.id,
        existing_refund_amount: existingRefund.amount,
      }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Bakiyeyi al
    const { data: balance, error: balanceError } = await supabase
      .from("user_balances")
      .select("*")
      .eq("user_id", targetUserId)
      .single();

    if (balanceError && balanceError.code !== "PGRST116") {
      throw balanceError;
    }

    const balanceBefore = parseFloat(balance?.balance || "0");
    const balanceAfter = balanceBefore + amountNum;

    // Bakiyeyi güncelle (oluşturmamışsa oluştur)
    if (balance) {
      await supabase
        .from("user_balances")
        .update({
          balance: balanceAfter,
          total_earned: parseFloat(balance.total_earned || "0") + amountNum,
          updated_at: new Date().toISOString(),
        })
        .eq("user_id", targetUserId);
    } else {
      await supabase
        .from("user_balances")
        .insert({
          user_id: targetUserId,
          balance: amountNum,
          total_earned: amountNum,
        });
    }

    // İade kaydı oluştur
    const { data: transaction, error: transactionError } = await supabase
      .from("balance_transactions")
      .insert({
        user_id: targetUserId,
        type: "refund",
        amount: amountNum,
        net_amount: amountNum,
        balance_before: balanceBefore,
        balance_after: balanceAfter,
        reference_type: "order",
        reference_id: order_id,
        status: "completed",
        description: reason || `Sipariş iadesi - ${order.order_number || order_id.substring(0, 8)}`,
        payment_method: "balance",
        metadata: {
          refund_reason: reason,
          refunded_by: user.id,
          refunded_at: new Date().toISOString(),
        },
      })
      .select()
      .single();

    if (transactionError) {
      throw transactionError;
    }

    console.log("✅ Bakiyeye iade yapıldı:", {
      orderId: order_id,
      userId: targetUserId,
      amount: amountNum,
      newBalance: balanceAfter,
      refundedBy: isAdmin ? "admin" : "customer",
    });

    return new Response(JSON.stringify({
      status: "success",
      transaction_id: transaction.id,
      refund_amount: amountNum,
      new_balance: balanceAfter,
    }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err: unknown) {
    const error = err as Error;
    console.error("❌ refund-to-balance error:", error.message);

    return new Response(JSON.stringify({
      status: "error",
      error: error.message,
    }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});

// use-balance-for-order Edge Function
// Sipariş ödemesinde bakiye kullanır
// Deploy: supabase functions deploy use-balance-for-order

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

    const body = await req.json();
    const { order_id, amount, order_total } = body;

    if (!order_id || !amount) {
      return new Response(JSON.stringify({ error: "order_id ve amount zorunludur" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const amountNum = parseFloat(amount);

    // Siparişi kontrol et
    const { data: order, error: orderError } = await supabase
      .from("orders")
      .select("*")
      .eq("id", order_id)
      .eq("user_id", user.id)
      .single();

    if (orderError || !order) {
      return new Response(JSON.stringify({ error: "Sipariş bulunamadı" }), {
        status: 404,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Zaten ödenmişse kontrol et
    if (order.payment_status === "completed" || order.payment_status === "paid") {
      return new Response(JSON.stringify({ error: "Bu sipariş zaten ödenmiş" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Bakiyeyi atomik olarak düş (check-then-act race condition önleme)
    // Tek sorguda: WHERE balance >= amount kontrolü + UPDATE + RETURNING
    // Eşzamanlı iki istek aynı snapshot'ı okuyup üzerine yazamaz çünkü UPDATE
    // PostgreSQL'de satır bazlı lock alır ve koşulu tekrar değerlendirir.
    const { data: deductedRows, error: deductError } = await supabase
      .rpc("deduct_from_balance", {
        p_user_id: user.id,
        p_amount: amountNum,
        p_type: "order_payment",
        p_reference_type: "order",
        p_reference_id: order_id,
        p_description: `Sipariş ödemesi - ${order.order_number || order_id.substring(0, 8)}`,
      });

    if (deductError) {
      // Yetersiz bakiye veya bakiye kaydı yok RPC içinde raise exception fırlatır
      const msg = deductError.message || "Bakiye düşülemedi";
      const isInsufficient = /Insufficient balance/i.test(msg);
      const isNoRecord = /Balance record not found/i.test(msg);
      return new Response(JSON.stringify({
        status: "error",
        error: isInsufficient ? "Yetersiz bakiye" : isNoRecord ? "Bakiye kaydı bulunamadı" : msg,
      }), {
        status: isInsufficient ? 400 : 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // deduct_from_balance RPC atomik olarak (FOR UPDATE lock ile):
    //   - bakiye kontrolü yapar (yetersizse exception fırlatır)
    //   - user_balances.balance düşürür
    //   - balance_transactions kaydı oluşturur
    //   - transaction_id, balance_before, balance_after döndürür
    // Transaction kaydı RPC içinde oluşturulduğu için burada tekrar insert edilmez.
    // RPC RETURNS TABLE(...) döndürdüğü için Supabase-JS data bir dizi (array) döner.
    const row = Array.isArray(deductedRows) ? deductedRows[0] : deductedRows;
    const transactionId = row?.transaction_id ?? null;
    const balanceAfter = row?.balance_after != null ? parseFloat(row.balance_after) : null;

    // Siparişin payment_method ve payment_status'unu güncelle
    // Eğer tamamen bakiye ile ödendiyse
    const remainingAmount = (order_total ?? 0) - amountNum;

    await supabase
      .from("orders")
      .update({
        payment_method: "balance", // bakiye ile ödeme
        payment_status: remainingAmount <= 0 ? "completed" : "partial",
        updated_at: new Date().toISOString(),
      })
      .eq("id", order_id);

    console.log("✅ Bakiye ile sipariş ödemesi:", {
      orderId: order_id,
      amount: amountNum,
      remainingAmount,
      newBalance: balanceAfter,
      transactionId,
    });

    return new Response(JSON.stringify({
      status: "success",
      transaction_id: transactionId,
      amount_paid: amountNum,
      remaining_amount: remainingAmount,
      new_balance: balanceAfter,
      is_fully_paid: remainingAmount <= 0,
    }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err: unknown) {
    const error = err as Error;
    console.error("❌ use-balance-for-order error:", error.message);

    return new Response(JSON.stringify({
      status: "error",
      error: error.message,
    }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});

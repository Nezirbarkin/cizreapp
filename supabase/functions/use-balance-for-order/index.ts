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

    // Bakiyeyi kilitle ve kontrol et
    const { data: balance, error: balanceError } = await supabase
      .from("user_balances")
      .select("*")
      .eq("user_id", user.id)
      .single();

    if (balanceError) {
      throw balanceError;
    }

    if (!balance) {
      return new Response(JSON.stringify({ error: "Bakiye kaydı bulunamadı" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const availableBalance = parseFloat(balance.balance) - parseFloat(balance.locked_balance);

    if (availableBalance < amountNum) {
      return new Response(JSON.stringify({
        error: "Yetersiz bakiye",
        available_balance: availableBalance,
        required_amount: amountNum,
      }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // İşlem başlangıcı
    const balanceBefore = parseFloat(balance.balance);
    const balanceAfter = balanceBefore - amountNum;

    // Bakiyeyi düş
    await supabase
      .from("user_balances")
      .update({
        balance: balanceAfter,
        total_spent: parseFloat(balance.total_spent) + amountNum,
        updated_at: new Date().toISOString(),
      })
      .eq("user_id", user.id);

    // İşlem kaydı oluştur
    const { data: transaction, error: transactionError } = await supabase
      .from("balance_transactions")
      .insert({
        user_id: user.id,
        type: "order_payment",
        amount: amountNum,
        net_amount: amountNum,
        balance_before: balanceBefore,
        balance_after: balanceAfter,
        reference_type: "order",
        reference_id: order_id,
        status: "completed",
        description: `Sipariş ödemesi - ${order.order_number || order_id.substring(0, 8)}`,
        payment_method: "balance",
      })
      .select()
      .single();

    if (transactionError) {
      throw transactionError;
    }

    // Siparişin payment_method ve payment_status'unu güncelle
    // Eğer tamamen bakiye ile ödendiyse
    const remainingAmount = order_total - amountNum;
    
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
    });

    return new Response(JSON.stringify({
      status: "success",
      transaction_id: transaction.id,
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

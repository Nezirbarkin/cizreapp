// get-balance Edge Function
// Kullanıcının mevcut bakiyesini getirir
// Deploy: supabase functions deploy get-balance

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

    // Bakiyeyi getir
    const { data: balance, error: balanceError } = await supabase
      .from("user_balances")
      .select("*")
      .eq("user_id", user.id)
      .maybeSingle();

    if (balanceError) {
      throw balanceError;
    }

    // Bakiye yoksa oluştur
    if (!balance) {
      const { data: newBalance, error: createError } = await supabase
        .from("user_balances")
        .insert({ user_id: user.id, balance: 0, locked_balance: 0 })
        .select()
        .single();

      if (createError) {
        throw createError;
      }

      return new Response(JSON.stringify({
        status: "success",
        balance: {
          ...newBalance,
          available_balance: newBalance.balance,
        },
      }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    return new Response(JSON.stringify({
      status: "success",
      balance: {
        ...balance,
        available_balance: balance.balance - balance.locked_balance,
      },
    }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err: unknown) {
    const error = err as Error;
    console.error("❌ get-balance error:", error.message);

    return new Response(JSON.stringify({
      status: "error",
      error: error.message,
    }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});

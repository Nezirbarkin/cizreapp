// request-withdrawal Edge Function
// Satıcı çekim talebi oluşturur
// Deploy: supabase functions deploy request-withdrawal

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
      .select("role, full_name")
      .eq("id", user.id)
      .single();

    if (profile?.role !== "seller" && profile?.role !== "admin") {
      return new Response(JSON.stringify({ error: "Bu işlem için satıcı hesabı gerekli" }), {
        status: 403,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const body = await req.json();
    const { amount, bank_account_name, bank_account_number, bank_name, iban } = body;

    if (!amount || !bank_name || !iban) {
      return new Response(JSON.stringify({
        error: "amount, bank_name ve iban zorunludur"
      }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const amountNum = parseFloat(amount);

    // Sistem ayarlarını al
    const { data: settings } = await supabase
      .from("app_about_settings")
      .select("min_withdrawal_amount, withdrawal_fee_percent")
      .maybeSingle();

    const minWithdrawal = settings?.min_withdrawal_amount || 50;
    const feePercent = settings?.withdrawal_fee_percent || 2;

    if (amountNum < minWithdrawal) {
      return new Response(JSON.stringify({
        error: `Minimum çekim tutarı ${minWithdrawal} TL'dir`
      }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Çekilebilir tutarı hesapla
    const fee = Math.round(amountNum * feePercent / 100 * 100) / 100;
    const netAmount = amountNum - fee;

    // Bekleyen çekimleri kontrol et
    const { data: pendingWithdrawals } = await supabase
      .from("seller_withdrawals")
      .select("id")
      .eq("seller_id", user.id)
      .eq("status", "pending");

    if (pendingWithdrawals && pendingWithdrawals.length > 0) {
      return new Response(JSON.stringify({
        error: "Zaten bekleyen bir çekim talebiniz var. Lütfen önce onu iptal edin veya tamamlanmasını bekleyin."
      }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Çekilebilir tutarı kontrol et (satıcı kazançlarından)
    const { data: earningsData } = await supabase
      .from("seller_earnings")
      .select("net_amount")
      .eq("seller_id", user.id)
      .eq("status", "available");

    const withdrawableFromEarnings = earningsData?.reduce((sum, e) => sum + parseFloat(e.net_amount || "0"), 0) || 0;

    // IBAN format kontrolü (basit) + mod-97 checksum doğrulaması
    const cleanIban = iban.replace(/\s/g, "").toUpperCase();
    if (!cleanIban.startsWith("TR") || cleanIban.length !== 26) {
      return new Response(JSON.stringify({
        error: "Geçersiz IBAN formatı. Türk IBAN'ı TR ile başlamalı ve 26 karakter olmalıdır."
      }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // IBAN checksum (mod-97) doğrulaması - ISO 13616
    // 1. İlk 4 karakteri sona taşı
    // 2. Harfleri sayıya çevir (A=10, B=11, ..., Z=35)
    // 3. Mod 97 == 1 olmalı
    const rearranged = cleanIban.slice(4) + cleanIban.slice(0, 4);
    const numericIban = rearranged.replace(/[A-Z]/g, (ch) =>
      (ch.charCodeAt(0) - 55).toString()
    );
    // BigInt ile büyük sayı hesabı
    let remainder = 0n;
    for (const digit of numericIban) {
      remainder = (remainder * 10n + BigInt(digit)) % 97n;
    }
    if (remainder !== 1n) {
      return new Response(JSON.stringify({
        error: "Geçersiz IBAN (checksum doğrulaması başarısız)"
      }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Çekim talebi oluştur
    const { data: withdrawal, error: withdrawalError } = await supabase
      .from("seller_withdrawals")
      .insert({
        seller_id: user.id,
        amount: amountNum,
        fee_percent: feePercent,
        fee: fee,
        net_amount: netAmount,
        status: "pending",
        bank_account_name: bank_account_name || profile?.full_name || "",
        bank_account_number: bank_account_number || "",
        bank_name: bank_name,
        iban: cleanIban,
      })
      .select()
      .single();

    if (withdrawalError) {
      throw withdrawalError;
    }

    console.log("✅ Çekim talebi oluşturuldu:", {
      withdrawalId: withdrawal.id,
      sellerId: user.id,
      amount: amountNum,
      netAmount,
    });

    return new Response(JSON.stringify({
      status: "success",
      withdrawal_id: withdrawal.id,
      amount: amountNum,
      fee: fee,
      net_amount: netAmount,
      status: "pending",
    }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err: unknown) {
    const error = err as Error;
    console.error("❌ request-withdrawal error:", error.message);

    return new Response(JSON.stringify({
      status: "error",
      error: error.message,
    }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});

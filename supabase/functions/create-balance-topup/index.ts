// create-balance-topup Edge Function
// Bakiye yükleme için iyzico ödeme başlatır
// Deploy: supabase functions deploy create-balance-topup

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.38.4";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const IYZICO_API_URL = Deno.env.get("IYZICO_API_URL") || "https://sandbox-api.iyzipay.com";
const IYZICO_API_KEY = Deno.env.get("IYZICO_API_KEY") || "";
const IYZICO_SECRET_KEY = Deno.env.get("IYZICO_SECRET_KEY") || "";

// iyzico v2 Authorization
async function generateAuthorizationHeaderV2(
  apiKey: string,
  secretKey: string,
  randomString: string,
  requestBody: string
): Promise<{ authorization: string; randomString: string }> {
  const uri = "/payment/iyzipos/checkoutform/initialize/auth/ecom";
  const hashStr = randomString + uri + requestBody;

  const encoder = new TextEncoder();
  const keyData = encoder.encode(secretKey);
  const msgData = encoder.encode(hashStr);

  const cryptoKey = await crypto.subtle.importKey("raw", keyData, { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const signatureBuffer = await crypto.subtle.sign("HMAC", cryptoKey, msgData);
  const signatureArray = new Uint8Array(signatureBuffer);
  const signatureHex = Array.from(signatureArray).map((b) => b.toString(16).padStart(2, "0")).join("");

  const authorizationParams = `apiKey:${apiKey}&randomKey:${randomString}&signature:${signatureHex}`;
  const authorizationBase64 = btoa(authorizationParams);

  return { authorization: `IYZWSv2 ${authorizationBase64}`, randomString };
}

function generateRandomString(): string {
  const array = new Uint8Array(8);
  crypto.getRandomValues(array);
  return Array.from(array, (byte) => byte.toString(16).padStart(2, "0")).join("");
}

function generateConversationId(): string {
  return `bal_${Date.now()}_${Math.random().toString(36).substring(2, 10)}`;
}

function formatPhoneNumber(phone: string): string {
  const digits = phone.replace(/\D/g, "");
  if (digits.startsWith("90")) return `+${digits}`;
  if (digits.startsWith("0")) return `+9${digits}`;
  return `+90${digits}`;
}

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

    // Kullanıcı profilini al
    const { data: profile, error: profileError } = await supabase
      .from("profiles")
      .select("*")
      .eq("id", user.id)
      .single();

    if (profileError || !profile) {
      throw new Error("Kullanıcı profili bulunamadı");
    }

    // Sistem ayarlarını al
    const { data: settings } = await supabase
      .from("app_about_settings")
      .select("min_topup_amount, max_topup_amount, balance_enabled")
      .maybeSingle();

    if (!settings?.balance_enabled) {
      throw new Error("Bakiye yükleme şu an aktif değil");
    }

    const body = await req.json();
    const amount = parseFloat(body.amount);

    // Tutar validasyonu
    const minAmount = settings?.min_topup_amount || 10;
    const maxAmount = settings?.max_topup_amount || 10000;

    if (isNaN(amount) || amount < minAmount) {
      throw new Error(`Minimum yükleme tutarı ${minAmount} TL'dir`);
    }

    if (amount > maxAmount) {
      throw new Error(`Maximum yükleme tutarı ${maxAmount} TL'dir`);
    }

    // Conversation ID oluştur
    const conversationId = generateConversationId();

    // Callback URL
    const callbackUrl = `${supabaseUrl}/functions/v1/confirm-balance-topup`;

    // iyzico request body
    const iyzicoRequest = {
      locale: "tr",
      conversationId: conversationId,
      price: amount.toFixed(2),
      paidPrice: amount.toFixed(2),
      currency: "TRY",
      basketId: `BAL_${conversationId}`,
      paymentGroup: "PRODUCT",
      callbackUrl: callbackUrl,
      enabledInstallments: [1],
      buyer: {
        id: user.id,
        name: profile.full_name?.split(" ")[0] || "User",
        surname: profile.full_name?.split(" ").slice(1).join(" ") || "User",
        identityNumber: "11111111111",
        email: user.email || "user@example.com",
        gsmNumber: formatPhoneNumber(profile.phone || "5000000000"),
        registrationAddress: profile.address || "Adres",
        city: "İstanbul",
        country: "Turkey",
        zipCode: "34000",
        ip: req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() || "127.0.0.1",
      },
      shippingAddress: {
        contactName: profile.full_name || "User",
        city: "İstanbul",
        country: "Turkey",
        address: profile.address || "Adres",
        zipCode: "34000",
      },
      billingAddress: {
        contactName: profile.full_name || "User",
        city: "İstanbul",
        country: "Turkey",
        address: profile.address || "Adres",
        zipCode: "34000",
      },
      basketItems: [{
        id: "BALANCE_TOPUP",
        name: "Bakiye Yükleme",
        category1: "Bakiye",
        itemType: "VIRTUAL",
        price: amount.toFixed(2),
      }],
    };

    const bodyString = JSON.stringify(iyzicoRequest);
    const randomHeaderValue = generateRandomString();
    const { authorization, randomString } = await generateAuthorizationHeaderV2(
      IYZICO_API_KEY, IYZICO_SECRET_KEY, randomHeaderValue, bodyString
    );

    // iyzico API'ye istek gönder
    const response = await fetch(`${IYZICO_API_URL}/payment/iyzipos/checkoutform/initialize/auth/ecom`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
        Authorization: authorization,
        "x-iyzi-rnd": randomString,
      },
      body: bodyString,
    });

    const result = await response.json();

    if (result.status !== "success") {
      throw new Error(result.errorMessage || "Ödeme başlatılamadı");
    }

    // İşlem kaydı oluştur (pending durumunda)
    await supabase.from("balance_transactions").insert({
      user_id: user.id,
      type: "topup",
      amount: amount,
      net_amount: amount,
      balance_before: 0,
      balance_after: 0,
      reference_type: "topup",
      reference_id: null,
      status: "pending",
      description: `Bakiye yükleme - ${amount} TL`,
      payment_method: "card",
      payment_reference: conversationId,
      metadata: { token: result.token },
    });

    console.log("✅ Balance topup başlatıldı:", { conversationId, amount });

    return new Response(JSON.stringify({
      status: "success",
      payment_page_url: result.paymentPageUrl,
      token: result.token,
      conversation_id: conversationId,
    }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err: unknown) {
    const error = err as Error;
    console.error("❌ create-balance-topup error:", error.message);

    return new Response(JSON.stringify({
      status: "error",
      error: error.message,
    }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});

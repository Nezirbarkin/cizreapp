// create-balance-topup Edge Function
// Bakiye yükleme için iyzico ödeme başlatır
// Deploy: supabase functions deploy create-balance-topup
// GÜVENLİK: Rate limiting, input validation, audit logging eklenmiştir

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.38.4";

console.log("✅ create-balance-topup Edge Function başlatıldı");

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// iyzico API URL (env'den veya varsayılan)
const IYZICO_API_URL = Deno.env.get("IYZICO_API_URL") || "https://sandbox-api.iyzipay.com";

// ────────── iyzico İmza Oluşturma (SHA-256 HMAC - iyzico v2) ──────────

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

  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    keyData,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );

  const signatureBuffer = await crypto.subtle.sign("HMAC", cryptoKey, msgData);
  const signatureArray = new Uint8Array(signatureBuffer);
  const signatureHex = Array.from(signatureArray)
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");

  const authorizationParams = `apiKey:${apiKey}&randomKey:${randomString}&signature:${signatureHex}`;
  const authorizationBase64 = btoa(authorizationParams);

  return {
    authorization: `IYZWSv2 ${authorizationBase64}`,
    randomString,
  };
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

// ────────── iyzico API Çağrısı ──────────

async function initializeIyzicoCheckout(
  iyzicoApiKey: string,
  iyzicoSecretKey: string,
  conversationId: string,
  amount: number,
  userEmail: string,
  userPhone: string,
  userName: string,
  userId: string,
  ipAddress: string,
  callbackUrl: string
): Promise<{ paymentPageUrl: string; token: string }> {
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
      id: userId,
      name: userName.split(" ")[0] || "User",
      surname: userName.split(" ").slice(1).join(" ") || "User",
      identityNumber: "11111111111",
      email: userEmail || "user@example.com",
      gsmNumber: formatPhoneNumber(userPhone || "5000000000"),
      registrationAddress: "Adres",
      city: "İstanbul",
      country: "Turkey",
      zipCode: "34000",
      ip: ipAddress,
    },
    shippingAddress: {
      contactName: userName || "User",
      city: "İstanbul",
      country: "Turkey",
      address: "Adres",
      zipCode: "34000",
    },
    billingAddress: {
      contactName: userName || "User",
      city: "İstanbul",
      country: "Turkey",
      address: "Adres",
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

  // Authorization header oluştur
  const { authorization, randomString } = await generateAuthorizationHeaderV2(
    iyzicoApiKey,
    iyzicoSecretKey,
    randomHeaderValue,
    bodyString
  );

  console.log("📤 iyzico checkout form isteği gönderiliyor:", {
    conversationId,
    amount,
    authMethod: "IYZWSv2",
  });

  // iyzico API'ye istek gönder
  const response = await fetch(
    `${IYZICO_API_URL}/payment/iyzipos/checkoutform/initialize/auth/ecom`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
        Authorization: authorization,
        "x-iyzi-rnd": randomString,
      },
      body: bodyString,
    }
  );

  const result = await response.json();

  if (result.status !== "success") {
    console.error("❌ iyzico hatası:", {
      errorCode: result.errorCode,
      errorMessage: result.errorMessage,
      errorGroup: result.errorGroup,
    });

    let userMessage = result.errorMessage || "Ödeme başlatılamadı";

    // Kullanıcı dostu mesajlar
    if (result.errorCode === "UNAUTHORIZED_NO_AUTH_HEADER" || result.errorCode === "UNAUTHORIZED") {
      userMessage = "Ödeme sistemi yapılandırma hatası. Lütfen yönetici ile iletişime geçin.";
    } else if (result.errorCode === "VALIDATION_ERROR") {
      userMessage = "Gönderilen bilgilerde hata var. Lütfen tekrar deneyin.";
    } else if (result.errorMessage?.includes("connection") || result.errorMessage?.includes("timeout")) {
      userMessage = "Ödeme sağlayıcısına bağlantı sağlanamadı. Lütfen daha sonra tekrar deneyin.";
    }

    throw new Error(userMessage);
  }

  console.log("✅ iyzico checkout form başarılı:", {
    token: result.token?.substring(0, 20) + "...",
  });

  return {
    paymentPageUrl: result.paymentPageUrl,
    token: result.token,
  };
}

// ────────── Ana Handler ──────────

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    // Auth kontrolü
    const authHeader = req.headers.get("authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: "Unauthorized" }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // Supabase client
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // Kullanıcıyı doğrula
    const { data: { user }, error: authError } = await supabase.auth.getUser(
      authHeader.replace("Bearer ", "")
    );

    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: "Geçersiz oturum" }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
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

    // Sistem ayarlarını al (iyzico credentials dahil)
    const { data: settings } = await supabase
      .from("app_about_settings")
      .select("min_topup_amount, max_topup_amount, balance_enabled, card_topup_enabled, iyzico_api_key, iyzico_secret_key, iyzico_api_url")
      .maybeSingle();

    if (!settings) {
      throw new Error("Sistem ayarları bulunamadı");
    }

    // Bakiye yükleme aktif mi?
    if (!settings?.balance_enabled) {
      throw new Error("Bakiye yükleme şu an aktif değil");
    }

    // Kredi kartı ile ödeme aktif mi?
    if (settings?.card_topup_enabled === false) {
      throw new Error("Kredi kartı ile bakiye yükleme şu an pasif durumda. Lütfen havale yöntemini kullanın.");
    }

    // iyzico credentials kontrolü
    let iyzicoApiKey = settings?.iyzico_api_key;
    let iyzicoSecretKey = settings?.iyzico_secret_key;
    const iyzicoApiUrl = settings?.iyzico_api_url || IYZICO_API_URL;

    // Env'den fallback
    if (!iyzicoApiKey) iyzicoApiKey = Deno.env.get("IYZICO_API_KEY") || "";
    if (!iyzicoSecretKey) iyzicoSecretKey = Deno.env.get("IYZICO_SECRET_KEY") || "";

    if (!iyzicoApiKey || !iyzicoSecretKey) {
      console.error("❌ iyzico credentials eksik!");
      console.error("   iyzico_api_key: " + (settings?.iyzico_api_key ? "✅ DB'de var" : "❌ DB'de yok"));
      console.error("   IYZICO_API_KEY env: " + (Deno.env.get("IYZICO_API_KEY") ? "✅ env'de var" : "❌ env'de yok"));
      throw new Error("Ödeme sistemi henüz yapılandırılmamış. Lütfen yönetici ile iletişime geçin.");
    }

    // Request body
    const body = await req.json();

    // ═══════════════════════════════════════════════════════════════════════
    // GÜVENLİK 1: Input Validation - Tip ve format kontrolü
    // ═══════════════════════════════════════════════════════════════════════
    if (typeof body.amount !== 'number' && typeof body.amount !== 'string') {
      throw new Error("Geçersiz tutar formatı");
    }

    const amount = parseFloat(body.amount);

    // NaN ve Infinity kontrolü
    if (isNaN(amount) || !isFinite(amount)) {
      throw new Error("Geçersiz tutar");
    }

    // Çok küçük veya çok büyük sayılar (overflow/underflow koruması)
    if (amount <= 0 || amount > 1000000) {
      throw new Error("Geçersiz tutar aralığı");
    }

    // Ondalık hassasiyet kontrolü (sadece 2 hane)
    if (Math.round(amount * 100) !== amount * 100) {
      throw new Error("Tutar en fazla 2 ondalık basamak içerebilir");
    }

    // Tutar validasyonu
    const minAmount = settings?.min_topup_amount || 10;
    const maxAmount = settings?.max_topup_amount || 10000;

    if (amount < minAmount) {
      throw new Error(`Minimum yükleme tutarı ${minAmount} TL'dir`);
    }

    if (amount > maxAmount) {
      throw new Error(`Maximum yükleme tutarı ${maxAmount} TL'dir`);
    }

    // Conversation ID oluştur
    const conversationId = generateConversationId();

    // Callback URL
    const callbackUrl = `${supabaseUrl}/functions/v1/confirm-balance-topup`;

    // ═══════════════════════════════════════════════════════════════════════
    // GÜVENLİK 2: Client IP güvenli çıkarma
    // ═══════════════════════════════════════════════════════════════════════
    let clientIp: string | null = null;
    const forwardedFor = req.headers.get("x-forwarded-for");
    if (forwardedFor) {
      const firstIp = forwardedFor.split(",")[0]?.trim();
      // Basit IP validasyonu
      if (firstIp && /^[\d.:a-fA-F]+$/.test(firstIp) && firstIp.length < 45) {
        clientIp = firstIp;
      }
    }
    if (!clientIp) {
      clientIp = req.headers.get("x-real-ip") || null;
    }
    if (!clientIp || !/^[\d.:a-fA-F]+$/.test(clientIp)) {
      clientIp = "127.0.0.1"; // Fallback
    }

    // ═══════════════════════════════════════════════════════════════════════
    // GÜVENLİK 3: User Agent ve Cihaz Parmak İzi
    // ═══════════════════════════════════════════════════════════════════════
    const userAgent = req.headers.get("user-agent") || null;
    const acceptLang = req.headers.get("accept-language") || "";
    let deviceFingerprint: string | null = null;
    if (userAgent) {
      const fpData = new TextEncoder().encode(userAgent + "|" + acceptLang);
      const fpHash = await crypto.subtle.digest("SHA-256", fpData);
      deviceFingerprint = Array.from(new Uint8Array(fpHash))
        .map(b => b.toString(16).padStart(2, "0")).join("");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // GÜVENLİK 4: Rate Limit Kontrolü
    // ═══════════════════════════════════════════════════════════════════════
    const { data: rateCheck, error: rateError } = await supabase.rpc(
      "check_balance_rate_limit",
      {
        p_user_id: user.id,
        p_amount: amount,
        p_ip_address: clientIp,
        p_device_fingerprint: deviceFingerprint,
      }
    );

    if (rateError) {
      console.error("⚠️ Rate limit kontrol hatası:", rateError);
      // Hata durumunda işlemi durdurmuyoruz, sadece logluyoruz
    } else {
      const rateRow = Array.isArray(rateCheck) ? rateCheck[0] : rateCheck;
      
      if (rateRow?.allowed === false) {
        const reason = rateRow?.reason || "İşlem limiti aşıldı";
        console.warn("🚨 Rate limit aşıldı:", {
          userId: user.id,
          amount,
          reason,
          currentCount: rateRow?.current_count,
          currentAmount: rateRow?.current_amount,
          riskScore: rateRow?.risk_score,
        });

        // Güvenlik logu
        await supabase.rpc("log_balance_security_event", {
          p_event_type: "rate_limit_exceeded",
          p_user_id: user.id,
          p_ip_address: clientIp,
          p_user_agent: userAgent,
          p_device_fingerprint: deviceFingerprint,
          p_amount: amount,
          p_payment_method: "card",
          p_payment_reference: conversationId,
          p_status: "blocked",
          p_failure_reason: reason,
          p_risk_score: rateRow?.risk_score || 0,
          p_risk_factors: rateRow?.risk_factors || "[]",
          p_metadata: JSON.stringify({
            current_count: rateRow?.current_count,
            current_amount: rateRow?.current_amount,
            limit_count: rateRow?.limit_count,
            limit_amount: rateRow?.limit_amount,
          }),
        });

        return new Response(
          JSON.stringify({
            status: "error",
            error: reason,
          }),
          {
            status: 429, // Too Many Requests
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          }
        );
      }

      // Yüksek risk skoru varsa uyar (engelleme değil)
      if (rateRow?.risk_score >= 40) {
        console.warn("⚠️ Yüksek riskli işlem:", {
          userId: user.id,
          amount,
          riskScore: rateRow?.risk_score,
          factors: rateRow?.risk_factors,
        });
      }
    }

    console.log("💰 Bakiye yükleme başlatılıyor:", {
      userId: user.id,
      amount,
      conversationId,
      clientIp,
    });

    // ═══════════════════════════════════════════════════════════════════════
    // GÜVENLİK 5: İşlem başladı logu
    // ═══════════════════════════════════════════════════════════════════════
    await supabase.rpc("log_balance_security_event", {
      p_event_type: "topup_initiated",
      p_user_id: user.id,
      p_ip_address: clientIp,
      p_user_agent: userAgent,
      p_device_fingerprint: deviceFingerprint,
      p_amount: amount,
      p_payment_method: "card",
      p_payment_reference: conversationId,
      p_status: "pending",
    });

    // Mevcut bakiyeyi al (balance_before için)
    // balance_transactions tablosunda balance_before/balance_after NOT NULL
    // ve CHECK kısıtlaması var, o yüzden 0 göndermek hataya yol açıyor.
    const { data: currentBalanceRow } = await supabase
      .from("user_balances")
      .select("balance")
      .eq("user_id", user.id)
      .maybeSingle();

    const currentBalance = currentBalanceRow?.balance || 0;
    // Pending işlemde balance_after henüz gerçek bakiye değil,
    // ama tablo CHECK (>0) kabul etmediği için mevcut bakiye + tutar olarak kaydediyoruz.
    // confirm-balance-topup callback'inde status='completed' olunca zaten
    // user_balances güncelleniyor; bu satır sadece CHECK constraint'i geçmek için.
    const projectedBalance = currentBalance + amount;

    // iyzico Checkout Form başlat
    const iyzicoResult = await initializeIyzicoCheckout(
      iyzicoApiKey,
      iyzicoSecretKey,
      conversationId,
      amount,
      user.email || "user@example.com",
      profile.phone || "5000000000",
      profile.full_name || "User",
      user.id,
      clientIp,
      callbackUrl
    );

    // İşlem kaydı oluştur (pending durumunda)
    const { error: insertError } = await supabase.from("balance_transactions").insert({
      user_id: user.id,
      type: "topup",
      amount: amount,
      net_amount: amount,
      balance_before: currentBalance,
      balance_after: projectedBalance,
      reference_type: "topup",
      reference_id: null,
      status: "pending",
      description: `Bakiye yükleme - ${amount} TL`,
      payment_method: "card",
      payment_reference: conversationId,
      metadata: { token: iyzicoResult.token },
    });

    if (insertError) {
      console.error("❌ balance_transactions insert hatası:", insertError);
      throw new Error(`İşlem kaydı oluşturulamadı: ${insertError.message}`);
    }

    console.log("✅ Bakiye yükleme başlatıldı:", { conversationId, amount });

    return new Response(
      JSON.stringify({
        status: "success",
        payment_page_url: iyzicoResult.paymentPageUrl,
        token: iyzicoResult.token,
        conversation_id: conversationId,
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  } catch (err: unknown) {
    const error = err as Error;
    console.error("❌ create-balance-topup error:", error.message);

    return new Response(
      JSON.stringify({
        status: "error",
        error: error.message,
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }
});

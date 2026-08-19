// iyzico Ödeme Başlatma Edge Function (SERVER-AUTHORITATIVE)
// Tarih: 2026-08-02
//
// Bu fonksiyon artik SADECE checkout_session_id + idempotency_key alir.
// Tum finansal alanlar (items, price, paidPrice, buyer) sunucu tarafindan
// private.server_checkout_sessions tablosundan okunur.
// Client ASLA fiyat/kupon/buyer gonderemez.
//
// Güvenlik özet:
// - IYZICO_ENV zorunlu (sandbox veya production); eksikse 403
// - Production'da sandbox URL'e sessiz fallback YOK
// - TCKN sabit '11111111111' fallback KALDIRILDI
// - JWT dogrulanir, session user_id ile eslesme zorunlu
// - Loglama yalnizca transaction_id, expected_amount, hata kodu

// deno-lint-ignore-file no-explicit-any
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.38.4";

console.log("iyzico Payment Init (server-authoritative) baslatildi");

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// ═════════════════════════════════════════════════════════════════
// IYZICO API CONFIG — fail-closed
// ═════════════════════════════════════════════════════════════════
const IYZICO_ENV = Deno.env.get("IYZICO_ENV"); // 'sandbox' | 'production' — ZORUNLU
const IYZICO_API_KEY = Deno.env.get("IYZICO_API_KEY") || "";
const IYZICO_SECRET_KEY = Deno.env.get("IYZICO_SECRET_KEY") || "";

function getIyzicoApiUrl(): string {
  if (IYZICO_ENV === "production") return "https://api.iyzipay.com";
  if (IYZICO_ENV === "sandbox") return "https://sandbox-api.iyzipay.com";
  // FAIL CLOSED: env yok veya gecersiz
  throw new Error("IYZICO_ENV gecersiz veya eksik. 'sandbox' veya 'production' olmali.");
}

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// ═════════════════════════════════════════════════════════════════
// IYZICO V2 IMZA
// ═════════════════════════════════════════════════════════════════
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

function formatPhoneNumber(phone: string): string {
  const digits = phone.replace(/\D/g, "");
  if (digits.startsWith("90")) return `+${digits}`;
  if (digits.startsWith("0")) return `+9${digits}`;
  return `+90${digits}`;
}

// ═════════════════════════════════════════════════════════════════
// HANDLER
// ═════════════════════════════════════════════════════════════════
interface InitRequest {
  checkout_session_id: string;   // ZORUNLU: private.server_checkout_sessions.id
  idempotency_key: string;        // ZORUNLU
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  try {
    // ═════════════════════════════════════════════════════════════
    // 0) FAIL-CLOSED: IYZICO_ENV zorunlu
    // ═════════════════════════════════════════════════════════════
    let IYZICO_API_URL: string;
    try {
      IYZICO_API_URL = getIyzicoApiUrl();
    } catch (envErr) {
      console.error("IYZICO_ENV hatasi:", (envErr as Error).message);
      return new Response(
        JSON.stringify({
          error: "Odeme altyapisi su an kullanilamaz (IYZICO_ENV eksik).",
          code: "IYZICO_ENV_MISSING",
        }),
        {
          status: 503,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // API key/secret zorunlu
    if (!IYZICO_API_KEY || !IYZICO_SECRET_KEY) {
      console.error("IYZICO_API_KEY veya IYZICO_SECRET_KEY eksik");
      return new Response(
        JSON.stringify({ error: "Odeme altyapisi yapilandirilmamis.", code: "IYZICO_CREDENTIALS_MISSING" }),
        { status: 503, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ═════════════════════════════════════════════════════════════
    // 1) AUTH
    // ═════════════════════════════════════════════════════════════
    const authHeader = req.headers.get("authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser(authHeader.replace("Bearer ", ""));

    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: "Gecersiz oturum." }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ═════════════════════════════════════════════════════════════
    // 2) REQUEST BODY
    // ═════════════════════════════════════════════════════════════
    const body: InitRequest = await req.json();

    if (!body.checkout_session_id || !body.idempotency_key) {
      return new Response(
        JSON.stringify({ error: "checkout_session_id ve idempotency_key zorunlu." }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ═════════════════════════════════════════════════════════════
    // 3) SESSION'ı SUNUCUDAN OKU
    // ═════════════════════════════════════════════════════════════
    // NOT: .schema("private") kullanilamaz — private semasi PostgREST'e
    // expose edilmemis (PGRST106), bu yuzden eski surum her istekte 404
    // donuyordu. Sahiplik kontrolu RPC icinde p_user_id ile yapilir.
    const { data: sessionRows, error: sessionError } = await supabase.rpc(
      "get_checkout_session_for_payment",
      {
        p_session_id: body.checkout_session_id,
        p_user_id: user.id,
      },
    );

    const session = Array.isArray(sessionRows) ? sessionRows[0] : sessionRows;

    if (sessionError || !session) {
      console.error("Session okunamadi:", sessionError?.message);
      return new Response(
        JSON.stringify({ error: "Checkout session bulunamadi veya size ait degil." }),
        { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Session dogrulamalari
    if (session.status !== "pending") {
      return new Response(
        JSON.stringify({ error: `Session zaten ${session.status} durumunda.` }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (new Date(session.expires_at) < new Date()) {
      return new Response(
        JSON.stringify({ error: "Checkout session suresi dolmus. Lutfen yeniden olusturun." }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (session.payment_method !== "online") {
      return new Response(
        JSON.stringify({ error: "Bu session online odeme icin degil." }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ═════════════════════════════════════════════════════════════
    // 4) BUYER BILGISI — profiles + addresses'ten SUNUCUDA
    // ═════════════════════════════════════════════════════════════
    const { data: profile, error: profileError } = await supabase
      .from("profiles")
      .select("id, full_name, email, phone, tc_no, identity_number")
      .eq("id", user.id)
      .single();

    if (profileError || !profile) {
      return new Response(
        JSON.stringify({ error: "Profil bilgisi bulunamadi." }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // iyzico zorunlu identityNumber. tc_no yoksa ODEME BASLATILMAZ (guvenli hata).
    const identityNumber = (profile.tc_no || profile.identity_number || "").toString().trim();
    if (!identityNumber || identityNumber.length !== 11) {
      console.warn("identityNumber eksik/gecersiz, odeme reddedildi (user_id prefix):", user.id.substring(0, 8));
      return new Response(
        JSON.stringify({
          error: "Kimlik dogrulama bilgileriniz eksik. Lutfen profil sayfasindan TCKN bilgisini ekleyin.",
          code: "IDENTITY_NUMBER_REQUIRED",
        }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (!profile.email) {
      return new Response(
        JSON.stringify({ error: "E-posta adresi zorunlu." }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Adres
    let shippingAddress: any = null;
    if (session.address_id) {
      const { data: addr } = await supabase
        .from("addresses")
        .select("*")
        .eq("id", session.address_id)
        .eq("user_id", user.id)
        .single();

      if (addr) {
        shippingAddress = {
          contactName: addr.full_name || profile.full_name,
          city: addr.city || "Şırnak",
          country: "Turkey",
          address: [addr.address_line1, addr.address_line2].filter(Boolean).join(" "),
          zipCode: addr.postal_code || "73200",
        };
      }
    }

    // ═════════════════════════════════════════════════════════════
    // 5) ITEMS — server snapshot'tan (client ASLA gondermez)
    // ═════════════════════════════════════════════════════════════
    const items = session.items_snapshot as any[];
    if (!items || items.length === 0) {
      return new Response(
        JSON.stringify({ error: "Session item snapshot bos." }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const basketItems = items.map((it: any) => ({
      id: it.product_id,
      name: (it.product_name || "Urun").substring(0, 50),
      category1: "Urunler",
      itemType: "PHYSICAL",
      price: Number(it.unit_price * it.quantity).toFixed(2),
    }));

    // Teslimat ucreti (session'dan)
    if (Number(session.server_delivery_fee) > 0) {
      basketItems.push({
        id: "DELIVERY_FEE",
        name: "Teslimat Ucreti",
        category1: "Teslimat",
        itemType: "PHYSICAL",
        price: Number(session.server_delivery_fee).toFixed(2),
      });
    }

    // iyzico price/paidPrice (server-authoritative)
    const price = basketItems.reduce(
      (sum: number, item: any) => sum + parseFloat(item.price),
      0
    );
    // paidPrice = server_total (kupon indirimi dahil)
    const paidPrice = Number(session.server_total);

    // Sanity check
    if (paidPrice <= 0) {
      return new Response(
        JSON.stringify({ error: "Gecersiz odeme tutari." }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ═════════════════════════════════════════════════════════════
    // 6) CONVERSATION + BASKET ID (server)
    // ═════════════════════════════════════════════════════════════
    const conversationId = `cizre_${Date.now()}_${Math.random().toString(36).substring(2, 10)}`;
    const basketId = `B_${body.checkout_session_id.substring(0, 8)}_${Date.now()}`;

    // ═════════════════════════════════════════════════════════════
    // 7) IYZICO CHECKOUT FORM
    // ═════════════════════════════════════════════════════════════
    const fullName = (profile.full_name || "Musteri").toString().trim();
    const nameParts = fullName.split(/\s+/);
    const firstName = nameParts[0] || "Musteri";
    const lastName = nameParts.slice(1).join(" ") || "Musteri";

    const iyzicoBuyer = {
      id: user.id,
      name: firstName,
      surname: lastName,
      identityNumber: identityNumber,  // server'dan, fallback YOK
      email: profile.email,
      gsmNumber: formatPhoneNumber(profile.phone || shippingAddress?.contactName || ""),
      registrationAddress: shippingAddress?.address || "Adres",
      city: shippingAddress?.city || "Şırnak",
      country: "Turkey",
      zipCode: shippingAddress?.zipCode || "73200",
      ip: req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() || "127.0.0.1",
    };

    const requestBody = {
      locale: "tr",
      conversationId: conversationId,
      price: price.toFixed(2),
      paidPrice: paidPrice.toFixed(2),
      currency: "TRY",
      basketId: basketId,
      paymentGroup: "PRODUCT",
      callbackUrl: `${supabaseUrl}/functions/v1/iyzico-payment-callback`,
      enabledInstallments: [1, 2, 3, 6, 9],
      buyer: iyzicoBuyer,
      shippingAddress: shippingAddress || {
        contactName: `${firstName} ${lastName}`,
        city: "Şırnak",
        country: "Turkey",
        address: "Adres",
        zipCode: "73200",
      },
      billingAddress: shippingAddress || {
        contactName: `${firstName} ${lastName}`,
        city: "Şırnak",
        country: "Turkey",
        address: "Adres",
        zipCode: "73200",
      },
      basketItems: basketItems,
    };

    const bodyString = JSON.stringify(requestBody);
    const randomHeaderValue = generateRandomString();
    const { authorization, randomString } = await generateAuthorizationHeaderV2(
      IYZICO_API_KEY, IYZICO_SECRET_KEY, randomHeaderValue, bodyString
    );

    console.log("iyzico init istegi gonderiliyor:", {
      sessionIdPrefix: body.checkout_session_id.substring(0, 8),
      expectedAmount: paidPrice.toFixed(2),
      itemCount: basketItems.length,
      env: IYZICO_ENV,
    });

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
      console.error("iyzico checkout form hatasi:", {
        errorCode: result.errorCode,
        errorGroup: result.errorGroup,
      });
      return new Response(
        JSON.stringify({
          error: result.errorMessage || "Odeme baslatilamadi.",
          code: result.errorCode,
        }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ═════════════════════════════════════════════════════════════
    // 8) PAYMENT TRANSACTION OLUSTUR (server-authoritative expected_*)
    // ═════════════════════════════════════════════════════════════
    const { data: txn, error: txnError } = await supabase
      .from("payment_transactions")
      .insert({
        user_id: user.id,
        checkout_session_id: body.checkout_session_id,
        conversation_id: conversationId,
        basket_id: basketId,
        amount: paidPrice,
        expected_amount: paidPrice,
        expected_currency: "TRY",
        expected_conversation_id: conversationId,
        expected_basket_id: basketId,
        currency: "TRY",
        iyzico_environment: IYZICO_ENV,
        idempotency_key: body.idempotency_key,
        payment_status: "pending",
        token: result.token,
        ip_address: iyzicoBuyer.ip,
      })
      .select("id")
      .single();

    if (txnError || !txn) {
      console.error("Payment transaction olusturulamadi:", txnError?.message);
      return new Response(
        JSON.stringify({ error: "Odeme kaydi olusturulamadi." }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Session'i txn ile linkle + expected_* set et.
    //
    // Bu adim GUVENLIK ACISINDAN ZORUNLU: commit_online_order tutar
    // dogrulamasini session.expected_paid_price uzerinden yapiyor ve alan
    // NULL ise kontrolu atliyor. Bu yuzden hata artik yutulmuyor.
    //
    // NOT: .schema("private") kullanilamaz — private semasi PostgREST'e
    // expose edilmemis (PGRST106). service_role'e acik public RPC uzerinden.
    const { data: linked, error: linkError } = await supabase.rpc(
      "link_checkout_session_payment",
      {
        p_session_id: body.checkout_session_id,
        p_payment_transaction_id: txn.id,
        p_expected_paid_price: paidPrice,
        p_expected_currency: "TRY",
        p_expected_conversation_id: conversationId,
        p_expected_basket_id: basketId,
        p_iyzico_environment: IYZICO_ENV,
      },
    );

    if (linkError || linked !== true) {
      console.error("Checkout session linklenemedi:", {
        sessionPrefix: body.checkout_session_id.substring(0, 8),
        code: linkError?.code,
      });
      // Beklenen tutar yazilamadiysa odemeye devam etmek, callback'te tutar
      // dogrulamasi olmadan siparis olusmasi demektir. Fail-closed.
      await supabase
        .from("payment_transactions")
        .update({
          payment_status: "failure",
          error_code: "SESSION_LINK_FAILED",
          error_message: "Checkout session expected_* alanlari yazilamadi.",
        })
        .eq("id", txn.id);

      return new Response(
        JSON.stringify({ error: "Odeme baslatilamadi. Lutfen tekrar deneyin." }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    console.log("iyzico init basarili:", {
      paymentTxnPrefix: txn.id.substring(0, 8),
      sessionPrefix: body.checkout_session_id.substring(0, 8),
    });

    return new Response(
      JSON.stringify({
        status: "success",
        payment_page_url: result.paymentPageUrl,
        token: result.token,
        token_expire_time: result.tokenExpireTime,
        conversation_id: conversationId,
        payment_transaction_id: txn.id,
        checkout_session_id: body.checkout_session_id,
        expected_amount: paidPrice,
        currency: "TRY",
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (err: unknown) {
    const error = err as Error;
    console.error("iyzico-payment-init beklenmeyen hata:", error.message);
    return new Response(
      JSON.stringify({
        error: "Odeme baslatilamadi. Lutfen tekrar deneyin.",
      }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});

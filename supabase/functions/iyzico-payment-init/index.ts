// iyzico Ödeme Başlatma Edge Function
// Bu fonksiyon iyzico Checkout Form ödemesini başlatır
// Deploy: supabase functions deploy iyzico-payment-init

// deno-lint-ignore-file no-explicit-any
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.38.4";

console.log("iyzico Payment Init Edge Function başlatıldı");

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// iyzico API Ayarları (Supabase secrets olarak saklanır)
const IYZICO_API_URL =
  Deno.env.get("IYZICO_API_URL") || "https://sandbox-api.iyzipay.com";
const IYZICO_API_KEY = Deno.env.get("IYZICO_API_KEY") || "";
const IYZICO_SECRET_KEY = Deno.env.get("IYZICO_SECRET_KEY") || "";

// Supabase client (service role - RLS bypass)
const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// ────────── Interface Tanımları ──────────

interface AddressInfo {
  address: string;
  city: string;
  country: string;
  zipCode?: string;
  contactName?: string;
}

interface BuyerInfo {
  id: string;
  name: string;
  surname: string;
  email: string;
  phone: string;
  identityNumber: string;
  address: string;
  city: string;
  country: string;
  zipCode?: string;
}

interface OrderItem {
  product_id: string;
  product_name: string;
  quantity: number;
  price: number;
  variant_data?: Record<string, any>;
}

interface OrderData {
  shop_id: string;
  items: OrderItem[];
  delivery_address_text: string;
  delivery_address_id?: string;
  total: number;
  subtotal: number;
  delivery_fee: number;
  coupon_discount?: number;
  coupon_id?: string;
  note?: string;
}

interface PaymentInitRequest {
  user_id: string;
  order_data: OrderData;
  buyer: BuyerInfo;
  billing_address?: AddressInfo;
  shipping_address?: AddressInfo;
}

// ────────── iyzico İmza Oluşturma (SHA-256 HMAC - iyzico v2) ──────────

async function generateAuthorizationHeaderV2(
  apiKey: string,
  secretKey: string,
  randomString: string,
  requestBody: string
): Promise<{ authorization: string; randomString: string }> {
  // iyzico v2 API Authorization:
  // 1. uri = /payment/iyzipos/checkoutform/initialize/auth/ecom
  // 2. hashStr = randomString + uri + requestBody
  // 3. signature = HMAC-SHA256(secretKey, hashStr) -> hex
  // 4. authorizationParams = "apiKey:" + apiKey + "&randomKey:" + randomString + "&signature:" + signature
  // 5. Authorization = "IYZWSv2 " + Base64(authorizationParams)
  
  const uri = "/payment/iyzipos/checkoutform/initialize/auth/ecom";
  const hashStr = randomString + uri + requestBody;
  
  const encoder = new TextEncoder();
  const keyData = encoder.encode(secretKey);
  const msgData = encoder.encode(hashStr);

  // HMAC-SHA256 key oluştur
  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    keyData,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );

  // İmzala
  const signatureBuffer = await crypto.subtle.sign("HMAC", cryptoKey, msgData);
  const signatureArray = new Uint8Array(signatureBuffer);
  const signatureHex = Array.from(signatureArray)
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");

  // Authorization params
  const authorizationParams = `apiKey:${apiKey}&randomKey:${randomString}&signature:${signatureHex}`;
  const authorizationBase64 = btoa(authorizationParams);

  return {
    authorization: `IYZWSv2 ${authorizationBase64}`,
    randomString,
  };
}

// Fallback: iyzico v1 imza (eski format)
async function generateAuthorizationHeaderV1(
  apiKey: string,
  secretKey: string,
  randomHeaderValue: string,
  requestBody: string
): Promise<string> {
  // iyzico v1 Authorization header format:
  // IYZWS {apiKey}:{hash}
  // hash = Base64(SHA1(apiKey + randomHeaderValue + secretKey + requestBody))
  const hashStr = apiKey + randomHeaderValue + secretKey + requestBody;

  const encoder = new TextEncoder();
  const data = encoder.encode(hashStr);

  // SHA-1 hash
  const hashBuffer = await crypto.subtle.digest("SHA-1", data);
  const hashArray = new Uint8Array(hashBuffer);
  const hashBase64 = btoa(String.fromCharCode(...hashArray));

  return `IYZWS ${apiKey}:${hashBase64}`;
}

function generateRandomString(): string {
  const array = new Uint8Array(8);
  crypto.getRandomValues(array);
  return Array.from(array, (byte) => byte.toString(16).padStart(2, "0")).join(
    ""
  );
}

// ────────── Yardımcı Fonksiyonlar ──────────

function generateConversationId(): string {
  return `cizre_${Date.now()}_${Math.random().toString(36).substring(2, 10)}`;
}

function formatPhoneNumber(phone: string): string {
  // Sadece rakamları al, başında + varsa kalsın
  const digits = phone.replace(/\D/g, "");
  if (digits.startsWith("90")) return `+${digits}`;
  if (digits.startsWith("0")) return `+9${digits}`;
  return `+90${digits}`;
}

// ────────── DB İşlemleri ──────────

async function createPaymentTransaction(
  supabase: any,
  userId: string,
  conversationId: string,
  orderData: OrderData,
  ipAddress: string
): Promise<string> {
  const { data, error } = await supabase
    .from("payment_transactions")
    .insert({
      user_id: userId,
      conversation_id: conversationId,
      amount: orderData.total,
      currency: "TRY",
      payment_status: "pending",
      ip_address: ipAddress,
    })
    .select("id")
    .single();

  if (error) {
    console.error("Payment transaction oluşturma hatası:", error);
    throw new Error(`Payment transaction oluşturulamadı: ${error.message}`);
  }

  return data.id;
}

// Sipariş verilerini geçici olarak saklama (callback'te kullanılacak)
async function storeOrderDataForCallback(
  supabase: any,
  paymentTransactionId: string,
  orderData: OrderData,
  userId: string
): Promise<void> {
  // payment_transactions tablosundaki callback_data alanına order bilgilerini yaz
  const { error } = await supabase
    .from("payment_transactions")
    .update({
      callback_data: {
        order_data: orderData,
        user_id: userId,
        stored_at: new Date().toISOString(),
      },
    })
    .eq("id", paymentTransactionId);

  if (error) {
    console.error("Order data saklama hatası:", error);
    throw new Error(`Order data saklanamadı: ${error.message}`);
  }
}

// ────────── iyzico Checkout Form Başlatma ──────────

async function initializeIyzicoCheckout(
  requestData: PaymentInitRequest,
  conversationId: string,
  ipAddress: string
): Promise<{ paymentPageUrl: string; token: string; tokenExpireTime: number }> {
  const { order_data, buyer, billing_address, shipping_address } = requestData;

  // Buyer bilgileri
  const iyzicoBuyer = {
    id: buyer.id,
    name: buyer.name,
    surname: buyer.surname,
    identityNumber: buyer.identityNumber || "11111111111",
    email: buyer.email,
    gsmNumber: formatPhoneNumber(buyer.phone),
    registrationAddress: buyer.address,
    city: buyer.city,
    country: buyer.country || "Turkey",
    zipCode: buyer.zipCode || "34000",
    ip: ipAddress,
  };

  // Adres bilgileri
  const shippingAddr = {
    contactName: shipping_address?.contactName || `${buyer.name} ${buyer.surname}`,
    city: shipping_address?.city || buyer.city,
    country: shipping_address?.country || buyer.country || "Turkey",
    address: shipping_address?.address || order_data.delivery_address_text,
    zipCode: shipping_address?.zipCode || buyer.zipCode || "34000",
  };

  const billingAddr = {
    contactName: billing_address?.contactName || `${buyer.name} ${buyer.surname}`,
    city: billing_address?.city || buyer.city,
    country: billing_address?.country || buyer.country || "Turkey",
    address: billing_address?.address || buyer.address,
    zipCode: billing_address?.zipCode || buyer.zipCode || "34000",
  };

  // Sepet kalemleri
  const basketItems = order_data.items.map((item) => ({
    id: item.product_id,
    name: item.product_name.substring(0, 50), // iyzico max 50 char
    category1: "Ürünler",
    itemType: "PHYSICAL",
    price: (item.price * item.quantity).toFixed(2),
  }));

  // Teslimat ücreti varsa sepete ekle
  if (order_data.delivery_fee > 0) {
    basketItems.push({
      id: "DELIVERY_FEE",
      name: "Teslimat Ücreti",
      category1: "Teslimat",
      itemType: "PHYSICAL",
      price: order_data.delivery_fee.toFixed(2),
    });
  }

  // Sepet toplamını hesapla ve tutarla eşleştir
  const basketTotal = basketItems.reduce(
    (sum, item) => sum + parseFloat(item.price),
    0
  );
  const paidPrice = order_data.total;

  // Kupon indirimi varsa, fiyat ayarlaması yap
  // iyzico'da basketItems toplamı = price olmalı
  // paidPrice >= price olmalı
  const price = basketTotal.toFixed(2);

  // Callback URL
  const callbackUrl = `${supabaseUrl}/functions/v1/iyzico-payment-callback`;

  // iyzico Checkout Form request body
  const requestBody = {
    locale: "tr",
    conversationId: conversationId,
    price: price,
    paidPrice: paidPrice.toFixed(2),
    currency: "TRY",
    basketId: `B_${conversationId}`,
    paymentGroup: "PRODUCT",
    callbackUrl: callbackUrl,
    enabledInstallments: [1, 2, 3, 6, 9],
    buyer: iyzicoBuyer,
    shippingAddress: shippingAddr,
    billingAddress: billingAddr,
    basketItems: basketItems,
  };

  const bodyString = JSON.stringify(requestBody);
  const randomHeaderValue = generateRandomString();

  // Authorization header oluştur (v2 HMAC-SHA256)
  const { authorization, randomString } = await generateAuthorizationHeaderV2(
    IYZICO_API_KEY,
    IYZICO_SECRET_KEY,
    randomHeaderValue,
    bodyString
  );

  console.log("📤 iyzico checkout form isteği gönderiliyor:", {
    conversationId,
    price,
    paidPrice: paidPrice.toFixed(2),
    basketItemCount: basketItems.length,
    callbackUrl,
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
    console.error("❌ iyzico checkout form hatası:", {
      errorCode: result.errorCode,
      errorMessage: result.errorMessage,
      errorGroup: result.errorGroup,
    });
    throw new Error(
      result.errorMessage || `iyzico ödeme başlatılamadı (${result.errorCode})`
    );
  }

  console.log("✅ iyzico checkout form başarılı:", {
    token: result.token?.substring(0, 20) + "...",
    tokenExpireTime: result.tokenExpireTime,
  });

  return {
    paymentPageUrl: result.paymentPageUrl,
    token: result.token,
    tokenExpireTime: result.tokenExpireTime,
  };
}

// ────────── Ana Handler ──────────

serve(async (req: Request) => {
  // CORS preflight
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  // Sadece POST kabul et
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
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

    // Supabase client oluştur (her request'te yeni instance)
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // Kullanıcıyı doğrula
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser(authHeader.replace("Bearer ", ""));

    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: "Geçersiz oturum. Lütfen tekrar giriş yapın." }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // Request body'yi parse et
    const requestData: PaymentInitRequest = await req.json();

    // Zorunlu alan kontrolü
    if (!requestData.order_data || !requestData.buyer) {
      return new Response(
        JSON.stringify({
          error: "Eksik bilgi: order_data ve buyer alanları zorunludur.",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // Items kontrolü
    if (
      !requestData.order_data.items ||
      requestData.order_data.items.length === 0
    ) {
      return new Response(
        JSON.stringify({ error: "Sepet boş. En az bir ürün ekleyin." }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // Tutar kontrolü
    if (requestData.order_data.total <= 0) {
      return new Response(
        JSON.stringify({ error: "Geçersiz sipariş tutarı." }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // user_id'yi authenticated user'dan al (güvenlik)
    requestData.user_id = user.id;

    // Client IP
    const clientIp =
      req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ||
      req.headers.get("x-real-ip") ||
      "127.0.0.1";

    console.log("📋 Ödeme başlatma isteği:", {
      userId: user.id,
      shopId: requestData.order_data.shop_id,
      total: requestData.order_data.total,
      itemCount: requestData.order_data.items.length,
      clientIp,
    });

    // Conversation ID oluştur
    const conversationId = generateConversationId();

    // 1. Payment transaction kaydı oluştur
    const paymentTransactionId = await createPaymentTransaction(
      supabase,
      user.id,
      conversationId,
      requestData.order_data,
      clientIp
    );

    // 2. Sipariş verilerini callback için sakla
    await storeOrderDataForCallback(
      supabase,
      paymentTransactionId,
      requestData.order_data,
      user.id
    );

    // 3. iyzico Checkout Form başlat
    const iyzicoResult = await initializeIyzicoCheckout(
      requestData,
      conversationId,
      clientIp
    );

    // 4. Payment transaction'a token bilgisini ekle
    await supabase
      .from("payment_transactions")
      .update({
        token: iyzicoResult.token,
        updated_at: new Date().toISOString(),
      })
      .eq("id", paymentTransactionId);

    console.log("✅ Ödeme başarıyla başlatıldı:", {
      paymentTransactionId,
      conversationId,
    });

    // Başarılı yanıt
    return new Response(
      JSON.stringify({
        status: "success",
        payment_page_url: iyzicoResult.paymentPageUrl,
        token: iyzicoResult.token,
        token_expire_time: iyzicoResult.tokenExpireTime,
        conversation_id: conversationId,
        payment_transaction_id: paymentTransactionId,
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  } catch (err: unknown) {
    const error = err as Error;
    console.error("❌ Payment init error:", error.message);

    return new Response(
      JSON.stringify({
        status: "error",
        error: error.message || "Ödeme başlatılamadı. Lütfen tekrar deneyin.",
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }
});

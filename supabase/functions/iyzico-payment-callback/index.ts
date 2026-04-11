// iyzico Ödeme Callback Edge Function
// Bu fonksiyon iyzico'dan gelen ödeme sonucunu işler ve siparişi oluşturur
// Deploy: supabase functions deploy iyzico-payment-callback

// deno-lint-ignore-file no-explicit-any
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.38.4";

console.log("iyzico Payment Callback Edge Function başlatıldı");

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// iyzico API Ayarları
const IYZICO_API_URL =
  Deno.env.get("IYZICO_API_URL") || "https://sandbox-api.iyzipay.com";
const IYZICO_API_KEY = Deno.env.get("IYZICO_API_KEY") || "";
const IYZICO_SECRET_KEY = Deno.env.get("IYZICO_SECRET_KEY") || "";

// Supabase client
const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// ────────── Interface Tanımları ──────────

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

interface IyzicoPaymentResult {
  status: string;
  locale: string;
  systemTime: number;
  conversationId: string;
  price: string;
  paidPrice: string;
  installment: number;
  paymentId: string;
  fraudStatus: number;
  merchantCommissionRate: string;
  merchantCommissionRateAmount: string;
  iyziCommissionRateAmount: string;
  iyziCommissionFee: string;
  cardType: string;
  cardAssociation: string;
  cardFamily: string;
  cardToken: string;
  cardUserKey: string;
  binNumber: string;
  lastFourDigits: string;
  basketId: string;
  currency: string;
  itemTransactions: any[];
  authCode: string;
  phase: string;
  mdStatus: number;
  errorCode?: string;
  errorMessage?: string;
  errorGroup?: string;
}

// ────────── iyzico V2 İmza Oluşturma (IYZWSv2) ──────────

async function generateAuthorizationHeaderV2(
  apiKey: string,
  secretKey: string,
  randomHeaderValue: string,
  requestBody: string
): Promise<{ authorization: string; randomString: string }> {
  // iyzico v2 API Authorization (retrieve/detail endpoint):
  // 1. uri = /payment/iyzipos/checkoutform/auth/ecom/detail
  // 2. hashStr = randomString + uri + requestBody
  // 3. signature = HMAC-SHA256(secretKey, hashStr) -> hex
  // 4. authorizationParams = "apiKey:" + apiKey + "&randomKey:" + randomString + "&signature:" + signature
  // 5. Authorization = "IYZWSv2 " + Base64(authorizationParams)

  const uri = "/payment/iyzipos/checkoutform/auth/ecom/detail";
  const hashStr = randomHeaderValue + uri + requestBody;

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
  const signatureArray = Array.from(new Uint8Array(signatureBuffer));
  const signatureHex = signatureArray
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");

  // Authorization params
  const authorizationParams = `apiKey:${apiKey}&randomKey:${randomHeaderValue}&signature:${signatureHex}`;
  const authorizationBase64 = btoa(authorizationParams);

  return {
    authorization: `IYZWSv2 ${authorizationBase64}`,
    randomString: randomHeaderValue,
  };
}

function generateRandomString(): string {
  const array = new Uint8Array(8);
  crypto.getRandomValues(array);
  return Array.from(array, (byte) => byte.toString(16).padStart(2, "0")).join(
    ""
  );
}

// ────────── iyzico'dan Ödeme Sonucunu Sorgula ──────────

async function retrievePaymentResult(
  token: string
): Promise<IyzicoPaymentResult> {
  const requestBody = {
    locale: "tr",
    conversationId: `callback_${Date.now()}`,
    token: token,
  };

  const bodyString = JSON.stringify(requestBody);
  const randomHeaderValue = generateRandomString();

  // V2 Authorization header oluştur
  const { authorization, randomString } = await generateAuthorizationHeaderV2(
    IYZICO_API_KEY,
    IYZICO_SECRET_KEY,
    randomHeaderValue,
    bodyString
  );

  console.log("🔍 iyzico ödeme sonucu sorgulanıyor, token:", token.substring(0, 20) + "...");

  const response = await fetch(
    `${IYZICO_API_URL}/payment/iyzipos/checkoutform/auth/ecom/detail`,
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
    console.error("❌ iyzico ödeme sorgulama hatası:", {
      errorCode: result.errorCode,
      errorMessage: result.errorMessage,
    });
    throw new Error(result.errorMessage || "Ödeme sonucu alınamadı");
  }

  console.log("✅ iyzico ödeme sonucu alındı:", {
    paymentId: result.paymentId,
    paidPrice: result.paidPrice,
    cardLastFour: result.lastFourDigits,
    fraudStatus: result.fraudStatus,
  });

  return result;
}

// ────────── Veritabanı İşlemleri ──────────

async function getPaymentTransaction(
  supabase: any,
  token: string
): Promise<any> {
  const { data, error } = await supabase
    .from("payment_transactions")
    .select("*")
    .eq("token", token)
    .single();

  if (error || !data) {
    console.error("Payment transaction bulunamadı:", error);
    throw new Error("Ödeme işlemi bulunamadı");
  }

  return data;
}

async function updatePaymentTransaction(
  supabase: any,
  transactionId: string,
  paymentResult: IyzicoPaymentResult,
  status: "success" | "failure",
  existingCallbackData?: any
): Promise<void> {
  // ÖNEMLİ: callback_data'yı tamamen üzerine yazmak yerine,
  // mevcut sipariş verilerini (order_data, user_id) koruyarak merge ediyoruz.
  // Aksi halde complete_online_payment RPC fonksiyonu sipariş verilerini bulamaz!
  const mergedCallbackData = {
    ...(existingCallbackData || {}),  // Mevcut sipariş verileri (order_data, user_id) korunur
    iyzico_response: paymentResult,   // iyzico sonucu ayrı key'de saklanır
    callback_processed_at: new Date().toISOString(),
  };

  const updateData: any = {
    payment_status: status,
    payment_id: paymentResult.paymentId, // payment_transactions tablosundaki sütun adı "payment_id"
    paid_price: parseFloat(paymentResult.paidPrice),
    card_type: paymentResult.cardType,
    card_association: paymentResult.cardAssociation,
    card_family: paymentResult.cardFamily,
    card_bank_name: paymentResult.binNumber,
    last_four_digits: paymentResult.lastFourDigits,
    fraud_status: paymentResult.fraudStatus,
    callback_received_at: new Date().toISOString(),
    callback_data: mergedCallbackData,
    updated_at: new Date().toISOString(),
  };

  if (status === "failure") {
    updateData.error_code = paymentResult.errorCode;
    updateData.error_message = paymentResult.errorMessage;
    updateData.error_group = paymentResult.errorGroup;
  }

  const { error } = await supabase
    .from("payment_transactions")
    .update(updateData)
    .eq("id", transactionId);

  if (error) {
    console.error("Payment transaction güncelleme hatası:", error);
    throw new Error("Ödeme kaydı güncellenemedi");
  }

  console.log(`✅ Payment transaction güncellendi: ${status}`);
}

// Siparişi oluştur (complete_online_payment fonksiyonunu çağır)
async function createOrderFromPayment(
  supabase: any,
  paymentTransactionId: string,
  paymentResult: IyzicoPaymentResult
): Promise<string> {
  console.log("📦 Sipariş oluşturuluyor, payment_transaction_id:", paymentTransactionId);

  // RPC fonksiyonunu çağır
  const { data, error } = await supabase.rpc("complete_online_payment", {
    p_payment_transaction_id: paymentTransactionId,
  });

  if (error) {
    console.error("Sipariş oluşturma hatası:", error);
    throw new Error(`Sipariş oluşturulamadı: ${error.message}`);
  }

  console.log("✅ Sipariş başarıyla oluşturuldu, order_id:", data);
  return data; // order_id döner
}

// Bildirim gönder (push + email)
async function sendNotifications(
  supabase: any,
  userId: string,
  orderId: string,
  orderNumber: string
): Promise<void> {
  try {
    // Kullanıcı bilgilerini al
    const { data: profile } = await supabase
      .from("profiles")
      .select("full_name, email, fcm_token")
      .eq("id", userId)
      .single();

    if (!profile) return;

    // Push notification gönder
    if (profile.fcm_token) {
      console.log("📤 Push notification gönderiliyor...");
      await supabase.functions.invoke("send-push-notification", {
        body: {
          fcm_token: profile.fcm_token,
          title: "Ödeme Başarılı! 🎉",
          body: `Siparişiniz (#${orderNumber}) başarıyla oluşturuldu.`,
          data: {
            type: "order_created",
            order_id: orderId,
          },
        },
      });
    }

    // Email gönder (eğer email servisi aktifse)
    if (profile.email) {
      console.log("📧 Email bildirimi gönderiliyor...");
      // Email gönderme kodu burada olabilir (opsiyonel)
    }

    console.log("✅ Bildirimler gönderildi");
  } catch (error) {
    console.error("⚠️ Bildirim gönderme hatası (kritik değil):", error);
    // Bildirim hatası kritik değil, sipariş oluşturulmuştur
  }
}

// ────────── Ana Handler ──────────

// HTML yanıt oluştur (WebView'de JSON yerine güzel bir sayfa göster)
function htmlResponse(title: string, message: string, isSuccess: boolean, extraInfo?: string): Response {
  const html = `<!DOCTYPE html>
<html lang="tr">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${title}</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      background: linear-gradient(135deg, #f5f7fa 0%, #e4e8ec 100%);
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 20px;
    }
    .container {
      background: white;
      border-radius: 20px;
      padding: 40px 30px;
      max-width: 400px;
      width: 100%;
      text-align: center;
      box-shadow: 0 10px 40px rgba(0,0,0,0.1);
    }
    .icon {
      width: 80px;
      height: 80px;
      border-radius: 50%;
      display: flex;
      align-items: center;
      justify-content: center;
      margin: 0 auto 20px;
      font-size: 40px;
    }
    .icon.success { background: #e8f5e9; }
    .icon.error { background: #ffebee; }
    .icon.warning { background: #fff3e0; }
    h1 { font-size: 22px; color: #333; margin-bottom: 12px; }
    p { font-size: 15px; color: #666; line-height: 1.5; margin-bottom: 8px; }
    .extra { font-size: 13px; color: #999; margin-top: 12px; }
    .close-btn {
      margin-top: 24px;
      padding: 12px 24px;
      background: #4CAF50;
      color: white;
      border: none;
      border-radius: 8px;
      font-size: 15px;
      cursor: pointer;
      transition: background 0.3s;
    }
    .close-btn:hover { background: #45a049; }
    .info-text {
      font-size: 13px;
      color: #999;
      margin-top: 16px;
      font-style: italic;
    }
  </style>
</head>
<body>
  <div class="container">
    <div class="icon ${isSuccess ? 'success' : 'error'}">
      ${isSuccess ? '✅' : '❌'}
    </div>
    <h1>${title}</h1>
    <p>${message}</p>
    ${extraInfo ? `<p class="extra">${extraInfo}</p>` : ''}
    ${isSuccess ? '<button class="close-btn" onclick="closeWindow()">Bu Sekmeyi Kapat</button><p class="info-text">Ana sayfanız otomatik olarak güncellendi</p>' : '<button class="close-btn" onclick="closeWindow()">Kapat</button>'}
  </div>
  <script>
    function closeWindow() {
      // Web'de: sekmeyi kapatmaya çalış
      window.close();
      // Eğer kapanamazsa (güvenlik nedeniyle), kullanıcıyı bilgilendir
      setTimeout(() => {
        alert('Bu sekmeyi manuel olarak kapatabilirsiniz.');
      }, 100);
    }
    
    // Başarılı ödemelerde 3 saniye sonra otomatik kapanmayı dene
    ${isSuccess ? 'setTimeout(() => { closeWindow(); }, 3000);' : ''}
  </script>
</body>
</html>`;
  return new Response(html, {
    headers: { ...corsHeaders, "Content-Type": "text/html; charset=utf-8" },
  });
}

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
    // Supabase client oluştur
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // Request body'den token al
    // iyzico application/x-www-form-urlencoded formatında gönderir
    const contentType = req.headers.get("content-type") || "";
    
    let token: string | null = null;

    if (contentType.includes("application/json")) {
      // JSON format (test için)
      const jsonBody = await req.json();
      token = jsonBody.token;
    } else {
      // URL-encoded format (iyzico default)
      const textBody = await req.text();
      const params = new URLSearchParams(textBody);
      token = params.get('token');
    }

    if (!token) {
      console.error("Token eksik");
      return new Response(
        JSON.stringify({ error: "Token parametresi gerekli" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    console.log("📥 Callback alındı, token:", token.substring(0, 20) + "...");
    console.log("📥 Content-Type:", contentType);

    // 1. Payment transaction'ı bul
    const paymentTransaction = await getPaymentTransaction(supabase, token);

    // Eğer daha önce işlenmiş bir callback ise, tekrar işleme (idempotency)
    if (
      paymentTransaction.payment_status === "success" ||
      paymentTransaction.payment_status === "failure"
    ) {
      console.log("⚠️ Bu ödeme zaten işlenmiş:", paymentTransaction.payment_status);
      
      // Eğer başarılı ise ve order oluşmuşsa, order bilgisini döndür
      if (paymentTransaction.payment_status === "success") {
        const { data: order } = await supabase
          .from("orders")
          .select("id, order_number")
          .eq("payment_transaction_id", paymentTransaction.id)
          .single();

        return htmlResponse(
          "Ödeme Başarılı! ✅",
          "Bu ödeme zaten işlenmiştir.",
          true,
          `Sipariş No: ${order?.order_number || ""}`
        );
      }

      return htmlResponse(
        "Ödeme Başarısız",
        "Bu ödeme daha önce başarısız olmuş.",
        false
      );
    }

    // 2. iyzico'dan ödeme sonucunu sorgula
    const paymentResult = await retrievePaymentResult(token);

    // 3. Ödeme başarılı mı kontrolü
    // SANDBOX: fraudStatus ve mdStatus sandbox'ta 0 olabiliyor, ama status="success" önemli
    // Production'da fraudStatus=1 ve mdStatus=1 olmalı
    const isSandbox = IYZICO_API_URL.includes("sandbox");
    const isPaymentSuccess = isSandbox
      ? paymentResult.status === "success" // Sandbox: sadece status kontrolü
      : paymentResult.status === "success" && // Production: tam kontrol
        paymentResult.fraudStatus === 1 &&
        paymentResult.mdStatus === 1;

    console.log("💳 Ödeme sonucu değerlendiriliyor:", {
      status: paymentResult.status,
      fraudStatus: paymentResult.fraudStatus,
      mdStatus: paymentResult.mdStatus,
      isSandbox,
      isPaymentSuccess,
    });

    // 4. Payment transaction güncelle (mevcut callback_data korunur)
    await updatePaymentTransaction(
      supabase,
      paymentTransaction.id,
      paymentResult,
      isPaymentSuccess ? "success" : "failure",
      paymentTransaction.callback_data // Sipariş verilerini korumak için mevcut callback_data'yı geç
    );

    // 5. Başarılıysa sipariş oluştur
    if (isPaymentSuccess) {
      try {
        // complete_online_payment RPC fonksiyonunu çağır
        const orderId = await createOrderFromPayment(
          supabase,
          paymentTransaction.id,
          paymentResult
        );

        // Sipariş bilgisini al
        const { data: order } = await supabase
          .from("orders")
          .select("order_number, user_id")
          .eq("id", orderId)
          .single();

        // Bildirimleri gönder
        if (order) {
          await sendNotifications(
            supabase,
            order.user_id,
            orderId,
            order.order_number
          );
        }

        console.log("✅ Ödeme callback işlemi başarıyla tamamlandı");

        return htmlResponse(
          "Ödeme Başarılı! 🎉",
          "Siparişiniz başarıyla oluşturuldu.",
          true,
          `Sipariş No: ${order?.order_number || orderId.substring(0, 8)}`
        );
      } catch (orderError: unknown) {
        const err = orderError as Error;
        console.error("❌ Sipariş oluşturma hatası:", err.message);

        // Sipariş oluşturulamazsa, ödeme başarılı ama sipariş oluşturulamadı
        // Bu durumda manuel müdahale gerekir
        return htmlResponse(
          "Sipariş Hatası",
          "Ödemeniz alındı ancak sipariş oluşturulamadı. Lütfen destek ekibiyle iletişime geçin.",
          false,
          `Ödeme ID: ${paymentResult.paymentId}`
        );
      }
    } else {
      // Ödeme başarısız
      console.log("❌ Ödeme başarısız:", {
        errorCode: paymentResult.errorCode,
        errorMessage: paymentResult.errorMessage,
        fraudStatus: paymentResult.fraudStatus,
        mdStatus: paymentResult.mdStatus,
      });

      return htmlResponse(
        "Ödeme Başarısız",
        paymentResult.errorMessage || "Ödeme başarısız oldu. Lütfen tekrar deneyin.",
        false
      );
    }
  } catch (err: unknown) {
    const error = err as Error;
    console.error("❌ Callback işleme hatası:", error.message);

    return htmlResponse(
      "İşlem Hatası",
      error.message || "Callback işlenirken bir hata oluştu.",
      false
    );
  }
});

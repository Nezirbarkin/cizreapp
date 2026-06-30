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

// ─────────────────────────────────────────────────────────────────
// getPaymentTransaction — token bazlı arama (HATA-2 REGRESYON FIX)
// ─────────────────────────────────────────────────────────────────
// ÖNCEKİ SORUNLAR:
// 1. .single() → aynı token ile birden fazla kayıt varsa PGRST116 hatası
// 2. En son kaydı alıyor ama pending değilse "zaten işlenmiş" hatası
// 3. iyzico token reuse yapabilir (aynı token farklı siparişlerde)
//
// ÇÖZÜM: Önce PENDING olan en yeni kaydı bul → en sık karşılaşılan
// normal akış. Pending yoksa tüm kayıtları al (duplicate callback durumu).
// ─────────────────────────────────────────────────────────────────
async function getPaymentTransaction(
  supabase: any,
  token: string
): Promise<any> {
  // ── 1. Önce PENDING olan en yeni transaction'ı bul ──
  // Bu, normal akışta her zaman bu transaction'ı döner
  const { data: pendingData, error: pendingError } = await supabase
    .from("payment_transactions")
    .select("*")
    .eq("token", token)
    .eq("payment_status", "pending")
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (pendingData) {
    console.log("✅ PENDING transaction bulundu, ID:", pendingData.id);
    return pendingData;
  }

  // ── 2. Pending yoksa — tüm kayıtları sorgula (hata/failure/duplikate) ──
  if (pendingError) {
    console.error("Payment transaction sorgu hatası:", pendingError);
    throw new Error(`Ödeme işlemi sorgulanamadı: ${pendingError.message}`);
  }

  const { data, error } = await supabase
    .from("payment_transactions")
    .select("*")
    .eq("token", token)
    .order("created_at", { ascending: false })
    .limit(5) // En fazla 5 eski kayıt al (debug için)
    .maybeSingle();

  if (error) {
    console.error("Payment transaction sorgu hatası:", error);
    throw new Error(`Ödeme işlemi sorgulanamadı: ${error.message}`);
  }

  if (!data) {
    console.error("❌ Payment transaction bulunamadı, token:", token.substring(0, 20));
    throw new Error("Ödeme işlemi bulunamadı. Geçersiz veya süresi dolmuş ödeme.");
  }

  // Pending yok ama kayıt var — kullanıcı muhtemelen aynı token ile tekrar callback
  // yapıyor (iyzico retry veya kullanıcı aynı ödeme sayfasını tekrar açtı)
  console.log("ℹ️ Pending değil, mevcut status:", data.payment_status, "ID:", data.id);
  return data;
}

// ─────────────────────────────────────────────────────────────────
// ATOMİK GÜNCELLEME — SQL RPC (FIX-HATA-2 + REGRESYON ÇÖZÜMÜ)
// 2026-06-30
// ─────────────────────────────────────────────────────────────────
// ÖNCEKİ SORUN: JS tarafındaki count tabanlı kontrol Supabase JS
// client v2'de güvenilir değildi. UPDATE ... WHERE status='pending'
// yapılıp .select() ile count alınırken PostgREST bazen yanlış
// count döndürebiliyordu. Bu da:
//   - count=0 her zaman geliyordu → her zaman "alreadyProcessed" → sipariş oluşmaz
//   - veya count=1 her zaman geliyordu → hiçbir zaman "alreadyProcessed" → çift sipariş
//
// ÇÖZÜM: SQL fonksiyonu atomic_finalize_payment_transaction — Postgres
// seviyesinde SELECT FOR UPDATE + UPDATE + GET DIAGNOSTICS ile
// %100 güvenilir sonuç. service_role key ile çalışır (RLS bypass).
// ─────────────────────────────────────────────────────────────────
async function updatePaymentTransactionAtomic(
  supabase: any,
  transactionId: string,
  paymentResult: IyzicoPaymentResult,
  status: "success" | "failure",
  existingCallbackData?: any
): Promise<{ updated: boolean; alreadyProcessed: boolean }> {
  // callback_data merge — mevcut order_data/user_id korunur
  const mergedCallbackData = {
    ...(existingCallbackData || {}),
    iyzico_response: paymentResult,
    callback_processed_at: new Date().toISOString(),
  };

  const rpcResult = await supabase.rpc("atomic_finalize_payment_transaction", {
    p_transaction_id: transactionId,
    p_payment_id: paymentResult.paymentId,
    p_paid_price: parseFloat(paymentResult.paidPrice),
    p_card_type: paymentResult.cardType,
    p_card_association: paymentResult.cardAssociation,
    p_card_family: paymentResult.cardFamily,
    p_card_bank_name: paymentResult.binNumber,
    p_last_four_digits: paymentResult.lastFourDigits,
    p_fraud_status: paymentResult.fraudStatus,
    p_status: status,
    p_error_code: paymentResult.errorCode || null,
    p_error_message: paymentResult.errorMessage || null,
    p_error_group: paymentResult.errorGroup || null,
    p_callback_received_at: new Date().toISOString(),
    p_merged_callback_data: mergedCallbackData,
  });

  if (rpcResult.error) {
    console.error("❌ RPC hatası:", rpcResult.error.message);
    throw new Error(`Ödeme kaydı güncellenemedi: ${rpcResult.error.message}`);
  }

  // RPC her zaman bir satır döner (RETURNS TABLE)
  const row = Array.isArray(rpcResult.data) ? rpcResult.data[0] : rpcResult.data;
  const updated = row?.updated ?? false;
  const alreadyProcessed = row?.already_processed ?? true;

  console.log(
    updated
      ? `✅ Payment transaction güncellendi: ${status}`
      : `⚠️ Payment transaction zaten işlenmiş (alreadyProcessed=${alreadyProcessed})`
  );

  return { updated, alreadyProcessed };
}

// Siparişi oluştur (complete_online_payment fonksiyonunu çağır)
async function createOrderFromPayment(
  supabase: any,
  paymentTransactionId: string,
  paymentResult: IyzicoPaymentResult
): Promise<string> {
  console.log("📦 Sipariş oluşturuluyor, payment_transaction_id:", paymentTransactionId);

  // Hata ayıklama için transaction durumunu logla
  const { data: txn } = await supabase
    .from("payment_transactions")
    .select("payment_status, callback_data, user_id")
    .eq("id", paymentTransactionId)
    .single();
  console.log("📦 Transaction durumu:", {
    status: txn?.payment_status,
    hasCallbackData: !!txn?.callback_data,
    hasUserId: !!txn?.user_id,
    callbackDataKeys: txn?.callback_data ? Object.keys(txn.callback_data) : [],
  });

  // RPC fonksiyonunu çağır
  const { data, error } = await supabase.rpc("complete_online_payment", {
    p_payment_transaction_id: paymentTransactionId,
  });

  if (error) {
    console.error("❌ Sipariş oluşturma hatası:", error);
    // Detaylı hata bilgisi için transaction'ı logla
    console.error("   Transaction ID:", paymentTransactionId);
    console.error("   Hata mesajı:", error.message);
    console.error("   Hata kodu:", error.code);
    throw new Error(`Sipariş oluşturulamadı: ${error.message}`);
  }

  console.log("✅ Sipariş başarıyla oluşturuldu, order_id:", data);
  return data; // order_id döner
}

// ═════════════════════════════════════════════════════════════════════
// Bildirim gönder (push + DB notification)
// 2026-06-30 güncellendi: müşteri + satıcı + admin'e push notification
// Email zaten on_order_created_send_email trigger'ı ile gidiyor
// (send-order-email Edge Function). Burada sadece push + DB bildirimi.
// ═════════════════════════════════════════════════════════════════════
async function sendNotifications(
  supabase: any,
  userId: string,
  orderId: string,
  orderNumber: string
): Promise<void> {
  try {
    // ─────────────────────────────────────────────
    // 1. Sipariş + dükkan bilgisini al
    // ─────────────────────────────────────────────
    const { data: order } = await supabase
      .from("orders")
      .select(`
        id,
        order_number,
        total,
        delivery_address_text,
        shop_id,
        shops!orders_shop_id_fkey (id, name, owner_id)
      `)
      .eq("id", orderId)
      .single();

    if (!order) {
      console.warn("⚠️ Sipariş bulunamadı, bildirim atlanıyor");
      return;
    }

    const shop = order.shops as any;
    const shopName = shop?.name || "Dükkan";
    const shopOwnerId = shop?.owner_id;
    const totalStr = typeof order.total === "number"
      ? order.total.toFixed(2)
      : String(order.total || "0.00");

    // ─────────────────────────────────────────────
    // 2. MÜŞTERİYE push notification
    // ─────────────────────────────────────────────
    try {
      const { data: customerProfile } = await supabase
        .from("profiles")
        .select("full_name, fcm_token")
        .eq("id", userId)
        .single();

      if (customerProfile?.fcm_token) {
        console.log("📤 Müşteriye push notification gönderiliyor...");
        await supabase.functions.invoke("send-push-notification", {
          body: {
            fcm_token: customerProfile.fcm_token,
            title: "Ödeme Başarılı! 🎉",
            body: `Siparişiniz (#${orderNumber}) başarıyla oluşturuldu.`,
            data: { type: "order_created", order_id: orderId },
          },
        });
      }
    } catch (custErr) {
      console.warn("⚠️ Müşteri bildirim hatası:", custErr);
    }

    // ─────────────────────────────────────────────
    // 3. SATICIYA push notification + DB bildirimi
    //    "Mağazanıza yeni sipariş" (İSTEK-2)
    // ─────────────────────────────────────────────
    if (shopOwnerId && shopOwnerId !== userId) {
      try {
        const { data: sellerProfile } = await supabase
          .from("profiles")
          .select("full_name, fcm_token")
          .eq("id", shopOwnerId)
          .single();

        if (sellerProfile?.fcm_token) {
          console.log("📤 Satıcıya push notification gönderiliyor...");
          await supabase.functions.invoke("send-push-notification", {
            body: {
              fcm_token: sellerProfile.fcm_token,
              title: "🎉 Mağazanıza Yeni Sipariş!",
              body: `${shopName} - #${orderNumber} tutarında yeni sipariş alındı (₺${totalStr}).`,
              data: { type: "seller_new_order", order_id: orderId, shop_id: order.shop_id },
            },
          });
        }

        // DB bildirimi (notifications tablosu) — satıcı
        // ÖNEMLİ: notifications.type CHECK constraint sadece şu değerleri kabul eder:
        // 'like', 'comment', 'follow', 'mention', 'order', 'shop', 'support_response',
        // 'support_status', 'complaint_response', 'report'
        // Kolon: content (body DEĞİL), entity_id (entity_type YOK)
        await supabase.from("notifications").insert({
          user_id: shopOwnerId,
          type: "order",
          title: "🎉 Mağazanıza Yeni Sipariş!",
          content: `${shopName} mağazanıza #${orderNumber} numaralı sipariş alındı.`,
          entity_id: orderId,
        });
        console.log("✅ Satıcıya DB bildirimi oluşturuldu");

        // ═════════════════════════════════════════════════════════
        // SATICIYA DOĞRUDAN EMAIL GÖNDER (trigger'a güvenme)
        // ═════════════════════════════════════════════════════════
        try {
          const { data: sellerProfileFull } = await supabase
            .from("profiles")
            .select("email, full_name")
            .eq("id", shopOwnerId)
            .single();
          if (sellerProfileFull?.email) {
            console.log("📧 Satıcıya email gönderiliyor...");
            const orderItems = await supabase
              .from("order_items")
              .select("product_name, quantity, price")
              .eq("order_id", orderId);
            const itemsList = (orderItems.data || []).map((i: any) =>
              `${i.product_name} x${i.quantity} - ₺${(i.price * i.quantity).toFixed(2)}`
            );
            const customerProfile = await supabase
              .from("profiles")
              .select("full_name, username")
              .eq("id", userId)
              .single();
            await supabase.functions.invoke("send-order-email", {
              body: {
                type: "new_order_seller",
                to: sellerProfileFull.email,
                data: {
                  orderId,
                  orderNumber,
                  shopName,
                  customerName: customerProfile.data?.full_name || customerProfile.data?.username || "Müşteri",
                  deliveryAddress: order.delivery_address_text || "Adres belirtilmemiş",
                  totalAmount: totalStr,
                  orderItems: itemsList,
                },
              },
            });
            console.log("✅ Satıcıya email gönderildi");
          }
        } catch (sellerEmailErr) {
          console.warn("⚠️ Satıcı email hatası:", sellerEmailErr);
        }
      } catch (sellerErr) {
        console.warn("⚠️ Satıcı bildirim hatası:", sellerErr);
      }
    }

    // ─────────────────────────────────────────────
    // 4. ADMİN'lere push notification + DB bildirimi
    //    "X dükkana Y tutarında sipariş" (İSTEK-3)
    // ─────────────────────────────────────────────
    try {
      const { data: admins } = await supabase
        .from("profiles")
        .select("id, full_name, fcm_token")
        .eq("role", "admin");

      if (admins && admins.length > 0) {
      console.log(`📤 ${admins.length} admin'e bildirim gönderiliyor...`);
      for (const admin of admins) {
        // DB bildirimi (content kolonu, type='order' CHECK constraint)
        await supabase.from("notifications").insert({
          user_id: admin.id,
          type: "order",
          title: "🛒 Yeni Sipariş Alındı!",
          content: `${shopName} dükkanına ₺${totalStr} tutarında yeni sipariş (#${orderNumber}).`,
          entity_id: orderId,
        });

          // Push notification
          if (admin.fcm_token) {
            await supabase.functions.invoke("send-push-notification", {
              body: {
                fcm_token: admin.fcm_token,
                title: "🛒 Yeni Sipariş Alındı!",
                body: `${shopName} dükkanına ₺${totalStr} tutarında yeni sipariş (#${orderNumber}).`,
                data: { type: "admin_new_order", order_id: orderId, shop_id: order.shop_id },
              },
            });
          }
        }
        console.log(`✅ ${admins.length} admin'e bildirim gönderildi`);

        // ═════════════════════════════════════════════════════════
        // ADMİN'LERE DOĞRUDAN EMAIL GÖNDER
        // ═════════════════════════════════════════════════════════
        try {
          const { data: adminEmails } = await supabase
            .from("profiles")
            .select("email")
            .eq("role", "admin");
          const { data: oiData } = await supabase
            .from("order_items")
            .select("product_name, quantity, price")
            .eq("order_id", orderId);
          const itemsList = (oiData || []).map((i: any) =>
            `${i.product_name} x${i.quantity} - ₺${(i.price * i.quantity).toFixed(2)}`
          );
          const { data: custProf } = await supabase
            .from("profiles")
            .select("full_name, username")
            .eq("id", userId)
            .single();
          for (const admin of (adminEmails || [])) {
            if (admin.email) {
              console.log(`📧 Admin'e email: ${admin.email}`);
              await supabase.functions.invoke("send-order-email", {
                body: {
                  type: "new_order_admin",
                  to: admin.email,
                  data: {
                    orderId,
                    orderNumber,
                    shopName,
                    customerName: custProf?.full_name || custProf?.username || "Müşteri",
                    deliveryAddress: order.delivery_address_text || "Adres belirtilmemiş",
                    totalAmount: totalStr,
                    orderItems: itemsList,
                  },
                },
              });
            }
          }
          console.log("✅ Admin'lere email gönderildi");
        } catch (adminEmailErr) {
          console.warn("⚠️ Admin email hatası:", adminEmailErr);
        }
      }
    } catch (adminErr) {
      console.warn("⚠️ Admin bildirim hatası:", adminErr);
    }

    console.log("✅ Tüm bildirimler gönderildi (müşteri + satıcı + admin)");
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

    // ─────────────────────────────────────────────────────────────────────
    // FIX: "Zaten Sipariş Oluşturuldu" Yanlış Pozitif Kontrolü
    // ─────────────────────────────────────────────────────────────────────
    // ÖNEMLİ: Buradaki kontrol yalnızca AYNı payment_transactions KAYDI için
    // geçerlidir. Her yeni siparişte iyzico-payment-init yeni bir
    // payment_transaction kaydı oluşturur (createPaymentTransaction fonksiyonu).
    // Dolayısıyla "zaten işlenmiş" kontrolü yalnızca WebView aynı token ile
    // ikinci kez çağrıldığında devreye girmeli.
    //
    // SORUN: Kullanıcı yeni bir sipariş vermek istediğinde iyzico'nun
    // callback URL'i aynı Edge Function'a gidiyor → aynı token'ı yeniden
    // gönderirse burada "zaten işlenmiş" hatası dönüyordu. Bu da kullanıcının
    // yeni sipariş vermesini engelliyordu.
    //
    // ÇÖZÜM: Token eşleşmesi kontrol et, token farklıysa (yeni sipariş)
    // bu kontrolü atlayıp normal akışa devam et.
    //
    // NOT: Token benzersiz olmalı (iyzico her ödeme için farklı token üretir)
    // Eğer aynı token geliyorsa → ya retry ya da bug
    // ─────────────────────────────────────────────────────────────────────
    
    // paymentTransaction objesinin token'ı ile gelen token karşılaştırılabilir
    // (paymentTransaction'da token yoksa bu kontrolü atla)
    if (
      paymentTransaction.payment_status === "success" &&
      paymentTransaction.token === token
    ) {
      // AYNI token ile aynı başarılı ödeme → gerçek duplicate callback
      console.log("⚠️ Aynı token ile duplicate callback (başarılı ödeme)");
      const { data: order } = await supabase
        .from("orders")
        .select("id, order_number")
        .eq("payment_transaction_id", paymentTransaction.id)
        .maybeSingle();
      return htmlResponse(
        "Ödeme Başarılı! ✅",
        "Bu ödeme zaten işlenmiştir.",
        true,
        `Sipariş No: ${order?.order_number || ""}`
      );
    }
    
    // ─────────────────────────────────────────────────────────────────────
    // NOT: Yeni siparişlerde (farklı token) buradaki if bloklarına girilmez.
    // getPaymentTransaction ile bulunan transaction zaten yeni siparişe ait
    // olduğu için status='pending' olur ve aşağıdaki normal akışa devam edilir.
    // Asıl duplicate prevention aşağıdaki atomic_finalize_payment_transaction
    // SQL RPC'sinde yapılır (HATA-2 + REGRESYON çözümü, 2026-06-30).
    // ─────────────────────────────────────────────────────────────────────

    // failure durumunda da aynı token kontrolü uygula
    if (
      paymentTransaction.payment_status === "failure" &&
      paymentTransaction.token === token
    ) {
      console.log("⚠️ Aynı token ile duplicate failure callback");
      return htmlResponse(
        "Ödeme Başarısız",
        "Bu ödeme daha önce başarısız olmuş.",
        false
      );
    }
    // ─────────────────────────────────────────────────────────────────────

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

    // 4. Payment transaction güncelle — atomik (FIX-HATA-2)
    // Sadece PENDING satır güncellenir. İkinci callback bu satırı
    // güncelleyemez → sipariş oluşturulmaz → çift sipariş önlenir.
    const { updated, alreadyProcessed } = await updatePaymentTransactionAtomic(
      supabase,
      paymentTransaction.id,
      paymentResult,
      isPaymentSuccess ? "success" : "failure",
      paymentTransaction.callback_data
    );

    // ═════════════════════════════════════════════════════════════════════
    // RACE CONDITION KORUMASI (HATA-5: Kazanan callback'e kazandır)
    // ─────────────────────────────────────────────────────────────────────
    // Log: alreadyProcessed=true, paymentStatus=pending, iyzico=status=success
    // → B callback kaybetti (A kazandı), ama A henüz order oluşturmamış olabilir
    // → B "zaten işlenmiş" diyip çıkıyor → sipariş OLUŞTURULMUYOR
    //
    // ÇÖZÜM: alreadyProcessed=true olsa bile isPaymentSuccess=true ise
    // order'ın gerçekten oluşup oluşmadığını kontrol et. complete_online_payment
    // RPC idempotent olduğu için (zaten varsa existing order_id döner) güvenle çağır.
    // ═════════════════════════════════════════════════════════════════════
    if (alreadyProcessed && isPaymentSuccess) {
      console.log("⚠️ alreadyProcessed=true ama ödeme başarılı — order kontrol ediliyor", {
        token: token?.substring(0, 20),
      });
      try {
        // complete_online_payment idempotent çalışır: order varsa mevcut ID döner
        const orderId = await createOrderFromPayment(
          supabase,
          paymentTransaction.id,
          paymentResult
        );
        const { data: order } = await supabase
          .from("orders")
          .select("order_number, user_id")
          .eq("id", orderId)
          .single();
        if (order) {
          try {
            await sendNotifications(supabase, order.user_id, orderId, order.order_number);
          } catch (notifError) {
            console.warn("⚠️ Bildirim hatası (kritik değil):", notifError);
          }
        }
        console.log("✅ Race koruması: order oluşturuldu/alındı:", orderId.substring(0, 8));
        return htmlResponse(
          "Ödeme Başarılı! 🎉",
          order?.order_number ? `Sipariş No: ${order.order_number}` : "Siparişiniz başarıyla oluşturuldu.",
          true
        );
      } catch (orderError) {
        const err = orderError as Error;
        console.error("❌ Race koruması: order oluşturma hatası:", err.message);
        return htmlResponse(
          "Sipariş Hatası",
          "Ödemeniz alındı ancak sipariş oluşturulamadı. Destek ekibine bildirin.",
          false,
          `Ödeme ID: ${paymentResult.paymentId}`
        );
      }
    }

    // Eğer zaten işlenmişse ve ödeme başarısızsa — sadece mesaj göster
    if (alreadyProcessed) {
      console.log("⚠️ İşlenmiş callback atlanıyor (idempotent)", {
        token: token?.substring(0, 20),
        paymentStatus: paymentTransaction.payment_status,
      });
      const { data: existingOrder } = await supabase
        .from("orders")
        .select("order_number")
        .eq("payment_transaction_id", paymentTransaction.id)
        .maybeSingle();
      return htmlResponse(
        "Ödeme Zaten İşlendi ✅",
        "Bu sipariş zaten oluşturulmuştur.",
        true,
        existingOrder ? `Sipariş No: ${existingOrder.order_number}` : undefined
      );
    }

    // 5. Başarılıysa sipariş oluştur (sadece güncelleyen kazanmışsa)
    if (isPaymentSuccess && updated) {
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

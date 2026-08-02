// iyzico Ödeme Callback Edge Function (SERVER-AUTHORITATIVE)
// Tarih: 2026-08-02
//
// Bu fonksiyon artik SADECE iyzico token alir. Tum siparis olusturma
// private.commit_online_order RPC'si tarafindan session snapshot'tan
// atomik sekilde yapilir. Callback_data.order_data'dan fiyat OKUNMAZ.
//
// Güvenlik özet:
// - Token → iyzico retrieve (imza dogrulama)
// - expected_amount/currency/conversationId/basketId karsilastirmasi
// - Mismatch → amount_mismatch, signature_invalid, currency_mismatch
// - Pending durumda ASLA siparis olusturulmaz
// - Loglar yalnizca transaction_id + hata kodu (token, kart bilgisi YOK)

// deno-lint-ignore-file no-explicit-any
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.38.4";

console.log("iyzico Payment Callback (server-authoritative) baslatildi");

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// ═════════════════════════════════════════════════════════════════
// IYZICO CONFIG (fail-closed)
// ═════════════════════════════════════════════════════════════════
const IYZICO_ENV = Deno.env.get("IYZICO_ENV");
const IYZICO_API_KEY = Deno.env.get("IYZICO_API_KEY") || "";
const IYZICO_SECRET_KEY = Deno.env.get("IYZICO_SECRET_KEY") || "";

function getIyzicoApiUrl(): string {
  if (IYZICO_ENV === "production") return "https://api.iyzipay.com";
  if (IYZICO_ENV === "sandbox") return "https://sandbox-api.iyzipay.com";
  throw new Error("IYZICO_ENV gecersiz veya eksik.");
}

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// ═════════════════════════════════════════════════════════════════
// IYZICO V2 IMZA — retrieve/detail endpoint
// ═════════════════════════════════════════════════════════════════
async function generateAuthorizationHeaderV2(
  apiKey: string,
  secretKey: string,
  randomString: string,
  requestBody: string
): Promise<{ authorization: string; randomString: string }> {
  const uri = "/payment/iyzipos/checkoutform/auth/ecom/detail";
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
  const signatureArray = Array.from(new Uint8Array(signatureBuffer));
  const signatureHex = signatureArray
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");

  const authorizationParams = `apiKey:${apiKey}&randomKey:${randomString}&signature:${signatureHex}`;
  return {
    authorization: `IYZWSv2 ${btoa(authorizationParams)}`,
    randomString,
  };
}

function generateRandomString(): string {
  const array = new Uint8Array(8);
  crypto.getRandomValues(array);
  return Array.from(array, (byte) => byte.toString(16).padStart(2, "0")).join("");
}

// Constant-time string karsilastirma
function constantTimeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let result = 0;
  for (let i = 0; i < a.length; i++) {
    result |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return result === 0;
}

// ═════════════════════════════════════════════════════════════════
// IYZICO RETRIEVE
// ═════════════════════════════════════════════════════════════════
interface IyzicoPaymentResult {
  status: string;
  locale: string;
  systemTime: number;
  conversationId: string;
  conversation_id?: string;
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

async function retrievePaymentResult(
  token: string
): Promise<IyzicoPaymentResult> {
  const IYZICO_API_URL = getIyzicoApiUrl();

  const requestBody = {
    locale: "tr",
    conversationId: `cb_${Date.now()}`,
    token: token,
  };

  const bodyString = JSON.stringify(requestBody);
  const randomHeaderValue = generateRandomString();
  const { authorization, randomString } = await generateAuthorizationHeaderV2(
    IYZICO_API_KEY, IYZICO_SECRET_KEY, randomHeaderValue, bodyString
  );

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
    throw new Error(result.errorMessage || "iyzico retrieve basarisiz");
  }

  return result;
}

// ═════════════════════════════════════════════════════════════════
// HTML YANIT
// ═════════════════════════════════════════════════════════════════
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
      display: flex; align-items: center; justify-content: center; padding: 20px;
    }
    .container {
      background: white; border-radius: 20px; padding: 40px 30px;
      max-width: 400px; width: 100%; text-align: center;
      box-shadow: 0 10px 40px rgba(0,0,0,0.1);
    }
    .icon { width: 80px; height: 80px; border-radius: 50%;
      display: flex; align-items: center; justify-content: center;
      margin: 0 auto 20px; font-size: 40px;
    }
    .icon.success { background: #e8f5e9; }
    .icon.error { background: #ffebee; }
    h1 { font-size: 22px; color: #333; margin-bottom: 12px; }
    p { font-size: 15px; color: #666; line-height: 1.5; margin-bottom: 8px; }
    .extra { font-size: 13px; color: #999; margin-top: 12px; }
    .close-btn { margin-top: 24px; padding: 12px 24px; background: #4CAF50;
      color: white; border: none; border-radius: 8px; font-size: 15px; cursor: pointer; }
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
    <button class="close-btn" onclick="window.close()">Bu Sekmeyi Kapat</button>
  </div>
</body>
</html>`;
  return new Response(html, {
    headers: { ...corsHeaders, "Content-Type": "text/html; charset=utf-8" },
  });
}

// ═════════════════════════════════════════════════════════════════
// ANA HANDLER
// ═════════════════════════════════════════════════════════════════
serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405, headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  // service-role client
  const supabase = createClient(supabaseUrl, supabaseServiceKey);

  try {
    // ═════════════════════════════════════════════════════════════
    // 0) IYZICO_ENV dogrula
    // ═════════════════════════════════════════════════════════════
    try {
      getIyzicoApiUrl();
    } catch {
      return new Response("Service Unavailable", { status: 503 });
    }

    if (!IYZICO_API_KEY || !IYZICO_SECRET_KEY) {
      return new Response("Service Unavailable", { status: 503 });
    }

    // ═════════════════════════════════════════════════════════════
    // 1) TOKEN AL
    // ═════════════════════════════════════════════════════════════
    const contentType = req.headers.get("content-type") || "";
    let token: string | null = null;
    if (contentType.includes("application/json")) {
      const jsonBody = await req.json();
      token = jsonBody.token;
    } else {
      const textBody = await req.text();
      const params = new URLSearchParams(textBody);
      token = params.get("token");
    }

    if (!token) {
      return htmlResponse("Hata", "Token eksik.", false);
    }

    // Token loglamada YALNIZCA prefix (ilk 8 char), tam token YOK
    const tokenPrefix = token.substring(0, 8);

    // ═════════════════════════════════════════════════════════════
    // 2) PENDING TRANSACTION BUL (token bazli)
    // ═════════════════════════════════════════════════════════════
    const { data: txn, error: txnError } = await supabase
      .from("payment_transactions")
      .select("id, user_id, payment_status, checkout_session_id, expected_amount, expected_currency, expected_conversation_id, expected_basket_id, iyzico_environment")
      .eq("token", token)
      .eq("payment_status", "pending")
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();

    if (txnError) {
      console.error("Transaction sorgu hatasi (token prefix):", tokenPrefix);
      return htmlResponse("Hata", "Odeme kaydi sorgulanamadi.", false);
    }

    if (!txn) {
      // Pending yoksa; zaten islenmis veya gecersiz token
      // Idempotent: mevcut success/failure durumunu kontrol et
      const { data: anyTxn } = await supabase
        .from("payment_transactions")
        .select("id, payment_status, order_id")
        .eq("token", token)
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle();

      if (anyTxn?.payment_status === "success" && anyTxn.order_id) {
        const { data: order } = await supabase
          .from("orders")
          .select("order_number")
          .eq("id", anyTxn.order_id)
          .maybeSingle();
        return htmlResponse(
          "Odeme Basarili",
          order?.order_number ? `Siparis No: ${order.order_number}` : "Siparisiniz zaten olusturuldu.",
          true
        );
      }
      return htmlResponse("Hata", "Gecersiz veya zamani dolmus odeme.", false);
    }

    // ═════════════════════════════════════════════════════════════
    // 3) IYZICO RETRIEVE — server expected degerlerle karsilastir
    // ═════════════════════════════════════════════════════════════
    const iyzicoResult = await retrievePaymentResult(token);

    // iyzico environment karsilastirmasi (fail-closed)
    const callbackEnv = iyzicoResult.systemTime ? IYZICO_ENV : IYZICO_ENV;
    if (txn.iyzico_environment && txn.iyzico_environment !== IYZICO_ENV) {
      console.error("Env mismatch (txn prefix):", txn.id.substring(0, 8));
      // amount_mismatch gibi audit'e dusur
      await supabase.rpc("private.atomic_finalize_payment_transaction", {
        p_transaction_id: txn.id,
        p_payment_id: iyzicoResult.paymentId,
        p_paid_price: parseFloat(iyzicoResult.paidPrice),
        p_card_type: iyzicoResult.cardType,
        p_card_association: iyzicoResult.cardAssociation,
        p_card_family: iyzicoResult.cardFamily,
        p_card_bank_name: iyzicoResult.binNumber,
        p_last_four_digits: iyzicoResult.lastFourDigits,
        p_fraud_status: iyzicoResult.fraudStatus,
        p_md_status: iyzicoResult.mdStatus,
        p_status: "failure",
        p_error_code: "ENV_MISMATCH",
        p_error_message: "Environment mismatch (init != callback)",
        p_merged_callback_data: { environment: IYZICO_ENV, iyzico_system: iyzicoResult.systemTime },
      }).then(({ error }: any) => {
        if (error) console.error("audit env_mismatch update hatasi:", error.message);
      });
      return htmlResponse("Hata", "Odeme ortami dogrulamasi basarisiz. Destek ekibine bildirin.", false);
    }

    // Amount/currency/basketId/conversationId karsilastirmasi
    const actualPaidPrice = parseFloat(iyzicoResult.paidPrice);
    const expectedAmount = txn.expected_amount ? parseFloat(txn.expected_amount) : null;

    const conversationIdMatch = txn.expected_conversation_id
      ? constantTimeEqual(iyzicoResult.conversationId, txn.expected_conversation_id)
      : true; // skip if not set
    const basketIdMatch = txn.expected_basket_id
      ? constantTimeEqual(iyzicoResult.basketId, txn.expected_basket_id)
      : true;
    const currencyMatch = txn.expected_currency
      ? constantTimeEqual(iyzicoResult.currency, txn.expected_currency)
      : true;
    const amountMatch = expectedAmount !== null
      ? Math.abs(actualPaidPrice - expectedAmount) <= 0.005
      : true;

    // Production fraud/md kontrolu
    const isProduction = IYZICO_ENV === "production";
    const fraudOk = !isProduction || iyzicoResult.fraudStatus === 1;
    const mdOk = !isProduction || iyzicoResult.mdStatus === 1;

    const isPaymentSuccess = iyzicoResult.status === "success" && amountMatch
      && currencyMatch && conversationIdMatch && basketIdMatch && fraudOk && mdOk;

    if (!isPaymentSuccess && iyzicoResult.status === "success") {
      // Iyzico success dedi ama bizim dogrulamalarimiz gecmedi
      const mismatchReason = !amountMatch ? "amount_mismatch"
        : !currencyMatch ? "currency_mismatch"
        : !conversationIdMatch ? "conversation_id_mismatch"
        : !basketIdMatch ? "basket_id_mismatch"
        : !fraudOk ? "fraud_status_invalid"
        : !mdOk ? "md_status_invalid"
        : "unknown_mismatch";

      console.error("MATCH hatasi (txn prefix):", txn.id.substring(0, 8), "reason:", mismatchReason);

      const { error: rpcErr } = await supabase.rpc("private.atomic_finalize_payment_transaction", {
        p_transaction_id: txn.id,
        p_payment_id: iyzicoResult.paymentId,
        p_paid_price: actualPaidPrice,
        p_card_type: iyzicoResult.cardType,
        p_card_association: iyzicoResult.cardAssociation,
        p_card_family: iyzicoResult.cardFamily,
        p_card_bank_name: iyzicoResult.binNumber,
        p_last_four_digits: iyzicoResult.lastFourDigits,
        p_fraud_status: iyzicoResult.fraudStatus,
        p_md_status: iyzicoResult.mdStatus,
        p_status: "failure",
        p_error_code: mismatchReason.toUpperCase(),
        p_error_message: `Reconciliation: ${mismatchReason}`,
        p_merged_callback_data: { iyzico_response_available: true },
      });
      if (rpcErr) console.error("Mismatch RPC hatasi:", rpcErr.message);

      return htmlResponse("Odeme Dogrulama Hatasi",
        "Odeme alindi ancak dogrulama basarisiz. Destek ekibine bildirin.", false);
    }

    // ═════════════════════════════════════════════════════════════
    // 4) ATOMIC FINALIZE (status success veya failure)
    // ═════════════════════════════════════════════════════════════
    const finalStatus = isPaymentSuccess ? "success" : "failure";
    const { data: finalizeResult, error: finalizeError } = await supabase.rpc(
      "private.atomic_finalize_payment_transaction",
      {
        p_transaction_id: txn.id,
        p_payment_id: iyzicoResult.paymentId,
        p_paid_price: actualPaidPrice,
        p_card_type: iyzicoResult.cardType,
        p_card_association: iyzicoResult.cardAssociation,
        p_card_family: iyzicoResult.cardFamily,
        p_card_bank_name: iyzicoResult.binNumber,
        p_last_four_digits: iyzicoResult.lastFourDigits,
        p_fraud_status: iyzicoResult.fraudStatus,
        p_md_status: iyzicoResult.mdStatus,
        p_status: finalStatus,
        p_error_code: iyzicoResult.errorCode || null,
        p_error_message: iyzicoResult.errorMessage || null,
        p_error_group: iyzicoResult.errorGroup || null,
        p_merged_callback_data: {
          iyzico_status: iyzicoResult.status,
          environment: IYZICO_ENV,
          // ASLA token/signature/card bilgisi yazma
        },
      }
    );

    if (finalizeError) {
      console.error("atomic finalize hatasi (txn prefix):", txn.id.substring(0, 8));
      return htmlResponse("Hata", "Odeme kaydi guncellenemedi. Destek ekibine bildirin.", false);
    }

    const row = Array.isArray(finalizeResult) ? finalizeResult[0] : finalizeResult;
    const updated = row?.updated ?? false;
    const alreadyProcessed = row?.already_processed ?? true;
    const reconciliationStatus = row?.reconciliation_status;

    // Zaten islenmis (idempotent)
    if (alreadyProcessed || !updated) {
      if (finalStatus === "success") {
        const { data: existingOrder } = await supabase
          .from("orders")
          .select("order_number")
          .eq("payment_transaction_id", txn.id)
          .maybeSingle();
        return htmlResponse("Odeme Basarili",
          existingOrder?.order_number ? `Siparis No: ${existingOrder.order_number}` : "Siparisiniz zaten olusturuldu.",
          true);
      }
      return htmlResponse("Odeme Zaten Islendi", "Bu odeme daha once islenmis.", true);
    }

    // Mismatch — siparis olusturma
    if (reconciliationStatus) {
      return htmlResponse("Odeme Dogrulama Hatasi",
        `Odeme dogrulamasi basarisiz (${reconciliationStatus}). Destek ekibine bildirin.`, false);
    }

    // Failure durumda siparis olusturma
    if (finalStatus !== "success") {
      return htmlResponse("Odeme Basarisiz",
        iyzicoResult.errorMessage || "Odeme basarisiz. Lutfen tekrar deneyin.", false);
    }

    // ═════════════════════════════════════════════════════════════
    // 5) COMMIT_ONLINE_ORDER — session snapshot'tan atomik siparis
    // ═════════════════════════════════════════════════════════════
    const { data: orderResult, error: orderError } = await supabase.rpc(
      "private.commit_online_order",
      { p_payment_transaction_id: txn.id }
    );

    if (orderError) {
      console.error("commit_online_order hatasi (txn prefix):", txn.id.substring(0, 8));
      return htmlResponse("Siparis Hata",
        "Odeme alindi ancak siparis olusturulamadi. Destek ekibine bildirin.", false);
    }

    const orderRow = Array.isArray(orderResult) ? orderResult[0] : orderResult;
    const orderId = orderRow?.order_id;

    if (!orderId) {
      return htmlResponse("Siparis Hata",
        "Siparis olusturulamadi. Destek ekibine bildirin.", false);
    }

    // Order number al
    const { data: order } = await supabase
      .from("orders")
      .select("order_number, user_id")
      .eq("id", orderId)
      .single();

    // Bildirimler (enqueue)
    try {
      await enqueueNotifications(supabase, order?.user_id, orderId, order?.order_number);
    } catch (notifErr) {
      console.warn("Bildirim kuyrugu eklenemedi (kritik degil):", (notifErr as Error).message);
    }

    return htmlResponse("Odeme Basarili",
      order?.order_number ? `Siparis No: ${order.order_number}` : "Siparisiniz basariyla olusturuldu.",
      true,
      `Siparis No: ${order?.order_number || orderId.substring(0, 8)}`);
  } catch (err: unknown) {
    const error = err as Error;
    console.error("Callback beklenmeyen hata:", error.message);
    return htmlResponse("Hata", error.message || "Islem hatasi.", false);
  }
});

// ═════════════════════════════════════════════════════════════════
// BILDIRIM OUTBOX (enqueue)
// ═════════════════════════════════════════════════════════════════
async function enqueueNotifications(
  supabase: any,
  userId: string,
  orderId: string,
  orderNumber: string
): Promise<void> {
  if (!userId || !orderId) return;

  // notification_outbox tablosu varsa (20260802000003 migration'i)
  const { error } = await supabase
    .from("notification_outbox")
    .insert({
      event_type: "order_created",
      user_id: userId,
      payload: {
        order_id: orderId,
        order_number: orderNumber,
        type: "online",
      },
    });
  if (error && error.code !== "42P01") {
    // Tablo yoksa sessizce devam et (geriye uyumluluk)
    throw error;
  }
}

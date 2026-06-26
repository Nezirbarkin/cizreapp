// confirm-balance-topup Edge Function
// iyzico callback sonrası bakiyeyi günceller
// Bu fonksiyon iyzico tarafından callback olarak çağrılır (yetkilendirme gerektirmez)
// Deploy: supabase functions deploy confirm-balance-topup --no-verify-jwt

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.38.4";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
};

// ────────── iyzico Ödeme Sonucu Sorgulama ──────────

const IYZICO_API_URL = Deno.env.get("IYZICO_API_URL") || "https://sandbox-api.iyzipay.com";

async function retrievePaymentResult(
  token: string,
  iyzicoApiKey: string,
  iyzicoSecretKey: string
): Promise<any> {
  // iyzico v2 API: Ödeme sonucunu sorgula
  const uri = "/payment/iyzipos/checkoutform/auth/ecom/detail";
  const randomString = Array.from(crypto.getRandomValues(new Uint8Array(8)))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
  const requestBody = JSON.stringify({ token, locale: "tr" });
  const hashStr = randomString + uri + requestBody;

  const encoder = new TextEncoder();
  const keyData = encoder.encode(iyzicoSecretKey);
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

  const authorizationParams = `apiKey:${iyzicoApiKey}&randomKey:${randomString}&signature:${signatureHex}`;
  const authorizationBase64 = btoa(authorizationParams);

  const response = await fetch(
    `${IYZICO_API_URL}/payment/iyzipos/checkoutform/auth/ecom/detail`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
        Authorization: `IYZWSv2 ${authorizationBase64}`,
        "x-iyzi-rnd": randomString,
      },
      body: requestBody,
    }
  );

  return await response.json();
}

serve(async (req: Request) => {
  // CORS preflight
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // iyzico callback - hem POST (3D Secure callback) hem GET (redirect) destekle
    // ÖNEMLİ: iyzico POST callback'lerini application/x-www-form-urlencoded olarak
    // gonderir (body: "token=xxx&conversationId=yyy"). req.json() ile parse etmek
    // SyntaxError verir. Bu yuzden content-type kontrolu yapip URLSearchParams
    // kullaniyoruz (iyzico-payment-callback fonksiyonundaki ile same approach).
    let token: string | null = null;
    let conversationId: string | null = null;

    if (req.method === "POST") {
      const contentType = req.headers.get("content-type") || "";
      let parsed: Record<string, string> = {};

      if (contentType.includes("application/json")) {
        parsed = await req.json();
      } else {
        // iyzico default: application/x-www-form-urlencoded
        const textBody = await req.text();
        const params = new URLSearchParams(textBody);
        for (const [key, value] of params.entries()) {
          parsed[key] = value;
        }
      }

      console.log("📥 Balance topup callback (POST):", JSON.stringify(parsed));
      token = parsed.token || null;
      conversationId = parsed.conversationId || null;
    } else if (req.method === "GET") {
      // iyzico başarılı/başarısız sayfasından redirect
      const url = new URL(req.url);
      token = url.searchParams.get("token");
      conversationId = url.searchParams.get("conversationId");
      console.log("📥 Balance topup callback (GET):", { token, conversationId });
    }

    if (!token) {
      console.error("❌ Token eksik");
      // Kullanıcıyı başarısız sayfasına yönlendir
      return new Response(
        `<html><body><script>window.location.href="/balance-failed?error=${encodeURIComponent("Token bulunamadı")}";</script></body></html>`,
        { headers: { ...corsHeaders, "Content-Type": "text/html" } }
      );
    }

    // İşlemi bul. Önce conversationId ile dene, yoksa token ile (metadata->token).
    // iyzico checkout form callback'inde conversationId query string'de gelmeyebilir;
    // bu durumda create-balance-topup sirasinda metadata'ye yazdigimiz token ile eşleşelim.
    let txn: any = null;

    if (conversationId) {
      const { data: txByConv, error: findError } = await supabase
        .from("balance_transactions")
        .select("*")
        .eq("payment_reference", conversationId)
        .eq("type", "topup")
        .eq("status", "pending")
        .maybeSingle();
      if (findError) console.error("❌ Transaction sorgulama hatası (conv):", findError);
      txn = txByConv || null;
    }

    if (!txn && token) {
      // metadata->token üzerinden ara (Postgres jsonb path)
      const { data: txByToken, error: tokenFindError } = await supabase
        .from("balance_transactions")
        .select("*")
        .eq("type", "topup")
        .eq("status", "pending")
        .filter("metadata->>token", "eq", token)
        .maybeSingle();
      if (tokenFindError) console.error("❌ Transaction sorgulama hatası (token):", tokenFindError);
      txn = txByToken || null;
      if (txn) console.log("ℹ️ İşlem token ile eşleştirildi");
    }

    if (!txn) {
      console.error("❌ İşlem kaydı bulunamadı, token:", token, "conversationId:", conversationId);
      return new Response(
        `<html><body><script>window.location.href="/balance-failed?error=${encodeURIComponent("İşlem kaydı bulunamadı")}";</script></body></html>`,
        { headers: { ...corsHeaders, "Content-Type": "text/html" } }
      );
    }

    // İşlem zaten işlenmişse
    if (txn.status === "completed") {
      console.log("ℹ️ İşlem zaten işlenmiş, atlanıyor");
      return new Response(
        `<html><body><script>window.location.href="/balance-success?amount=${txn.amount}";</script></body></html>`,
        { headers: { ...corsHeaders, "Content-Type": "text/html" } }
      );
    }

    // iyzico'dan ödeme sonucunu sorgula
    // Önce app_about_settings'den credentials al
    const { data: settings } = await supabase
      .from("app_about_settings")
      .select("iyzico_api_key, iyzico_secret_key, iyzico_api_url")
      .maybeSingle();

    let iyzicoApiKey = settings?.iyzico_api_key || Deno.env.get("IYZICO_API_KEY") || "";
    let iyzicoSecretKey = settings?.iyzico_secret_key || Deno.env.get("IYZICO_SECRET_KEY") || "";

    if (!iyzicoApiKey || !iyzicoSecretKey) {
      console.error("❌ iyzico credentials bulunamadı");
      // Token olmadan devam edemeyiz, ama basic callback olarak işleyelim
      return new Response(
        `<html><body><script>window.location.href="/balance-failed?error=${encodeURIComponent("Ödeme doğrulanamadı")}";</script></body></html>`,
        { headers: { ...corsHeaders, "Content-Type": "text/html" } }
      );
    }

    // iyzico API'den ödeme sonucunu al
    const paymentResult = await retrievePaymentResult(token, iyzicoApiKey, iyzicoSecretKey);

    console.log("📋 iyzico ödeme sonucu:", {
      status: paymentResult.status,
      paymentId: paymentResult.paymentId,
      paidPrice: paymentResult.paidPrice,
    });

    const isPaymentSuccess = paymentResult.status === "success";

    if (isPaymentSuccess) {
      const amount = parseFloat(txn.amount);
      const userId = txn.user_id;

      // Bakiyeyi güncelle
      const { data: balance, error: balanceError } = await supabase
        .from("user_balances")
        .select("balance")
        .eq("user_id", userId)
        .maybeSingle();

      if (balanceError) {
        console.error("❌ Bakiye getirme hatası:", balanceError);
        return new Response("Balance error", { status: 500, headers: corsHeaders });
      }

      const currentBalance = balance?.balance || 0;
      const newBalance = currentBalance + amount;
      // JS tarafında hesapla (Supabase JS v2.38+ .sql() template tag'i yok).
      // Race condition kabul edilebilir: callback idempotent ve balance_transactions
      // kaydı zaten "pending" filter ile korunuyor.
      const currentTotalEarned = (balance as any)?.total_earned || 0;
      const newTotalEarned = currentTotalEarned + amount;

      // Bakiyeyi güncelle (upsert)
      if (balance) {
        await supabase
          .from("user_balances")
          .update({
            balance: newBalance,
            total_earned: newTotalEarned,
            updated_at: new Date().toISOString(),
          })
          .eq("user_id", userId);
      } else {
        await supabase
          .from("user_balances")
          .insert({
            user_id: userId,
            balance: amount,
            total_earned: amount,
          });
      }

      // İşlemi tamamlandı olarak işaretle
      const { data: updatedTxn, error: updateError } = await supabase
        .from("balance_transactions")
        .update({
          status: "completed",
          balance_before: currentBalance,
          balance_after: newBalance,
          metadata: {
            ...txn.metadata,
            confirmed_at: new Date().toISOString(),
            payment_result: { paymentId: paymentResult.paymentId, paidPrice: paymentResult.paidPrice },
          },
        })
        .eq("id", txn.id)
        .select()
        .single();

      if (updateError) {
        console.error("❌ balance_transactions update hatası:", updateError);
        throw new Error("İşlem tamamlanamadı");
      }

      console.log("✅ Bakiye yüklendi:", { userId, amount, newBalance });

      // ────────── Bildirimler (sadece başarılı bakiye yüklemede) ──────────
      // 1) Kullanıcıya push notification gönder
      try {
        const { data: profile } = await supabase
          .from("profiles")
          .select("full_name, fcm_token")
          .eq("id", userId)
          .single();

        if (profile?.fcm_token) {
          await supabase.functions.invoke("send-push-notification", {
            body: {
              fcm_token: profile.fcm_token,
              title: "Bakiye Yüklendi ✅",
              body: `${amount} TL bakiye hesabınıza yüklendi. Yeni bakiyeniz: ${newBalance.toFixed(2)} TL`,
              data: {
                type: "balance_topup_success",
                transaction_id: updatedTxn.id,
                amount: amount,
                new_balance: newBalance,
              },
            },
          });
          console.log("📤 Kullanıcıya push gönderildi");
        }
      } catch (pushErr) {
        console.error("⚠️ Kullanıcı push hatası (kritik değil):", pushErr);
      }

      // 2) Tüm admin'lere in-app bildirim gönder
      try {
        const { data: admins } = await supabase
          .from("profiles")
          .select("id")
          .eq("role", "admin");

        if (admins && admins.length > 0) {
          // Kullanıcı adını al
          const { data: userProfile } = await supabase
            .from("profiles")
            .select("full_name")
            .eq("id", userId)
            .single();

          const userName = userProfile?.full_name || "Kullanıcı";
          const adminNotifications = admins.map((admin: { id: string }) => ({
            user_id: admin.id,
            type: "admin_notification",
            title: "Bakiye Yüklendi 💰",
            content: `${userName} bakiye yükledi: ₺${amount.toFixed(2)}`,
            entity_id: updatedTxn.id,
          }));

          const { error: notifErr } = await supabase
            .from("notifications")
            .insert(adminNotifications);

          if (notifErr) {
            console.error("⚠️ Admin bildirim hatası:", notifErr);
          } else {
            console.log(`📤 ${admins.length} admin'e bildirim gönderildi`);
          }
        }
      } catch (notifErr) {
        console.error("⚠️ Admin bildirim hatası (kritik değil):", notifErr);
      }
      // ────────── Bildirimler Sonu ──────────

      // Başarılı sayfaya yönlendir
      return new Response(
        `<html><body><script>window.location.href="/balance-success?amount=${amount}";</script></body></html>`,
        { headers: { ...corsHeaders, "Content-Type": "text/html" } }
      );
    } else {
      // Ödeme başarısız
      const errorMsg = paymentResult.errorMessage || paymentResult.errorGroup || "Ödeme başarısız";

      await supabase
        .from("balance_transactions")
        .update({
          status: "failed",
          description: `Ödeme başarısız: ${errorMsg}`,
          metadata: { ...txn.metadata, failed_at: new Date().toISOString(), error: paymentResult },
        })
        .eq("id", txn.id);

      console.log("❌ Bakiye yükleme başarısız:", errorMsg);

      return new Response(
        `<html><body><script>window.location.href="/balance-failed?error=${encodeURIComponent(errorMsg)}";</script></body></html>`,
        { headers: { ...corsHeaders, "Content-Type": "text/html" } }
      );
    }
  } catch (err: unknown) {
    const error = err as Error;
    console.error("❌ confirm-balance-topup error:", error.message, error.stack);

    return new Response(
      `<html><body><script>window.location.href="/balance-failed?error=${encodeURIComponent(error.message)}";</script></body></html>`,
      { status: 500, headers: { ...corsHeaders, "Content-Type": "text/html" } }
    );
  }
});

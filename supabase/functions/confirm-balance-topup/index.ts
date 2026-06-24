// confirm-balance-topup Edge Function
// iyzico callback sonrası bakiyeyi günceller
// Bu fonksiyon iyzico tarafından callback olarak çağrılır
// Deploy: supabase functions deploy confirm-balance-topup

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.38.4";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

serve(async (req: Request) => {
  try {
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // iyzico callback body
    const body = await req.json();
    console.log("📥 Balance topup callback:", JSON.stringify(body));

    const { token, conversationId, status } = body;

    if (!token && !conversationId) {
      return new Response("Missing token or conversationId", { status: 400 });
    }

    // İşlemi bul
    let query = supabase
      .from("balance_transactions")
      .select("*")
      .eq("payment_reference", conversationId)
      .eq("type", "topup")
      .eq("status", "pending")
      .maybeSingle();

    const { data: transaction, error: findError } = await query;

    if (findError) {
      console.error("❌ Transaction bulunamadı:", findError);
      return new Response("Transaction not found", { status: 404 });
    }

    if (!transaction) {
      console.error("❌ Bekleyen işlem bulunamadı");
      return new Response("Pending transaction not found", { status: 404 });
    }

    // Ödeme başarılı mı?
    if (status === "success" || body.paymentStatus === "SUCCESS") {
      // İşlem zaten işlenmişse tekrar işleme
      if (transaction.status === "completed") {
        console.log("ℹ️ İşlem zaten işlenmiş, atlanıyor");
        return new Response("Already processed", { status: 200 });
      }

      const amount = parseFloat(transaction.amount);
      const userId = transaction.user_id;

      // Bakiyeyi güncelle
      const { data: balance, error: balanceError } = await supabase
        .from("user_balances")
        .select("balance")
        .eq("user_id", userId)
        .maybeSingle();

      if (balanceError) {
        console.error("❌ Bakiye getirme hatası:", balanceError);
        return new Response("Balance error", { status: 500 });
      }

      const currentBalance = balance?.balance || 0;
      const newBalance = currentBalance + amount;

      // Bakiyeyi güncelle
      if (balance) {
        await supabase
          .from("user_balances")
          .update({
            balance: newBalance,
            total_earned: supabase.sql`total_earned + ${amount}`,
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
      await supabase
        .from("balance_transactions")
        .update({
          status: "completed",
          balance_before: currentBalance,
          balance_after: newBalance,
          metadata: { ...transaction.metadata, confirmed_at: new Date().toISOString() },
        })
        .eq("id", transaction.id);

      console.log("✅ Bakiye yüklendi:", { userId, amount, newBalance });

      // Başarılı sayfaya yönlendir
      return new Response(
        `<html><body><script>window.location.href="/balance-success?amount=${amount}";</script></body></html>`,
        { headers: { "Content-Type": "text/html" } }
      );
    } else {
      // Ödeme başarısız
      await supabase
        .from("balance_transactions")
        .update({
          status: "failed",
          description: `Ödeme başarısız: ${body.errorMessage || "Bilinmeyen hata"}`,
          metadata: { ...transaction.metadata, failed_at: new Date().toISOString(), error: body },
        })
        .eq("id", transaction.id);

      console.log("❌ Bakiye yükleme başarısız:", body.errorMessage);

      return new Response(
        `<html><body><script>window.location.href="/balance-failed?error=${encodeURIComponent(body.errorMessage || "Ödeme başarısız")}";</script></body></html>`,
        { headers: { "Content-Type": "text/html" } }
      );
    }
  } catch (err: unknown) {
    const error = err as Error;
    console.error("❌ confirm-balance-topup error:", error.message);

    return new Response(`Error: ${error.message}`, { status: 500 });
  }
});

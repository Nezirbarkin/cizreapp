// use-balance-for-order Edge Function
// Tarih: 2026-09-02 (contract fix)
//
// GECMIS: 2026-08-02'de bu fonksiyon "server-authoritative session" modeline
// (private.commit_balance_order + { checkout_session_id }) gecirilmisti.
// Ancak canli uygulamanin ana sepet/checkout ekrani (checkout_screen.dart ->
// lib/core/services/balance_service.dart) hala ESKI sozlesmeyi kullaniyor:
// siparis client tarafinda once dogrudan INSERT edilir (payment_status=
// 'pending'), sonra bu fonksiyon { order_id, amount, order_total } ile
// cagrilip bakiyeden dusulmesi istenir. Session tabanli yeni sozlesme ile
// uyusmadigi icin HER bakiye siparisi "session_required" (400) donuyor,
// bakiye hic dusulmuyor ve siparis client tarafindan iptal ediliyor
// ("bakiye ile siparis olusturulamiyor" hatasi - 2026-09-02'de tespit edildi).
//
// Uygulama zaten yayinda oldugu icin (magaza guncellemesi gerektirmeden)
// ESKI sozlesme geri getirildi: { order_id }. Gercek dusum artik atomik
// public.use_balance_for_order(p_order_id) RPC'si tarafindan yapiliyor
// (siparis sahipligi + payment_method='balance' + idempotency kontrolu +
// deduct_from_balance ile tek transaction'da kilitleme/dusum/ledger kaydi).
// Client `amount`/`order_total` gonderse de guvenilmez; gercek tutar her
// zaman orders.total'dan (server'da zaten hesaplanmis) okunur.

// deno-lint-ignore-file no-explicit-any
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.38.4";

console.log("use-balance-for-order baslatildi");

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  if (req.method !== "POST") {
    return new Response(
      JSON.stringify({ ok: false, error: "method_not_allowed" }),
      { status: 405, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  try {
    // ═════════════════════════════════════════════════════════════
    // 0) Auth (user)
    // ═════════════════════════════════════════════════════════════
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({ ok: false, error: "auth_required" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const userSupabase = createClient(supabaseUrl, supabaseServiceKey, {
      global: { headers: { Authorization: authHeader } },
    });
    // KRITIK: getUser() token PARAMETRESIZ cagrilirsa (Deno edge ortaminda
    // kalici session/localStorage olmadigi icin) auth-js bazi surumlerde
    // agdan hic istek atmadan "Auth session missing!" ile basarisiz oluyor
    // -- ayni token'la /auth/v1/user'a dogrudan istek atmak calisiyordu,
    // bu da sorunu bu satira izole etti (2026-09-02). Diger tum fonksiyonlar
    // (iyzico-payment-init, admin-add-balance, vb.) token'i ACIKCA veriyor;
    // ayni desene uyduruldu.
    const jwt = authHeader.replace("Bearer ", "");
    const { data: { user }, error: userError } = await userSupabase.auth.getUser(jwt);
    if (userError || !user) {
      return new Response(
        JSON.stringify({ ok: false, error: "auth_invalid" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ═════════════════════════════════════════════════════════════
    // 1) Body parse — client'in gonderdigi eski sozlesme: { order_id }.
    //    `amount`/`order_total` alanlari kabul edilir ama GUVENILMEZ;
    //    gercek tutar RPC icinde orders.total'dan okunur.
    // ═════════════════════════════════════════════════════════════
    const body = await req.json().catch(() => ({}));
    const { order_id } = body as { order_id?: string };

    if (!order_id) {
      return new Response(
        JSON.stringify({ status: "error", error: "order_id_required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ═════════════════════════════════════════════════════════════
    // 2) use_balance_for_order — atomik dusum
    //
    // KRITIK: RPC KULLANICI baglaminda cagrilmali. Fonksiyon auth.uid()
    // okuyor; service-role baglaminda auth.uid() NULL doner ve fonksiyon
    // "Oturum acmaniz gerekiyor" ile patlar. userSupabase kullanicinin
    // JWT'sini tasidigi icin dogru baglam odur.
    // ═════════════════════════════════════════════════════════════
    const { data: result, error: rpcError } = await userSupabase.rpc(
      "use_balance_for_order",
      { p_order_id: order_id }
    );

    if (rpcError) {
      return new Response(
        JSON.stringify({ status: "error", error: rpcError.message }),
        {
          status: 409,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    const row = Array.isArray(result) ? result[0] : result;
    return new Response(
      JSON.stringify({
        status: "success",
        transaction_id: row?.transaction_id,
        amount_paid: row?.amount_paid,
        remaining_amount: row?.remaining_amount,
        new_balance: row?.new_balance,
        is_fully_paid: row?.is_fully_paid === true,
      }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (err: unknown) {
    const error = err as Error;
    console.error("use-balance-for-order beklenmeyen hata:", error.message);
    return new Response(
      JSON.stringify({ ok: false, error: "internal_error" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});

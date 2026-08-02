// use-balance-for-order Edge Function (SERVER-AUTHORITATIVE)
// Tarih: 2026-08-02
//
// Bu fonksiyon client sadece { checkout_session_id } gonderir. Tum
// hesaplamalar (subtotal, delivery, coupon, total, bakiye yeterliligi)
// private.commit_balance_order RPC'si tarafindan YAPILIR.
//
// Client asla amount göndermez. Fiyat/ucret yetersizse RPC EXCEPTION firlatir.

// deno-lint-ignore-file no-explicit-any
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.38.4";

console.log("use-balance-for-order (server-authoritative) baslatildi");

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
    const { data: { user }, error: userError } = await userSupabase.auth.getUser();
    if (userError || !user) {
      return new Response(
        JSON.stringify({ ok: false, error: "auth_invalid" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ═════════════════════════════════════════════════════════════
    // 1) Body parse
    // ═════════════════════════════════════════════════════════════
    const body = await req.json().catch(() => ({}));
    const { checkout_session_id } = body as { checkout_session_id?: string };

    if (!checkout_session_id) {
      return new Response(
        JSON.stringify({ ok: false, error: "session_required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ═════════════════════════════════════════════════════════════
    // 2) Session sahiplik kontrolu
    // ═════════════════════════════════════════════════════════════
    const supabase = createClient(supabaseUrl, supabaseServiceKey);
    const { data: session, error: sessionError } = await supabase
      .from("server_checkout_sessions")
      .select("id, user_id, status, expires_at, payment_method, server_total")
      .eq("id", checkout_session_id)
      .eq("user_id", user.id)
      .maybeSingle();

    if (sessionError || !session) {
      return new Response(
        JSON.stringify({ ok: false, error: "session_not_found" }),
        { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (session.payment_method !== "balance") {
      return new Response(
        JSON.stringify({ ok: false, error: "wrong_payment_method" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (session.status === "completed" || session.status === "expired") {
      return new Response(
        JSON.stringify({ ok: false, error: `session_${session.status}` }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // ═════════════════════════════════════════════════════════════
    // 3) commit_balance_order — server-authoritative atomik
    // ═════════════════════════════════════════════════════════════
    const { data: result, error: rpcError } = await supabase.rpc(
      "private.commit_balance_order",
      { p_session_id: session.id }
    );

    if (rpcError) {
      const errorCode = rpcError.code === "P0001" ? "app_error" : "commit_failed";
      return new Response(
        JSON.stringify({ ok: false, error: errorCode, message: rpcError.message }),
        {
          status: 409,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    const row = Array.isArray(result) ? result[0] : result;
    return new Response(
      JSON.stringify({
        ok: true,
        order_id: row?.order_id,
        order_number: row?.order_number,
        amount_paid: row?.amount_paid,
        remaining_balance: row?.remaining_balance,
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

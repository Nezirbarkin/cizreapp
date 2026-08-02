// =====================================================
// DEPRECATED + FAIL-CLOSED
// =====================================================
// Bu Edge Function güvenlik nedenleriyle devre dışı bırakıldı. Artık
// kullanılmıyor. Supabase Auth'un yerleşik recovery OTP sistemi kullanılıyor
// (Supabase.instance.client.auth.resetPasswordForEmail + verifyOTP).
//
// Bu fonksiyona gelen tüm isteklere 410 Gone ile cevap verilir. service-role
// ile şifre değiştiren eski kod canlıda çalıştırılmamalıdır.
//
// Canlı Supabase projesinden bu fonksiyonun deploy'unu kaldırmak için:
//   supabase functions delete send-password-reset-otp
// =====================================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

serve((_req: Request) => {
  return new Response(
    JSON.stringify({
      error: "Gone",
      message:
        "send-password-reset-otp devre dışı. Supabase Auth yerleşik " +
        "recovery OTP sistemini kullanın (auth.resetPasswordForEmail + " +
        "auth.verifyOTP OtpType.recovery).",
    }),
    {
      status: 410,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    },
  );
});

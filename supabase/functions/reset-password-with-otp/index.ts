// =====================================================
// DEPRECATED + FAIL-CLOSED
// =====================================================
// Bu Edge Function güvenlik nedenleriyle devre dışı bırakıldı. service-role
// anahtarı ile kullanıcının şifresini doğrudan değiştiriyordu; tek kullanımlık
// recovery token veya session doğrulaması yapmıyordu, used=true kaydını
// 10 dakika boyunca yeniden oynatabiliyordu.
//
// Şifre sıfırlama artık Supabase Auth'un yerleşik recovery akışı üzerinden
// yapılıyor:
//   1) Supabase.instance.client.auth.resetPasswordForEmail(email)
//   2) Supabase.instance.client.auth.verifyOTP(type: OtpType.recovery)
//   3) Supabase.instance.client.auth.updateUser(UserAttributes(password: ...))
//
// Bu fonksiyona gelen tüm isteklere 410 Gone ile cevap verilir. service-role
// ile şifre değiştiren eski kod canlıda çalıştırılmamalıdır.
//
// Canlı Supabase projesinden bu fonksiyonun deploy'unu kaldırmak için:
//   supabase functions delete reset-password-with-otp
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
        "reset-password-with-otp devre dışı. Supabase Auth yerleşik " +
        "recovery OTP sistemini kullanın (auth.verifyOTP OtpType.recovery " +
        "sonrası auth.updateUser).",
    }),
    {
      status: 410,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    },
  );
});

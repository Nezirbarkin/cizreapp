// =====================================================
// SUPABASE EDGE FUNCTION - OTP ile Şifre Güncelle
// =====================================================
// OTP doğrulandıktan sonra kullanıcının şifresini günceller
// Deploy: supabase functions deploy reset-password-with-otp
// =====================================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.38.4";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

interface ResetPasswordRequest {
  email: string;
  new_password: string;
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  try {
    const body: ResetPasswordRequest = await req.json();
    const { email, new_password } = body;

    if (!email || !new_password) {
      return new Response(
        JSON.stringify({
          status: "error",
          error: "E-posta ve yeni şifre gerekli",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    if (new_password.length < 6) {
      return new Response(
        JSON.stringify({
          status: "error",
          error: "Şifre en az 6 karakter olmalı",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    const normalizedEmail = email.toLowerCase().trim();
    console.log(`🔐 Password reset request for: ${normalizedEmail}`);

    // Service role key ile Supabase client oluştur
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // Kullanıcıyı bul (profiles tablosundan)
    const { data: profile, error: profileError } = await supabase
      .from("profiles")
      .select("id")
      .eq("email", normalizedEmail)
      .maybeSingle();

    if (profileError || !profile) {
      console.error("User not found:", profileError);
      return new Response(
        JSON.stringify({
          status: "error",
          error: "Kullanıcı bulunamadı",
        }),
        {
          status: 404,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // OTP kullanıldı mı kontrol et
    const { data: otpData } = await supabase
      .from("password_reset_otps")
      .select("*")
      .eq("email", normalizedEmail)
      .eq("used", true)
      .order("used_at", { ascending: false })
      .limit(1);

    if (!otpData || otpData.length === 0) {
      return new Response(
        JSON.stringify({
          status: "error",
          error: "Lütfen önce doğrulama kodunu girin",
        }),
        {
          status: 403,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // Son OTP kullanımı 10 dakikadan daha eski mi? (güvenlik için)
    const lastOtpUsedAt = new Date(otpData[0].used_at);
    const tenMinutesAgo = new Date(Date.now() - 10 * 60 * 1000);
    
    if (lastOtpUsedAt < tenMinutesAgo) {
      return new Response(
        JSON.stringify({
          status: "error",
          error: "Doğrulama kodu süresi doldu. Lütfen yeni kod isteyin",
        }),
        {
          status: 403,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // Şifreyi güncelle (Admin API ile)
    const { error: updateError } = await supabase.auth.admin.updateUserById(
      profile.id,
      { password: new_password }
    );

    if (updateError) {
      console.error("Password update error:", updateError);
      throw new Error("Şifre güncellenemedi");
    }

    // Kullanılan OTP'yi temizle
    await supabase
      .from("password_reset_otps")
      .delete()
      .eq("email", normalizedEmail);

    console.log(`✅ Password updated for: ${normalizedEmail}`);

    return new Response(
      JSON.stringify({
        status: "success",
        message: "Şifreniz başarıyla güncellendi",
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  } catch (err: unknown) {
    const error = err as Error;
    console.error("❌ Password reset error:", error.message);

    return new Response(
      JSON.stringify({
        status: "error",
        error: error.message || "Şifre güncellenemedi",
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }
});

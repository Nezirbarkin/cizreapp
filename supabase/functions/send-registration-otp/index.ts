// =====================================================
// SUPABASE EDGE FUNCTION - Kayıt Doğrulama OTP Gönder
// =====================================================
// Gmail link prefetching sorununu çözmek için OTP kodu gönderir
// Deploy: supabase functions deploy send-registration-otp
// =====================================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.38.4";
import { Resend } from "npm:resend@2.0.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const resendApiKey = Deno.env.get("RESEND_API_KEY");
const appName = Deno.env.get("APP_NAME") || "CizreApp";

interface SendOtpRequest {
  email: string;
  locale?: string;
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
    const body: SendOtpRequest = await req.json();
    const { email, locale = "tr" } = body;

    if (!email) {
      return new Response(
        JSON.stringify({ status: "error", error: "E-posta adresi gerekli" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    const normalizedEmail = email.toLowerCase().trim();
    console.log(`📧 Registration OTP request for: ${normalizedEmail}`);

    // Service role key ile Supabase client oluştur
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // Rate limiting: Son 1 dakika içinde kod gönderilmiş mi?
    const { data: recentCodes } = await supabase
      .from("registration_otps")
      .select("id, created_at")
      .eq("email", normalizedEmail)
      .gt("created_at", new Date(Date.now() - 60000).toISOString())
      .order("created_at", { ascending: false })
      .limit(1);

    if (recentCodes && recentCodes.length > 0) {
      return new Response(
        JSON.stringify({
          status: "error",
          error: "Lütfen 1 dakika bekleyin ve tekrar deneyin",
        }),
        {
          status: 429,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // 6 haneli kod oluştur
    const code = Math.floor(100000 + Math.random() * 900000).toString();
    const expiresAt = new Date(Date.now() + 5 * 60 * 1000); // 5 dakika geçerli

    // Eski kullanılmamış kodları temizle
    await supabase
      .from("registration_otps")
      .delete()
      .eq("email", normalizedEmail)
      .eq("verified", false);

    // Yeni kodu kaydet
    const { error: insertError } = await supabase
      .from("registration_otps")
      .insert({
        email: normalizedEmail,
        code: code,
        expires_at: expiresAt.toISOString(),
      });

    if (insertError) {
      console.error("OTP insert error:", insertError);
      throw new Error("Kod oluşturulamadı");
    }

    // E-posta gönder
    if (resendApiKey) {
      const resend = new Resend(resendApiKey);
      
      const htmlContent = `
        <!DOCTYPE html>
        <html>
        <head>
          <style>
            body { font-family: Arial, sans-serif; background-color: #f5f5f5; padding: 20px; margin: 0; }
            .container { background: white; max-width: 600px; margin: 0 auto; padding: 30px; border-radius: 10px; }
            .header { text-align: center; padding-bottom: 20px; border-bottom: 2px solid #4CAF50; }
            .header h1 { color: #4CAF50; margin: 0; font-size: 24px; }
            .code-box { background: linear-gradient(135deg, #4CAF50, #45a049); padding: 30px; border-radius: 10px; text-align: center; margin: 30px 0; }
            .code { font-size: 42px; font-weight: bold; color: white; letter-spacing: 8px; }
            .content { padding: 20px 0; color: #333; line-height: 1.6; }
            .footer { text-align: center; color: #888; font-size: 12px; margin-top: 20px; padding-top: 20px; border-top: 1px solid #eee; }
            .warning { background: #fff3cd; padding: 15px; border-radius: 5px; margin: 20px 0; border-left: 4px solid #ffc107; }
          </style>
        </head>
        <body>
          <div class="container">
            <div class="header">
              <h1>📧 E-Posta Doğrulama</h1>
            </div>
            <div class="content">
              <p>Merhaba,</p>
              <p>${appName} hesabınızı doğrulamak için aşağıdaki kodu kullanın:</p>
              
              <div class="code-box">
                <div class="code">${code}</div>
              </div>
              
              <p>Bu kod <strong>5 dakika</strong> boyunca geçerlidir.</p>
              
              <div class="warning">
                <strong>⚠️ Önemli:</strong> Bu kodu kimseyle paylaşmayın. Eğer bu isteği siz yapmadıysanız, bu e-postayı yok sayabilirsiniz.
              </div>
            </div>
            <div class="footer">
              <p>Bu e-posta otomatik olarak gönderilmiştir. Lütfen yanıtlamayınız.</p>
              <p>© ${new Date().getFullYear()} ${appName}</p>
            </div>
          </div>
        </body>
        </html>
      `;

      const result = await resend.emails.send({
        from: `${appName} <noreply@cizreapp.com>`,
        to: [normalizedEmail],
        subject: `${appName} - E-Posta Doğrulama Kodu: ${code}`,
        html: htmlContent,
      });

      console.log("✅ Registration OTP email sent:", result);
    } else {
      console.warn("⚠️ RESEND_API_KEY not set, skipping email send");
    }

    return new Response(
      JSON.stringify({
        status: "success",
        verification_id: crypto.randomUUID(),
        expires_in_seconds: 300,
        message: "Doğrulama kodu e-posta adresinize gönderildi",
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  } catch (err: unknown) {
    const error = err as Error;
    console.error("❌ Registration OTP error:", error.message);

    return new Response(
      JSON.stringify({
        status: "error",
        error: error.message || "Doğrulama kodu gönderilemedi",
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }
});

# 📤 Supabase Edge Function'ları Manuel Deploy

## Fonksiyon 1: send-registration-otp

**Supabase Dashboard'da:**
1. **Edge Functions** sekmesine tıklayın
2. **Create a new function** butonuna tıklayın
3. **Function name:** `send-registration-otp`
4. Aşağıdaki kodu yapıştırın:

```typescript
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.38.4";
import { Resend } from "npm:resend@2.0.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

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
    const body = await req.json();
    const { email } = body;

    if (!email) {
      return new Response(
        JSON.stringify({ status: "error", error: "E-posta adresi gerekli" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const normalizedEmail = email.toLowerCase().trim();
    console.log(`📧 Registration OTP request for: ${normalizedEmail}`);

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // Rate limiting
    const { data: recentCodes } = await supabase
      .from("registration_otps")
      .select("id")
      .eq("email", normalizedEmail)
      .gt("created_at", new Date(Date.now() - 60000).toISOString())
      .limit(1);

    if (recentCodes && recentCodes.length > 0) {
      return new Response(
        JSON.stringify({ status: "error", error: "Lütfen 1 dakika bekleyin" }),
        { status: 429, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // 6 haneli kod oluştur
    const code = Math.floor(100000 + Math.random() * 900000).toString();
    const expiresAt = new Date(Date.now() + 5 * 60 * 1000);

    // Eski kodları temizle
    await supabase.from("registration_otps").delete().eq("email", normalizedEmail).eq("verified", false);

    // Yeni kodu kaydet
    const { error: insertError } = await supabase.from("registration_otps").insert({
      email: normalizedEmail,
      code: code,
      expires_at: expiresAt.toISOString(),
    });

    if (insertError) throw new Error("Kod oluşturulamadı");

    // E-posta gönder
    const resendApiKey = Deno.env.get("RESEND_API_KEY");
    if (resendApiKey) {
      const resend = new Resend(resendApiKey);
      
      await resend.emails.send({
        from: "CizreApp <noreply@cizreapp.com>",
        to: [normalizedEmail],
        subject: `CizreApp - E-Posta Doğrulama Kodu: ${code}`,
        html: `
          <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 30px;">
            <h2 style="color: #4CAF50; text-align: center;">📧 E-Posta Doğrulama</h2>
            <p style="text-align: center;">Hesabınızı doğrulamak için aşağıdaki kodu kullanın:</p>
            <div style="background: linear-gradient(135deg, #4CAF50, #45a049); padding: 30px; border-radius: 10px; text-align: center; margin: 30px 0;">
              <span style="font-size: 42px; font-weight: bold; color: white; letter-spacing: 8px;">${code}</span>
            </div>
            <p style="text-align: center;">Bu kod <strong>5 dakika</strong> boyunca geçerlidir.</p>
            <p style="text-align: center; color: #888; font-size: 12px;">Bu kodu kimseyle paylaşmayın.</p>
          </div>
        `,
      });
      console.log("✅ Registration OTP email sent");
    }

    return new Response(
      JSON.stringify({
        status: "success",
        verification_id: crypto.randomUUID(),
        expires_in_seconds: 300,
        message: "Doğrulama kodu e-posta adresinize gönderildi",
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (err: unknown) {
    const error = err as Error;
    console.error("❌ Error:", error.message);
    return new Response(
      JSON.stringify({ status: "error", error: error.message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
```

5. **Deploy Function** butonuna tıklayın

---

## Fonksiyon 2: send-password-reset-otp

Aynı şekilde **Create a new function** ile:

**Function name:** `send-password-reset-otp`

```typescript
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.38.4";
import { Resend } from "npm:resend@2.0.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

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
    const body = await req.json();
    const { email } = body;

    if (!email) {
      return new Response(
        JSON.stringify({ status: "error", error: "E-posta adresi gerekli" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const normalizedEmail = email.toLowerCase().trim();
    console.log(`🔑 Password reset OTP request for: ${normalizedEmail}`);

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // Kullanıcı var mı kontrol et
    const { data: user } = await supabase.auth.admin.getUserByEmail(normalizedEmail);
    
    if (!user) {
      // Güvenlik için başarılı gibi döndür
      return new Response(
        JSON.stringify({
          status: "success",
          verification_id: crypto.randomUUID(),
          expires_in_seconds: 300,
          message: "Eğer bu e-posta kayıtlıysa kod gönderildi",
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Rate limiting
    const { data: recentCodes } = await supabase
      .from("password_reset_otps")
      .select("id")
      .eq("email", normalizedEmail)
      .gt("created_at", new Date(Date.now() - 60000).toISOString())
      .limit(1);

    if (recentCodes && recentCodes.length > 0) {
      return new Response(
        JSON.stringify({ status: "error", error: "Lütfen 1 dakika bekleyin" }),
        { status: 429, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // 6 haneli kod oluştur
    const code = Math.floor(100000 + Math.random() * 900000).toString();
    const expiresAt = new Date(Date.now() + 5 * 60 * 1000);

    // Eski kodları temizle
    await supabase.from("password_reset_otps").delete().eq("email", normalizedEmail).eq("used", false);

    // Yeni kodu kaydet
    const { error: insertError } = await supabase.from("password_reset_otps").insert({
      email: normalizedEmail,
      code: code,
      expires_at: expiresAt.toISOString(),
    });

    if (insertError) throw new Error("Kod oluşturulamadı");

    // E-posta gönder
    const resendApiKey = Deno.env.get("RESEND_API_KEY");
    if (resendApiKey) {
      const resend = new Resend(resendApiKey);
      
      await resend.emails.send({
        from: "CizreApp <noreply@cizreapp.com>",
        to: [normalizedEmail],
        subject: `CizreApp - Şifre Sıfırlama Kodu: ${code}`,
        html: `
          <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 30px;">
            <h2 style="color: #FF5722; text-align: center;">🔒 Şifre Sıfırlama</h2>
            <p style="text-align: center;">Şifrenizi sıfırlamak için aşağıdaki kodu kullanın:</p>
            <div style="background: linear-gradient(135deg, #FF5722, #E64A19); padding: 30px; border-radius: 10px; text-align: center; margin: 30px 0;">
              <span style="font-size: 42px; font-weight: bold; color: white; letter-spacing: 8px;">${code}</span>
            </div>
            <p style="text-align: center;">Bu kod <strong>5 dakika</strong> boyunca geçerlidir.</p>
            <p style="text-align: center; color: #888; font-size: 12px;">Bu kodu kimseyle paylaşmayın.</p>
          </div>
        `,
      });
      console.log("✅ Password reset OTP email sent");
    }

    return new Response(
      JSON.stringify({
        status: "success",
        verification_id: crypto.randomUUID(),
        expires_in_seconds: 300,
        message: "Şifre sıfırlama kodu gönderildi",
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (err: unknown) {
    const error = err as Error;
    console.error("❌ Error:", error.message);
    return new Response(
      JSON.stringify({ status: "error", error: error.message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
```

---

## Fonksiyon 3: reset-password-with-otp

**Function name:** `reset-password-with-otp`

```typescript
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.38.4";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

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
    const body = await req.json();
    const { email, new_password } = body;

    if (!email || !new_password) {
      return new Response(
        JSON.stringify({ status: "error", error: "E-posta ve yeni şifre gerekli" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (new_password.length < 6) {
      return new Response(
        JSON.stringify({ status: "error", error: "Şifre en az 6 karakter olmalı" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const normalizedEmail = email.toLowerCase().trim();

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // Kullanıcıyı bul
    const { data: userData, error: userError } = await supabase.auth.admin.getUserByEmail(normalizedEmail);

    if (userError || !userData.user) {
      return new Response(
        JSON.stringify({ status: "error", error: "Kullanıcı bulunamadı" }),
        { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } }
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
        JSON.stringify({ status: "error", error: "Lütfen önce doğrulama kodunu girin" }),
        { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Son OTP kullanımı 10 dakikadan daha eski mi?
    const lastOtpUsedAt = new Date(otpData[0].used_at);
    const tenMinutesAgo = new Date(Date.now() - 10 * 60 * 1000);
    
    if (lastOtpUsedAt < tenMinutesAgo) {
      return new Response(
        JSON.stringify({ status: "error", error: "Kod süresi doldu. Yeni kod isteyin" }),
        { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Şifreyi güncelle
    const { error: updateError } = await supabase.auth.admin.updateUserById(
      userData.user.id,
      { password: new_password }
    );

    if (updateError) throw new Error("Şifre güncellenemedi");

    // Kullanılan OTP'yi temizle
    await supabase.from("password_reset_otps").delete().eq("email", normalizedEmail);

    console.log(`✅ Password updated for: ${normalizedEmail}`);

    return new Response(
      JSON.stringify({ status: "success", message: "Şifreniz güncellendi" }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (err: unknown) {
    const error = err as Error;
    console.error("❌ Error:", error.message);
    return new Response(
      JSON.stringify({ status: "error", error: error.message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
```

---

## ✅ Tamamlandıktan Sonra

3 fonksiyon da deploy edildikten sonra:

1. **SQL Migration** çalıştırın (önceki rehberdeki gibi)
2. **Authentication > Providers > Email > Confirm email** DISABLE yapın
3. Flutter'ı build edin ve test edin

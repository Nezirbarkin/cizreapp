// =====================================================
// SUPABASE EDGE FUNCTION - Push ile Onay Kodu Gönder
// =====================================================
// Sipariş onayı için email ile doğrulama kodu gönderir
// Deploy: supabase functions deploy send-verification-code
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
const APP_NAME = Deno.env.get("APP_NAME") || "CizreApp";

interface SendCodeRequest {
  code_type?: string;
  user_id?: string;
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
    // Body'den user_id al (authorization header'a dokunma)
    const body: SendCodeRequest = await req.json();
    const userId = body.user_id;

    console.log(`🔐 Request received - user_id: ${userId}, body: ${JSON.stringify(body)}`);

    // Service role key ile Supabase client oluştur (auth kontrolü atla)
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    if (!userId) {
      console.error("❌ user_id eksik");
      return new Response(
        JSON.stringify({
          status: "error",
          error: "Kullanıcı ID'si gerekli"
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    console.log(`🔐 Verification code request for user: ${userId}`);

    const codeType = body.code_type || "order_confirmation";

    // Son 1 dakika içinde kod gönderilmi�� mi kontrol et (spam önleme)
    const { data: recentCodes } = await supabase
      .from("verification_codes")
      .select("id, created_at")
      .eq("user_id", userId)
      .eq("code_type", codeType)
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

    // Kodu veritabanına kaydet (5 dakika geçerli)
    const { data: verificationData, error: insertError } = await supabase
      .from("verification_codes")
      .insert({
        user_id: userId,
        code: code,
        code_type: codeType,
        expires_at: new Date(Date.now() + 5 * 60 * 1000).toISOString(),
      })
      .select("id")
      .single();

    if (insertError) {
      console.error("Verification code insert error:", insertError);
      throw new Error("Kod oluşturulamadı");
    }

    // Push notification ile kodu gönder (KOD BAŞTA)
    await supabase
      .from("notifications")
      .insert({
        user_id: userId,
        type: "verification_code",
        title: code,  // KOD BAŞLIKTA - EN BELİRGİN YERDE
        content: "Sipariş onay kodunuz. Bu kodu siparişinizi onaylamak için kullanın.",
      });

    console.log(`✅ Verification code sent via push to ${userId}: ${code}`);

    return new Response(
      JSON.stringify({
        status: "success",
        message: "Onay kodu bildirim olarak gönderildi",
        verification_id: verificationData.id,
        expires_in_seconds: 300,
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  } catch (err: unknown) {
    const error = err as Error;
    console.error("❌ Verification code error:", error.message);

    return new Response(
      JSON.stringify({
        status: "error",
        error: error.message || "Onay kodu gönderilemedi",
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }
});

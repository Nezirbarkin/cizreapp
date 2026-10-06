// live-token Edge Function (Görev 3.4 — satıcı canlı yayını)
//
// Agora RTC erişim anahtarı üretir. App Certificate YALNIZ burada (Supabase
// secret) durur; istemciye App ID + 1 saatlik, tek kanala ve tek uid'e bağlı
// anahtar döner. Satıcı (uid 1) yayınlar; izleyici yalnız izler.
//
// Yetki kararı SQL'de: public.live_token_grant(session, role, user) — yalnız
// service_role çalıştırabilir (canlı SQL testi:
// supabase/tests/manual/live_stream_completion_test.sql). Misafir (oturumsuz)
// yalnız canlı yayını izleyebilir.
//
// Kurulum (bir kez):
//   1) console.agora.io → proje oluştur → "Secured mode: APP ID + Token".
//   2) supabase secrets set AGORA_APP_ID=<app id> AGORA_APP_CERTIFICATE=<primary certificate>
//   Ayarlar yoksa fonksiyon {ok:false, error:"LIVE_NOT_CONFIGURED"} döner.
//
// Deploy: supabase functions deploy live-token

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { getAdminClient } from "../_shared/client.ts";
import { json, safeErrorCode } from "../_shared/http.ts";
import { handleLiveTokenRequest, type LiveTokenGrant, type LiveTokenRole } from "../_shared/live_token.ts";

// Isolate başına kaba hız sınırı (dakikada 30 anahtar / kullanıcı ya da IP):
// meşru kullanım (katıl + saatlik yenileme + birkaç yeniden bağlanma) etkilenmez.
const RATE_WINDOW_MS = 60_000;
const RATE_MAX = 30;
const hits = new Map<string, number[]>();

function rateLimited(key: string): boolean {
  const now = Date.now();
  const recent = (hits.get(key) ?? []).filter((t) => now - t < RATE_WINDOW_MS);
  if (recent.length >= RATE_MAX) {
    hits.set(key, recent);
    return true;
  }
  recent.push(now);
  hits.set(key, recent);
  if (hits.size > 2000) {
    for (const [k, v] of hits) {
      if (v.every((t) => now - t >= RATE_WINDOW_MS)) hits.delete(k);
    }
  }
  return false;
}

serve(async (req: Request) => {
  try {
    const admin = getAdminClient();
    return await handleLiveTokenRequest(req, {
      appId: Deno.env.get("AGORA_APP_ID"),
      appCertificate: Deno.env.get("AGORA_APP_CERTIFICATE"),
      userIdFromJwt: async (jwt) => {
        // Anon anahtarı ya da süresi geçmiş JWT → hata → misafir.
        const { data, error } = await admin.auth.getUser(jwt);
        return error ? null : data.user?.id ?? null;
      },
      grant: async (sessionId: string, role: LiveTokenRole, userId: string | null) => {
        const { data, error } = await admin.rpc("live_token_grant", {
          p_session_id: sessionId,
          p_role: role,
          p_user_id: userId,
        });
        if (error) throw new Error("GRANT_FAILED");
        return data as LiveTokenGrant;
      },
      rateLimited,
    });
  } catch (err) {
    console.error("live-token error:", err);
    return json({ ok: false, error: safeErrorCode(err) }, 500);
  }
});

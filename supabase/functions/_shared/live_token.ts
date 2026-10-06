// `live-token` Edge Function'ının istek mantığı (Görev 3.4).
//
// Ağ/Supabase bağımlılıkları dışarıdan verilir (LiveTokenDeps) — böylece
// mantık Node'da ağsız test edilir (live_token_test.ts).
//
// Akış: gövde doğrulanır → Agora ayarları var mı → çağıran kullanıcı (JWT;
// misafirde anon anahtarı → kullanıcı yok) → yetki kararı SQL'de
// (public.live_token_grant, yalnız service_role) → anahtar imzalanır.
// Beklenen retler 200 + {ok:false, error} döner (istemci mesajı doğrudan
// gösterir); yalnız beklenmeyen hatalar 500'dür.

import { buildRtcToken } from "./agora_token.ts";
import { json, options } from "./http.ts";

/** Anahtar ömrü; istemci bitişe ~30 sn kala yenisini ister. */
export const LIVE_TOKEN_TTL_SECONDS = 3600;

export type LiveTokenRole = "host" | "viewer";

export interface LiveTokenGrant {
  ok: boolean;
  error?: string;
  channel?: string;
  host_uid?: number;
}

export interface LiveTokenDeps {
  appId: string | undefined;
  appCertificate: string | undefined;
  /** JWT'nin sahibi; anon anahtarı ya da geçersiz/süresi geçmiş JWT → null. */
  userIdFromJwt: (jwt: string) => Promise<string | null>;
  grant: (sessionId: string, role: LiveTokenRole, userId: string | null) => Promise<LiveTokenGrant>;
  /** İzleyiciye verilecek rastgele Agora uid'i. */
  randomViewerUid?: () => number;
  /** Kaba hız sınırı anahtarı başına: true → reddet. */
  rateLimited?: (key: string) => boolean;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const HEX32 = /^[0-9a-fA-F]{32}$/;

/** Satıcının uid'i 1; izleyiciler 100000..2^31-1 aralığından (çakışma ihmal edilir). */
export function randomViewerUid(): number {
  const buf = new Uint32Array(1);
  crypto.getRandomValues(buf);
  return 100000 + (buf[0] % (0x7fffffff - 100000));
}

function bearer(req: Request): string | null {
  const match = /^Bearer\s+(.+)$/i.exec(req.headers.get("authorization") ?? "");
  return match?.[1]?.trim() || null;
}

export async function handleLiveTokenRequest(req: Request, deps: LiveTokenDeps): Promise<Response> {
  if (req.method === "OPTIONS") return options("POST, OPTIONS");
  if (req.method !== "POST") {
    return json({ ok: false, error: "METHOD_NOT_ALLOWED" }, 405, { Allow: "POST, OPTIONS" });
  }

  const appId = deps.appId?.trim() ?? "";
  const appCertificate = deps.appCertificate?.trim() ?? "";
  // Sertifikasız ("test modu") Agora projesinde App ID'yi bilen herkes her
  // kanala yayıncı olarak girebilir → canlıda kabul edilmez.
  if (!HEX32.test(appId) || !HEX32.test(appCertificate)) {
    return json({ ok: false, error: "LIVE_NOT_CONFIGURED" });
  }

  const body = await req.json().catch(() => null) as Record<string, unknown> | null;
  const sessionId = typeof body?.session_id === "string" ? body.session_id : "";
  const role = body?.role === "host" || body?.role === "viewer" ? body.role as LiveTokenRole : null;
  if (!UUID.test(sessionId) || role === null) {
    return json({ ok: false, error: "BAD_REQUEST" }, 400);
  }

  const jwt = bearer(req);
  const userId = jwt ? await deps.userIdFromJwt(jwt) : null;

  const limiterKey = userId ?? `ip:${req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ?? "?"}`;
  if (deps.rateLimited?.(limiterKey)) {
    return json({ ok: false, error: "RATE_LIMITED" }, 429);
  }

  const grant = await deps.grant(sessionId, role, userId);
  if (!grant.ok || !grant.channel) {
    return json({ ok: false, error: grant.error ?? "FORBIDDEN" });
  }

  const hostUid = grant.host_uid ?? 1;
  const uid = role === "host" ? hostUid : (deps.randomViewerUid ?? randomViewerUid)();
  const token = await buildRtcToken({
    appId,
    appCertificate,
    channelName: grant.channel,
    uid,
    role: role === "host" ? "publisher" : "subscriber",
    tokenExpireSeconds: LIVE_TOKEN_TTL_SECONDS,
  });

  return json({
    ok: true,
    app_id: appId,
    channel: grant.channel,
    uid,
    host_uid: hostUid,
    role,
    token,
    expires_in: LIVE_TOKEN_TTL_SECONDS,
  });
}

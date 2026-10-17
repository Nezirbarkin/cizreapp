// live-replay-cleanup Edge Function — canlı yayın kayıtlarının temizliği.
//
// Saatlik pg_cron (live-replay-cleanup-hourly, göç 20261016000040) çağırır;
// x-cron-secret başlığı CRON_SECRET ile eşleşmeli. Süresi dolan/silinen
// kayıtların dosyaları Storage API'siyle silinir (karar SQL'de:
// public.live_replay_cleanup_batch). Mantık ve testler: _shared/live_replay_cleanup.ts.
//
// Deploy: supabase functions deploy live-replay-cleanup --no-verify-jwt

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { getAdminClient } from "../_shared/client.ts";
import { json, options, safeErrorCode } from "../_shared/http.ts";
import {
  isCronAuthorized,
  LIVE_REPLAY_BUCKET,
  parseCleanupBatch,
  runLiveReplayCleanup,
} from "../_shared/live_replay_cleanup.ts";

serve(async (req: Request) => {
  if (req.method === "OPTIONS") return options();
  if (!isCronAuthorized(req.headers.get("x-cron-secret"), Deno.env.get("CRON_SECRET"))) {
    return json({ ok: false, error: "UNAUTHORIZED" }, 401);
  }

  try {
    const admin = getAdminClient();
    const result = await runLiveReplayCleanup({
      batch: async (limit) => {
        const { data, error } = await admin.rpc("live_replay_cleanup_batch", { p_limit: limit });
        if (error) {
          console.error("live_replay_cleanup_batch:", error.message);
          throw new Error("CLEANUP_BATCH_FAILED");
        }
        return parseCleanupBatch(data);
      },
      remove: async (paths) => {
        const { data, error } = await admin.storage.from(LIVE_REPLAY_BUCKET).remove(paths);
        if (error) {
          console.error("live-replays remove:", error.message);
          return [];
        }
        return (data ?? []).map((o: { name: string }) => o.name);
      },
    });
    if (result.removed > 0 || result.expired > 0 || result.failed > 0) {
      console.log("live-replay-cleanup:", JSON.stringify(result));
    }
    return json({ ok: true, ...result });
  } catch (e) {
    return json({ ok: false, error: safeErrorCode(e) }, 500);
  }
});

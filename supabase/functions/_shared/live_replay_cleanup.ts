// Canlı yayın kayıtlarının (live-replays kovası) temizliği — saatlik cron.
//
// Karar SQL'de: public.live_replay_cleanup_batch(limit) süresi dolan kayıtları
// 'deleted' yapar, yükleme penceresi kapananları sonlandırır ve silinecek
// nesne yollarını döndürür (silinmiş kaydın dosyaları, sahipsiz/biçim dışı
// dosyalar, parçalara işlenmemiş artıklar). Dosyalar SQL'den silinemez
// (storage.protect_objects_delete); burada Storage API'siyle silinir.
//
// Silinemeyen yol bir sonraki turda yine gelir: aynı çalıştırmada ikinci kez
// denenmez (sonsuz döngü olmasın), bir sonraki saatte yeniden denenir.

import { timingSafeEqual } from "./crypto.ts";

export const LIVE_REPLAY_BUCKET = "live-replays";

export interface LiveReplayCleanupBatch {
  paths: string[];
  expired: number;
  finalized: number;
}

export interface LiveReplayCleanupDeps {
  batch: (limit: number) => Promise<LiveReplayCleanupBatch>;
  /** Silinen yolları döndürür; hata olursa boş liste. */
  remove: (paths: string[]) => Promise<string[]>;
  batchSize?: number;
  maxRounds?: number;
  removeChunk?: number;
}

export interface LiveReplayCleanupResult {
  rounds: number;
  removed: number;
  failed: number;
  expired: number;
  finalized: number;
}

export function isCronAuthorized(given: string | null, expected: string | undefined): boolean {
  const secret = expected?.trim();
  if (!secret || !given) return false;
  return timingSafeEqual(given.trim(), secret);
}

export function parseCleanupBatch(data: unknown): LiveReplayCleanupBatch {
  const row = (data && typeof data === "object" ? data : {}) as Record<string, unknown>;
  const paths = Array.isArray(row.paths)
    ? row.paths.filter((p): p is string => typeof p === "string" && p.length > 0)
    : [];
  return {
    paths,
    expired: Number(row.expired) || 0,
    finalized: Number(row.finalized) || 0,
  };
}

export async function runLiveReplayCleanup(deps: LiveReplayCleanupDeps): Promise<LiveReplayCleanupResult> {
  const batchSize = deps.batchSize ?? 200;
  const maxRounds = deps.maxRounds ?? 10;
  const chunkSize = deps.removeChunk ?? 100;
  const tried = new Set<string>();
  const result: LiveReplayCleanupResult = { rounds: 0, removed: 0, failed: 0, expired: 0, finalized: 0 };

  for (let round = 0; round < maxRounds; round++) {
    const batch = await deps.batch(batchSize);
    result.rounds++;
    result.expired += batch.expired;
    result.finalized += batch.finalized;

    const fresh = batch.paths.filter((p) => !tried.has(p));
    if (fresh.length === 0) break;
    for (const p of fresh) tried.add(p);

    for (let i = 0; i < fresh.length; i += chunkSize) {
      const chunk = fresh.slice(i, i + chunkSize);
      const removed = new Set(await deps.remove(chunk));
      const ok = chunk.filter((p) => removed.has(p)).length;
      result.removed += ok;
      result.failed += chunk.length - ok;
    }
    // Sayfa dolmadıysa silinecek başka nesne yok.
    if (batch.paths.length < batchSize) break;
  }
  return result;
}

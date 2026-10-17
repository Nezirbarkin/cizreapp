// deno test _shared/live_replay_cleanup_test.ts
//
// `live-replay-cleanup` Edge Function mantığı — ağsız (sahte SQL turu ve sahte
// Storage silme). `node:assert` hem Deno'da hem Node'da çalışır.

import assert from "node:assert/strict";
import {
  isCronAuthorized,
  type LiveReplayCleanupBatch,
  parseCleanupBatch,
  runLiveReplayCleanup,
} from "./live_replay_cleanup.ts";

const path = (i: number) => `0b6f5a3e-8d0c-4c55-9a55-2f3e1c0a7b11/part-${String(i).padStart(4, "0")}.mp4`;

/** Depo + SQL turu taklidi: silinmeyen yol sonraki turda yine gelir. */
function fakeStore(count: number, opts: { failing?: Set<string>; expired?: number } = {}) {
  const objects = new Set(Array.from({ length: count }, (_, i) => path(i + 1)));
  const removeCalls: string[][] = [];
  let firstBatch = true;
  return {
    objects,
    removeCalls,
    batch: (limit: number): Promise<LiveReplayCleanupBatch> => {
      const paths = [...objects].slice(0, limit);
      const expired = firstBatch ? opts.expired ?? 0 : 0;
      firstBatch = false;
      return Promise.resolve({ paths, expired, finalized: 0 });
    },
    remove: (paths: string[]): Promise<string[]> => {
      removeCalls.push(paths);
      const removed = paths.filter((p) => !opts.failing?.has(p));
      for (const p of removed) objects.delete(p);
      return Promise.resolve(removed);
    },
  };
}

Deno.test("hepsini sayfa sayfa siler, 100'lük parçalarla", async () => {
  const store = fakeStore(250, { expired: 3 });
  const result = await runLiveReplayCleanup({ batch: store.batch, remove: store.remove, batchSize: 200 });
  assert.equal(store.objects.size, 0);
  assert.equal(result.removed, 250);
  assert.equal(result.failed, 0);
  assert.equal(result.expired, 3);
  assert.deepEqual(store.removeCalls.map((c) => c.length), [100, 100, 50]);
  assert.equal(result.rounds, 2);
});

Deno.test("silinemeyen yol aynı çalıştırmada yeniden denenmez", async () => {
  const failing = new Set([path(2)]);
  const store = fakeStore(3, { failing });
  const result = await runLiveReplayCleanup({ batch: store.batch, remove: store.remove, batchSize: 2 });
  assert.equal(result.removed, 2);
  assert.equal(result.failed, 1);
  assert.deepEqual([...store.objects], [path(2)]);
  const attempts = store.removeCalls.flat().filter((p) => p === path(2)).length;
  assert.equal(attempts, 1);
});

Deno.test("boş tur hemen biter; tur sınırı aşılmaz", async () => {
  const empty = fakeStore(0);
  const none = await runLiveReplayCleanup({ batch: empty.batch, remove: empty.remove });
  assert.deepEqual(none, { rounds: 1, removed: 0, failed: 0, expired: 0, finalized: 0 });

  const big = fakeStore(50);
  const capped = await runLiveReplayCleanup({ batch: big.batch, remove: big.remove, batchSize: 10, maxRounds: 2 });
  assert.equal(capped.rounds, 2);
  assert.equal(capped.removed, 20);
  assert.equal(big.objects.size, 30);
});

Deno.test("SQL yanıtı ayrıştırılır; bozuk alanlar yok sayılır", () => {
  assert.deepEqual(parseCleanupBatch({ paths: ["a/part-0001.mp4", 3, "", null], expired: "2", finalized: 1 }), {
    paths: ["a/part-0001.mp4"],
    expired: 2,
    finalized: 1,
  });
  assert.deepEqual(parseCleanupBatch(null), { paths: [], expired: 0, finalized: 0 });
});

Deno.test("cron sırrı: boş/eksik/yanlış reddedilir", () => {
  assert.equal(isCronAuthorized("s3cret", "s3cret"), true);
  assert.equal(isCronAuthorized(" s3cret ", "s3cret\n"), true);
  assert.equal(isCronAuthorized("yanlis", "s3cret"), false);
  assert.equal(isCronAuthorized(null, "s3cret"), false);
  assert.equal(isCronAuthorized("s3cret", undefined), false);
  assert.equal(isCronAuthorized("", ""), false);
});

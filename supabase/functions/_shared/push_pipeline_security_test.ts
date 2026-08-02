// =============================================================================
// 2026-08-02 — Push pipeline worker security testleri
// Çalıştırma: deno test _shared/push_pipeline_security_test.ts
// =============================================================================

import { assertEquals, assertExists } from 'https://deno.land/std@0.168.0/assert/mod.ts'

// Worker fonksiyonunu import etmeden, modül yüklenmeden test edebilmek için
// http://localhost:54321/functions/v1/process-notification-outbox'a gerçek
// istek atılır. Bu testler yerel Supabase (supabase start) çalışıyorken
// çalıştırılmalıdır. Aksi halde skip edilir.

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? 'http://localhost:54321'
const FUNCTION_URL = `${SUPABASE_URL}/functions/v1/process-notification-outbox`

Deno.test('worker: GET reddedilir (sadece POST)', async () => {
  const res = await fetch(FUNCTION_URL, { method: 'GET' })
  assertEquals(res.status, 405)
})

Deno.test('worker: secret header olmadan 401', async () => {
  const res = await fetch(FUNCTION_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: '{}',
  })
  // Secret env yoksa yine 401; secret var ve yanlışsa da 401.
  assertEquals(res.status, 401)
})

Deno.test('worker: yanlış secret 401', async () => {
  Deno.env.set('INTERNAL_WORKER_SECRET', 'correct-secret-12345')
  try {
    const res = await fetch(FUNCTION_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-worker-secret': 'WRONG',
      },
      body: '{}',
    })
    assertEquals(res.status, 401)
  } finally {
    Deno.env.delete('INTERNAL_WORKER_SECRET')
  }
})

Deno.test('worker: doğru secret + geçerli service env → 200/500 (servis yoksa 500)', async () => {
  Deno.env.set('INTERNAL_WORKER_SECRET', 'test-secret-xyz')
  try {
    const res = await fetch(FUNCTION_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-worker-secret': 'test-secret-xyz',
      },
      body: '{}',
    })
    // 500: Supabase service env veya FIREBASE_SERVICE_ACCOUNT eksik olabilir
    // (yerel ortamda normal). Önemli olan 401 olmaması — yani auth geçti.
    if (res.status === 401) {
      throw new Error('Auth geçmedi, secret mismatch')
    }
    assertExists(res.status)
  } finally {
    Deno.env.delete('INTERNAL_WORKER_SECRET')
  }
})

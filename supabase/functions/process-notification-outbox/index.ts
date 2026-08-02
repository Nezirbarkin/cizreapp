// =====================================================
// SUPABASE EDGE FUNCTION — Push notification outbox worker
// =====================================================
// 2026-08-02 push pipeline refaktörü.
//
// Bu worker:
//   - Service role ile public.notification_outbox'tan kayıt claim eder
//     (FOR UPDATE SKIP LOCKED; eşzamanlı worker güvenliği).
//   - Server tarafında notifications + kullanıcı FCM token'ını okur.
//   - FCM HTTP v1 API ile push gönderir.
//   - Başarıda sent, geçici hatada failed (exponential backoff), kalıcı
//     hatada dead yapar.
//   - UNREGISTERED/NOT_FOUND token'ları temizler.
//   - FCM token'ı, service account, OAuth header, kullanıcı notification
//     data değerlerini LOGLMAZ.
//
// Auth: Kullanıcı JWT'si yok. Secret header (INTERNAL_WORKER_SECRET)
// veya Authorization: Bearer <secret> zorunlu. CORS yok; istemci
// çağırmaz.
// =====================================================

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const FIREBASE_SCOPES = ['https://www.googleapis.com/auth/firebase.messaging']

interface OutboxRow {
  outbox_id: string
  notification_id: string
  user_id: string
  type: string
  title: string
  content: string
  entity_id: string | null
  notification_metadata: Record<string, unknown> | null
  attempt_number: number
}

interface ClaimResult extends OutboxRow {}

// -------- Access token cache (sadece process içinde) --------
let cachedAccessToken: string | null = null
let tokenExpiry = 0

// -------- Authorization: yalnızca internal secret --------

function checkAuth(req: Request): boolean {
  const expected = Deno.env.get('INTERNAL_WORKER_SECRET') ?? ''
  if (!expected) {
    // Secret ayarlanmamışsa her şeyi reddet; uydurma değer kullanma.
    return false
  }
  const headerSecret = req.headers.get('x-worker-secret') ?? ''
  const authHeader = req.headers.get('authorization') ?? ''
  const bearer = authHeader.toLowerCase().startsWith('bearer ')
    ? authHeader.slice(7).trim()
    : ''
  // Constant-time karşılaştırma
  return constantTimeEqual(headerSecret, expected) ||
    constantTimeEqual(bearer, expected)
}

function constantTimeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false
  let result = 0
  for (let i = 0; i < a.length; i++) {
    result |= a.charCodeAt(i) ^ b.charCodeAt(i)
  }
  return result === 0
}

// -------- Firebase OAuth2 access token --------

async function getAccessToken(serviceAccount: any): Promise<string> {
  if (cachedAccessToken && Date.now() < tokenExpiry) {
    return cachedAccessToken
  }

  const now = Math.floor(Date.now() / 1000)
  const header = { alg: 'RS256', typ: 'JWT' }
  const payload = {
    iss: serviceAccount.client_email,
    scope: FIREBASE_SCOPES.join(' '),
    aud: 'https://oauth2.googleapis.com/token',
    exp: now + 3600,
    iat: now,
  }

  const base64UrlEncode = (obj: unknown) =>
    btoa(JSON.stringify(obj))
      .replace(/\+/g, '-')
      .replace(/\//g, '_')
      .replace(/=/g, '')

  const encodedHeader = base64UrlEncode(header)
  const encodedPayload = base64UrlEncode(payload)
  const signatureInput = `${encodedHeader}.${encodedPayload}`

  const privateKeyPem = serviceAccount.private_key.replace(/\\n/g, '\n')
  const b64 = privateKeyPem
    .replace(/-----BEGIN PRIVATE KEY-----/g, '')
    .replace(/-----END PRIVATE KEY-----/g, '')
    .replace(/\s/g, '')
  const binary = atob(b64)
  const bytes = new Uint8Array(binary.length)
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i)
  }

  const cryptoKey = await crypto.subtle.importKey(
    'pkcs8',
    bytes.buffer,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  )
  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    cryptoKey,
    new TextEncoder().encode(signatureInput),
  )
  const encodedSignature = btoa(
    String.fromCharCode(...new Uint8Array(signature)),
  )
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=/g, '')

  const jwt = `${signatureInput}.${encodedSignature}`

  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  })
  if (!response.ok) {
    const error = await response.text()
    throw new Error(`Failed to get access token: ${error}`)
  }
  const data = await response.json()
  cachedAccessToken = data.access_token
  tokenExpiry = Date.now() + (data.expires_in - 300) * 1000
  return cachedAccessToken
}

// -------- FCM HTTP v1 push --------

interface FcmResult {
  success: boolean
  unregistered: boolean
  error?: string
}

async function sendFcm(
  accessToken: string,
  projectId: string,
  token: string,
  title: string,
  body: string,
  data: Record<string, string>,
): Promise<FcmResult> {
  const url = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`
  const message = {
    notification: { title, body },
    data,
    android: {
      priority: 'high' as const,
      notification: {
        sound: 'default' as const,
        channel_id: 'high_importance_channel' as const,
      },
    },
    apns: {
      payload: {
        aps: {
          sound: 'default' as const,
          badge: 1,
        },
      },
    },
  }

  const response = await fetch(url, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ message, token }),
  })

  if (!response.ok) {
    const errorText = await response.text()
    const unregistered = errorText.includes('UNREGISTERED') ||
      errorText.includes('NOT_FOUND') ||
      errorText.includes('INVALID_ARGUMENT')
    return { success: false, unregistered, error: errorText }
  }
  return { success: true, unregistered: false }
}

// -------- Server-side token fetch + cleanup --------

async function getUserTokens(
  supabase: any,
  userId: string,
): Promise<string[]> {
  // profiles.fcm_token + notification_tokens'tan oku. Yalnızca service_role.
  const tokens = new Set<string>()
  const { data: profile } = await supabase
    .from('profiles')
    .select('fcm_token')
    .eq('id', userId)
    .maybeSingle()
  if (profile?.fcm_token) tokens.add(profile.fcm_token)

  const { data: notifTokens } = await supabase
    .from('notification_tokens')
    .select('token')
    .eq('user_id', userId)
  for (const t of notifTokens ?? []) {
    if (t?.token) tokens.add(t.token)
  }
  return [...tokens]
}

async function cleanupInvalidToken(supabase: any, token: string) {
  // profiles.fcm_token'ı temizle
  await supabase
    .from('profiles')
    .update({ fcm_token: null })
    .eq('fcm_token', token)
  // notification_tokens'tan sil
  await supabase
    .from('notification_tokens')
    .delete()
    .eq('token', token)
}

// -------- Main worker --------

const WORKER_ID = `worker-${crypto.randomUUID()}`
const MAX_ATTEMPTS = 8
const CLAIM_LIMIT = 25

serve(async (req: Request) => {
  if (req.method !== 'POST') {
    return new Response(
      JSON.stringify({ error: 'Method not allowed' }),
      { status: 405, headers: { 'Content-Type': 'application/json' } },
    )
  }

  if (!checkAuth(req)) {
    return new Response(
      JSON.stringify({ error: 'Unauthorized' }),
      { status: 401, headers: { 'Content-Type': 'application/json' } },
    )
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL')
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  if (!supabaseUrl || !serviceKey) {
    return new Response(
      JSON.stringify({ error: 'Service not configured' }),
      { status: 500, headers: { 'Content-Type': 'application/json' } },
    )
  }
  const firebaseJson = Deno.env.get('FIREBASE_SERVICE_ACCOUNT')
  if (!firebaseJson) {
    return new Response(
      JSON.stringify({ error: 'FIREBASE_SERVICE_ACCOUNT secret missing' }),
      { status: 500, headers: { 'Content-Type': 'application/json' } },
    )
  }

  const supabase = createClient(supabaseUrl, serviceKey)
  const serviceAccount = JSON.parse(firebaseJson)
  const projectId = serviceAccount.project_id

  try {
    // 1) Eski processing kayıtlarını serbest bırak
    await supabase.rpc('release_stale_outbox', {
      p_max_age: '5 minutes',
    })

    // 2) Outbox'tan atomik claim
    const { data: rows, error: claimError } = await supabase.rpc(
      'claim_notification_outbox',
      { p_limit: CLAIM_LIMIT, p_worker_id: WORKER_ID },
    )

    if (claimError) {
      return new Response(
        JSON.stringify({ error: 'Claim failed' }),
        { status: 500, headers: { 'Content-Type': 'application/json' } },
      )
    }

    const claims = (rows ?? []) as ClaimResult[]
    if (claims.length === 0) {
      return new Response(
        JSON.stringify({ processed: 0 }),
        { status: 200, headers: { 'Content-Type': 'application/json' } },
      )
    }

    const accessToken = await getAccessToken(serviceAccount)
    let sent = 0
    let failed = 0
    let dead = 0
    let unregisteredCleaned = 0

    for (const row of claims) {
      // Token'ları al
      const tokens = await getUserTokens(supabase, row.user_id)
      if (tokens.length === 0) {
        // Kullanıcının token'ı yok → sent olarak işaretle
        // (outbox'a alındı; teslim adresi yok; tekrar denenmenin anlamı yok)
        await supabase.rpc('mark_outbox_sent', { p_outbox_id: row.outbox_id })
        sent++
        continue
      }

      const data: Record<string, string> = {
        notification_id: row.notification_id,
        type: row.type,
        entity_id: row.entity_id ?? '',
      }
      // metadata varsa data'ya düzleştir (string-only FCM data)
      const meta = row.notification_metadata
      if (meta && typeof meta === 'object') {
        for (const [k, v] of Object.entries(meta)) {
          if (typeof v === 'string' || typeof v === 'number' || typeof v === 'boolean') {
            data[`meta_${k}`] = String(v)
          }
        }
      }

      let anySuccess = false
      let allUnregistered = true
      let lastError: string | null = null
      let cleanedAny = false

      for (const token of tokens) {
        try {
          const result = await sendFcm(
            accessToken,
            projectId,
            token,
            row.title,
            row.content,
            data,
          )
          if (result.success) {
            anySuccess = true
            allUnregistered = false
          } else {
            lastError = result.error ?? 'unknown FCM error'
            if (result.unregistered) {
              await cleanupInvalidToken(supabase, token)
              cleanedAny = true
              unregisteredCleaned++
            } else {
              allUnregistered = false
            }
          }
        } catch (err) {
          lastError = err instanceof Error ? err.message : 'fetch failed'
          allUnregistered = false
        }
      }

      if (anySuccess) {
        await supabase.rpc('mark_outbox_sent', { p_outbox_id: row.outbox_id })
        sent++
      } else if (allUnregistered) {
        // Tüm token'lar unregistered; kullanıcıya artık ulaşılamaz.
        // Sent olarak işaretle (başarısız değil; teslim adresi yok).
        await supabase.rpc('mark_outbox_sent', { p_outbox_id: row.outbox_id })
        sent++
      } else {
        const { data: failedRow } = await supabase.rpc('mark_outbox_failed', {
          p_outbox_id: row.outbox_id,
          p_error: lastError ?? 'unknown',
          p_max_attempts: MAX_ATTEMPTS,
        })
        // dead olup olmadığını anlamak için tekrar oku
        const { data: status } = await supabase
          .from('notification_outbox')
          .select('status')
          .eq('id', row.outbox_id)
          .maybeSingle()
        if (status?.status === 'dead') dead++
        else failed++
      }

      // Hassas içerik loglanmaz; yalnızca uuid ve status.
      console.log(
        `outbox=${row.outbox_id} status=processed attempts=${row.attempt_number}`,
      )
      if (cleanedAny) {
        // Token loglanmaz.
        console.log(`outbox=${row.outbox_id} cleaned_invalid_token=true`)
      }
    }

    return new Response(
      JSON.stringify({
        processed: claims.length,
        sent,
        failed,
        dead,
        unregistered_cleaned: unregisteredCleaned,
      }),
      { status: 200, headers: { 'Content-Type': 'application/json' } },
    )
  } catch (error) {
    const msg = error instanceof Error ? error.message : 'unknown error'
    // Service account/credential içeriksiz generic mesaj
    console.error(`worker_error: ${msg.slice(0, 200)}`)
    return new Response(
      JSON.stringify({ error: 'Worker error' }),
      { status: 500, headers: { 'Content-Type': 'application/json' } },
    )
  }
})

// =====================================================
// SUPABASE EDGE FUNCTION - Firebase FCM HTTP v1 API
// =====================================================
//
// Firebase Cloud Messaging HTTP v1 API ile push notification gönderir
//
// KULLANIM:
// curl -X POST https://xsbukxkgtmdyickknqzf.supabase.co/functions/v1/send-push \
//   -H "Authorization: Bearer YOUR_SERVICE_ROLE_KEY" \
//   -H "Content-Type: application/json" \
//   -d '{"user_id": "uuid", "title": "Test", "body": "Mesaj"}'
//
// =====================================================

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// Firebase OAuth2 scopes
const FIREBASE_SCOPES = ['https://www.googleapis.com/auth/firebase.messaging']

// Cache access token (5 dakika geçerli)
let cachedAccessToken: string | null = null
let tokenExpiry: number = 0

interface SendPushRequest {
  user_id: string
  title: string
  body: string
  data?: Record<string, string>
}

// Firebase OAuth2 Access Token al
async function getAccessToken(serviceAccount: any): Promise<string> {
  // Cache kontrolü
  if (cachedAccessToken && Date.now() < tokenExpiry) {
    console.log('✅ Using cached access token')
    return cachedAccessToken
  }

  console.log('🔄 Getting new Firebase access token...')

  // JWT oluştur
  const header = {
    alg: 'RS256',
    typ: 'JWT',
  }

  const now = Math.floor(Date.now() / 1000)
  const payload = {
    iss: serviceAccount.client_email,
    scope: FIREBASE_SCOPES.join(' '),
    aud: 'https://oauth2.googleapis.com/token',
    exp: now + 3600,
    iat: now,
  }

  // JWT base64url encode
  const base64UrlEncode = (obj: any) => {
    return btoa(JSON.stringify(obj))
      .replace(/\+/g, '-')
      .replace(/\//g, '_')
      .replace(/=/g, '')
  }

  const encodedHeader = base64UrlEncode(header)
  const encodedPayload = base64UrlEncode(payload)
  const signatureInput = `${encodedHeader}.${encodedPayload}`

  // RSA imzala (private key ile)
  const privateKey = serviceAccount.private_key.replace(/\\n/g, '\n')
  
  // PEM'i ArrayBuffer'a çevir (TextEncoder kullanmak ASN.1 DER hatası verir!)
  const pemToBuffer = (pem: string): ArrayBuffer => {
    const b64 = pem
      .replace(/-----BEGIN PRIVATE KEY-----/g, '')
      .replace(/-----END PRIVATE KEY-----/g, '')
      .replace(/\s/g, '')
    const binary = atob(b64)
    const bytes = new Uint8Array(binary.length)
    for (let i = 0; i < binary.length; i++) {
      bytes[i] = binary.charCodeAt(i)
    }
    return bytes.buffer
  }
  
  const cryptoKey = await crypto.subtle.importKey(
    'pkcs8',
    pemToBuffer(privateKey),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign']
  )

  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    cryptoKey,
    new TextEncoder().encode(signatureInput)
  )

  const encodedSignature = btoa(String.fromCharCode(...new Uint8Array(signature)))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=/g, '')

  const jwt = `${signatureInput}.${encodedSignature}`

  // OAuth2 token isteği
  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
    },
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
  tokenExpiry = Date.now() + (data.expires_in - 300) * 1000 // 5 dakika önce expire

  console.log('✅ Access token obtained')
  return cachedAccessToken
}

// Kullanıcının FCM token'ını al
async function getFCMTokens(supabase: any, userId: string): Promise<string[]> {
  const { data: profile } = await supabase
    .from('profiles')
    .select('fcm_token')
    .eq('id', userId)
    .single()

  const tokens: string[] = []

  if (profile?.fcm_token) {
    tokens.push(profile.fcm_token)
  }

  // notification_tokens tablosundan da al
  const { data: notificationTokens } = await supabase
    .from('notification_tokens')
    .select('token')
    .eq('user_id', userId)

  if (notificationTokens) {
    tokens.push(...notificationTokens.map((t: any) => t.token))
  }

  return [...new Set(tokens)] // Duplicate'ları kaldır
}

// FCM HTTP v1 API ile push gönder
async function sendFCMPush(
  accessToken: string,
  projectId: string,
  token: string,
  title: string,
  body: string,
  data: Record<string, string>
): Promise<{ success: boolean; error?: string; shouldDeleteToken?: boolean }> {
  const url = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`

  const message = {
    message: {
      token,
      notification: {
        title,
        body,
      },
      data,
    },
  }

  const response = await fetch(url, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(message),
  })

  if (!response.ok) {
    const errorText = await response.text()
    console.error(`❌ FCM error for token ${token.substring(0, 20)}...: ${errorText}`)
    
    // Hata detayını kontrol et - UNREGISTERED token'ları sil
    let shouldDelete = false
    try {
      const errorData = JSON.parse(errorText)
      if (errorData.error?.code === 404 ||
          errorData.error?.details?.[0]?.errorCode === 'UNREGISTERED') {
        shouldDelete = true
        console.log(`🗑️ Token is UNREGISTERED, should be deleted: ${token.substring(0, 20)}...`)
      }
    } catch (e) {
      // JSON parse hatası - detay alınamadı
    }
    
    return { success: false, error: errorText, shouldDeleteToken: shouldDelete }
  }

  console.log(`✅ Push sent to ${token.substring(0, 20)}...`)
  return { success: true }
}

// Geçersiz token'ı veritabanından sil
async function deleteInvalidToken(supabase: any, token: string): Promise<void> {
  try {
    // profiles.fcm_token'dan sil
    await supabase
      .from('profiles')
      .update({ fcm_token: null })
      .eq('fcm_token', token)
    
    // notification_tokens tablosundan sil
    await supabase
      .from('notification_tokens')
      .delete()
      .eq('token', token)
    
    console.log(`🗑️ Deleted invalid token from database: ${token.substring(0, 20)}...`)
  } catch (e) {
    console.error(`❌ Error deleting token: ${e}`)
  }
}

serve(async (req) => {
  try {
    // CORS headers
    if (req.method === 'OPTIONS') {
      return new Response('ok', { headers: { 'Access-Control-Allow-Origin': '*' } })
    }

    // Sadece POST
    if (req.method !== 'POST') {
      return new Response(JSON.stringify({ error: 'Method not allowed' }), {
        status: 405,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    // Request body
    const { user_id, title, body, data = {} }: SendPushRequest = await req.json()

    if (!user_id || !title || !body) {
      return new Response(JSON.stringify({ error: 'Missing required fields' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    console.log(`📤 Sending push to user ${user_id}: ${title}`)

    // Supabase client
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const supabase = createClient(supabaseUrl, supabaseServiceKey)

    // Firebase service account
    const { data: vaultData } = await supabase
      .from('vault')
      .select('decrypted_secrets')
      .eq('name', 'firebase_service_account')
      .single()

    // Vault erişimi yoksa, alternatif: Environment variable
    const firebaseServiceAccountJson = Deno.env.get('FIREBASE_SERVICE_ACCOUNT')

    if (!firebaseServiceAccountJson) {
      return new Response(
        JSON.stringify({
          error: 'Firebase service account not found',
          hint: 'Add FIREBASE_SERVICE_ACCOUNT to Edge Function secrets',
        }),
        {
          status: 500,
          headers: { 'Content-Type': 'application/json' },
        }
      )
    }

    const serviceAccount = JSON.parse(firebaseServiceAccountJson)
    const projectId = serviceAccount.project_id

    console.log(`🔥 Firebase project: ${projectId}`)

    // Access token al
    const accessToken = await getAccessToken(serviceAccount)

    // FCM token'ları al
    const tokens = await getFCMTokens(supabase, user_id)

    if (tokens.length === 0) {
      return new Response(
        JSON.stringify({
          success: false,
          error: 'No FCM tokens found for user',
          user_id,
        }),
        {
          status: 404,
          headers: { 'Content-Type': 'application/json' },
        }
      )
    }

    console.log(`📱 Found ${tokens.length} FCM tokens`)

    // Her token için push gönder
    let successCount = 0
    let errorCount = 0
    let deletedCount = 0

    for (const token of tokens) {
      const result = await sendFCMPush(accessToken, projectId, token, title, body, data)
      if (result.success) {
        successCount++
      } else {
        errorCount++
        
        // UNREGISTERED token'ı temizle
        if (result.shouldDeleteToken) {
          await deleteInvalidToken(supabase, token)
          deletedCount++
        }
      }
    }

    return new Response(
      JSON.stringify({
        success: true,
        sent_count: successCount,
        error_count: errorCount,
        deleted_count: deletedCount,
        message: `Push notification sent to ${successCount} device(s)${deletedCount > 0 ? `, ${deletedCount} invalid token(s) cleaned` : ''}`,
      }),
      {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      }
    )
  } catch (error) {
    console.error('❌ Edge function error:', error)
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
        headers: { 'Content-Type': 'application/json' },
    })
  }
})

// =====================================================
// KURULUM ADIMLARI:
// =====================================================
// 1. Firebase Service Account JSON'unu alın (Firebase Console → Project Settings → Service Accounts)
// 2. Supabase Dashboard → Edge Functions → Secrets
// 3. Yeni secret ekleyin:
//    Name: FIREBASE_SERVICE_ACCOUNT
//    Value: {Firebase service account JSON}
// 4. Edge Function'ı deploy edin:
//    supabase functions deploy send-push
// 5. SQL fonksiyonunu güncelleyin (bkz. FIREBASE_PUSH_EDGE_FUNCTION.sql)
// =====================================================

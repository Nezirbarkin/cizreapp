// =====================================================
// SUPABASE EDGE FUNCTION - Firebase FCM HTTP v1 API
// =====================================================
// Fixed RSA key import for Deno
// =====================================================

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const FIREBASE_SCOPES = ['https://www.googleapis.com/auth/firebase.messaging']

let cachedAccessToken: string | null = null
let tokenExpiry: number = 0

interface SendPushRequest {
  user_id: string
  title: string
  body: string
  data?: Record<string, string>
}

// PEM to ArrayBuffer conversion (fixes ASN.1 DER error)
function pemToArrayBuffer(pem: string): ArrayBuffer {
  // Remove PEM headers and newlines
  const b64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/g, '')
    .replace(/-----END PRIVATE KEY-----/g, '')
    .replace(/\s/g, '')
  
  // Base64 decode
  const binary = atob(b64)
  const bytes = new Uint8Array(binary.length)
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i)
  }
  return bytes.buffer
}

// Base64 URL encode
function base64UrlEncode(data: string | ArrayBuffer): string {
  let b64: string
  if (typeof data === 'string') {
    b64 = btoa(data)
  } else {
    const bytes = new Uint8Array(data)
    let binary = ''
    for (let i = 0; i < bytes.length; i++) {
      binary += String.fromCharCode(bytes[i])
    }
    b64 = btoa(binary)
  }
  return b64.replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '')
}

// Firebase OAuth2 Access Token al
async function getAccessToken(serviceAccount: any): Promise<string> {
  if (cachedAccessToken && Date.now() < tokenExpiry) {
    console.log('✅ Using cached access token')
    return cachedAccessToken!
  }

  console.log('🔄 Getting new Firebase access token...')

  const now = Math.floor(Date.now() / 1000)
  
  // JWT Header
  const header = JSON.stringify({ alg: 'RS256', typ: 'JWT' })
  
  // JWT Payload
  const payload = JSON.stringify({
    iss: serviceAccount.client_email,
    scope: FIREBASE_SCOPES.join(' '),
    aud: 'https://oauth2.googleapis.com/token',
    exp: now + 3600,
    iat: now,
  })

  const encodedHeader = base64UrlEncode(header)
  const encodedPayload = base64UrlEncode(payload)
  const signatureInput = `${encodedHeader}.${encodedPayload}`

  // Private key'i düzgün şekilde import et
  // \n escape'lerini gerçek newline'a çevir
  let privateKeyPem = serviceAccount.private_key
  if (privateKeyPem.includes('\\n')) {
    privateKeyPem = privateKeyPem.replace(/\\n/g, '\n')
  }

  console.log('🔑 Importing RSA private key...')
  
  // PEM'i ArrayBuffer'a çevir (CRITICAL FIX)
  const keyBuffer = pemToArrayBuffer(privateKeyPem)
  
  const cryptoKey = await crypto.subtle.importKey(
    'pkcs8',
    keyBuffer,  // ArrayBuffer kullan, TextEncoder değil!
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign']
  )

  console.log('✅ RSA key imported successfully')

  // İmzala
  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    cryptoKey,
    new TextEncoder().encode(signatureInput)
  )

  const encodedSignature = base64UrlEncode(signature)
  const jwt = `${signatureInput}.${encodedSignature}`

  // OAuth2 token isteği
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

  console.log('✅ Access token obtained successfully')
  return cachedAccessToken!
}

// FCM token'ları al
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
  return [...new Set(tokens)]
}

// FCM push gönder
async function sendFCMPush(
  accessToken: string,
  projectId: string,
  token: string,
  title: string,
  body: string,
  data: Record<string, string>
): Promise<{ success: boolean; error?: string; unregistered?: boolean }> {
  const url = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`

  const response = await fetch(url, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      message: {
        token,
        notification: { title, body },
        data,
        android: {
          priority: 'high',
          notification: {
            sound: 'default',
            channel_id: 'high_importance_channel',
          },
        },
        apns: {
          payload: {
            aps: {
              sound: 'default',
              badge: 1,
            },
          },
        },
      },
    }),
  })

  if (!response.ok) {
    const error = await response.text()
    console.error(`❌ FCM error for token ${token.substring(0, 20)}...: ${error}`)
    
    // UNREGISTERED hatası - token artık geçersiz
    const isUnregistered = error.includes('UNREGISTERED') || error.includes('NOT_FOUND')
    if (isUnregistered) {
      console.log(`🗑️ Token UNREGISTERED, silinecek: ${token.substring(0, 20)}...`)
    }
    
    return { success: false, error, unregistered: isUnregistered }
  }

  const result = await response.json()
  console.log(`✅ Push sent to ${token.substring(0, 20)}... Result:`, result)
  return { success: true }
}

// Geçersiz FCM token'ı veritabanından sil
async function removeInvalidToken(supabase: any, token: string): Promise<void> {
  try {
    // profiles tablosundan fcm_token'ı temizle
    const { error } = await supabase
      .from('profiles')
      .update({ fcm_token: null })
      .eq('fcm_token', token)
    
    if (error) {
      console.error(`❌ Token silme hatası: ${error.message}`)
    } else {
      console.log(`✅ Geçersiz token veritabanından silindi: ${token.substring(0, 20)}...`)
    }
  } catch (e: any) {
    console.error(`❌ Token silme exception: ${e.message}`)
  }
}

serve(async (req) => {
  try {
    if (req.method === 'OPTIONS') {
      return new Response('ok', {
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
        },
      })
    }

    if (req.method !== 'POST') {
      return new Response(JSON.stringify({ error: 'Method not allowed' }), {
        status: 405,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    const { user_id, title, body, data = {} }: SendPushRequest = await req.json()

    if (!user_id || !title || !body) {
      return new Response(JSON.stringify({ error: 'Missing required fields: user_id, title, body' }), {
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
    const firebaseJson = Deno.env.get('FIREBASE_SERVICE_ACCOUNT')
    if (!firebaseJson) {
      return new Response(
        JSON.stringify({ error: 'FIREBASE_SERVICE_ACCOUNT secret not found' }),
        { status: 500, headers: { 'Content-Type': 'application/json' } }
      )
    }

    const serviceAccount = JSON.parse(firebaseJson)
    console.log(`🔥 Firebase project: ${serviceAccount.project_id}`)

    // Access token al
    const accessToken = await getAccessToken(serviceAccount)

    // FCM token'ları al
    const tokens = await getFCMTokens(supabase, user_id)

    if (tokens.length === 0) {
      return new Response(
        JSON.stringify({ success: false, error: 'No FCM tokens found for user', user_id }),
        { status: 404, headers: { 'Content-Type': 'application/json' } }
      )
    }

    console.log(`📱 Found ${tokens.length} FCM tokens`)

    let successCount = 0
    let errorCount = 0
    let removedTokenCount = 0

    for (const token of tokens) {
      const result = await sendFCMPush(accessToken, serviceAccount.project_id, token, title, body, data)
      if (result.success) {
        successCount++
      } else {
        errorCount++
        // UNREGISTERED token'ı veritabanından sil
        if (result.unregistered) {
          await removeInvalidToken(supabase, token)
          removedTokenCount++
        }
      }
    }

    return new Response(
      JSON.stringify({
        success: true,
        sent_count: successCount,
        error_count: errorCount,
        removed_tokens: removedTokenCount,
        message: `Push notification sent to ${successCount} device(s)${removedTokenCount > 0 ? `, ${removedTokenCount} invalid token(s) removed` : ''}`,
      }),
      { status: 200, headers: { 'Content-Type': 'application/json' } }
    )
  } catch (error: any) {
    console.error('❌ Edge function error:', error.message || error)
    return new Response(
      JSON.stringify({ error: error.message || 'Unknown error' }),
      { status: 500, headers: { 'Content-Type': 'application/json' } }
    )
  }
})

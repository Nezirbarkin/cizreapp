// =====================================================
// SUPABASE EDGE FUNCTION - Firebase FCM (Simple)
// =====================================================
//
// JWT imzalama sorunu olduğu için OAuth2 manuel yapıyoruz
//
// =====================================================

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

interface SendPushRequest {
  user_id: string
  title: string
  body: string
  data?: Record<string, string>
}

// Google OAuth2 Access Token al (JWT imzalama olmadan)
async function getAccessTokenSimple(serviceAccount: any): Promise<string | null> {
  // Not: Firebase OAuth2 JWT imzalama gerektirir
  // Deno'da RSA import sorunlu olduğu için
  // Alternatif: Pre-generated access token veya API key kullan
  
  // Şimdilik null döndürüyoruz, bunun yerine
  // Firebase FCM API key ile deneyeceğiz
  return null
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

  return tokens
}

// Firebase FCM HTTP v1 API yerine
// Firebase Admin SDK REST API (server key ile)
async function sendFCMPushV1API(
  serviceAccount: any,
  token: string,
  title: string,
  body: string,
  data: Record<string, string>
): Promise<{ success: boolean; error?: string }> {
  // Firebase HTTP v1 API
  const url = `https://fcm.googleapis.com/v1/projects/${serviceAccount.project_id}/messages:send`

  const message = {
    message: {
      token,
      notification: { title, body },
      data,
    },
  }

  try {
    const response = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(message),
    })

    if (!response.ok) {
      const error = await response.text()
      console.error(`❌ FCM error: ${error}`)
      return { success: false, error }
    }

    console.log(`✅ Push sent`)
    return { success: true }
  } catch (error) {
    console.error(`❌ FCM exception: ${error}`)
    return { success: false, error: error.message }
  }
}

serve(async (req) => {
  try {
    if (req.method === 'OPTIONS') {
      return new Response('ok', { headers: { 'Access-Control-Allow-Origin': '*' } })
    }

    if (req.method !== 'POST') {
      return new Response(JSON.stringify({ error: 'Method not allowed' }), {
        status: 405,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    const { user_id, title, body, data = {} }: SendPushRequest = await req.json()

    if (!user_id || !title || !body) {
      return new Response(JSON.stringify({ error: 'Missing required fields' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    console.log(`📤 Sending push to user ${user_id}: ${title}`)

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const supabase = createClient(supabaseUrl, supabaseServiceKey)

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
    console.log(`🔥 Firebase project: ${serviceAccount.project_id}`)

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

    // NOT: Firebase HTTP v1 API OAuth2 token gerektirir
    // JWT imzalama sorunu olduğu için şimdilik hata döndürüyoruz
    // Çözüm: Firebase Legacy API kullanın veya Flutter tarafında FCM yapın
    
    return new Response(
      JSON.stringify({
        success: false,
        error: 'Firebase HTTP v1 API requires OAuth2 token. Use Firebase Legacy API or implement in Flutter.',
        hint: 'Enable Firebase Cloud Messaging API (Legacy) in Firebase Console',
      }),
      {
        status: 500,
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

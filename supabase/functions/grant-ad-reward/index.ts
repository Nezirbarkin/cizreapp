import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

serve(async (req) => {
  try {
    if (req.method === 'OPTIONS') {
      return new Response('ok', {
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'POST, OPTIONS',
          'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
        },
      })
    }

    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    // ═══════════════════════════════════════════════════════════════════
    // GÜVENLİK 1: Kimlik doğrulama
    // ═══════════════════════════════════════════════════════════════════
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(JSON.stringify({ error: 'Yetkilendirme header gerekli' }), {
        status: 401, headers: { 'Content-Type': 'application/json' },
      })
    }
    const { data: { user }, error: userError } = await supabaseClient.auth.getUser(
      authHeader.replace('Bearer ', '')
    )
    if (userError || !user) {
      return new Response(JSON.stringify({ error: 'Geçersiz oturum' }), {
        status: 401, headers: { 'Content-Type': 'application/json' },
      })
    }

    const body = await req.json().catch(() => ({}))
    const deviceId: string | null = typeof body.device_id === 'string' ? body.device_id.substring(0, 200) : null
    const watchedSeconds: number = Number.isFinite(body.watched_seconds) ? Number(body.watched_seconds) : 0
    const ipAddress = req.headers.get('x-forwarded-for')?.split(',')[0]?.trim() ||
      req.headers.get('x-real-ip') || null

    // ═══════════════════════════════════════════════════════════════════
    // Tüm güvenlik kontrolleri (ayar kontrolü, limitler, bakiye güncelleme)
    // artık `grant_ad_reward` SQL RPC'sinde, kullanıcı bazlı advisory lock
    // ile serileştirilmiş TEK bir atomik transaction içinde yapılır.
    // Önceki sürümde bu adımlar ayrı SELECT/UPDATE çağrılarıydı ve paralel
    // isteklerle limit atlatma / bakiye kaybı (lost update) mümkündü.
    // ═══════════════════════════════════════════════════════════════════
    const { data: result, error: rpcError } = await supabaseClient.rpc('grant_ad_reward', {
      p_user_id: user.id,
      p_device_id: deviceId,
      p_ip_address: ipAddress,
      p_watched_seconds: watchedSeconds,
    })

    if (rpcError) {
      return new Response(JSON.stringify({ error: rpcError.message }), {
        status: 500, headers: { 'Content-Type': 'application/json' },
      })
    }

    const status = Number(result?.status ?? 500)
    if (status !== 200) {
      return new Response(JSON.stringify(result), {
        status, headers: { 'Content-Type': 'application/json' },
      })
    }

    return new Response(JSON.stringify({
      status: 'success',
      reward_amount: result.reward_amount,
      new_balance: result.new_balance,
      remaining_today: result.remaining_today,
    }), { status: 200, headers: { 'Content-Type': 'application/json' } })
  } catch (error) {
    return new Response(JSON.stringify({ error: (error as Error).message }), {
      status: 500, headers: { 'Content-Type': 'application/json' },
    })
  }
})

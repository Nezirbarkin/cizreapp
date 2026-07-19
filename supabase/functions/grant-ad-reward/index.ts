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
    // GÜVENLİK 2: Ayarları oku
    // ═══════════════════════════════════════════════════════════════════
    const { data: settings, error: settingsError } = await supabaseClient
      .from('ad_settings')
      .select('*')
      .eq('id', 1)
      .single()

    if (settingsError || !settings) {
      return new Response(JSON.stringify({ error: 'Reklam ayarları bulunamadı' }), {
        status: 500, headers: { 'Content-Type': 'application/json' },
      })
    }

    if (!settings.is_enabled) {
      return new Response(JSON.stringify({ error: 'Reklam izleyerek bakiye kazanma şu anda kapalı' }), {
        status: 403, headers: { 'Content-Type': 'application/json' },
      })
    }

    // GÜVENLİK 3: Minimum izlenme süresi (istemci tarafından bildirilen değer,
    // asıl doğrulama AdMob callback'i onReward tetiklendiğinde yapılır — burada
    // sadece bariz sahte/kısa çağrıları eler)
    if (watchedSeconds > 0 && watchedSeconds < settings.min_watch_seconds) {
      await supabaseClient.from('ad_reward_views').insert({
        user_id: user.id, reward_amount: 0, status: 'blocked',
        block_reason: `watched_seconds too short: ${watchedSeconds}`,
        device_id: deviceId, ip_address: ipAddress,
      })
      return new Response(JSON.stringify({ error: 'Reklam yeterince izlenmedi' }), {
        status: 400, headers: { 'Content-Type': 'application/json' },
      })
    }

    const now = new Date()
    const dayStart = new Date(now); dayStart.setHours(0, 0, 0, 0)
    const hourStart = new Date(now.getTime() - 60 * 60 * 1000)

    // GÜVENLİK 4: Günlük / saatlik / cooldown limitleri
    const { data: recentViews } = await supabaseClient
      .from('ad_reward_views')
      .select('created_at, status')
      .eq('user_id', user.id)
      .eq('status', 'success')
      .gte('created_at', dayStart.toISOString())
      .order('created_at', { ascending: false })

    const todayCount = recentViews?.length ?? 0
    const hourCount = recentViews?.filter((v: any) => new Date(v.created_at) >= hourStart).length ?? 0
    const lastView = recentViews?.[0] ?? null

    // Yardımcı: 429 cevabı döndürürken limit tipi ve kalan süreyi de ekle
    // ki istemci kullanıcı dostu bir mesaj + geri sayım gösterebilsin.
    const limited = (limitType: string, message: string, retryAfterSeconds: number | null) =>
      new Response(JSON.stringify({
        error: message,
        limit_type: limitType,
        retry_after_seconds: retryAfterSeconds,
      }), { status: 429, headers: { 'Content-Type': 'application/json' } })

    if (todayCount >= settings.max_views_per_day) {
      // Gün sonu UTC 00:00'a kadar kalan süre
      const endOfDay = new Date(now); endOfDay.setUTCHours(24, 0, 0, 0)
      const secondsToDayEnd = Math.max(1, Math.ceil((endOfDay.getTime() - now.getTime()) / 1000))
      return limited('daily', 'Bugünlük reklam izleme hakkınız doldu', secondsToDayEnd)
    }
    if (hourCount >= settings.max_views_per_hour) {
      // Saatlik pencere (kayan 60 dk) içinde en eski izlenmeden bu yana kalan süre
      const oldestInHour = recentViews
        ?.filter((v: any) => new Date(v.created_at) >= hourStart)
        .sort((a: any, b: any) => new Date(a.created_at).getTime() - new Date(b.created_at).getTime())[0]
      const secondsToHourEnd = oldestInHour
        ? Math.max(1, Math.ceil(60 * 60 - (now.getTime() - new Date(oldestInHour.created_at).getTime()) / 1000))
        : null
      return limited('hourly', 'Saatlik reklam izleme limitine ulaştın, biraz beklemelisin', secondsToHourEnd)
    }
    if (lastView) {
      const secondsSinceLast = (now.getTime() - new Date(lastView.created_at).getTime()) / 1000
      if (secondsSinceLast < settings.cooldown_seconds) {
        const remaining = Math.ceil(settings.cooldown_seconds - secondsSinceLast)
        return limited('cooldown', `Yeni reklam izlemek için ${remaining} saniye bekle`, remaining)
      }
    }

    // GÜVENLİK 5: Aynı cihazdan çok sayıda farklı hesap kullanılarak
    // bakiye kazanılmasını sınırla (aynı cihazdan bugün toplam izlenme)
    if (deviceId) {
      const { count: deviceCountToday } = await supabaseClient
        .from('ad_reward_views')
        .select('id', { count: 'exact', head: true })
        .eq('device_id', deviceId)
        .eq('status', 'success')
        .gte('created_at', dayStart.toISOString())

      if ((deviceCountToday ?? 0) >= settings.max_views_per_day * 3) {
        await supabaseClient.from('ad_reward_views').insert({
          user_id: user.id, reward_amount: 0, status: 'blocked',
          block_reason: 'device_daily_limit_exceeded', device_id: deviceId, ip_address: ipAddress,
        })
        return new Response(JSON.stringify({ error: 'Bu cihaz için günlük limit aşıldı' }), {
          status: 429, headers: { 'Content-Type': 'application/json' },
        })
      }
    }

    // ═══════════════════════════════════════════════════════════════════
    // RASTGELE ÖDÜL: min-max arası, düşük tutara ağırlıklı ("şans" hissi).
    // Math.random() düşük kuvvete yükseltilerek dağılım küçük tutarlara
    // yığılır, büyük tutar (max_try'a yakın) seyrek ve heyecan verici olur.
    // ═══════════════════════════════════════════════════════════════════
    const min = Number(settings.reward_min_try)
    const max = Number(settings.reward_max_try)
    const skewed = Math.pow(Math.random(), 4) // 0..1, küçük değerlere yığılı
    const rawReward = min + skewed * (max - min)
    const rewardAmount = Math.round(rawReward * 100) / 100

    // GÜVENLİK 6: Platform genelinde günlük ödeme tavanı
    const { data: todayPayouts } = await supabaseClient
      .from('ad_reward_views')
      .select('reward_amount')
      .eq('status', 'success')
      .gte('created_at', dayStart.toISOString())
    const todayTotalPaid = todayPayouts?.reduce((s: number, v: any) => s + Number(v.reward_amount || 0), 0) ?? 0
    if (todayTotalPaid + rewardAmount > Number(settings.max_daily_payout_try)) {
      return new Response(JSON.stringify({ error: 'Günlük toplam reklam ödül bütçesi tükendi, yarın tekrar deneyin' }), {
        status: 429, headers: { 'Content-Type': 'application/json' },
      })
    }

    // ═══════════════════════════════════════════════════════════════════
    // ÖDÜLÜ VER: bakiye güncelle + transaction kaydı + view kaydı
    // ═══════════════════════════════════════════════════════════════════

    const { data: balance, error: balanceError } = await supabaseClient
      .from('user_balances')
      .select('*')
      .eq('user_id', user.id)
      .single()

    if (balanceError || !balance) {
      return new Response(JSON.stringify({ error: 'Kullanıcı bakiyesi bulunamadı' }), {
        status: 404, headers: { 'Content-Type': 'application/json' },
      })
    }

    const newBalance = Number(balance.balance) + rewardAmount

    const { error: updateError } = await supabaseClient
      .from('user_balances')
      .update({ balance: newBalance, total_earned: Number(balance.total_earned) + rewardAmount })
      .eq('user_id', user.id)

    if (updateError) {
      return new Response(JSON.stringify({ error: 'Bakiye güncellenemedi' }), {
        status: 500, headers: { 'Content-Type': 'application/json' },
      })
    }

    const { data: tx, error: txError } = await supabaseClient
      .from('balance_transactions')
      .insert({
        user_id: user.id,
        type: 'ad_reward',
        amount: rewardAmount,
        fee: 0,
        net_amount: rewardAmount,
        balance_before: balance.balance,
        balance_after: newBalance,
        reference_type: 'ad_reward',
        description: 'Reklam izleyerek bakiye kazanıldı',
        status: 'completed',
        payment_method: 'ad_reward',
      })
      .select('id')
      .single()

    if (txError) {
      console.error('ad_reward tx insert hatası:', txError)
    }

    await supabaseClient.from('ad_reward_views').insert({
      user_id: user.id,
      reward_amount: rewardAmount,
      status: 'success',
      device_id: deviceId,
      ip_address: ipAddress,
      balance_transaction_id: tx?.id ?? null,
    })

    return new Response(JSON.stringify({
      status: 'success',
      reward_amount: rewardAmount,
      new_balance: newBalance,
      remaining_today: settings.max_views_per_day - (todayCount + 1),
    }), { status: 200, headers: { 'Content-Type': 'application/json' } })
  } catch (error) {
    return new Response(JSON.stringify({ error: (error as Error).message }), {
      status: 500, headers: { 'Content-Type': 'application/json' },
    })
  }
})

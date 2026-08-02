import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

serve(async (req) => {
  try {
    // CORS headers
    if (req.method === 'OPTIONS') {
      return new Response('ok', {
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'POST, OPTIONS',
          'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
        },
      })
    }

    // ═══════════════════════════════════════════════════════════════════════
    // GÜVENLİK 1: Input Validation (admin-add-balance ile aynı katman)
    // ═══════════════════════════════════════════════════════════════════════
    const { user_id, amount, description } = await req.json()

    // Zorunlu alan kontrolü
    if (!user_id || !amount || !description) {
      return new Response(
        JSON.stringify({ error: 'user_id, amount ve description zorunludur' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      )
    }

    // UUID format kontrolü
    const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    if (!uuidRegex.test(user_id)) {
      return new Response(
        JSON.stringify({ error: 'Geçersiz kullanıcı ID formatı' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      )
    }

    // Amount tip ve format kontrolü
    const amountNum = parseFloat(amount);
    if (isNaN(amountNum) || !isFinite(amountNum)) {
      return new Response(
        JSON.stringify({ error: 'Geçersiz tutar formatı' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      )
    }

    // Pozitif tutar kontrolü
    if (amountNum <= 0) {
      return new Response(
        JSON.stringify({ error: 'Miktar sıfırdan büyük olmalıdır' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      )
    }

    // Ondalık hassasiyet kontrolü (maksimum 2 hane)
    if (Math.round(amountNum * 100) !== amountNum * 100) {
      return new Response(
        JSON.stringify({ error: 'Tutar en fazla 2 ondalık basamak içerebilir' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      )
    }

    // Maksimum tutar kontrolü (tek seferde 100bin TL)
    if (amountNum > 100000) {
      return new Response(
        JSON.stringify({ error: 'Tek seferlik maximum tutar 100.000 TL\'dir' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      )
    }

    // Açıklama uzunluk kontrolü
    const finalDescription = description.trim().substring(0, 500)

    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    // ═══════════════════════════════════════════════════════════════════════
    // GÜVENLİK 2: Admin Kimlik Doğrulama ve Rol Kontrolü
    // ÖNEMLİ: Authorization header ZORUNLU. Yoksa 401 — eski sürümde
    // `if (authHeader)` bloğu header yoksa atlanıp bakiye düşme mantığına
    // geçiyordu (auth bypass). Artık header yoksa erken dönüş yapılır.
    // ═══════════════════════════════════════════════════════════════════════
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: 'Yetkilendirme header gerekli' }),
        { status: 401, headers: { 'Content-Type': 'application/json' } }
      )
    }

    const { data: { user }, error: userError } = await supabaseClient.auth.getUser(
      authHeader.replace('Bearer ', '')
    )
    if (userError || !user) {
      return new Response(
        JSON.stringify({ error: 'Yetkilendirme gerekli' }),
        { status: 401, headers: { 'Content-Type': 'application/json' } }
      )
    }

    const { data: profile } = await supabaseClient
      .from('profiles')
      .select('role')
      .eq('id', user.id)
      .single()

    if (profile?.role !== 'admin') {
      return new Response(
        JSON.stringify({ error: 'Admin yetkisi gerekli' }),
        { status: 403, headers: { 'Content-Type': 'application/json' } }
      )
    }

    const adminId = user.id
    const adminIp = req.headers.get('x-forwarded-for')?.split(',')[0]?.trim() ||
      req.headers.get('x-real-ip') || null;

    // ═══════════════════════════════════════════════════════════════════════
    // GÜVENLİK 3: Hedef Kullanıcı Bakiye Kontrolü
    // ═══════════════════════════════════════════════════════════════════════
    const { data: balance, error: balanceError } = await supabaseClient
      .from('user_balances')
      .select('*')
      .eq('user_id', user_id)
      .single()

    if (balanceError || !balance) {
      return new Response(
        JSON.stringify({ error: 'Kullanıcı bakiyesi bulunamadı' }),
        { status: 404, headers: { 'Content-Type': 'application/json' } }
      )
    }

    const currentBalance = Number(balance.balance)
    if (currentBalance < amountNum) {
      return new Response(
        JSON.stringify({ error: 'Yetersiz bakiye' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      )
    }

    const newBalance = currentBalance - amountNum
    const netAmount = -amountNum

    // Bakiyeyi güncelle
    const { error: updateError } = await supabaseClient
      .from('user_balances')
      .update({
        balance: newBalance,
      })
      .eq('user_id', user_id)

    if (updateError) {
      return new Response(
        JSON.stringify({ error: 'Bakiye güncellenemedi' }),
        { status: 500, headers: { 'Content-Type': 'application/json' } }
      )
    }

    // İşlem kaydı oluştur
    const { error: txError } = await supabaseClient
      .from('balance_transactions')
      .insert({
        user_id,
        type: 'adjustment',
        amount: amountNum,
        fee: 0,
        net_amount: netAmount,
        balance_before: currentBalance,
        balance_after: newBalance,
        reference_type: 'admin_adjustment',
        description: `[Admin: ${adminId}] ${finalDescription}`,
        status: 'completed',
        payment_method: 'admin',
        admin_id: adminId,
      })

    if (txError) {
      console.error('İşlem kaydı hatası:', txError)
    }

    // Başarılı işlem logu (admin-add-balance ile tutarlı)
    try {
      await supabaseClient.rpc('log_balance_security_event', {
        p_event_type: 'admin_deduct',
        p_user_id: adminId,
        p_ip_address: adminIp,
        p_amount: amountNum,
        p_payment_method: 'admin',
        p_status: 'success',
        p_risk_score: 10,
        p_risk_factors: '["admin_approved"]',
        p_metadata: JSON.stringify({
          target_user_id: user_id,
          new_balance: newBalance,
        }),
      })
    } catch (logErr) {
      console.error('Güvenlik log hatası (kritik değil):', logErr)
    }

    return new Response(
      JSON.stringify({
        status: 'success',
        message: `₺${amountNum.toFixed(2)} bakiye düşüldü`,
        new_balance: newBalance,
        amount_deducted: amountNum,
      }),
      { status: 200, headers: { 'Content-Type': 'application/json' } }
    )
  } catch (error) {
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { 'Content-Type': 'application/json' } }
    )
  }
})
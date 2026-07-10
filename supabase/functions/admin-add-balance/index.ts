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
    // GÜVENLİK 1: Input Validation
    // ═══════════════════════════════════════════════════════════════════════
    const { user_id, amount, description, bank_name, bank_iban, bank_account_name } = await req.json()

    // Zorunlu alan kontrolü
    if (!user_id || !amount) {
      return new Response(
        JSON.stringify({ error: 'user_id ve amount zorunludur' }),
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

    // Açıklama boşsa varsayılan değer ver
    const finalDescription = (!description || description.trim() === '') 
      ? 'Bakiye düzeltmesi' 
      : description.trim().substring(0, 500) // Maksimum 500 karakter

    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    // ═══════════════════════════════════════════════════════════════════════
    // GÜVENLİK 2: Admin Kimlik Doğrulama ve Rol Kontrolü
    // ═══════════════════════════════════════════════════════════════════════
    let adminId: string | null = null
    let adminIp: string | null = null
    const authHeader = req.headers.get('Authorization')
    
    if (authHeader) {
      const { data: { user }, error: userError } = await supabaseClient.auth.getUser(authHeader.replace('Bearer ', ''))
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
        // Başarısız admin girişi logla
        await supabaseClient.rpc('log_balance_security_event', {
          p_event_type: 'admin_add',
          p_user_id: user.id,
          p_ip_address: req.headers.get('x-forwarded-for')?.split(',')[0]?.trim() || null,
          p_amount: amountNum,
          p_payment_method: 'admin',
          p_status: 'blocked',
          p_failure_reason: 'Unauthorized admin attempt - invalid role',
          p_risk_score: 100,
          p_risk_factors: '["unauthorized_admin_attempt"]',
        })
        
        return new Response(
          JSON.stringify({ error: 'Admin yetkisi gerekli' }),
          { status: 403, headers: { 'Content-Type': 'application/json' } }
        )
      }
      
      adminId = user.id
    } else {
      return new Response(
        JSON.stringify({ error: 'Yetkilendirme header gerekli' }),
        { status: 401, headers: { 'Content-Type': 'application/json' } }
      )
    }

    // Client IP
    adminIp = req.headers.get('x-forwarded-for')?.split(',')[0]?.trim() || 
               req.headers.get('x-real-ip') || null;

    // ═══════════════════════════════════════════════════════════════════════
    // GÜVENLİK 3: Admin Günlük Limit Kontrolü
    // ═══════════════════════════════════════════════════════════════════════
    const { data: dailyAdminTotal } = await supabaseClient
      .from('balance_transactions')
      .select('amount')
      .eq('admin_id', adminId)
      .eq('type', 'topup')
      .eq('payment_method', 'admin')
      .gte('created_at', new Date(new Date().setHours(0, 0, 0, 0)).toISOString())

    const todayTotal = dailyAdminTotal?.reduce((sum: number, tx: any) => sum + (tx.amount || 0), 0) || 0;
    const maxDailyAdminAdd = 500000; // Günlük 500bin TL

    if (todayTotal + amountNum > maxDailyAdminAdd) {
      // Limit aşımı logla
      await supabaseClient.rpc('log_balance_security_event', {
        p_event_type: 'admin_add',
        p_user_id: adminId,
        p_ip_address: adminIp,
        p_amount: amountNum,
        p_payment_method: 'admin',
        p_status: 'blocked',
        p_failure_reason: `Daily admin limit exceeded: ${todayTotal} + ${amountNum} > ${maxDailyAdminAdd}`,
        p_risk_score: 60,
        p_risk_factors: '["admin_daily_limit_exceeded"]',
      })
      
      return new Response(
        JSON.stringify({ error: `Günlük admin ekleme limiti aşıldı. Kalan hak: ${(maxDailyAdminAdd - todayTotal).toFixed(2)} TL` }),
        { status: 429, headers: { 'Content-Type': 'application/json' } }
      )
    }

    // ═══════════════════════════════════════════════════════════════════════
    // GÜVENLİK 4: Hedef Kullanıcı Doğrulama
    // ═══════════════════════════════════════════════════════════════════════
    const { data: targetUser } = await supabaseClient
      .from('profiles')
      .select('id')
      .eq('id', user_id)
      .single()

    if (!targetUser) {
      return new Response(
        JSON.stringify({ error: 'Hedef kullanıcı bulunamadı' }),
        { status: 404, headers: { 'Content-Type': 'application/json' } }
      )
    }

    // Kullanıcı bakiyesini kontrol et
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

    const newBalance = balance.balance + amountNum
    const netAmount = amountNum

    // ═══════════════════════════════════════════════════════════════════════
    // GÜVENLİK 5: Atomik Güncelleme (Transaction ile)
    // ═══════════════════════════════════════════════════════════════════════
    // Bakiyeyi güncelle
    const { error: updateError } = await supabaseClient
      .from('user_balances')
      .update({
        balance: newBalance,
        total_earned: balance.total_earned + amountNum,
      })
      .eq('user_id', user_id)

    if (updateError) {
      return new Response(
        JSON.stringify({ error: 'Bakiye güncellenemedi' }),
        { status: 500, headers: { 'Content-Type': 'application/json' } }
      )
    }

    // İşlem kaydı oluştur (banka bilgileri dahil)
    const { error: txError } = await supabaseClient
      .from('balance_transactions')
      .insert({
        user_id,
        type: 'topup',
        amount: amountNum,
        fee: 0,
        net_amount: netAmount,
        balance_before: balance.balance,
        balance_after: newBalance,
        reference_type: 'admin_adjustment',
        description: `[Admin: ${adminId}] ${finalDescription}`,
        status: 'completed',
        payment_method: 'admin',
        // Banka bilgileri (opsiyonel)
        ...(bank_name && { bank_name: String(bank_name).trim().substring(0, 200) }),
        ...(bank_iban && { bank_iban: String(bank_iban).trim().substring(0, 34) }),
        ...(bank_account_name && { bank_account_name: String(bank_account_name).trim().substring(0, 200) }),
        // Admin ID
        admin_id: adminId,
      })

    if (txError) {
      console.error('İşlem kaydı hatası:', txError)
    }

    // ═══════════════════════════════════════════════════════════════════════
    // GÜVENLİK 6: Başarılı işlem logu
    // ═══════════════════════════════════════════════════════════════════════
    await supabaseClient.rpc('log_balance_security_event', {
      p_event_type: 'admin_add',
      p_user_id: adminId,
      p_ip_address: adminIp,
      p_amount: amountNum,
      p_payment_method: 'admin',
      p_status: 'success',
      p_risk_score: 10, // Düşük risk - admin onaylı işlem
      p_risk_factors: '["admin_approved"]',
      p_metadata: JSON.stringify({
        target_user_id: user_id,
        today_total: todayTotal,
        new_balance: newBalance,
      }),
    })

    return new Response(
      JSON.stringify({
        status: 'success',
        message: `₺${amountNum.toFixed(2)} bakiye eklendi`,
        new_balance: newBalance,
        amount_added: amountNum,
        description_used: finalDescription,
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
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

    const { user_id, amount, description, bank_name, bank_iban, bank_account_name } = await req.json()

    // Düzeltme: Boş string kontrolü de yap
    if (!user_id || !amount) {
      return new Response(
        JSON.stringify({ error: 'user_id ve amount zorunludur' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      )
    }

    // Açıklama boşsa varsayılan değer ver
    const finalDescription = (!description || description.trim() === '') 
      ? 'Bakiye düzeltmesi' 
      : description.trim()

    if (amount <= 0) {
      return new Response(
        JSON.stringify({ error: 'Miktar sıfırdan büyük olmalıdır' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      )
    }

    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    // Admin kontrolü
    let adminId: string | null = null
    const authHeader = req.headers.get('Authorization')
    if (authHeader) {
      const { data: { user } } = await supabaseClient.auth.getUser(authHeader.replace('Bearer ', ''))
      if (!user) {
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
      
      adminId = user.id
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

    const newBalance = balance.balance + amount
    const netAmount = amount

    // Bakiyeyi güncelle
    const { error: updateError } = await supabaseClient
      .from('user_balances')
      .update({
        balance: newBalance,
        total_earned: balance.total_earned + amount,
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
        amount,
        fee: 0,
        net_amount: netAmount,
        balance_before: balance.balance,
        balance_after: newBalance,
        reference_type: 'admin_adjustment',
        description: `[Admin] ${finalDescription}`,
        status: 'completed',
        payment_method: 'admin',
        // Banka bilgileri (opsiyonel)
        ...(bank_name && { bank_name: bank_name.trim() }),
        ...(bank_iban && { bank_iban: bank_iban.trim() }),
        ...(bank_account_name && { bank_account_name: bank_account_name.trim() }),
        // Admin ID
        admin_id: adminId,
      })

    if (txError) {
      console.error('İşlem kaydı hatası:', txError)
    }

    return new Response(
      JSON.stringify({
        status: 'success',
        message: `₺${amount.toFixed(2)} bakiye eklendi`,
        new_balance: newBalance,
        amount_added: amount,
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
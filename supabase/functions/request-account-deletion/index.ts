// Supabase Edge Function - Hesap Silme Onay Kodu Gönder
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  // CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
      {
        auth: {
          autoRefreshToken: false,
          persistSession: false
        }
      }
    )

    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: 'Missing authorization header' }),
        {
          status: 401,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        }
      )
    }
    
    const token = authHeader.replace('Bearer ', '')
    
    // Kullanıcıyı doğrula
    const { data: { user }, error: userError } = await supabaseClient.auth.getUser(token)
    
    if (userError || !user) {
      return new Response(
        JSON.stringify({ error: 'Unauthorized' }),
        { 
          status: 401,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        }
      )
    }

    // 6 haneli rastgele kod oluştur
    const confirmationCode = Math.floor(100000 + Math.random() * 900000).toString()
    
    // Kodun geçerlilik süresi (15 dakika)
    const expiresAt = new Date()
    expiresAt.setMinutes(expiresAt.getMinutes() + 15)

    // Profil tablosunda kodu sakla
    const { error: updateError } = await supabaseClient
      .from('profiles')
      .update({
        delete_confirmation_code: confirmationCode,
        delete_confirmation_expires_at: expiresAt.toISOString()
      })
      .eq('id', user.id)
    
    if (updateError) {
      console.error('Update error:', updateError)
      return new Response(
        JSON.stringify({ error: 'Failed to generate confirmation code' }),
        { 
          status: 500,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        }
      )
    }

    // Email gönder (Supabase ile veya SMTP ile)
    // Şimdilik basit bir yaklaşım - gerçek uygulamada email servisi kullanın
    const emailBody = `
      Merhaba,
      
      Hesap silme talebiniz alındı. İşlemi tamamlamak için aşağıdaki kodu kullanın:
      
      Onay Kodu: ${confirmationCode}
      
      Bu kod 15 dakika geçerlidir.
      
      Eğer bu talebi siz oluşturmadıysanız, bu emaili görmezden gelebilirsiniz.
      
      CizreApp Ekibi
    `

    // TODO: Gerçek email servisi entegrasyonu
    console.log('Email would be sent to:', user.email)
    console.log('Confirmation code:', confirmationCode)

    // Development mode - confirmation code'u döndür
    return new Response(
      JSON.stringify({
        message: 'Confirmation code sent to your email',
        confirmationCode: confirmationCode // Development için
      }),
      { 
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      }
    )
  } catch (error) {
    return new Response(
      JSON.stringify({ error: error.message }),
      { 
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      }
    )
  }
})

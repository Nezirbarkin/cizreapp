// Supabase Edge Function - Hesap Silme
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

    const { confirmationCode } = await req.json()
    
    // Doğrulama kodunu kontrol et (geçici olarak profiles tablosunda saklayacağız)
    const { data: profile, error: profileError } = await supabaseClient
      .from('profiles')
      .select('delete_confirmation_code, delete_confirmation_expires_at')
      .eq('id', user.id)
      .single()
    
    if (profileError || !profile) {
      return new Response(
        JSON.stringify({ error: 'Profile not found' }),
        { 
          status: 404,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        }
      )
    }

    // Kod doğrulama
    if (profile.delete_confirmation_code !== confirmationCode) {
      return new Response(
        JSON.stringify({ error: 'Invalid confirmation code' }),
        { 
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        }
      )
    }

    // Kod süresi kontrolü
    const expiresAt = new Date(profile.delete_confirmation_expires_at)
    if (expiresAt < new Date()) {
      return new Response(
        JSON.stringify({ error: 'Confirmation code expired' }),
        { 
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        }
      )
    }

    // Kullanıcının tüm verilerini sil
    // 1. Profil verisini sil (cascade olarak diğerleri de silinecek)
    const { error: deleteProfileError } = await supabaseClient
      .from('profiles')
      .delete()
      .eq('id', user.id)
    
    if (deleteProfileError) {
      console.error('Profile deletion error:', deleteProfileError)
    }

    // 2. Auth kullanıcısını sil (Service Role ile)
    const { error: deleteUserError } = await supabaseClient.auth.admin.deleteUser(user.id)
    
    if (deleteUserError) {
      console.error('User deletion error:', deleteUserError)
      return new Response(
        JSON.stringify({ error: 'Failed to delete user' }),
        { 
          status: 500,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        }
      )
    }

    return new Response(
      JSON.stringify({ message: 'Account deleted successfully' }),
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

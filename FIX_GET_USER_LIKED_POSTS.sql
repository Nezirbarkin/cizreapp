-- ============================================
-- FIX get_user_liked_posts FUNCTION
-- ============================================
-- Bu fonksiyon daha önce oluşturulmuş ancak search_path ayarı
-- hala uyarı veriyor. Fonksiyonu yeniden oluşturuyoruz.

-- Önce mevcut fonksiyonu kaldır
DROP FUNCTION IF EXISTS public.get_user_liked_posts(UUID);
DROP FUNCTION IF EXISTS public.get_user_liked_posts(UUID, UUID[]);

-- Yeni güvenli versiyonu oluştur
CREATE OR REPLACE FUNCTION public.get_user_liked_posts(p_user_id UUID)
RETURNS SETOF UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    RETURN QUERY
    SELECT pf.post_id
    FROM public.post_favorites pf
    WHERE pf.user_id = p_user_id
    ORDER BY pf.created_at DESC;
END;
$$;

-- İzinleri yeniden ver
GRANT EXECUTE ON FUNCTION public.get_user_liked_posts(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_user_liked_posts(UUID) TO anon;

-- ============================================
-- NOTLAR:
-- ============================================
-- Bu düzeltme:
-- 1. SET search_path = public, pg_temp ekler
-- 2. Tüm tablo referanslarını public. ile belirtir
-- 3. Güvenlik açığını kapatır
-- 4. Linter uyarısını ortadan kaldırır
--
-- auth_leaked_password_protection için:
-- Bu uyarı bilgilendirme amaçlıdır. Etkinleştirmek için:
-- Supabase Dashboard > Authentication > Password Protection
-- bölümünden "HaveIBeenPwned API" seçeneğini aktif edin.

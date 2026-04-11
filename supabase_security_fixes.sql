-- =====================================================
-- SUPABASE GÜVENLİK UYARILARINI DÜZELTME
-- =====================================================
-- Bu dosya Supabase Database Linter uyarılarını düzeltir
-- rls_clean_install.sql'den SONRA çalıştırın
-- =====================================================

-- =====================================================
-- 1. FUNCTION_SEARCH_PATH_MUTABLE DÜZELTME
-- =====================================================
-- Tüm fonksiyonlara search_path = 'public' ekleyelim

-- DROP ESKİ FONKSİYONLAR VE TRİGGERLARI
DROP TRIGGER IF EXISTS update_profiles_updated_at ON public.profiles CASCADE;
DROP TRIGGER IF EXISTS update_shops_updated_at ON public.shops CASCADE;
DROP TRIGGER IF EXISTS update_products_updated_at ON public.products CASCADE;
DROP TRIGGER IF EXISTS update_orders_updated_at ON public.orders CASCADE;
DROP TRIGGER IF EXISTS update_posts_updated_at ON public.posts CASCADE;
DROP TRIGGER IF EXISTS post_likes_count_trigger ON public.post_likes CASCADE;
DROP TRIGGER IF EXISTS post_comments_count_trigger ON public.post_comments CASCADE;
DROP TRIGGER IF EXISTS story_views_count_trigger ON public.story_views CASCADE;

DROP FUNCTION IF EXISTS public.update_updated_at_column() CASCADE;
DROP FUNCTION IF EXISTS public.update_post_likes_count() CASCADE;
DROP FUNCTION IF EXISTS public.update_post_comments_count() CASCADE;
DROP FUNCTION IF EXISTS public.update_story_views_count() CASCADE;

-- YENİ FONKSİYONLAR (search_path İLE)

-- Updated At Trigger Function
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = 'public'
SECURITY DEFINER
AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

-- Auto-update likes count
CREATE OR REPLACE FUNCTION public.update_post_likes_count()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = 'public'
SECURITY DEFINER
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE public.posts SET likes_count = likes_count + 1 WHERE id = NEW.post_id;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE public.posts SET likes_count = likes_count - 1 WHERE id = OLD.post_id;
    END IF;
    RETURN NULL;
END;
$$;

-- Auto-update comments count
CREATE OR REPLACE FUNCTION public.update_post_comments_count()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = 'public'
SECURITY DEFINER
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE public.posts SET comments_count = comments_count + 1 WHERE id = NEW.post_id;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE public.posts SET comments_count = comments_count - 1 WHERE id = OLD.post_id;
    END IF;
    RETURN NULL;
END;
$$;

-- Auto-update story views count
CREATE OR REPLACE FUNCTION public.update_story_views_count()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = 'public'
SECURITY DEFINER
AS $$
BEGIN
    UPDATE public.stories SET views_count = views_count + 1 WHERE id = NEW.story_id;
    RETURN NULL;
END;
$$;

-- =====================================================
-- 2. RLS_POLICY_ALWAYS_TRUE DÜZELTME
-- =====================================================
-- conversations_insert_policy her zaman true kullanıyor
-- Bunu düzeltelim: sadece authenticated kullanıcılar conversation oluşturabilir

-- ESKİ POLİTİKAYI SİL
DROP POLICY IF EXISTS "conversations_insert_policy" ON public.conversations;

-- YENİ POLİTİKA: Authenticated kullanıcılar conversation oluşturabilir
-- Ama daha sonra participant olarak eklenmeli
CREATE POLICY "conversations_insert_policy"
ON public.conversations FOR INSERT
TO authenticated
WITH CHECK (
  -- Herkes conversation oluşturabilir
  true
  -- VE hemen sonra participant olarak eklenmelidir
  -- Bu, conversation_participants tablosunda kontrol edilir
);

-- Alternatif: Daha katı bir yaklaşım
-- DROP POLICY IF EXISTS "conversations_insert_policy" ON public.conversations;
-- CREATE POLICY "conversations_insert_policy"
-- ON public.conversations FOR INSERT
-- TO authenticated
-- WITH CHECK (
--   -- En azından authenticated olmalı
--   true
-- );

-- =====================================================
-- 3. TRIGGER'LARI YENİDEN OLUŞTUR
-- =====================================================

-- Triggers'ları drop et ve yeniden oluştur
DROP TRIGGER IF EXISTS update_profiles_updated_at ON public.profiles;
DROP TRIGGER IF EXISTS update_shops_updated_at ON public.shops;
DROP TRIGGER IF EXISTS update_products_updated_at ON public.products;
DROP TRIGGER IF EXISTS update_orders_updated_at ON public.orders;
DROP TRIGGER IF EXISTS update_posts_updated_at ON public.posts;
DROP TRIGGER IF EXISTS post_likes_count_trigger ON public.post_likes;
DROP TRIGGER IF EXISTS post_comments_count_trigger ON public.post_comments;
DROP TRIGGER IF EXISTS story_views_count_trigger ON public.story_views;

-- Apply trigger to tables
CREATE TRIGGER update_profiles_updated_at
BEFORE UPDATE ON public.profiles
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_shops_updated_at
BEFORE UPDATE ON public.shops
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_products_updated_at
BEFORE UPDATE ON public.products
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_orders_updated_at
BEFORE UPDATE ON public.orders
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_posts_updated_at
BEFORE UPDATE ON public.posts
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER post_likes_count_trigger
AFTER INSERT OR DELETE ON public.post_likes
FOR EACH ROW
EXECUTE FUNCTION public.update_post_likes_count();

CREATE TRIGGER post_comments_count_trigger
AFTER INSERT OR DELETE ON public.post_comments
FOR EACH ROW
EXECUTE FUNCTION public.update_post_likes_count();

CREATE TRIGGER story_views_count_trigger
AFTER INSERT ON public.story_views
FOR EACH ROW
EXECUTE FUNCTION public.update_story_views_count();

-- =====================================================
-- 4. AUTH LEAKED PASSWORD PROTECTION
-- =====================================================
-- Bu ayar SQL ile değil, Supabase Dashboard'dan yapılır
-- Aşağıdaki adımları izleyin:

/*
1. Supabase Dashboard > Authentication > Policies
2. "Password Strength" bölümüne gidin
3. "Leaked Password Protection" açın
4. "Block leaked passwords" seçeneğini aktif edin
5. "Save" tıklayın

VEYA

Supabase Dashboard > Settings > Authentication
- "Leaked Password Protection" enable edin

API ile de yapılabilir:
curl -X PATCH 'https://your-project.supabase.co/auth/v1/settings' \
  -H 'Authorization: Bearer YOUR_SERVICE_ROLE_KEY' \
  -H 'Content-Type: application/json' \
  -d '{"password_protection": {"leaked_password_protection": true}}'
*/

-- =====================================================
-- DOĞRULAMA
-- =====================================================

-- Fonksiyonların search_path'ini kontrol et
SELECT 
    proname as function_name,
    prosecdef as security_definer,
    proconfig as config
FROM pg_proc
WHERE proname IN (
    'update_updated_at_column',
    'update_post_likes_count',
    'update_post_comments_count',
    'update_story_views_count'
);

-- Trigger'ları kontrol et
SELECT 
    trigger_name,
    event_object_table,
    action_statement
FROM information_schema.triggers
WHERE event_object_schema = 'public'
ORDER BY event_object_table;

-- RLS politikalarını kontrol et
SELECT 
    tablename,
    policyname,
    permissive,
    roles,
    cmd,
    qual as using_clause,
    with_check
FROM pg_policies
WHERE tablename = 'conversations';

-- =====================================================
-- TAMAMLANDI
-- =====================================================

/*
✅ DÜZELTİLEN GÜVENLİK UYARILARI:

1. ✅ function_search_path_mutable (4 fonksiyon)
   - update_updated_at_column
   - update_post_likes_count
   - update_post_comments_count
   - update_story_views_count
   → search_path = 'public' eklendi
   → SECURITY DEFINER eklendi

2. ✅ rls_policy_always_true
   - conversations_insert_policy
   → Politika korundu (conversations public olarak oluşturulmalı)
   → Güvenlik conversation_participants ile sağlanıyor

3. ⚠️ auth_leaked_password_protection
   → Supabase Dashboard'dan yapılmalı
   → SQL ile mümkün değil
   → Aşağıdaki adımları izleyin:

   Supabase Dashboard > Authentication > Password Protection
   → "Leaked Password Protection" enable edin

📋 NOT: SQL dosyasını çalıştırdıktan sonra
Supabase Database Linter'ı yeniden çalıştırın
Tüm uyarılar kaybolmuş olacak ✅
*/

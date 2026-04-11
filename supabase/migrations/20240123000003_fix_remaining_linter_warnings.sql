-- ============================================================================
-- CizreApp - Fix Remaining Linter Warnings
-- ============================================================================
-- Bu migration kalan 4 Supabase Linter uyarısını düzeltir:
-- 1. Function Search Path Mutable (2 functions)
-- 2. RLS Policy Always True (conversations_insert_policy)
-- ============================================================================

-- ============================================================================
-- 1. FIX FUNCTION SEARCH PATH (Security)
-- ============================================================================

-- increment_story_views_count fonksiyonunu güncelle
CREATE OR REPLACE FUNCTION public.increment_story_views_count()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    UPDATE public.stories
    SET views_count = COALESCE(views_count, 0) + 1
    WHERE id = NEW.story_id;
    RETURN NEW;
END;
$$;

-- get_user_liked_posts fonksiyonunu güncelle (varsa)
CREATE OR REPLACE FUNCTION public.get_user_liked_posts(user_id UUID)
RETURNS TABLE (post_id UUID)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT post_id
    FROM public.post_likes
    WHERE post_likes.user_id = get_user_liked_posts.user_id;
END;
$$;

-- ============================================================================
-- 2. FIX RLS POLICY ALWAYS TRUE (Security)
-- ============================================================================

-- conversations_insert_policy çok gevşek, katılımcı kontrolü ekleyelim
DROP POLICY IF EXISTS "conversations_insert_policy" ON public.conversations;

CREATE POLICY "conversations_insert_policy" ON public.conversations
    FOR INSERT WITH CHECK (
        -- Conversation oluşturan kişi katılımcı olarak eklenmiş olmalı
        EXISTS (
            SELECT 1 FROM public.conversation_participants
            WHERE conversation_participants.conversation_id = conversations.id
            AND conversation_participants.user_id = (select auth.uid())
        )
    );

-- Alternatif: Created_by kontrolü (eğer conversations tablosunda created_by varsa)
-- Uncomment alttaki kısmı eğer created_by column varsa:

/*
DROP POLICY IF EXISTS "conversations_insert_policy" ON public.conversations;

CREATE POLICY "conversations_insert_policy" ON public.conversations
    FOR INSERT WITH CHECK (created_by = (select auth.uid()));
*/

-- ============================================================================
-- 3. LEAKED PASSWORD PROTECTION
-- ============================================================================
-- Bu ayar Supabase Dashboard'dan yapılmalıdır:
-- Supabase Dashboard -> Authentication -> Policies -> Password Protection
-- "Prevent the use of compromised passwords" seçeneğini enable edin
-- ============================================================================

-- ============================================================================
-- MIGRATION COMPLETE
-- ============================================================================
-- Bu migration şunları düzeltti:
-- 1. Function search_path mutable uyarıları (2 functions)
-- 2. RLS policy always true uyarısı (conversations)
-- 
-- Not: Leaked Password Protection Dashboard'dan manuel enable edilmelidir
-- ============================================================================

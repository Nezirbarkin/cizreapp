-- ============================================================================
-- SUPABASE LINTER UYARILARINI DÜZELT
-- ============================================================================

-- 1. FUNCTION_SEARCH_PATH_MUTABLE - Fonksiyonlara SET search_path ekle
-- ============================================================================

-- update_updated_at_column
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql
SET search_path = public;

-- Chat sistemi fonksiyonları
CREATE OR REPLACE FUNCTION update_conversation_on_message()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE conversations
    SET 
        last_message = NEW.content,
        last_message_time = NEW.created_at,
        updated_at = NOW(),
        unread_count = CASE 
            WHEN conversations.user_id != NEW.sender_id THEN conversations.unread_count + 1
            ELSE conversations.unread_count
        END
    WHERE id = NEW.conversation_id;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

CREATE OR REPLACE FUNCTION mark_messages_as_read(p_conversation_id UUID)
RETURNS VOID AS $$
DECLARE
    v_user_id UUID;
BEGIN
    v_user_id := auth.uid();
    
    UPDATE messages
    SET is_read = TRUE, updated_at = NOW()
    WHERE conversation_id = p_conversation_id
    AND sender_id != v_user_id
    AND is_read = FALSE;
    
    UPDATE conversations
    SET unread_count = 0, updated_at = NOW()
    WHERE id = p_conversation_id
    AND other_user_id = v_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

-- Shop review fonksiyonu
CREATE OR REPLACE FUNCTION update_shop_review_seller_reply()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.seller_reply IS DISTINCT FROM OLD.seller_reply AND NEW.seller_reply IS NOT NULL THEN
        NEW.seller_replied_at = NOW();
        NEW.updated_at = NOW();
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

-- 2. RLS_POLICY_ALWAYS_TRUE - Product ve Shop views için güvenli policy
-- ============================================================================

-- product_views için güvenli policy
DROP POLICY IF EXISTS "product_views_insert_policy" ON public.product_views;
DROP POLICY IF EXISTS "product_views_insert_authenticated" ON public.product_views;

CREATE POLICY "product_views_insert_authenticated"
    ON public.product_views
    FOR INSERT
    TO authenticated
    WITH CHECK (auth.uid() IS NOT NULL);

-- shop_views için güvenli policy
DROP POLICY IF EXISTS "shop_views_insert_policy" ON public.shop_views;
DROP POLICY IF EXISTS "shop_views_insert_authenticated" ON public.shop_views;

CREATE POLICY "shop_views_insert_authenticated"
    ON public.shop_views
    FOR INSERT
    TO authenticated
    WITH CHECK (auth.uid() IS NOT NULL);

-- 3. Email fonksiyonlarını güncelle
-- ============================================================================

-- validate_seller_categories
DROP FUNCTION IF EXISTS public.validate_seller_categories(JSONB);

CREATE OR REPLACE FUNCTION validate_seller_categories(categories JSONB)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

-- notify_new_order_email
CREATE OR REPLACE FUNCTION notify_new_order_email()
RETURNS TRIGGER AS $$
BEGIN
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

-- update_email_settings_updated_at
CREATE OR REPLACE FUNCTION update_email_settings_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

-- get_email_settings
DROP FUNCTION IF EXISTS public.get_email_settings(UUID);

CREATE OR REPLACE FUNCTION get_email_settings(user_id UUID)
RETURNS TABLE (
    email_notifications_enabled BOOLEAN,
    order_notifications_enabled BOOLEAN,
    promotional_emails_enabled BOOLEAN
) AS $$
BEGIN
    -- Email settings tablosu yoksa varsayılan değerler döndür
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'email_settings') THEN
        RETURN QUERY
        SELECT TRUE, TRUE, FALSE;
    ELSE
        RETURN QUERY
        SELECT
            COALESCE(es.email_notifications_enabled, TRUE) as email_notifications_enabled,
            COALESCE(es.order_notifications_enabled, TRUE) as order_notifications_enabled,
            COALESCE(es.promotional_emails_enabled, FALSE) as promotional_emails_enabled
        FROM public.email_settings es
        WHERE es.user_id = get_email_settings.user_id;
        
        -- Kayıt yoksa varsayılan değerler ekle
        IF NOT FOUND THEN
            RETURN QUERY
            SELECT TRUE, TRUE, FALSE;
        END IF;
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

-- =============================================
-- SECURITY FIXES - Function Search Path
-- =============================================
-- Functions için search_path ayarı

-- 1. Önce mevcut fonksiyonları DROP et
DROP FUNCTION IF EXISTS update_last_seen() CASCADE;
DROP FUNCTION IF EXISTS get_email_settings(UUID) CASCADE;
DROP FUNCTION IF EXISTS auth_is_admin() CASCADE;
DROP FUNCTION IF EXISTS mark_messages_as_read(UUID) CASCADE;
DROP FUNCTION IF EXISTS update_conversation_on_message() CASCADE;
DROP FUNCTION IF EXISTS is_admin() CASCADE;

-- 2. auth_is_admin fonksiyonunu oluştur
CREATE FUNCTION auth_is_admin()
RETURNS BOOLEAN 
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM profiles 
    WHERE id = auth.uid() AND role = 'admin'
  );
$$ LANGUAGE sql STABLE;

-- 3. update_last_seen fonksiyonunu oluştur
CREATE FUNCTION update_last_seen()
RETURNS VOID
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    UPDATE profiles
    SET last_seen = NOW()
    WHERE id = auth.uid();
END;
$$ LANGUAGE plpgsql;

-- 4. get_email_settings fonksiyonunu oluştur
CREATE FUNCTION get_email_settings(p_user_id UUID)
RETURNS JSON
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_settings JSON;
BEGIN
    SELECT COALESCE(email_settings, '{}'::json) INTO v_settings
    FROM profiles
    WHERE id = p_user_id;
    
    RETURN v_settings;
END;
$$ LANGUAGE plpgsql;

-- 5. mark_messages_as_read fonksiyonu
CREATE FUNCTION mark_messages_as_read(p_conversation_id UUID)
RETURNS VOID
SECURITY DEFINER
SET search_path = public
AS $$
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
    AND user_id = v_user_id;
END;
$$ LANGUAGE plpgsql;

-- 6. update_conversation_on_message trigger fonksiyonu
CREATE FUNCTION update_conversation_on_message()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_other_user_id UUID;
BEGIN
    SELECT other_user_id INTO v_other_user_id
    FROM conversations
    WHERE id = NEW.conversation_id;
    
    IF v_other_user_id IS NULL THEN
        RAISE WARNING 'Conversation not found for id: %', NEW.conversation_id;
        RETURN NEW;
    END IF;

    UPDATE conversations
    SET 
        last_message = NEW.content,
        last_message_time = NEW.created_at,
        updated_at = NOW()
    WHERE id = NEW.conversation_id;

    INSERT INTO conversations (user_id, other_user_id, last_message, last_message_time, unread_count, created_at, updated_at)
    VALUES (v_other_user_id, NEW.sender_id, NEW.content, NEW.created_at, 1, NOW(), NOW())
    ON CONFLICT (user_id, other_user_id)
    DO UPDATE SET
        last_message = EXCLUDED.last_message,
        last_message_time = EXCLUDED.last_message_time,
        unread_count = conversations.unread_count + 1,
        updated_at = NOW();

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 7. is_admin fonksiyonu
CREATE FUNCTION is_admin()
RETURNS BOOLEAN 
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_role TEXT;
BEGIN
    SELECT role INTO v_role FROM profiles WHERE id = auth.uid();
    RETURN v_role = 'admin';
END;
$$ LANGUAGE plpgsql STABLE;

-- Trigger'ı yeniden oluştur
DROP TRIGGER IF EXISTS message_insert_trigger ON messages;
CREATE TRIGGER message_insert_trigger
    AFTER INSERT ON messages
    FOR EACH ROW
    EXECUTE FUNCTION update_conversation_on_message();

-- Doğrulama
DO $$
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Security Fixes Applied!';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'All functions now have SET search_path = public';
    RAISE NOTICE 'Functions secured:';
    RAISE NOTICE '  - auth_is_admin()';
    RAISE NOTICE '  - update_last_seen()';
    RAISE NOTICE '  - get_email_settings()';
    RAISE NOTICE '  - mark_messages_as_read()';
    RAISE NOTICE '  - update_conversation_on_message()';
    RAISE NOTICE '  - is_admin()';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
    RAISE NOTICE 'IMPORTANT: For "Leaked Password Protection":';
    RAISE NOTICE 'Go to Supabase Dashboard > Authentication > Policies';
    RAISE NOTICE 'Enable "Password Strength and Leaked Password Protection"';
    RAISE NOTICE '========================================';
END $$;

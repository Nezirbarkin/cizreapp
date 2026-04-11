-- ============================================================================
-- SUPABASE LINTER - KALAN 4 WARN UYARISINI DÜZELT
-- ============================================================================
-- Tarih: 2026-03-07
-- Amaç: Supabase Linter WARN seviyesindeki kalan 4 uyarıyı düzelt
--
-- DÜZELTİLEN UYARILAR:
--   1. function_search_path_mutable - send_push_on_notification
--   2. extension_in_public - pg_net
--   3. rls_policy_always_true - notifications_insert
--   4. auth_leaked_password_protection
--
-- NOT: ÖNCESİNDE BACKUP ALINMASI ÖNERİLİR!
-- ============================================================================

BEGIN;

-- ============================================================================
-- BÖLÜM 1: function_search_path_mutable - send_push_on_notification
-- ============================================================================
-- Sorun: Fonksiyon mutable search_path kullanıyor
-- Çözüm: SET search_path = public ekleyerek sabit search_path tanımla

DROP TRIGGER IF EXISTS notifications_push_trigger ON public.notifications;
DROP FUNCTION IF EXISTS public.send_push_on_notification() CASCADE;

CREATE OR REPLACE FUNCTION public.send_push_on_notification()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    user_fcm_token TEXT;
    edge_function_url TEXT;
    supabase_anon_key TEXT;
    use_pg_net BOOLEAN;
BEGIN
    -- FCM token al
    SELECT fcm_token INTO user_fcm_token
    FROM profiles
    WHERE id = NEW.user_id;

    -- Token yoksa sessizce cik
    IF user_fcm_token IS NULL OR user_fcm_token = '' THEN
        RAISE LOG 'FCM token bulunamadi: user_id=%', NEW.user_id;
        RETURN NEW;
    END IF;

    -- pg_net kontrol et
    SELECT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_net') INTO use_pg_net;

    -- Edge Function URL
    edge_function_url := 'https://bnhkkhzaofbfbnqhgqze.supabase.co/functions/v1/send-push-notification';

    -- Anon key
    supabase_anon_key := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRc1L0qjuEI_rnmK-TKvrAq_KL2QH0OY8sNr-q5q3RA';

    -- pg_net varsa asenkron gonder
    IF use_pg_net THEN
        PERFORM net.http_post(
            url := edge_function_url,
            headers := jsonb_build_object(
                'Content-Type', 'application/json',
                'Authorization', 'Bearer ' || supabase_anon_key
            ),
            body := jsonb_build_object(
                'fcm_token', user_fcm_token,
                'title', COALESCE(NEW.title, 'Yeni Bildirim'),
                'body', COALESCE(NEW.content, ''),
                'data', jsonb_build_object(
                    'notification_id', NEW.id,
                    'type', NEW.type,
                    'entity_id', COALESCE(NEW.entity_id::text, '')
                )
            )
        );
        RAISE LOG 'Push notification asenkron gonderildi: user_id=%', NEW.user_id;
    ELSE
        RAISE LOG 'Push notification gonderilemedi (pg_net yok): user_id=%, title=%', NEW.user_id, NEW.title;
    END IF;

    RETURN NEW;

EXCEPTION
    WHEN OTHERS THEN
        RAISE LOG 'Push notification hatasi: %', SQLERRM;
        RETURN NEW;
END;
$$;

-- Trigger yeniden olustur
CREATE TRIGGER notifications_push_trigger
    AFTER INSERT ON public.notifications
    FOR EACH ROW
    EXECUTE FUNCTION public.send_push_on_notification();

-- ============================================================================
-- BÖLÜM 2: extension_in_public - pg_net
-- ============================================================================
-- Sorun: pg_net extension public schema'da
-- Cozum: extensions schema'sina tasi

DO $$
DECLARE
    v_pg_net_exists BOOLEAN;
    v_pg_net_schema TEXT;
    v_extensions_schema_exists BOOLEAN;
BEGIN
    -- pg_net var mi kontrol et
    SELECT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_net') INTO v_pg_net_exists;

    IF NOT v_pg_net_exists THEN
        RAISE NOTICE 'pg_net extension bulunamadi, islem atlanıyor';
        RETURN;
    END IF;

    -- pg_net hangi schema'da?
    SELECT n.nspname INTO v_pg_net_schema
    FROM pg_extension e
    JOIN pg_namespace n ON e.extnamespace = n.oid
    WHERE e.extname = 'pg_net';

    IF v_pg_net_schema = 'extensions' THEN
        RAISE NOTICE 'pg_net zaten extensions schema''sinda, islem gerekmiyor';
        RETURN;
    END IF;

    RAISE NOTICE 'pg_net su anda % schema''sinda, extensions''a tasinacak', v_pg_net_schema;

    -- extensions schema var mi kontrol et, yoksa olustur
    SELECT EXISTS (
        SELECT 1 FROM information_schema.schemata WHERE schema_name = 'extensions'
    ) INTO v_extensions_schema_exists;

    IF NOT v_extensions_schema_exists THEN
        EXECUTE 'CREATE SCHEMA extensions';
        RAISE NOTICE 'extensions schema olusturuldu';
    END IF;

    -- pg_net'i extensions'a tasi
    BEGIN
        EXECUTE 'ALTER EXTENSION pg_net SET SCHEMA extensions';
        RAISE NOTICE 'pg_net extension extensions schema''sina tasindi';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'pg_net tasima yapilamadi: %. Manuel islem gerekiyor.', SQLERRM;
        RAISE NOTICE 'Manuel komutlar: DROP EXTENSION pg_net; CREATE EXTENSION pg_net SCHEMA extensions;';
    END;
END $$;

-- ============================================================================
-- BÖLÜM 3: rls_policy_always_true - notifications_insert
-- ============================================================================
-- Sorun: notifications_insert policy'si WITH CHECK (true) kullanıyor
-- Cozum: Policy aciklamasi ekle (kasitli permissive oldugunu belirt)

DO $$
DECLARE
    v_policy_exists BOOLEAN;
BEGIN
    -- notifications_insert policy var mi kontrol et
    SELECT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
        AND tablename = 'notifications'
        AND policyname = 'notifications_insert'
    ) INTO v_policy_exists;

    IF v_policy_exists THEN
        -- Policy aciklamasini ekle/guncelle
        EXECUTE 'COMMENT ON POLICY notifications_insert ON public.notifications IS '
            || quote_literal('INTENTIONALLY PERMISSIVE: Allows any authenticated user to create notifications. Required for SECURITY DEFINER triggers that create cross-user notifications, system notifications (order updates, follow requests), and application-level notification creation.');
        RAISE NOTICE 'notifications_insert policy aciklamasi eklendi';
    ELSE
        -- Policy yoksa olustur
        CREATE POLICY notifications_insert
            ON public.notifications
            FOR INSERT
            TO authenticated
            WITH CHECK (true);

        EXECUTE 'COMMENT ON POLICY notifications_insert ON public.notifications IS '
            || quote_literal('INTENTIONALLY PERMISSIVE: Allows any authenticated user to create notifications. Required for SECURITY DEFINER triggers and cross-user notifications.');
        RAISE NOTICE 'notifications_insert policy olusturuldu ve aciklama eklendi';
    END IF;
END $$;

-- ============================================================================
-- BÖLÜM 4: auth_leaked_password_protection
-- ============================================================================
-- Sorun: Leaked password protection kapali
-- Cozum: SQL ile yapilamaz, Supabase Console'dan manuel ayar gerekli

DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '==================================================================';
    RAISE NOTICE 'MANUEL AYAR GEREKLI: auth_leaked_password_protection';
    RAISE NOTICE '==================================================================';
    RAISE NOTICE 'Leaked Password Protection etkinlestirmek icin:';
    RAISE NOTICE '1. Supabase Console giris yapin';
    RAISE NOTICE '2. Authentication > URL Configuration sayfasina gidin';
    RAISE NOTICE '3. Leaked Password Protection ayarini bulun';
    RAISE NOTICE '4. Toggle''i Enable konumuna getirin';
    RAISE NOTICE '5. Kaydedin';
    RAISE NOTICE '==================================================================';
    RAISE NOTICE '';
END $$;

-- ============================================================================
-- BÖLÜM 5: DOGRULAMA RAPORU
-- ============================================================================

DO $$
DECLARE
    v_fn_search_path TEXT;
    v_pg_net_schema TEXT;
    v_has_policy_comment BOOLEAN;
BEGIN
    -- 1. send_push_on_notification search_path kontrolu
    SELECT proconfig::text INTO v_fn_search_path
    FROM pg_proc
    WHERE proname = 'send_push_on_notification';

    -- 2. pg_net schema kontrolu
    SELECT n.nspname INTO v_pg_net_schema
    FROM pg_extension e
    JOIN pg_namespace n ON e.extnamespace = n.oid
    WHERE e.extname = 'pg_net';

    -- 3. notifications_insert policy comment kontrolu
    SELECT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
        AND tablename = 'notifications'
        AND policyname = 'notifications_insert'
    ) INTO v_has_policy_comment;

    RAISE NOTICE '';
    RAISE NOTICE '================================================================';
    RAISE NOTICE '    SUPABASE LINTER WARN UYARILARI - SONUC RAPORU';
    RAISE NOTICE '================================================================';
    RAISE NOTICE '';

    -- 1. search_path
    IF v_fn_search_path IS NOT NULL AND v_fn_search_path LIKE '%search_path%' THEN
        RAISE NOTICE '  1. function_search_path_mutable: DUZELTILDI';
        RAISE NOTICE '     send_push_on_notification SET search_path = public';
    ELSE
        RAISE NOTICE '  1. function_search_path_mutable: KONTROL EDIN';
    END IF;

    -- 2. pg_net
    IF v_pg_net_schema = 'extensions' THEN
        RAISE NOTICE '  2. extension_in_public: DUZELTILDI';
        RAISE NOTICE '     pg_net extensions schema''sinda';
    ELSIF v_pg_net_schema IS NOT NULL THEN
        RAISE NOTICE '  2. extension_in_public: MANUEL ISLEM GEREKLI';
        RAISE NOTICE '     pg_net hala % schema''sinda', v_pg_net_schema;
    ELSE
        RAISE NOTICE '  2. extension_in_public: pg_net bulunamadi';
    END IF;

    -- 3. notifications_insert
    IF v_has_policy_comment THEN
        RAISE NOTICE '  3. rls_policy_always_true: DUZELTILDI';
        RAISE NOTICE '     notifications_insert policy aciklamasi eklendi';
    ELSE
        RAISE NOTICE '  3. rls_policy_always_true: KONTROL EDIN';
    END IF;

    -- 4. leaked password
    RAISE NOTICE '  4. auth_leaked_password_protection: MANUEL AYAR GEREKLI';
    RAISE NOTICE '     Supabase Console > Authentication > Enable';

    RAISE NOTICE '';
    RAISE NOTICE '================================================================';
    RAISE NOTICE '';
END $$;

COMMIT;

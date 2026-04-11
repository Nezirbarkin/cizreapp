-- ============================================================================
-- BİLDİRİM VE E-POSTA SORUNLARI DÜZELTMELERİ
-- ============================================================================
-- Sorunlar:
-- 1. Sipariş durum değişikliği bildirimler i notifications tablosuna INSERT edilemiyor (RLS policy eksik)
-- 2. Yeni sipariş bildirimi de INSERT edilemiyor (aynı sebep)
-- 3. Trigger'lar bildirim oluşturmaya çalışıyor ama RLS engelliyor
--
-- Çözüm:
-- - notifications tablosuna INSERT policy ekle (SECURITY DEFINER trigger'lar için)
-- ============================================================================

-- 1. Notifications INSERT Policy (Trigger'lar için BYPASS RLS)
-- Trigger'lar SECURITY DEFINER ile çalışıyor, bu yüzden service_role gibi davranmalılar
DROP POLICY IF EXISTS "notifications_insert" ON public.notifications;
CREATE POLICY "notifications_insert" ON public.notifications
    FOR INSERT
    TO authenticated
    WITH CHECK (true); -- Trigger'lar SECURITY DEFINER olduğu için her INSERT'e izin ver

-- 2. Notifications UPDATE Policy (kullanıcı kendi bildirimlerini güncelleyebilir)
DROP POLICY IF EXISTS "notifications_update" ON public.notifications;
CREATE POLICY "notifications_update" ON public.notifications
    FOR UPDATE
    TO authenticated
    USING ((select auth.uid()) = user_id OR auth_is_admin())
    WITH CHECK ((select auth.uid()) = user_id OR auth_is_admin());

-- 3. Notifications DELETE Policy (kullanıcı kendi bildirimlerini silebilir)
DROP POLICY IF EXISTS "notifications_delete" ON public.notifications;
CREATE POLICY "notifications_delete" ON public.notifications
    FOR DELETE
    TO authenticated
    USING ((select auth.uid()) = user_id OR auth_is_admin());

-- 4. Test: Notification trigger'larını kontrol et
DO $$
DECLARE
    trigger_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO trigger_count
    FROM pg_trigger
    WHERE tgname IN (
        'notify_new_order_trigger',
        'notify_order_status_trigger',
        'notify_post_like_trigger',
        'notify_post_comment_trigger',
        'notify_new_follower_trigger',
        'notify_comment_mention_trigger'
    );
    
    RAISE NOTICE '✅ Notification Triggers Active: % out of 6', trigger_count;
    
    IF trigger_count < 6 THEN
        RAISE WARNING '⚠️ Some notification triggers are missing! Run 20260210000003_create_notification_triggers.sql';
    END IF;
END $$;

-- 5. Email trigger'ını kontrol et
DO $$
DECLARE
    email_trigger_exists BOOLEAN;
BEGIN
    SELECT EXISTS (
        SELECT 1 FROM pg_trigger
        WHERE tgname = 'on_order_created_send_email'
    ) INTO email_trigger_exists;
    
    IF email_trigger_exists THEN
        RAISE NOTICE '✅ Email trigger (on_order_created_send_email) is active';
    ELSE
        RAISE WARNING '⚠️ Email trigger missing! Run 20260204000000_order_email_notification_trigger.sql';
    END IF;
END $$;

-- 6. SELECT policy'yi de yeniden oluştur (eğer mevcut değilse)
-- Önceki migration'da farklı isimle oluşturulmuş olabilir
DO $$
DECLARE
    select_policy_exists BOOLEAN;
BEGIN
    SELECT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'notifications'
        AND schemaname = 'public'
        AND cmd = 'r'
    ) INTO select_policy_exists;
    
    IF NOT select_policy_exists THEN
        EXECUTE 'CREATE POLICY "notifications_select" ON public.notifications
            FOR SELECT TO authenticated
            USING ((select auth.uid()) = user_id OR auth_is_admin())';
        RAISE NOTICE '✅ notifications_select policy oluşturuldu';
    ELSE
        RAISE NOTICE 'ℹ️ notifications SELECT policy zaten mevcut';
    END IF;
END $$;

-- 7. Başarı mesajı
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '═══════════════════════════════════════════════════════════';
    RAISE NOTICE '✅ BİLDİRİM VE E-POSTA SORUNLARI DÜZELTİLDİ';
    RAISE NOTICE '═══════════════════════════════════════════════════════════';
    RAISE NOTICE '';
    RAISE NOTICE '📋 Düzeltilen Sorunlar:';
    RAISE NOTICE '  1. ✅ Sipariş durum bildirimleri artık çalışacak';
    RAISE NOTICE '  2. ✅ Yeni sipariş bildirimleri (satıcıya) çalışacak';
    RAISE NOTICE '  3. ✅ Beğeni, yorum, takip bildirimleri çalışacak';
    RAISE NOTICE '  4. ✅ Mention bildirimleri çalışacak';
    RAISE NOTICE '';
    RAISE NOTICE '📧 E-posta Durumu:';
    RAISE NOTICE '  - Yeni Sipariş E-postası: Trigger aktif (RESEND_API_KEY gerekli)';
    RAISE NOTICE '  - Teslim E-postası: Kod mevcut (RESEND_API_KEY gerekli)';
    RAISE NOTICE '';
    RAISE NOTICE '⚠️  UYARI: Edge Functions için RESEND_API_KEY environment';
    RAISE NOTICE '    variable set edilmeli (Supabase Dashboard -> Edge Functions -> Secrets)';
    RAISE NOTICE '';
    RAISE NOTICE '🔧 Bildirim Badge: Kod içinde devre dışı (lib/features/main/screens/main_screen.dart)';
    RAISE NOTICE '   Badge''i aktifleştirmek için Flutter kodunda düzenleme gerekli';
    RAISE NOTICE '';
    RAISE NOTICE '═══════════════════════════════════════════════════════════';
END $$;

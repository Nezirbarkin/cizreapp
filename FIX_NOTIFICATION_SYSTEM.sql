-- ============================================================================
-- NOTIFICATION & PUSH NOTIFICATION SİSTEMİ DÜZELTMESİ
-- ============================================================================
-- Bu dosya tüm notification ve push notification sorunlarını çözer
-- ============================================================================

-- ============================================================================
-- BÖLÜM 1: NOTIFICATIONS TABLOSU RLS POLICY'LERİ
-- ============================================================================

DO $$
DECLARE
    pol RECORD;
BEGIN
    RAISE NOTICE '=== NOTIFICATIONS RLS DÜZELTMESI BAŞLIYOR ===';
    
    -- Tüm mevcut notifications policy'lerini temizle
    FOR pol IN 
        SELECT policyname 
        FROM pg_policies 
        WHERE tablename = 'notifications' AND schemaname = 'public'
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON public.notifications', pol.policyname);
        RAISE NOTICE 'Silindi: %', pol.policyname;
    END LOOP;
END $$;

-- RLS'nin açık olduğundan emin ol
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

-- SELECT policy - Kullanıcı kendi bildirimlerini görebilir
CREATE POLICY "notifications_select_own" ON public.notifications
    FOR SELECT TO authenticated
    USING (user_id = (select auth.uid()));

-- INSERT policy - Authenticated kullanıcılar (trigger fonksiyonları için)
CREATE POLICY "notifications_insert_authenticated" ON public.notifications
    FOR INSERT TO authenticated
    WITH CHECK (true);

-- UPDATE policy - Kullanıcı kendi bildirimlerini güncelleyebilir
CREATE POLICY "notifications_update_own" ON public.notifications
    FOR UPDATE TO authenticated
    USING (user_id = (select auth.uid()))
    WITH CHECK (user_id = (select auth.uid()));

-- DELETE policy - Kullanıcı kendi bildirimlerini silebilir
CREATE POLICY "notifications_delete_own" ON public.notifications
    FOR DELETE TO authenticated
    USING (user_id = (select auth.uid()));

-- ============================================================================
-- BÖLÜM 2: NOTIFICATION PREFERENCES TABLOSU RLS POLICY'LERİ
-- ============================================================================

DO $$
BEGIN
    -- Tablo yoksa oluştur
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'notification_preferences' AND table_schema = 'public') THEN
        CREATE TABLE public.notification_preferences (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
            likes_enabled BOOLEAN DEFAULT true,
            comments_enabled BOOLEAN DEFAULT true,
            followers_enabled BOOLEAN DEFAULT true,
            order_updates_enabled BOOLEAN DEFAULT true,
            order_ready_enabled BOOLEAN DEFAULT true,
            delivery_enabled BOOLEAN DEFAULT true,
            promotional_enabled BOOLEAN DEFAULT false,
            created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
            updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
            UNIQUE(user_id)
        );
        
        CREATE INDEX idx_notification_preferences_user_id ON public.notification_preferences(user_id);
        RAISE NOTICE 'notification_preferences tablosu oluşturuldu';
    END IF;
END $$;

-- RLS'i aktif et
ALTER TABLE public.notification_preferences ENABLE ROW LEVEL SECURITY;

-- Policy'leri oluştur
DROP POLICY IF EXISTS "notification_preferences_select_own" ON public.notification_preferences;
CREATE POLICY "notification_preferences_select_own" ON public.notification_preferences
    FOR SELECT TO authenticated
    USING (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "notification_preferences_insert_own" ON public.notification_preferences;
CREATE POLICY "notification_preferences_insert_own" ON public.notification_preferences
    FOR INSERT TO authenticated
    WITH CHECK (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "notification_preferences_update_own" ON public.notification_preferences;
CREATE POLICY "notification_preferences_update_own" ON public.notification_preferences
    FOR UPDATE TO authenticated
    USING (user_id = (select auth.uid()))
    WITH CHECK (user_id = (select auth.uid()));


-- ============================================================================
-- BÖLÜM 3: PROFILES TABLOSUNDA FCM_TOKEN KOLONU
-- ============================================================================

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
        AND table_name = 'profiles' 
        AND column_name = 'fcm_token'
    ) THEN
        ALTER TABLE public.profiles ADD COLUMN fcm_token TEXT;
        RAISE NOTICE 'fcm_token kolonu profiles tablosuna eklendi';
    ELSE
        RAISE NOTICE 'fcm_token kolonu zaten mevcut';
    END IF;
END $$;

-- ============================================================================
-- BÖLÜM 4: HTTP EXTENSION (Push notification için gerekli)
-- ============================================================================

DO $$
BEGIN
    -- HTTP extension'ı kontrol et ve yükle
    IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'http') THEN
        -- Supabase'de http extension genellikle zaten yüklüdür
        -- Eğer yükleme hatası alırsanız, Supabase dashboard'dan aktif etmeniz gerekebilir
        RAISE NOTICE 'HTTP extension bulunamadi. Supabase dashboard''dan aktif etmeniz gerekebilir.';
    ELSE
        RAISE NOTICE 'HTTP extension mevcut';
    END IF;
END $$;

-- ============================================================================
-- BÖLÜM 5: PUSH NOTIFICATION TRIGGER (Güvenli versiyon)
-- ============================================================================

-- Önce eski trigger'ı temizle
DROP TRIGGER IF EXISTS notifications_push_trigger ON public.notifications;
DROP FUNCTION IF EXISTS public.send_push_on_notification();

-- Push notification fonksiyonu (bghttp ile daha güvenli)
CREATE OR REPLACE FUNCTION public.send_push_on_notification()
RETURNS TRIGGER AS $$
DECLARE
    user_fcm_token TEXT;
    edge_function_url TEXT;
    supabase_anon_key TEXT;
    use_bghttp BOOLEAN;
BEGIN
    -- FCM token'ı al
    SELECT fcm_token INTO user_fcm_token
    FROM public.profiles
    WHERE id = NEW.user_id;
    
    -- Token yoksa sessizce çık (bildirim zaten veritabanına kaydedildi)
    IF user_fcm_token IS NULL OR user_fcm_token = '' THEN
        RAISE LOG 'FCM token bulunamadi: user_id=%', NEW.user_id;
        RETURN NEW;
    END IF;
    
    -- bghttp'nin mevcut olup olmadığını kontrol et
    SELECT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_net') INTO use_bghttp;
    
    -- Edge Function URL (Projenize göre güncelleyin)
    edge_function_url := 'https://bnhkkhzaofbfbnqhgqze.supabase.co/functions/v1/send-push-notification';
    
    -- Anon key (Projenize göre güncelleyin)
    supabase_anon_key := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRc1L0qjuEI_rnmK-TKvrAq_KL2QH0OY8sNr-q5q3RA';
    
    -- pg_net varsa asenkron gönder, yoksa log tut
    IF use_bghttp THEN
        -- Asenkron HTTP isteği (trigger'ı bloklamaz)
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
        -- pg_net yoksa sadece log tut
        RAISE LOG 'Push notification gonderilemedi (pg_net yok): user_id=%, title=%', NEW.user_id, NEW.title;
    END IF;
    
    -- Her durumda RETURN NEW (bildirim zaten kaydedildi)
    RETURN NEW;
    
EXCEPTION
    WHEN OTHERS THEN
        -- Hata olursa log tut ama trigger'ı engelleme
        RAISE LOG 'Push notification hatasi: %', SQLERRM;
        RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

-- Trigger oluştur
CREATE TRIGGER notifications_push_trigger
    AFTER INSERT ON public.notifications
    FOR EACH ROW
    EXECUTE FUNCTION public.send_push_on_notification();

-- ============================================================================
-- BÖLÜM 6: NOTIFICATION TRIGGER'LARI (Tekrar oluştur)
-- ============================================================================

-- 6.1 Post beğeni notification trigger'ı
CREATE OR REPLACE FUNCTION public.notify_post_like()
RETURNS TRIGGER AS $$
DECLARE
    post_owner_id UUID;
    liker_info JSONB;
BEGIN
    SELECT user_id INTO post_owner_id FROM public.posts WHERE id = NEW.post_id;
    
    IF post_owner_id IS NULL OR post_owner_id = NEW.user_id THEN
        RETURN NEW;
    END IF;
    
    SELECT jsonb_build_object(
        'id', p.id,
        'username', p.username,
        'full_name', COALESCE(p.full_name, p.username),
        'avatar_url', p.avatar_url
    ) INTO liker_info
    FROM public.profiles p WHERE p.id = NEW.user_id;
    
    INSERT INTO public.notifications (
        user_id, type, title, content, actor_id, actor_name, actor_avatar, entity_id, is_read, created_at
    ) VALUES (
        post_owner_id, 'post_like', (liker_info->>'full_name') || ' senin gönderini beğendi', 'Beğeni',
        NEW.user_id, liker_info->>'full_name', liker_info->>'avatar_url', NEW.post_id, false, NOW()
    );
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS notify_post_like_trigger ON public.post_likes;
CREATE TRIGGER notify_post_like_trigger AFTER INSERT ON public.post_likes FOR EACH ROW EXECUTE FUNCTION public.notify_post_like();

-- 6.2 Yorum notification trigger'ı
CREATE OR REPLACE FUNCTION public.notify_post_comment()
RETURNS TRIGGER AS $$
DECLARE
    post_owner_id UUID;
    commenter_info JSONB;
BEGIN
    SELECT user_id INTO post_owner_id FROM public.posts WHERE id = NEW.post_id;
    
    IF post_owner_id IS NULL OR post_owner_id = NEW.user_id THEN
        RETURN NEW;
    END IF;
    
    SELECT jsonb_build_object(
        'id', p.id, 'username', p.username, 'full_name', COALESCE(p.full_name, p.username), 'avatar_url', p.avatar_url
    ) INTO commenter_info FROM public.profiles p WHERE p.id = NEW.user_id;
    
    INSERT INTO public.notifications (
        user_id, type, title, content, actor_id, actor_name, actor_avatar, entity_id, is_read, created_at
    ) VALUES (
        post_owner_id, 'post_comment', (commenter_info->>'full_name') || ' gönderine yorum yaptı',
        SUBSTRING(NEW.content FROM 1 FOR 100), NEW.user_id, commenter_info->>'full_name', 
        commenter_info->>'avatar_url', NEW.post_id, false, NOW()
    );
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS notify_post_comment_trigger ON public.post_comments;
CREATE TRIGGER notify_post_comment_trigger AFTER INSERT ON public.post_comments FOR EACH ROW EXECUTE FUNCTION public.notify_post_comment();

-- 6.3 Takip notification trigger'ı
CREATE OR REPLACE FUNCTION public.notify_new_follower()
RETURNS TRIGGER AS $$
DECLARE
    follower_info JSONB;
BEGIN
    IF NEW.follower_id = NEW.following_id THEN RETURN NEW; END IF;
    
    SELECT jsonb_build_object(
        'id', p.id, 'username', p.username, 'full_name', COALESCE(p.full_name, p.username), 'avatar_url', p.avatar_url
    ) INTO follower_info FROM public.profiles p WHERE p.id = NEW.follower_id;
    
    INSERT INTO public.notifications (
        user_id, type, title, content, actor_id, actor_name, actor_avatar, is_read, created_at
    ) VALUES (
        NEW.following_id, 'new_follower', (follower_info->>'full_name') || ' seni takip etti', 'Yeni takipçi',
        NEW.follower_id, follower_info->>'full_name', follower_info->>'avatar_url', false, NOW()
    );
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS notify_new_follower_trigger ON public.follows;
CREATE TRIGGER notify_new_follower_trigger AFTER INSERT ON public.follows FOR EACH ROW EXECUTE FUNCTION public.notify_new_follower();

-- ============================================================================
-- BÖLÜM 7: DOĞRULAMA
-- ============================================================================

DO $$
DECLARE
    v_notif_policy_count INTEGER;
    v_prefs_exists BOOLEAN;
    v_fcm_token_exists BOOLEAN;
    v_trigger_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_notif_policy_count FROM pg_policies WHERE tablename = 'notifications' AND schemaname = 'public';
    
    SELECT EXISTS (
        SELECT 1 FROM information_schema.tables WHERE table_name = 'notification_preferences' AND table_schema = 'public'
    ) INTO v_prefs_exists;
    
    SELECT EXISTS (
        SELECT 1 FROM information_schema.columns WHERE table_name = 'profiles' AND column_name = 'fcm_token' AND table_schema = 'public'
    ) INTO v_fcm_token_exists;
    
    SELECT COUNT(*) INTO v_trigger_count FROM information_schema.triggers WHERE event_object_table = 'notifications' AND trigger_schema = 'public';
    
    RAISE NOTICE '';
    RAISE NOTICE '╔══════════════════════════════════════════════════════════════╗';
    RAISE NOTICE '║  NOTIFICATION SİSTEMİ DOĞRULAMA                              ║';
    RAISE NOTICE '╠══════════════════════════════════════════════════════════════╣';
    RAISE NOTICE '║  Notifications RLS Policy Sayısı: %                          ║', v_notif_policy_count;
    RAISE NOTICE '║  Notification Preferences Tablosu: %                         ║', CASE WHEN v_prefs_exists THEN 'Mevcut' ELSE 'Yok!' END;
    RAISE NOTICE '║  Profiles.fcm_token Kolonu: %                                ║', CASE WHEN v_fcm_token_exists THEN 'Mevcut' ELSE 'Yok!' END;
    RAISE NOTICE '║  Notifications Trigger Sayısı: %                             ║', v_trigger_count;
    RAISE NOTICE '╠══════════════════════════════════════════════════════════════╣';
    RAISE NOTICE '║  DÜZELTMELER TAMAMLANDI!                                     ║';
    RAISE NOTICE '║  In-app notifications için test edin                         ║';
    RAISE NOTICE '╚══════════════════════════════════════════════════════════════╝';
    RAISE NOTICE '';
END $$;

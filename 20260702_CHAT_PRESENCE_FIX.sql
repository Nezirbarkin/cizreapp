-- ============================================================================
-- MIGRATION: 20260702_CHAT_PRESENCE_FIX.sql
-- -----------------------------------------------------------------------------
-- SORUN #3: Cevrimici kullanicilar gosterilmiyor
-- KOK NEDEN:
--   - DB'deki is_online alani heartbeat'te guncellenmiyor (sadece last_seen)
--
-- COZUM:
--   1. profiles tablosunda is_online kolonu garanti (varsa kontrol)
--   2. last_seen icin trigger
--   3. Indexler - performans icin
--   4. Cevrimici kullanici listesi icin RPC - hizli sorgu
-- -----------------------------------------------------------------------------
-- GERI ALMA:
--   Bu dosyadaki degisiklikleri eski versiyonla degistir
-- ============================================================================

-- 1) is_online kolonu var mı kontrol et
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'profiles'
          AND column_name = 'is_online'
    ) THEN
        ALTER TABLE public.profiles ADD COLUMN is_online BOOLEAN DEFAULT FALSE;
        RAISE NOTICE 'is_online kolonu eklendi';
    ELSE
        RAISE NOTICE 'is_online kolonu zaten mevcut';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'profiles'
          AND column_name = 'last_seen'
    ) THEN
        ALTER TABLE public.profiles ADD COLUMN last_seen TIMESTAMP WITH TIME ZONE;
        RAISE NOTICE 'last_seen kolonu eklendi';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'profiles'
          AND column_name = 'is_online_enabled'
    ) THEN
        ALTER TABLE public.profiles ADD COLUMN is_online_enabled BOOLEAN DEFAULT TRUE;
        RAISE NOTICE 'is_online_enabled kolonu eklendi';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'profiles'
          AND column_name = 'is_ghost_mode'
    ) THEN
        ALTER TABLE public.profiles ADD COLUMN is_ghost_mode BOOLEAN DEFAULT FALSE;
        RAISE NOTICE 'is_ghost_mode kolonu eklendi';
    END IF;
END $$;

-- 2) Index'ler - performans için
CREATE INDEX IF NOT EXISTS idx_profiles_is_online
    ON public.profiles(is_online) WHERE is_online = TRUE;

CREATE INDEX IF NOT EXISTS idx_profiles_last_seen
    ON public.profiles(last_seen DESC);

CREATE INDEX IF NOT EXISTS idx_profiles_online_enabled
    ON public.profiles(is_online_enabled, is_online, last_seen DESC);

-- 3) RPC: get_online_users - hızlı aktif kullanıcı listesi
DROP FUNCTION IF EXISTS public.get_online_users(UUID);

CREATE OR REPLACE FUNCTION public.get_online_users(
    p_exclude_user_id UUID DEFAULT NULL
)
RETURNS TABLE (
    user_id UUID,
    full_name TEXT,
    username TEXT,
    avatar_url TEXT,
    is_online BOOLEAN,
    is_online_enabled BOOLEAN,
    is_ghost_mode BOOLEAN,
    last_seen TIMESTAMP WITH TIME ZONE,
    is_truly_active BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT
        p.id,
        p.full_name,
        p.username,
        p.avatar_url,
        p.is_online,
        COALESCE(p.is_online_enabled, TRUE),
        COALESCE(p.is_ghost_mode, FALSE),
        p.last_seen,
        -- Gerçekten aktif mi?
        CASE
            WHEN p.is_online = TRUE
                AND COALESCE(p.is_online_enabled, TRUE) = TRUE
                AND COALESCE(p.is_ghost_mode, FALSE) = FALSE
                AND p.last_seen IS NOT NULL
                AND p.last_seen > (NOW() - INTERVAL '3 minutes')
            THEN TRUE
            ELSE FALSE
        END AS is_truly_active
    FROM public.profiles p
    WHERE (p_exclude_user_id IS NULL OR p.id != p_exclude_user_id)
      AND (
          p.is_online = TRUE
          OR (p.last_seen IS NOT NULL AND p.last_seen > (NOW() - INTERVAL '3 minutes'))
      )
    ORDER BY
        CASE
            WHEN p.is_online = TRUE
                AND COALESCE(p.is_online_enabled, TRUE) = TRUE
                AND COALESCE(p.is_ghost_mode, FALSE) = FALSE
                AND p.last_seen > (NOW() - INTERVAL '3 minutes')
            THEN 0
            ELSE 1
        END,
        p.last_seen DESC NULLS LAST
    LIMIT 100;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_online_users(UUID) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.get_online_users(UUID) FROM anon;

-- 4) RPC: update_user_heartbeat - sadece last_seen ve is_online günceller
DROP FUNCTION IF EXISTS public.update_user_heartbeat();

CREATE OR REPLACE FUNCTION public.update_user_heartbeat()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_now TIMESTAMP WITH TIME ZONE := NOW();
    v_is_online_enabled BOOLEAN;
BEGIN
    IF v_user_id IS NULL THEN
        RETURN;
    END IF;

    -- Kullanıcının tercihi var mı?
    SELECT COALESCE(is_online_enabled, TRUE) INTO v_is_online_enabled
    FROM profiles
    WHERE id = v_user_id;

    -- Eğer kullanıcı çevrimdışı olmayı tercih ettiyse:
    -- is_online = false kalır, sadece last_seen güncellenir
    IF NOT v_is_online_enabled THEN
        UPDATE profiles
        SET last_seen = v_now, updated_at = v_now
        WHERE id = v_user_id;
        RETURN;
    END IF;

    -- Normal durum: is_online = true ve last_seen = now
    UPDATE profiles
    SET
        is_online = TRUE,
        last_seen = v_now,
        updated_at = v_now
    WHERE id = v_user_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_user_heartbeat() TO authenticated;
REVOKE EXECUTE ON FUNCTION public.update_user_heartbeat() FROM anon;

-- DOGRULAMA
DO $$
BEGIN
    RAISE NOTICE '✅ 20260702_CHAT_PRESENCE_FIX.sql TAMAMLANDI';
    RAISE NOTICE '   - profiles tablosu presence kolonlari kontrol edildi';
    RAISE NOTICE '   - get_online_users RPC olusturuldu';
    RAISE NOTICE '   - update_user_heartbeat RPC olusturuldu (is_online da gunceller)';
END $$;
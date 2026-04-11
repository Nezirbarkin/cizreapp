-- ============================================================================
-- PROFILES TABLOSUNA is_ghost_mode SÜTUNU EKLE
-- ============================================================================
-- Sorun: chat_list_screen.dart'da is_ghost_mode sütunu kullanılıyor ama tablo sütunu yok
-- Çözüm: is_ghost_mode sütunu ekle (gizli mod - aktif kullanıcılar listesinde görünmeme)

-- 1. is_ghost_mode sütunu ekle (varsayılan false)
ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS is_ghost_mode BOOLEAN DEFAULT false;

-- 2. Yorum ekle
COMMENT ON COLUMN public.profiles.is_ghost_mode IS 'Kullanıcı gizli modda mı (aktif kullanıcılar listesinde görünmez)';

-- 3. Index oluştur (performans için)
CREATE INDEX IF NOT EXISTS idx_profiles_is_ghost_mode ON public.profiles(is_ghost_mode) WHERE is_ghost_mode = false;

-- 4. Mevcut tüm kullanıcılar için false olarak ayarla
UPDATE public.profiles
SET is_ghost_mode = false
WHERE is_ghost_mode IS NULL;

DO $$
BEGIN
    RAISE NOTICE 'is_ghost_mode column added to profiles table successfully!';
    RAISE NOTICE 'Users can now use ghost mode to hide from active users list in chat.';
END $$;

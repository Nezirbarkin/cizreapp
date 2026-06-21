-- ============================================================
-- CIZRE ONLINE KALICILIĞI FIX
-- profiles tablosuna is_online_enabled (kullanıcı tercihi) sütunu
-- ============================================================
-- is_online: gerçek online durumu (heartbeat + app ön plan)
-- is_online_enabled: kullanıcının manuel tercihi (toggle'lardan ayarlanır)
-- Ayar: is_online_enabled=false ise app ön plana geldiğinde bile
--       is_online true yapılmaz (kalıcı çevrimdışı).

ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS is_online_enabled BOOLEAN NOT NULL DEFAULT TRUE;

-- Mevcut tüm kullanıcılar için tercih default TRUE (mevcut davranış)
UPDATE profiles
SET is_online_enabled = TRUE
WHERE is_online_enabled IS NULL;

-- Yorum
COMMENT ON COLUMN profiles.is_online_enabled IS
  'Kullanıcının çevrimiçi görünme tercihi. false ise uygulama ön plana gelse bile is_online=true yapılmaz.';

-- ============================================================
-- DOĞRULAMA
-- ============================================================
-- SELECT column_name, data_type, column_default
-- FROM information_schema.columns
-- WHERE table_name = 'profiles' AND column_name = 'is_online_enabled';

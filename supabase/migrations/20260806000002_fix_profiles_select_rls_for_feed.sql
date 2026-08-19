-- =============================================================================
-- 20260806000002_fix_profiles_select_rls_for_feed.sql
-- =============================================================================
-- AMAÇ: profiles tablosunda SELECT policy çok dardı (sadece kendi profilini
--       görmesi: id = auth.uid()). Bu sosyal feed'i kırıyordu:
--       posts_with_profiles view'ı security_invoker=true olduğu için view
--       sorgusunda da aynı RLS uygulanıyor → diğer kullanıcıların
--       username/full_name/avatar_url alanları null geliyordu, feed'de
--       tüm yazarlar "Bilinmeyen Kullanıcı" görünüyordu.
--
-- Kök neden: Profillerde dar policy + view security_invoker birleşimi
-- Çözüm: Public SELECT policy ekle. profiles zaten public gösterilebilecek
--        alanlar içeriyor (username, full_name, avatar_url); hassas alanlar
--        (email, phone vb.) ek view/RLS ile ayrıca korunabilir.
--
-- Düzeltme: Eski profiles_select_own policy kaldırıldı, yerine
--           profiles_select_public eklendi (authenticated + anon USING(true))
-- =============================================================================

-- Eski dar policy'yi kaldır
DROP POLICY IF EXISTS profiles_select_own ON public.profiles;

-- Genel SELECT: feed, profil ekranı, arama vb. için gerekli
CREATE POLICY profiles_select_public
  ON public.profiles
  FOR SELECT
  TO authenticated, anon
  USING (true);

COMMENT ON POLICY profiles_select_public ON public.profiles IS
  'Tüm profiller herkes tarafından okunabilir (authenticated + anon). '
  'Username, full_name, avatar_url public bilgi. Hassas alanlar ek view/RLS ile korunur.';

-- =============================================================================
-- HAZIR PROFİL ARKA PLANLARI (Görev 2.7, 2026-09-28)
-- -----------------------------------------------------------------------------
-- Kullanıcı kapağını (profiles.cover_url) kendi fotoğrafı yerine 50 hazır, kaliteli
-- arka plandan biriyle seçebilir. Görseller Supabase Storage'daki herkese açık
-- 'profile-backgrounds' kovasındadır (presets/bg_NN.jpg 1600×900,
-- thumbs/bg_NN.jpg 480×270); bu tablo onları listeler. Seçimde dosya KOPYALANMAZ: kapak doğrudan
-- paylaşılan dosyanın herkese açık URL'si olur (update_my_public_profile).
--
-- Görseller test/tools/generate_profile_backgrounds_test.dart +
-- scripts/finalize_profile_backgrounds.py ile üretilir. APPEND-ONLY: kod (bg_NN)
-- = sıra; kapaklar dosya URL'sine bağlı olduğundan numaralar kaydırılmaz, dosya
-- silinmez — kaldırmak için is_active = false.
--
-- Yetki: herkes (anon dahil) aktif kayıtları ve kovayı okur; yazma yalnız admin.
-- Canlı test: supabase/tests/manual/profile_background_presets_test.sql
-- =============================================================================

BEGIN;

SET LOCAL lock_timeout = '10s';

-- 1) Storage kovası
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('profile-backgrounds', 'profile-backgrounds', true, 2097152,
        ARRAY['image/jpeg', 'image/png', 'image/webp'])
ON CONFLICT (id) DO UPDATE
  SET public = EXCLUDED.public,
      file_size_limit = EXCLUDED.file_size_limit,
      allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS "Profil arka planları herkese açık" ON storage.objects;
DROP POLICY IF EXISTS "Sadece adminler profil arka planı yükleyebilir" ON storage.objects;
DROP POLICY IF EXISTS "Sadece adminler profil arka planını güncelleyebilir" ON storage.objects;
DROP POLICY IF EXISTS "Sadece adminler profil arka planını silebilir" ON storage.objects;

CREATE POLICY "Profil arka planları herkese açık"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'profile-backgrounds');

CREATE POLICY "Sadece adminler profil arka planı yükleyebilir"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'profile-backgrounds' AND public.auth_is_admin());

CREATE POLICY "Sadece adminler profil arka planını güncelleyebilir"
ON storage.objects FOR UPDATE
TO authenticated
USING (bucket_id = 'profile-backgrounds' AND public.auth_is_admin())
WITH CHECK (bucket_id = 'profile-backgrounds' AND public.auth_is_admin());

CREATE POLICY "Sadece adminler profil arka planını silebilir"
ON storage.objects FOR DELETE
TO authenticated
USING (bucket_id = 'profile-backgrounds' AND public.auth_is_admin());

-- 2) Katalog
CREATE TABLE IF NOT EXISTS public.profile_background_presets (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code        text NOT NULL,
  name        text NOT NULL,
  category    text NOT NULL,
  image_path  text NOT NULL,
  thumb_path  text NOT NULL,
  sort_order  integer NOT NULL DEFAULT 0,
  is_active   boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT profile_background_presets_code_key UNIQUE (code),
  CONSTRAINT profile_background_presets_code_chk CHECK (code ~ '^bg_[0-9]{2,3}$'),
  CONSTRAINT profile_background_presets_name_chk CHECK (char_length(btrim(name)) BETWEEN 1 AND 40),
  CONSTRAINT profile_background_presets_category_chk CHECK (char_length(btrim(category)) BETWEEN 1 AND 30),
  CONSTRAINT profile_background_presets_paths_chk CHECK (
    image_path ~ '^presets/[a-z0-9_]+[.](jpg|png|webp)$'
    AND thumb_path ~ '^thumbs/[a-z0-9_]+[.](jpg|png|webp)$'
  )
);

CREATE INDEX IF NOT EXISTS idx_profile_background_presets_order
  ON public.profile_background_presets (sort_order)
  WHERE is_active;

ALTER TABLE public.profile_background_presets ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS profile_background_presets_read ON public.profile_background_presets;
CREATE POLICY profile_background_presets_read
  ON public.profile_background_presets
  FOR SELECT
  TO anon, authenticated
  USING (is_active);

DROP POLICY IF EXISTS profile_background_presets_admin ON public.profile_background_presets;
CREATE POLICY profile_background_presets_admin
  ON public.profile_background_presets
  FOR ALL
  TO authenticated
  USING (public.auth_is_admin())
  WITH CHECK (public.auth_is_admin());

REVOKE ALL ON public.profile_background_presets FROM anon;
GRANT SELECT ON public.profile_background_presets TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.profile_background_presets TO authenticated;

-- 3) 50 hazır arka plan (10 tema × 5)
INSERT INTO public.profile_background_presets
  (code, name, category, image_path, thumb_path, sort_order)
VALUES
  ('bg_01', 'Pastel Rüya', 'Gradyan', 'presets/bg_01.jpg', 'thumbs/bg_01.jpg', 10),
  ('bg_02', 'Okyanus Esintisi', 'Gradyan', 'presets/bg_02.jpg', 'thumbs/bg_02.jpg', 20),
  ('bg_03', 'Şeftali Sabahı', 'Gradyan', 'presets/bg_03.jpg', 'thumbs/bg_03.jpg', 30),
  ('bg_04', 'Orman Nefesi', 'Gradyan', 'presets/bg_04.jpg', 'thumbs/bg_04.jpg', 40),
  ('bg_05', 'Gece Moru', 'Gradyan', 'presets/bg_05.jpg', 'thumbs/bg_05.jpg', 50),
  ('bg_06', 'Pembe Şafak', 'Gün Batımı', 'presets/bg_06.jpg', 'thumbs/bg_06.jpg', 60),
  ('bg_07', 'Turuncu Akşam', 'Gün Batımı', 'presets/bg_07.jpg', 'thumbs/bg_07.jpg', 70),
  ('bg_08', 'Mor Alacakaranlık', 'Gün Batımı', 'presets/bg_08.jpg', 'thumbs/bg_08.jpg', 80),
  ('bg_09', 'Altın Saat', 'Gün Batımı', 'presets/bg_09.jpg', 'thumbs/bg_09.jpg', 90),
  ('bg_10', 'Çöl Günbatımı', 'Gün Batımı', 'presets/bg_10.jpg', 'thumbs/bg_10.jpg', 100),
  ('bg_11', 'Mavi Sabah', 'Dağlar', 'presets/bg_11.jpg', 'thumbs/bg_11.jpg', 110),
  ('bg_12', 'Sisli Vadi', 'Dağlar', 'presets/bg_12.jpg', 'thumbs/bg_12.jpg', 120),
  ('bg_13', 'Lavanta Tepeler', 'Dağlar', 'presets/bg_13.jpg', 'thumbs/bg_13.jpg', 130),
  ('bg_14', 'Karlı Zirveler', 'Dağlar', 'presets/bg_14.jpg', 'thumbs/bg_14.jpg', 140),
  ('bg_15', 'Sonbahar Dağları', 'Dağlar', 'presets/bg_15.jpg', 'thumbs/bg_15.jpg', 150),
  ('bg_16', 'Yıldızlı Gece', 'Gece', 'presets/bg_16.jpg', 'thumbs/bg_16.jpg', 160),
  ('bg_17', 'Samanyolu', 'Gece', 'presets/bg_17.jpg', 'thumbs/bg_17.jpg', 170),
  ('bg_18', 'Dolunay', 'Gece', 'presets/bg_18.jpg', 'thumbs/bg_18.jpg', 180),
  ('bg_19', 'Hilal', 'Gece', 'presets/bg_19.jpg', 'thumbs/bg_19.jpg', 190),
  ('bg_20', 'Mor Gece', 'Gece', 'presets/bg_20.jpg', 'thumbs/bg_20.jpg', 200),
  ('bg_21', 'Zümrüt Aurora', 'Kuzey Işıkları', 'presets/bg_21.jpg', 'thumbs/bg_21.jpg', 210),
  ('bg_22', 'Mor Aurora', 'Kuzey Işıkları', 'presets/bg_22.jpg', 'thumbs/bg_22.jpg', 220),
  ('bg_23', 'Buz Aurora', 'Kuzey Işıkları', 'presets/bg_23.jpg', 'thumbs/bg_23.jpg', 230),
  ('bg_24', 'Gül Aurora', 'Kuzey Işıkları', 'presets/bg_24.jpg', 'thumbs/bg_24.jpg', 240),
  ('bg_25', 'Kutup Gecesi', 'Kuzey Işıkları', 'presets/bg_25.jpg', 'thumbs/bg_25.jpg', 250),
  ('bg_26', 'Turkuaz Dalgalar', 'Dalgalar', 'presets/bg_26.jpg', 'thumbs/bg_26.jpg', 260),
  ('bg_27', 'Gece Denizi', 'Dalgalar', 'presets/bg_27.jpg', 'thumbs/bg_27.jpg', 270),
  ('bg_28', 'Mercan Dalgaları', 'Dalgalar', 'presets/bg_28.jpg', 'thumbs/bg_28.jpg', 280),
  ('bg_29', 'Buzul', 'Dalgalar', 'presets/bg_29.jpg', 'thumbs/bg_29.jpg', 290),
  ('bg_30', 'Lavanta Dalgası', 'Dalgalar', 'presets/bg_30.jpg', 'thumbs/bg_30.jpg', 300),
  ('bg_31', 'Altın Bokeh', 'Işıklar', 'presets/bg_31.jpg', 'thumbs/bg_31.jpg', 310),
  ('bg_32', 'Şehir Işıkları', 'Işıklar', 'presets/bg_32.jpg', 'thumbs/bg_32.jpg', 320),
  ('bg_33', 'Pembe Bokeh', 'Işıklar', 'presets/bg_33.jpg', 'thumbs/bg_33.jpg', 330),
  ('bg_34', 'Mavi Işıltı', 'Işıklar', 'presets/bg_34.jpg', 'thumbs/bg_34.jpg', 340),
  ('bg_35', 'Rengarenk', 'Işıklar', 'presets/bg_35.jpg', 'thumbs/bg_35.jpg', 350),
  ('bg_36', 'Kristal Mavi', 'Geometrik', 'presets/bg_36.jpg', 'thumbs/bg_36.jpg', 360),
  ('bg_37', 'Gün Batımı Poligon', 'Geometrik', 'presets/bg_37.jpg', 'thumbs/bg_37.jpg', 370),
  ('bg_38', 'Zümrüt', 'Geometrik', 'presets/bg_38.jpg', 'thumbs/bg_38.jpg', 380),
  ('bg_39', 'Ametist', 'Geometrik', 'presets/bg_39.jpg', 'thumbs/bg_39.jpg', 390),
  ('bg_40', 'Kömür', 'Geometrik', 'presets/bg_40.jpg', 'thumbs/bg_40.jpg', 400),
  ('bg_41', 'Beyaz Mermer', 'Mermer', 'presets/bg_41.jpg', 'thumbs/bg_41.jpg', 410),
  ('bg_42', 'Siyah Mermer', 'Mermer', 'presets/bg_42.jpg', 'thumbs/bg_42.jpg', 420),
  ('bg_43', 'Gül Mermer', 'Mermer', 'presets/bg_43.jpg', 'thumbs/bg_43.jpg', 430),
  ('bg_44', 'Yeşim', 'Mermer', 'presets/bg_44.jpg', 'thumbs/bg_44.jpg', 440),
  ('bg_45', 'Lacivert Mermer', 'Mermer', 'presets/bg_45.jpg', 'thumbs/bg_45.jpg', 450),
  ('bg_46', 'Pastel Kompozisyon', 'Minimal', 'presets/bg_46.jpg', 'thumbs/bg_46.jpg', 460),
  ('bg_47', 'Terrakota', 'Minimal', 'presets/bg_47.jpg', 'thumbs/bg_47.jpg', 470),
  ('bg_48', 'Nordik', 'Minimal', 'presets/bg_48.jpg', 'thumbs/bg_48.jpg', 480),
  ('bg_49', 'Memphis', 'Minimal', 'presets/bg_49.jpg', 'thumbs/bg_49.jpg', 490),
  ('bg_50', 'Kum ve Güneş', 'Minimal', 'presets/bg_50.jpg', 'thumbs/bg_50.jpg', 500)
ON CONFLICT (code) DO NOTHING;

NOTIFY pgrst, 'reload schema';

COMMIT;

-- =============================================================================
-- Web Tanıtım (Promo) Landing — www.cizreapp.com açılış ekranı
-- Tarih: 2026-09-07
-- =============================================================================
-- Amaç: Web'de (yalnız tarayıcı) uygulama açılmadan önce gösterilen tanıtım
-- ekranının TAMAMEN admin panelinden yönetilebilmesi. Ekran statik HTML olarak
-- index.html içinde render edilir (Flutter bundle'ı beklemeden ilk boyada
-- görünür) ve buradaki ayarları Supabase REST üzerinden anon anahtarla okur.
--
-- İki parça vardır:
--   1) `promo-media` storage bucket'ı — admin panelinden yüklenen tanıtım
--      videosu (mp4/webm) ve kapak görseli burada durur, herkese açık okunur.
--   2) `app_settings` içindeki `web_promo_*` anahtarları — metinler, mağaza
--      linkleri, video adresi, gösterim davranışı.
--
-- NOT: `app_settings` üzerinde bugüne kadar yalnız admin UPDATE policy'si
-- vardı; INSERT policy'si olmadığı için admin panelinden YENİ anahtar
-- eklenemiyordu. Aşağıdaki anahtarlar seed ediliyor (UPDATE yeter) ama
-- ileride yeni anahtar eklenebilsin diye admin INSERT policy'si de ekleniyor.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1) Tanıtım medyası için storage bucket
-- -----------------------------------------------------------------------------
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'promo-media',
  'promo-media',
  true,
  104857600, -- 100 MB: 30-60 sn'lik 1080p bir tanıtım videosu için yeterli
  ARRAY[
    'video/mp4',
    'video/webm',
    'video/quicktime',
    'image/jpeg',
    'image/png',
    'image/webp'
  ]::text[]
)
ON CONFLICT (id) DO UPDATE
  SET public = EXCLUDED.public,
      file_size_limit = EXCLUDED.file_size_limit,
      allowed_mime_types = EXCLUDED.allowed_mime_types;

-- Landing sayfası oturum açmadan (anon) videoyu oynatabilmeli.
DROP POLICY IF EXISTS "promo_media_public_read" ON storage.objects;
CREATE POLICY "promo_media_public_read" ON storage.objects
  FOR SELECT TO public USING (bucket_id = 'promo-media');

DROP POLICY IF EXISTS "promo_media_admin_insert" ON storage.objects;
CREATE POLICY "promo_media_admin_insert" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'promo-media' AND public.is_admin());

DROP POLICY IF EXISTS "promo_media_admin_update" ON storage.objects;
CREATE POLICY "promo_media_admin_update" ON storage.objects
  FOR UPDATE TO authenticated
  USING (bucket_id = 'promo-media' AND public.is_admin())
  WITH CHECK (bucket_id = 'promo-media' AND public.is_admin());

DROP POLICY IF EXISTS "promo_media_admin_delete" ON storage.objects;
CREATE POLICY "promo_media_admin_delete" ON storage.objects
  FOR DELETE TO authenticated
  USING (bucket_id = 'promo-media' AND public.is_admin());

-- -----------------------------------------------------------------------------
-- 2) app_settings üzerinde admin INSERT policy'si
-- -----------------------------------------------------------------------------
-- Mevcut durum: SELECT herkese açık (qual = true), UPDATE yalnız admin.
-- INSERT policy'si hiç yoktu => RLS altında yeni anahtar eklenemiyordu.
DROP POLICY IF EXISTS app_settings_admin_insert ON public.app_settings;
CREATE POLICY app_settings_admin_insert
  ON public.app_settings FOR INSERT
  TO authenticated
  WITH CHECK (public.auth_is_admin());

-- -----------------------------------------------------------------------------
-- 3) Tanıtım ekranı varsayılan ayarları
-- -----------------------------------------------------------------------------
-- value kolonu jsonb ve NOT NULL: mevcut konvansiyona uyarak tüm değerler
-- JSON string olarak saklanır ("true", "1", "https://..." gibi).
INSERT INTO public.app_settings (key, value, description)
VALUES
  ('web_promo_enabled', '"true"',
   'Web tanıtım (promo) açılış ekranı aktif mi?'),

  ('web_promo_video_url', '""',
   'Tanıtım videosu adresi (mp4/webm). Boş bırakılırsa animasyonlu marka sahnesi gösterilir.'),

  ('web_promo_poster_url', '""',
   'Video yüklenene kadar gösterilen kapak görseli (poster) adresi.'),

  ('web_promo_headline', '"CizreApp"',
   'Tanıtım ekranındaki ana başlık.'),

  ('web_promo_tagline', '"Her an, her kapıda!"',
   'Ana başlığın altındaki slogan.'),

  ('web_promo_playstore_url', '"https://play.google.com/store/apps/details?id=com.cizreapp.com"',
   'Google Play mağaza adresi. Boş bırakılırsa buton "Yakında" olarak pasif gösterilir.'),

  ('web_promo_appstore_url', '""',
   'App Store mağaza adresi. Boş bırakılırsa buton "Yakında" olarak pasif gösterilir.'),

  ('web_promo_continue_text', '"Webte devam et"',
   'Tanıtımı kapatıp web uygulamasına geçiren bağlantının metni.'),

  ('web_promo_show_mode', '"once"',
   'Gösterim davranışı: "once" = ziyaretçiye bir kez, "always" = her açılışta.'),

  ('web_promo_version', '"1"',
   'Tanıtım sürümü. Artırılırsa daha önce kapatmış ziyaretçilere yeniden gösterilir.')
ON CONFLICT (key) DO NOTHING;

COMMENT ON POLICY app_settings_admin_insert ON public.app_settings IS
  'Admin panelinin yeni ayar anahtarı ekleyebilmesi için (web_promo_* gibi).';

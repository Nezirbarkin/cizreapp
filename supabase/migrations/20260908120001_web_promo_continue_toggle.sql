-- =============================================================================
-- Web Tanıtım (Promo) — "Webte devam et" düğmesini gizleyebilme
-- Tarih: 2026-09-08
-- =============================================================================
-- Amaç: Admin, tanıtım ekranındaki "Webte devam et" düğmesini kapatabilsin.
-- Kapalıyken tanıtım ekranı kalıcı bir iniş (landing) sayfası gibi durur ve
-- ziyaretçi yalnızca mağaza düğmelerine yönlendirilir. Derin bağlantılar
-- (/u/@kullanici, /s/dukkan, /verify ...) ve `?promo=0` yine web uygulamasını
-- açtığı için site erişilemez hale gelmez.
--
-- Anahtar `web_promo_*` ailesine eklenir; index.html içindeki tanıtım scripti
-- ve admin paneli aynı anahtarı okur. Değer, mevcut konvansiyona uyarak jsonb
-- içinde JSON string olarak tutulur ("true"/"false").
-- =============================================================================

INSERT INTO public.app_settings (key, value, description)
VALUES
  ('web_promo_continue_enabled', '"true"',
   'Tanıtım ekranındaki "Webte devam et" düğmesi gösterilsin mi? false ise ziyaretçi yalnızca mağazalara yönlendirilir.')
ON CONFLICT (key) DO NOTHING;

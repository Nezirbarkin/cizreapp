-- =============================================================================
-- Şehiriçi: "Otomatik Rota Yazımı" global anahtarı
-- Tarih: 2026-08-19
-- =============================================================================
-- NEDEN
--   Hat rotası (sehirici_lines.route_polyline) iki yoldan yazılabiliyor:
--     1) Admin'in elle çizmesi,
--     2) Şoförün sürüş izinden otomatik üretim
--        (sehirici_drivers.auto_route_from_traveled_path, 20260807130000).
--
--   (2) kirli rotaların kaynağı: ham GPS izi duruş bulutları ve hatalı fixler
--   taşır, bunlar rotaya yazılınca haritada "her tarafa çizgi" görüntüsü
--   oluşur. Şu ana kadar bunu kapatmanın tek yolu her şoförün ayarını tek tek
--   kapatmaktı; admin tarafında toplu bir anahtar yoktu.
--
-- NE YAPAR
--   Admin panelindeki Ayarlar sekmesinden yönetilen global anahtarı ekler.
--   Şoför paneli (_maybeStartAutoRouteWatcher) bu anahtarı şoför ayarından
--   ÖNCE kontrol eder: kapalıysa hiçbir şoför otomatik rota yazamaz.
--
-- VARSAYILAN: true — mevcut davranış birebir korunur. Şoför başına ayar zaten
--   DEFAULT FALSE olduğu için bu, kimseye yeni bir yetki açmaz; sadece var olan
--   akışa bir üst kapı ekler.
--
-- NOT: app_settings.value jsonb'dir; diğer sehirici_* anahtarları gibi JSON
--   string ("true") olarak yazılır — istemci getBool'u hem bool hem string
--   kabul eder.
--
-- İstemci tarafı: SehiriciCityService.updateSetting yalnız UPDATE yapar, satır
--   yoksa sessizce hiçbir şey yazmaz. Bu yüzden satırın burada oluşturulması
--   ZORUNLUDUR — aksi hâlde anahtar arayüzde çalışıyor görünüp kaydedilmezdi.
-- =============================================================================

BEGIN;

INSERT INTO public.app_settings (key, value, description)
SELECT 'sehirici_auto_route_enabled',
       '"true"'::jsonb,
       'false ise şoförün sürüş izinden otomatik hat rotası üretilmez; '
       'rotalar yalnız admin tarafından elle çizilir. Şoför başına '
       'sehirici_drivers.auto_route_from_traveled_path ayarının üstündedir.'
WHERE NOT EXISTS (
  SELECT 1 FROM public.app_settings WHERE key = 'sehirici_auto_route_enabled'
);

COMMIT;

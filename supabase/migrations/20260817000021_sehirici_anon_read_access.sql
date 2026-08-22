-- =============================================================================
-- Şehiriçi: gerçek misafir (anon) erişimi
-- =============================================================================
-- KÖK NEDEN (2026-08-16/17, canlı DB'ye anon key ile REST/RPC çağrılarıyla
-- doğrulandı — supabase/diagnostics altında ayrı bir dosya yok, aşağıdaki
-- DOĞRULAMA bloğundaki curl komutlarıyla tekrarlanabilir):
--
--   sehirici_cities / sehirici_lines / sehirici_stops / sehirici_trips
--   tablolarının "*_select_all" politikaları anon VE authenticated için
--   ORTAK tanımlıydı ve politika ifadesi public.auth_is_admin() çağırıyordu
--   (ör. "is_active = TRUE OR auth_is_admin()"). auth_is_admin() güvenlik
--   gereği anon'a KAPALI (repo standardı — bkz. reward_points_owner için
--   aynı netlik: 20260809000001). PostgreSQL kısa devre değerlendirmesi
--   yapmaz: politika ifadesindeki HER fonksiyon için çağıran rolün EXECUTE
--   yetkisi olmalı — is_active = TRUE olan, tamamen herkese açık satırlarda
--   bile anon sorgusu "permission denied for function auth_is_admin" (42501)
--   ile çöküyordu.
--
--   Ayrıca get_sehirici_lines_with_stops / get_sehirici_active_trips /
--   get_sehirici_trips_for_stop / compute_sehirici_next_stop RPC'leri
--   20260725000001_sehirici_services.sql içinde "TO authenticated, anon"
--   olarak tanımlanmıştı; canlıda anon GRANT'ı kaybolmuş (repo genelinde
--   tekrarlayan RPC-yetki drift sınıfı, bkz. 20260817000019).
--
--   NET SONUÇ: misafir kullanıcılar Şehiriçi modülünü hiç göremiyordu —
--   Flutter tarafında hata sessizce yutuluyor (SehiriciCityService/
--   SehiriciLineService try/catch'leri) ve kart boş render ediliyor.
--
-- ÇÖZÜM: ilanlar modülünde AYNI hata sınıfı için kullanılan desenin birebir
-- aynısı (bkz. 20260817000010_fix_guest_ilan_visibility.sql ve
-- 20260817000011_fix_anon_ilan_policy_function_permissions.sql): anon ve
-- authenticated politikalarını AYIR. Anon politikası hiçbir ayrıcalıklı
-- fonksiyon çağırmaz (sadece is_active/status kontrolü); authenticated
-- politikası mevcut admin/sahiplik mantığını korur.
--   -> auth_is_admin() anon'a KAPALI KALMAYA DEVAM EDER. Güvenlik sınırı
--      değişmiyor, sadece politika yeniden düzenleniyor.
--
-- KAPSAM: SADECE OKUMA.
--   - Yazma RPC'leri (start_sehirici_trip, update_sehirici_trip_location,
--     set_sehirici_trip_status, admin_upsert/delete_*) authenticated/admin'e
--     kapalı kalmaya devam ediyor — bu migration onlara dokunmuyor.
--   - sehirici_favorite_stops (favoriler bir hesap gerektirir) dokunulmuyor.
--   - İlanlar modülündeki gibi ayrı bir "misafir görünürlüğü" ayarı
--     (allow_guest_view) EKLENMEDİ — istek koşulsuz "herkese açık olsun"
--     şeklindeydi; mevcut sehirici_module_enabled anahtarı zaten istemci
--     tarafında (SehiriciProvider.moduleEnabled) kontrol ediliyor.
--
-- NOT: Bu dosya sadece hazırlanmıştır, canlı veritabanına UYGULANMAMIŞTIR.
-- Uygulamak için: `supabase db push` ya da Supabase SQL Editor.
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- Cities
-- -----------------------------------------------------------------------------
DROP POLICY IF EXISTS sehirici_cities_select_all ON public.sehirici_cities;

CREATE POLICY sehirici_cities_anon_read
  ON public.sehirici_cities FOR SELECT TO anon
  USING (is_active = TRUE);

CREATE POLICY sehirici_cities_authenticated_read
  ON public.sehirici_cities FOR SELECT TO authenticated
  USING (is_active = TRUE OR (SELECT public.auth_is_admin()));

-- -----------------------------------------------------------------------------
-- Lines
-- -----------------------------------------------------------------------------
DROP POLICY IF EXISTS sehirici_lines_select_all ON public.sehirici_lines;

CREATE POLICY sehirici_lines_anon_read
  ON public.sehirici_lines FOR SELECT TO anon
  USING (is_active = TRUE);

CREATE POLICY sehirici_lines_authenticated_read
  ON public.sehirici_lines FOR SELECT TO authenticated
  USING (is_active = TRUE OR (SELECT public.auth_is_admin()));

-- -----------------------------------------------------------------------------
-- Stops
-- -----------------------------------------------------------------------------
DROP POLICY IF EXISTS sehirici_stops_select_all ON public.sehirici_stops;

CREATE POLICY sehirici_stops_anon_read
  ON public.sehirici_stops FOR SELECT TO anon
  USING (is_active = TRUE);

CREATE POLICY sehirici_stops_authenticated_read
  ON public.sehirici_stops FOR SELECT TO authenticated
  USING (is_active = TRUE OR (SELECT public.auth_is_admin()));

-- -----------------------------------------------------------------------------
-- Trips (aktif/tamamlanmış seferler herkese görünür kalmalı — realtime
-- postgres_changes de bu politikaya tabi, yoksa canlı otobüs konumu
-- misafirlere hiç ulaşmaz)
-- -----------------------------------------------------------------------------
DROP POLICY IF EXISTS sehirici_trips_select_all ON public.sehirici_trips;

CREATE POLICY sehirici_trips_anon_read
  ON public.sehirici_trips FOR SELECT TO anon
  USING (
    status = ANY (ARRAY['active'::sehirici_trip_status,
                         'paused'::sehirici_trip_status,
                         'completed'::sehirici_trip_status])
  );

CREATE POLICY sehirici_trips_authenticated_read
  ON public.sehirici_trips FOR SELECT TO authenticated
  USING (
    status = ANY (ARRAY['active'::sehirici_trip_status,
                         'paused'::sehirici_trip_status,
                         'completed'::sehirici_trip_status])
    OR (SELECT public.auth_is_admin())
    OR driver_id IN (
      SELECT id FROM public.sehirici_drivers
      WHERE profile_id = (SELECT auth.uid())
    )
  );

-- -----------------------------------------------------------------------------
-- Line-Stops: zaten ayrıcalıklı fonksiyon çağırmıyor (USING (TRUE)) — sadece
-- rolleri açıkça netleştiriyoruz, davranış değişmiyor.
-- -----------------------------------------------------------------------------
DROP POLICY IF EXISTS sehirici_line_stops_select_all ON public.sehirici_line_stops;

CREATE POLICY sehirici_line_stops_select_all
  ON public.sehirici_line_stops FOR SELECT TO anon, authenticated
  USING (TRUE);

-- -----------------------------------------------------------------------------
-- Tablo izinlerini açıkça garanti et (ilanlar düzeltmesiyle aynı ihtiyat
-- deseni — hata mesajları fonksiyon izniyle ilgiliydi, tablo değil, yani bu
-- muhtemelen zaten vardı; yine de açıkça garantiliyoruz).
-- -----------------------------------------------------------------------------
GRANT SELECT ON public.sehirici_cities TO anon;
GRANT SELECT ON public.sehirici_lines TO anon;
GRANT SELECT ON public.sehirici_stops TO anon;
GRANT SELECT ON public.sehirici_line_stops TO anon;
GRANT SELECT ON public.sehirici_trips TO anon;

-- -----------------------------------------------------------------------------
-- Genel-okuma RPC'leri: kaybolan anon GRANT'ını geri yükle. Bu fonksiyonlar
-- auth_is_admin() çağırmıyor ve SECURITY DEFINER oldukları için tabloları
-- zaten bypass ediyorlar — sadece kendi EXECUTE yetkileri kaybolmuştu.
-- -----------------------------------------------------------------------------
GRANT EXECUTE ON FUNCTION public.get_sehirici_lines_with_stops(UUID) TO anon;
GRANT EXECUTE ON FUNCTION public.get_sehirici_active_trips(UUID) TO anon;
GRANT EXECUTE ON FUNCTION public.get_sehirici_trips_for_stop(UUID) TO anon;
GRANT EXECUTE ON FUNCTION public.compute_sehirici_next_stop(UUID) TO anon;

NOTIFY pgrst, 'reload schema';

COMMIT;

-- =============================================================================
-- DOĞRULAMA (migration canlıya uygulandıktan sonra, anon key ile):
--
--   curl -s "$SUPABASE_URL/rest/v1/sehirici_cities?select=id,name&limit=5" \
--     -H "apikey: $SUPABASE_ANON_KEY" -H "Authorization: Bearer $SUPABASE_ANON_KEY"
--   -- Beklenen: şehir listesi JSON'u. Önceden: 42501 permission denied for
--   -- function auth_is_admin.
--
--   curl -s -X POST "$SUPABASE_URL/rest/v1/rpc/get_sehirici_lines_with_stops" \
--     -H "apikey: $SUPABASE_ANON_KEY" -H "Authorization: Bearer $SUPABASE_ANON_KEY" \
--     -H "Content-Type: application/json" -d '{"p_city_id":"<gerçek-city-id>"}'
--   -- Beklenen: hat listesi JSON'u. Önceden: 42501 permission denied for
--   -- function get_sehirici_lines_with_stops.
-- =============================================================================

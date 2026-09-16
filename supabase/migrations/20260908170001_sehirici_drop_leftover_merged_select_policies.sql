-- =============================================================================
-- Şehiriçi: misafir (anon) okumalarını kıran artık "_select_merged"
-- politikalarını temizle
-- =============================================================================
-- KÖK NEDEN (2026-09-08, canlı DB'de pg_policies ile doğrulandı):
--
--   20260817000021_sehirici_anon_read_access.sql anon/authenticated ayrımını
--   doğru kurmuş ve "*_select_all" politikalarını düşürmüştü. ANCAK
--   20260212000005_merge_multiple_permissive_policies.sql'in ürettiği
--   "*_select_merged" politikaları hâlâ duruyor ve rolleri {public} —
--   yani anon'a DA uygulanıyorlar. İfadeleri public.auth_is_admin() çağırıyor:
--
--     sehirici_cities_select_merged : (is_active = true) OR auth_is_admin() OR auth_is_admin()
--     sehirici_lines_select_merged  : (is_active = true) OR auth_is_admin() OR auth_is_admin()
--     sehirici_stops_select_merged  : (is_active = true) OR auth_is_admin() OR auth_is_admin()
--     sehirici_line_stops_select_merged : auth_is_admin() OR true
--     sehirici_routes_select_merged : (true = true) OR auth_is_admin()
--     sehirici_drivers_select_merged: auth_is_admin() OR profile_id = auth.uid() OR auth_is_admin()
--     sehirici_favorite_stops_select_merged : user_id = auth.uid() OR auth_is_admin()
--
--   PostgreSQL kısa devre yapmaz: uygulanabilir HER politikanın ifadesindeki
--   HER fonksiyon için çağıran rolün EXECUTE yetkisi gerekir. auth_is_admin()
--   anon'a kapalı (has_function_privilege('anon',...) = false, repo standardı,
--   bkz. 20260809000001). Sonuç: misafir kullanıcının sehirici_cities /
--   _lines / _stops / _line_stops / _routes üzerindeki HER SELECT'i
--   "42501 permission denied for function auth_is_admin" ile düşüyor.
--
--   NET SONUÇ: webde misafir olarak Şehiriçi açıldığında şehir listesi boş
--   dönüyor -> hat/durak/rota yok -> HARİTA HİÇ ÇİZİLMİYOR. Flutter tarafı
--   hatayı yutuyor (SehiriciCityService try/catch), sadece konsola düşüyor:
--     "SehiriciCityService.getCities hata: PostgrestException(... 42501 ...)"
--   Bu, 20260817000021'in düzelttiğini sandığı hatanın ta kendisi; o migration
--   yalnızca "*_select_all" adını düşürdüğü için "*_select_merged" ikizleri
--   hayatta kaldı.
--
-- ÇÖZÜM: Güvenlik sınırı DEĞİŞMİYOR, sadece artık politikalar kaldırılıyor.
--   - cities/lines/stops/line_stops: "_select_merged" tamamen gereksiz —
--     "_anon_read" + "_authenticated_read" (ve line_stops'ta "_select_all")
--     çifti zaten birebir aynı görünürlüğü veriyor. DROP yeterli.
--   - routes: ifade zaten "(true = true) OR ..." yani sabit TRUE. Fonksiyon
--     çağırmayan, anon+authenticated'a açık bir politikayla değiştiriliyor.
--   - drivers / favorite_stops: ifade anon için ZATEN hiçbir satır döndüremez
--     (auth.uid() NULL, admin değil). Politikayı "TO authenticated" olarak
--     yeniden kurmak efektif görünürlüğü aynen korur, anon'u ise hata yerine
--     "politika eşleşmedi -> 0 satır" yoluna sokar.
--
-- KAPSAM: SADECE SELECT politikaları. INSERT/UPDATE/DELETE politikaları
-- ("*_insert_merged" vb.) ve auth_is_admin()'in anon'a kapalı olması
-- olduğu gibi kalıyor.
--
-- NOT: public.invoices üzerindeki "invoices_select_policy" de aynı sınıfa
-- giriyor ({public} + auth_is_admin()), ancak misafir akışının parçası değil;
-- bilerek kapsam dışı bırakıldı.
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- 1) Tamamen gereksiz olanlar: anon_read/authenticated_read çifti zaten var
-- -----------------------------------------------------------------------------
DROP POLICY IF EXISTS sehirici_cities_select_merged     ON public.sehirici_cities;
DROP POLICY IF EXISTS sehirici_lines_select_merged      ON public.sehirici_lines;
DROP POLICY IF EXISTS sehirici_stops_select_merged      ON public.sehirici_stops;
DROP POLICY IF EXISTS sehirici_line_stops_select_merged ON public.sehirici_line_stops;

-- -----------------------------------------------------------------------------
-- 2) routes: sabit-TRUE ifadeyi fonksiyonsuz politikayla değiştir
--    (bu tablonun TEK select politikası olduğu için önce yenisini kurmak
--     yerine drop+create yapıyoruz; işlem tek transaction içinde.)
-- -----------------------------------------------------------------------------
DROP POLICY IF EXISTS sehirici_routes_select_merged ON public.sehirici_routes;

CREATE POLICY sehirici_routes_select_all
  ON public.sehirici_routes FOR SELECT TO anon, authenticated
  USING (TRUE);

-- -----------------------------------------------------------------------------
-- 3) drivers / favorite_stops: aynı ifade, sadece rol authenticated'a daraltıldı
-- -----------------------------------------------------------------------------
DROP POLICY IF EXISTS sehirici_drivers_select_merged ON public.sehirici_drivers;

CREATE POLICY sehirici_drivers_select_authenticated
  ON public.sehirici_drivers FOR SELECT TO authenticated
  USING (
    (SELECT public.auth_is_admin())
    OR profile_id = (SELECT auth.uid())
  );

DROP POLICY IF EXISTS sehirici_favorite_stops_select_merged ON public.sehirici_favorite_stops;

CREATE POLICY sehirici_favorite_stops_select_authenticated
  ON public.sehirici_favorite_stops FOR SELECT TO authenticated
  USING (
    user_id = (SELECT auth.uid())
    OR (SELECT public.auth_is_admin())
  );

NOTIFY pgrst, 'reload schema';

COMMIT;

-- =============================================================================
-- DOĞRULAMA (anon key ile):
--
--   curl -s "$SUPABASE_URL/rest/v1/sehirici_cities?select=id,name&limit=5" \
--     -H "apikey: $SUPABASE_ANON_KEY" -H "Authorization: Bearer $SUPABASE_ANON_KEY"
--   -- Beklenen: şehir listesi. Önceden: 42501 permission denied for function
--   --           auth_is_admin.
--
--   Uygulamada: webde misafir olarak /sehirici-lines -> hatlar listelenmeli ve
--   canlı harita çizilmeli.
-- =============================================================================

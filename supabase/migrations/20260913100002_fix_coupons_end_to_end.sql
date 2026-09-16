-- =============================================================================
-- SATICI KUPONLARI: UCTAN UCA DUZELTME (yalniz Supabase tarafi)
-- =============================================================================
-- Satici panelinden kupon INSERT etmek tek basina calisiyordu (RLS insert
-- politikasi dogru; 10 saticinin hepsi icin canli DB'de dogrulandi). Ama
-- eklenen kuponun hicbir ise yaramadigi 5 ayri sunucu hatasi vardi. Hepsi
-- canli veritabaninda 2026-09-13'te dogrulandi:
--
--  1) private.validate_coupon() HER ZAMAN 42702 ile patliyor:
--     "column reference \"id\" is ambiguous". Fonksiyonun RETURNS TABLE(...)
--     kolonlari (id, code, discount_type, ...) ayni zamanda PL/pgSQL
--     degiskenidir; govdedeki `WHERE id = p_coupon_id` hem bu degiskene hem
--     shop_coupons.id kolonuna isaret ediyor. Yani musteri sepette kupon
--     kodunu girdiginde public.validate_coupon -> private.validate_coupon
--     cagrisi daima hata donuyordu: kupon hicbir zaman uygulanamiyordu.
--
--  2) Indirim tipi yanlis sabitle karsilastiriliyordu:
--     `ELSIF v_coupon.discount_type = 'fixed'` — oysa coupon_type enum degeri
--     'fixed_amount' ve satici panelinin VARSAYILAN kupon tipi bu. Sonuc:
--     "Bilinmeyen kupon tipi: fixed_amount". Ayni hata
--     private.prepare_checkout_session icinde de vardi; yani sabit tutarli
--     kupon secili checkout oturumu bile acilamiyordu.
--
--  3) shop_coupons SELECT politikasi 20260212000004 ile "sadece magaza sahibi
--     veya admin" haline gelmisti. Musteri/misafir hicbir kuponu goremiyordu:
--     "Kuponlarim" ekrani, magaza detayi, market ve magaza listelerindeki
--     kupon rozetleri hep bos donuyordu (istemci kodu — my_coupons_screen.dart
--     — "aktif kuponlari herkes gorur" varsayimiyla yazilmis).
--
--  4) coupon_usages SELECT politikasi ayni migration'da magaza sahibi dalini
--     kaybetmisti: satici kendi kuponunun kullanimlarini goremiyordu, kupon
--     istatistikleri her zaman 0 gosteriyordu.
--
--  5) usage_count CIFT artiyordu: coupon_usages uzerindeki
--     trigger_record_coupon_usage sayaci artiriyor, ayni islemde
--     use_coupon / commit_*_order RPC'leri de artiriyordu. usage_limit'i 10
--     olan kupon 5 kullanimda bitiyordu.
--
-- Ek olarak kupon ekleme yolu dayanikli hale getirildi (6. bolum): kod trim +
-- buyuk harfe normalize edilir, bos kod/baslik ve 100 ustu yuzde anlasilir
-- Turkce hata verir, ayni kod ikinci kez eklenirse mesaj nettir, istemci
-- shop_id'yi cozemediyse sunucu kuponu cagiranin magazasina baglar.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1) private.validate_coupon — ambiguity + 'fixed_amount' duzeltmesi
-- -----------------------------------------------------------------------------
-- Imza ve RETURNS TABLE kolon adlari AYNI kalmak zorunda: public.validate_coupon
-- `SELECT * FROM private.validate_coupon(...)` ile bu siralamaya guveniyor ve
-- CREATE OR REPLACE donus tipini degistiremez. Bu yuzden cozum kolon adlarini
-- degistirmek degil, govdedeki TUM kolon referanslarini takma adla nitelemek.
CREATE OR REPLACE FUNCTION private.validate_coupon(
  p_coupon_id UUID,
  p_subtotal NUMERIC,
  p_user_id UUID
)
RETURNS TABLE (
  id UUID,
  code TEXT,
  discount_type TEXT,
  discount_value NUMERIC,
  maximum_discount_amount NUMERIC,
  minimum_order_amount NUMERIC,
  computed_discount NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_coupon RECORD;
  v_user_usage_count INT;
  v_computed NUMERIC;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'user_id gerekli' USING ERRCODE = '42501';
  END IF;

  -- sc.* nitelemesi sart: id/code/... adlari ayni zamanda OUT degiskeni.
  SELECT sc.* INTO v_coupon
  FROM public.shop_coupons sc
  WHERE sc.id = p_coupon_id
  FOR UPDATE;  -- ayni anda iki commit ayni kupona erisemesin

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Kupon bulunamadi' USING ERRCODE = 'P0002';
  END IF;

  IF NOT v_coupon.is_active THEN
    RAISE EXCEPTION 'Kupon aktif degil' USING ERRCODE = 'P0001';
  END IF;

  IF v_coupon.start_date IS NOT NULL AND v_coupon.start_date > now() THEN
    RAISE EXCEPTION 'Kupon henuz baslamadi' USING ERRCODE = 'P0001';
  END IF;

  IF v_coupon.end_date IS NOT NULL AND v_coupon.end_date < now() THEN
    RAISE EXCEPTION 'Kuponun suresi dolmus' USING ERRCODE = 'P0001';
  END IF;

  IF v_coupon.minimum_order_amount IS NOT NULL
     AND p_subtotal < v_coupon.minimum_order_amount THEN
    RAISE EXCEPTION 'Minimum siparis tutari asilmadi' USING ERRCODE = 'P0001';
  END IF;

  IF v_coupon.usage_limit IS NOT NULL
     AND COALESCE(v_coupon.usage_count, 0) >= v_coupon.usage_limit THEN
    RAISE EXCEPTION 'Kupon kullanim limiti doldu' USING ERRCODE = 'P0001';
  END IF;

  IF v_coupon.usage_per_user IS NOT NULL THEN
    SELECT COUNT(*) INTO v_user_usage_count
    FROM public.coupon_usages cu
    WHERE cu.coupon_id = v_coupon.id
      AND cu.user_id = p_user_id;

    IF v_user_usage_count >= v_coupon.usage_per_user THEN
      RAISE EXCEPTION 'Kullanici basina kupon limiti doldu' USING ERRCODE = 'P0001';
    END IF;
  END IF;

  -- Indirim hesabi (server authoritative; istemci tutar gondermez).
  -- coupon_type enum'u: 'fixed_amount' | 'percentage'. Eski kod 'fixed' ile
  -- karsilastirdigi icin sabit tutarli kuponlarin HEPSI reddediliyordu.
  IF v_coupon.discount_type::TEXT = 'percentage' THEN
    v_computed := p_subtotal * (v_coupon.discount_value / 100.0);
  ELSIF v_coupon.discount_type::TEXT IN ('fixed_amount', 'fixed') THEN
    v_computed := v_coupon.discount_value;
  ELSE
    RAISE EXCEPTION 'Bilinmeyen kupon tipi: %', v_coupon.discount_type
      USING ERRCODE = 'P0001';
  END IF;

  IF v_coupon.maximum_discount_amount IS NOT NULL
     AND v_computed > v_coupon.maximum_discount_amount THEN
    v_computed := v_coupon.maximum_discount_amount;
  END IF;
  IF v_computed < 0 THEN v_computed := 0; END IF;
  IF v_computed > p_subtotal THEN v_computed := p_subtotal; END IF;

  RETURN QUERY SELECT
    v_coupon.id,
    v_coupon.code::TEXT,
    v_coupon.discount_type::TEXT,
    v_coupon.discount_value,
    v_coupon.maximum_discount_amount,
    v_coupon.minimum_order_amount,
    v_computed;
END;
$function$;

REVOKE ALL ON FUNCTION private.validate_coupon(UUID, NUMERIC, UUID) FROM PUBLIC;

-- -----------------------------------------------------------------------------
-- 2) public.validate_coupon — kod eslesmesi bosluk/buyuk-kucuk harf duyarsiz
-- -----------------------------------------------------------------------------
-- Satici kodu "yeni100 " gibi kaydettiyse (istemci toUpperCase yapiyor ama trim
-- etmiyordu) musterinin girdigi "YENI100" eslesmiyor, kupon "gecersiz"
-- goruluyordu. Artik iki taraf da normalize ediliyor.
CREATE OR REPLACE FUNCTION public.validate_coupon(
  p_shop_id UUID,
  p_code TEXT,
  p_subtotal NUMERIC,
  p_user_id UUID
)
RETURNS TABLE (
  id UUID,
  code TEXT,
  discount_type TEXT,
  discount_value NUMERIC,
  maximum_discount_amount NUMERIC,
  minimum_order_amount NUMERIC,
  computed_discount NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_coupon_id UUID;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'validate_coupon: not authenticated' USING ERRCODE = '28000';
  END IF;

  -- Kod -> kupon kimligi, MAGAZA KAPSAMLI.
  SELECT sc.id
    INTO v_coupon_id
  FROM public.shop_coupons sc
  WHERE sc.shop_id = p_shop_id
    AND upper(btrim(sc.code)) = upper(btrim(COALESCE(p_code, '')))
    AND sc.is_active = true
  LIMIT 1;

  IF v_coupon_id IS NULL THEN
    -- Eski public surumun davranisiyla ayni mesaj; uygulama bunu gosteriyor.
    RAISE EXCEPTION 'Geçersiz kupon kodu';
  END IF;

  -- Tarih, limit, kullanici basina limit ve tutar kontrolleri
  -- private.validate_coupon icinde (satir kilidiyle) yapiliyor.
  RETURN QUERY
  SELECT * FROM private.validate_coupon(v_coupon_id, p_subtotal, p_user_id);
END;
$function$;

REVOKE ALL ON FUNCTION public.validate_coupon(UUID, TEXT, NUMERIC, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.validate_coupon(UUID, TEXT, NUMERIC, UUID) TO authenticated;

-- -----------------------------------------------------------------------------
-- 3) private.prepare_checkout_session — 'fixed' -> 'fixed_amount'
-- -----------------------------------------------------------------------------
-- 620+ satirlik fonksiyonu bastan yazmak yerine yalniz hatali satir yamalanir:
-- canli tanim okunur, tek sabit degistirilir, CREATE OR REPLACE ile calisir.
-- Boylece fonksiyonun geri kalani birebir korunur. Yama noktasi bulunamazsa
-- migration sessizce gecmez, hata verir.
DO $mig$
DECLARE
  v_def TEXT;
  v_old TEXT := 'ELSIF v_coupon.discount_type = ''fixed'' THEN';
  v_new TEXT := 'ELSIF v_coupon.discount_type::TEXT IN (''fixed_amount'', ''fixed'') THEN';
BEGIN
  v_def := pg_get_functiondef(
    'private.prepare_checkout_session(jsonb,uuid,text,text,uuid,text,jsonb,uuid)'::regprocedure
  );

  IF position(v_old IN v_def) > 0 THEN
    EXECUTE replace(v_def, v_old, v_new);
    RAISE NOTICE 'prepare_checkout_session: fixed_amount kupon tipi yamasi uygulandi';
  ELSIF position(v_new IN v_def) > 0 THEN
    RAISE NOTICE 'prepare_checkout_session: yama zaten uygulanmis, atlandi';
  ELSE
    RAISE EXCEPTION 'prepare_checkout_session icinde beklenen kupon tipi dali bulunamadi; elle kontrol gerekiyor';
  END IF;
END
$mig$;

-- -----------------------------------------------------------------------------
-- 4) shop_coupons SELECT — musteri/misafir aktif kuponlari yeniden gorebilir
-- -----------------------------------------------------------------------------
DROP POLICY IF EXISTS shop_coupons_select ON public.shop_coupons;
CREATE POLICY shop_coupons_select ON public.shop_coupons
  FOR SELECT
  TO authenticated
  USING (
    -- magaza sahibi kendi kuponlarinin hepsini (pasif dahil) gorur
    EXISTS (
      SELECT 1 FROM public.shops s
      WHERE s.id = shop_coupons.shop_id
        AND s.owner_id = (SELECT auth.uid())
    )
    OR public.auth_is_admin()
    -- musteri: yayinda olan magazalarin aktif kuponlari
    OR (
      is_active = true
      AND EXISTS (
        SELECT 1 FROM public.shops s
        WHERE s.id = shop_coupons.shop_id
          AND s.is_active = true
          AND s.is_approved = true
      )
    )
  );

-- Misafir (anon) icin AYRI politika: auth_is_admin() CAGIRMAZ. anon rolunun
-- profiles uzerinde SELECT yetkisi olmadigi icin admin kontrolu iceren bir
-- politika misafirde 42501'e duser (leftover *_select_merged dersi).
DROP POLICY IF EXISTS shop_coupons_select_anon ON public.shop_coupons;
CREATE POLICY shop_coupons_select_anon ON public.shop_coupons
  FOR SELECT
  TO anon
  USING (
    is_active = true
    AND EXISTS (
      SELECT 1 FROM public.shops s
      WHERE s.id = shop_coupons.shop_id
        AND s.is_active = true
        AND s.is_approved = true
    )
  );

-- -----------------------------------------------------------------------------
-- 5) coupon_usages SELECT — satici kendi kuponunun kullanimlarini gorur
-- -----------------------------------------------------------------------------
DROP POLICY IF EXISTS coupon_usages_select ON public.coupon_usages;
CREATE POLICY coupon_usages_select ON public.coupon_usages
  FOR SELECT
  TO authenticated
  USING (
    user_id = (SELECT auth.uid())
    OR public.auth_is_admin()
    OR EXISTS (
      SELECT 1
      FROM public.shop_coupons sc
      JOIN public.shops s ON s.id = sc.shop_id
      WHERE sc.id = coupon_usages.coupon_id
        AND s.owner_id = (SELECT auth.uid())
    )
  );

-- -----------------------------------------------------------------------------
-- 6) Kupon ekleme yolunu dayanikli hale getir (BEFORE INSERT/UPDATE trigger)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.shop_coupons_normalize()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $function$
DECLARE
  v_shop_count INT;
  v_shop_id UUID;
BEGIN
  -- Istemci magazasini cozemediyse shop_id NULL geliyor ve saticiya anlamsiz
  -- bir NOT NULL hatasi donuyordu (ustelik dialogun arkasinda kalan snackbar'da
  -- gorunmuyor). Sunucu tarafinda cagiranin magazasindan doldur.
  IF NEW.shop_id IS NULL THEN
    -- min(uuid) diye bir aggregate yok; sayim ve secim ayri yapilir.
    SELECT count(*) INTO v_shop_count
    FROM public.shops s
    WHERE s.owner_id = auth.uid();

    IF v_shop_count = 1 THEN
      SELECT s.id INTO v_shop_id
      FROM public.shops s
      WHERE s.owner_id = auth.uid()
      LIMIT 1;
      NEW.shop_id := v_shop_id;
    ELSIF v_shop_count = 0 THEN
      RAISE EXCEPTION 'Kupon olusturabilmek icin once magaza olusturmalisiniz'
        USING ERRCODE = 'P0001';
    ELSE
      RAISE EXCEPTION 'Birden fazla magazaniz var; kupon icin magaza secilmeli'
        USING ERRCODE = 'P0001';
    END IF;
  END IF;

  NEW.code := upper(btrim(COALESCE(NEW.code, '')));
  IF NEW.code = '' THEN
    RAISE EXCEPTION 'Kupon kodu bos olamaz' USING ERRCODE = 'P0001';
  END IF;

  NEW.title := btrim(COALESCE(NEW.title, ''));
  IF NEW.title = '' THEN
    RAISE EXCEPTION 'Kupon basligi bos olamaz' USING ERRCODE = 'P0001';
  END IF;

  IF NEW.description IS NOT NULL AND btrim(NEW.description) = '' THEN
    NEW.description := NULL;
  END IF;

  IF NEW.discount_type::TEXT = 'percentage' AND NEW.discount_value > 100 THEN
    RAISE EXCEPTION 'Yuzde indirim 100 uzerinde olamaz' USING ERRCODE = 'P0001';
  END IF;

  IF NEW.usage_per_user IS NOT NULL AND NEW.usage_per_user < 1 THEN
    NEW.usage_per_user := 1;
  END IF;
  IF NEW.usage_limit IS NOT NULL AND NEW.usage_limit < 1 THEN
    NEW.usage_limit := NULL;
  END IF;

  -- Ayni magazada ayni kod: unique_shop_coupon_code'un teknik mesaji yerine
  -- saticinin anlayacagi bir mesaj don.
  IF EXISTS (
    SELECT 1 FROM public.shop_coupons c
    WHERE c.shop_id = NEW.shop_id
      AND upper(btrim(c.code)) = NEW.code
      AND c.id IS DISTINCT FROM NEW.id
  ) THEN
    RAISE EXCEPTION 'Bu kupon kodu magazanizda zaten kayitli: %', NEW.code
      USING ERRCODE = '23505';
  END IF;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS shop_coupons_normalize_trigger ON public.shop_coupons;
CREATE TRIGGER shop_coupons_normalize_trigger
  BEFORE INSERT OR UPDATE ON public.shop_coupons
  FOR EACH ROW
  EXECUTE FUNCTION public.shop_coupons_normalize();

COMMENT ON FUNCTION public.shop_coupons_normalize() IS
  'shop_coupons BEFORE INSERT/UPDATE: kod/baslik normalize, shop_id fallback, anlasilir Turkce hata mesajlari.';

-- -----------------------------------------------------------------------------
-- 7) usage_count cift artisini bitir
-- -----------------------------------------------------------------------------
-- coupon_usages'a yazan TUM yollar (public.use_coupon, private.use_coupon,
-- commit_online_order, private.commit_cod_order, private.commit_balance_order)
-- ayni islemde usage_count'u kendisi artiriyor. AFTER INSERT trigger'i bir kez
-- daha artirdigi icin sayac 2 kat isliyordu.
DROP TRIGGER IF EXISTS trigger_record_coupon_usage ON public.coupon_usages;

-- Gecmiste sismis sayaclari gercek kullanim sayisina esitle.
UPDATE public.shop_coupons sc
SET usage_count = sub.cnt
FROM (
  SELECT c.id AS coupon_id, COUNT(cu.id) AS cnt
  FROM public.shop_coupons c
  LEFT JOIN public.coupon_usages cu ON cu.coupon_id = c.id
  GROUP BY c.id
) sub
WHERE sc.id = sub.coupon_id
  AND COALESCE(sc.usage_count, 0) <> sub.cnt;

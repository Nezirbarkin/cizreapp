-- =============================================================================
-- Görev 3.7 — Satıcı zorunlu alanları: telefon + haritadan konum
-- =============================================================================
-- Canlıda 12 mağazanın 10'unda konum, 4'ünde telefon yok. Kurye/müşteri bu
-- mağazalara ulaşamıyor ya da yeri bulamıyor.
--
-- Kural (sunucuda, istemciden bağımsız):
--   * Yeni mağaza (satıcı açarken) telefon (en az 10 hane) ve haritadan konum
--     olmadan AÇILAMAZ.
--   * Var olan mağazada telefon/konum GİRİLDİKTEN sonra silinemez, geçersiz bir
--     değere çevrilemez. Eksik mağaza başka alanlarını (çalışma saati, teslimat
--     vb.) güncelleyebilir — tetikleyici yalnız bu üç sütun değişince çalışır;
--     böylece mevcut eksik mağazalar kilitlenmez, panellerindeki kalıcı
--     "Eksik bilgi" şeridiyle tamamlamaları istenir.
--   * Yönetici ve sistem/servis bağlamı (auth.uid() yok) serbesttir.
--
-- Tetikleyici BİLEREK SECURITY INVOKER: DEFINER olsaydı current_user/auth
-- bağlamı fonksiyon sahibine dönerdi (bkz. guard_shop_financial_columns notu).
-- =============================================================================

BEGIN;

-- Telefon: rakam sayısı 10–13 (5xx…, 05xx…, +90 5xx…, sabit hat dahil).
CREATE OR REPLACE FUNCTION public.shop_phone_is_valid(p_phone text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $fn$
  SELECT length(regexp_replace(COALESCE(p_phone, ''), '\D', '', 'g')) BETWEEN 10 AND 13;
$fn$;

GRANT EXECUTE ON FUNCTION public.shop_phone_is_valid(text) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.guard_shop_contact_info()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $fn$
BEGIN
  IF auth.uid() IS NULL OR public.auth_is_admin() THEN
    RETURN NEW;
  END IF;

  IF NEW.latitude IS NOT NULL AND NEW.longitude IS NOT NULL
     AND (NEW.latitude NOT BETWEEN -90 AND 90 OR NEW.longitude NOT BETWEEN -180 AND 180) THEN
    RAISE EXCEPTION 'Geçersiz mağaza konumu'
      USING ERRCODE = 'P0001', HINT = 'SHOP_LOCATION_INVALID';
  END IF;

  IF TG_OP = 'INSERT' THEN
    IF NOT public.shop_phone_is_valid(NEW.phone) THEN
      RAISE EXCEPTION 'Mağaza telefonu zorunludur (en az 10 haneli numara)'
        USING ERRCODE = 'P0001', HINT = 'SHOP_PHONE_REQUIRED';
    END IF;
    IF NEW.latitude IS NULL OR NEW.longitude IS NULL THEN
      RAISE EXCEPTION 'Mağaza konumunu haritadan seçmelisiniz'
        USING ERRCODE = 'P0001', HINT = 'SHOP_LOCATION_REQUIRED';
    END IF;
    RETURN NEW;
  END IF;

  -- UPDATE: girilmiş bilgi silinemez/bozulamaz.
  IF NEW.phone IS DISTINCT FROM OLD.phone AND NOT public.shop_phone_is_valid(NEW.phone) THEN
    RAISE EXCEPTION 'Mağaza telefonu zorunludur (en az 10 haneli numara)'
      USING ERRCODE = 'P0001', HINT = 'SHOP_PHONE_REQUIRED';
  END IF;
  IF (NEW.latitude IS NULL OR NEW.longitude IS NULL)
     AND (NEW.latitude IS DISTINCT FROM OLD.latitude OR NEW.longitude IS DISTINCT FROM OLD.longitude) THEN
    RAISE EXCEPTION 'Mağaza konumu silinemez; haritadan yeni konum seçin'
      USING ERRCODE = 'P0001', HINT = 'SHOP_LOCATION_REQUIRED';
  END IF;

  RETURN NEW;
END;
$fn$;

REVOKE ALL ON FUNCTION public.guard_shop_contact_info() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_shops_guard_contact_info ON public.shops;
CREATE TRIGGER trg_shops_guard_contact_info
  BEFORE INSERT OR UPDATE OF phone, latitude, longitude ON public.shops
  FOR EACH ROW EXECUTE FUNCTION public.guard_shop_contact_info();

COMMIT;

NOTIFY pgrst, 'reload schema';

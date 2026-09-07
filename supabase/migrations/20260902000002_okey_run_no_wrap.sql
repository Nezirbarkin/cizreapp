-- =============================================================================
-- 101 Okey Plus — SERİ 13'TE BİTER (13'ten sonra 1 GELMEZ)
-- -----------------------------------------------------------------------------
-- KURAL DEĞİŞİKLİĞİ (kullanıcı kararı): Seriler yalnızca artan yönde,
-- 1'den 13'e doğru ilerler. 13'ten sonra 1'e SARMA YOKTUR.
--
--   11-12-13   -> geçerli
--   12-13-1    -> GEÇERSİZ   (önce geçerliydi)
--   13-1-2     -> GEÇERSİZ   (zaten geçersizdi)
--
-- Önceki kural kitapçığı 12-13-1'i geçerli sayıyordu; kullanıcı bunu
-- açıkça değiştirdi.
-- =============================================================================

SET search_path = public, pg_temp;

CREATE OR REPLACE FUNCTION public.okey_expected_run_number(p_start int, p_index int)
RETURNS int
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  -- 13'ten sonrası YOK: seri orada biter.
  SELECT CASE
    WHEN p_start + p_index <= 13 THEN p_start + p_index
    ELSE NULL
  END;
$$;
REVOKE ALL ON FUNCTION public.okey_expected_run_number(int, int)
  FROM PUBLIC, anon, authenticated;

NOTIFY pgrst, 'reload schema';

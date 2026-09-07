-- =============================================================================
-- 101 Okey Plus — SAHTE OKEY ARTIK SERBEST JOKER DEĞİL
-- -----------------------------------------------------------------------------
-- BULUNAN HATA: Kod, sahte okeyi HER TAŞIN yerine geçebilen serbest bir joker
-- olarak işliyordu. Oysa RULES.md §1 zaten şunu yazıyordu:
--
--     "Sahte okey taşları, okey taşının yerine NORMAL SAYI DEĞERİYLE geçer"
--
-- Yani sahte okey belirli bir kimliğe sahiptir ve yalnızca O TAŞIN gittiği
-- yere girer. Kullanıcının örneği: sahte okey 11 ise, aynı renk 10-11-12
-- serisine ya da farklı renklerden 11-11-11 grubuna girer — başka yere DEĞİL.
--
-- Kod, onaylanmış kuralla çelişiyordu.
--
-- ÇÖZÜM — iki soru BİRBİRİNDEN AYRILDI:
--   1) "Bu taş JOKER mi?"  -> yalnızca OKEY taşının 2 kopyası (serbest joker)
--   2) "Bu taş hangi taş SAYILIR?" -> sahte okey, OKEY taşının renk/sayısı
--
-- Bu ayrım şart: sahte okeyi doğrudan okey taşına "çözseydik" yine joker
-- sayılır ve hiçbir şey değişmezdi (döngüsel tanım).
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '10s';

-- -----------------------------------------------------------------------------
-- 1) JOKER TANIMI DARALTILDI: yalnızca gerçek okey taşları
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.okey_tile_is_joker(p_tile jsonb, p_okey_tile jsonb)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  -- SAHTE OKEY JOKER DEĞİLDİR: okey taşının sayı değeriyle oynar.
  SELECT COALESCE((p_tile->>'isFalseJoker')::boolean, false) = false
     AND (p_tile->>'color') = (p_okey_tile->>'color')
     AND (p_tile->>'number')::int = (p_okey_tile->>'number')::int;
$$;
REVOKE ALL ON FUNCTION public.okey_tile_is_joker(jsonb, jsonb)
  FROM PUBLIC, anon, authenticated;

-- -----------------------------------------------------------------------------
-- 2) "Bu taş hangi taş sayılır?" — sahte okey, OKEY taşının kimliğini alır
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.okey_tile_color(p_tile jsonb, p_okey_tile jsonb)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT CASE
    WHEN COALESCE((p_tile->>'isFalseJoker')::boolean, false)
      THEN p_okey_tile->>'color'
    ELSE p_tile->>'color'
  END;
$$;
REVOKE ALL ON FUNCTION public.okey_tile_color(jsonb, jsonb)
  FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.okey_tile_number(p_tile jsonb, p_okey_tile jsonb)
RETURNS int
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT CASE
    WHEN COALESCE((p_tile->>'isFalseJoker')::boolean, false)
      THEN (p_okey_tile->>'number')::int
    ELSE (p_tile->>'number')::int
  END;
$$;
REVOKE ALL ON FUNCTION public.okey_tile_number(jsonb, jsonb)
  FROM PUBLIC, anon, authenticated;

-- -----------------------------------------------------------------------------
-- 3) DOĞRULAYICILAR: ham color/number yerine ÇÖZÜMLENMİŞ değerleri kullanır
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.okey_find_run_start(p_tiles jsonb, p_okey_tile jsonb)
RETURNS int
LANGUAGE plpgsql
IMMUTABLE
SET search_path = ''
AS $$
DECLARE
  v_len int := jsonb_array_length(p_tiles);
  v_color text;
  v_tile jsonb;
  v_expected int;
  v_ok boolean;
  i int;
  s int;
BEGIN
  IF v_len < 3 OR v_len > 14 THEN RETURN NULL; END IF;

  -- Seri tek renk olmalı. Sahte okey artık ATLANMAZ: okey taşının rengiyle
  -- karşılaştırılır, çünkü o renkte bir taş gibi oynar.
  FOR i IN 0 .. v_len - 1 LOOP
    v_tile := p_tiles -> i;
    IF public.okey_tile_is_joker(v_tile, p_okey_tile) THEN CONTINUE; END IF;
    IF v_color IS NULL THEN
      v_color := public.okey_tile_color(v_tile, p_okey_tile);
    ELSIF public.okey_tile_color(v_tile, p_okey_tile) IS DISTINCT FROM v_color THEN
      RETURN NULL;
    END IF;
  END LOOP;

  FOR s IN 1 .. 13 LOOP
    v_ok := true;
    FOR i IN 0 .. v_len - 1 LOOP
      v_expected := public.okey_expected_run_number(s, i);
      IF v_expected IS NULL THEN
        v_ok := false;
        EXIT;
      END IF;
      v_tile := p_tiles -> i;
      IF public.okey_tile_is_joker(v_tile, p_okey_tile) THEN CONTINUE; END IF;
      IF public.okey_tile_number(v_tile, p_okey_tile) IS DISTINCT FROM v_expected THEN
        v_ok := false;
        EXIT;
      END IF;
    END LOOP;
    IF v_ok THEN RETURN s; END IF;
  END LOOP;

  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION public.okey_find_run_start(jsonb, jsonb)
  FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.okey_is_valid_set(p_tiles jsonb, p_okey_tile jsonb)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
SET search_path = ''
AS $$
DECLARE
  v_len int := jsonb_array_length(p_tiles);
  v_target_number int;
  v_used_colors text[] := ARRAY[]::text[];
  v_tile jsonb;
  v_color text;
  i int;
BEGIN
  IF v_len <> 3 AND v_len <> 4 THEN RETURN false; END IF;
  FOR i IN 0 .. v_len - 1 LOOP
    v_tile := p_tiles -> i;
    IF public.okey_tile_is_joker(v_tile, p_okey_tile) THEN CONTINUE; END IF;

    -- Sahte okey burada da NORMAL taş gibi davranır
    IF v_target_number IS NULL THEN
      v_target_number := public.okey_tile_number(v_tile, p_okey_tile);
    ELSIF public.okey_tile_number(v_tile, p_okey_tile)
          IS DISTINCT FROM v_target_number THEN
      RETURN false;
    END IF;

    v_color := public.okey_tile_color(v_tile, p_okey_tile);
    IF v_color = ANY(v_used_colors) THEN RETURN false; END IF;
    v_used_colors := v_used_colors || v_color;
  END LOOP;
  RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION public.okey_is_valid_set(jsonb, jsonb)
  FROM PUBLIC, anon, authenticated;

-- Çift: sahte okey yalnızca OKEY taşıyla eşleşir (her taşla değil)
CREATE OR REPLACE FUNCTION public.okey_is_valid_pair(p_tiles jsonb, p_okey_tile jsonb)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT jsonb_array_length(p_tiles) = 2
     AND (
       public.okey_tile_is_joker(p_tiles -> 0, p_okey_tile)
       OR public.okey_tile_is_joker(p_tiles -> 1, p_okey_tile)
       OR (
         public.okey_tile_color(p_tiles -> 0, p_okey_tile)
           = public.okey_tile_color(p_tiles -> 1, p_okey_tile)
         AND public.okey_tile_number(p_tiles -> 0, p_okey_tile)
           = public.okey_tile_number(p_tiles -> 1, p_okey_tile)
       )
     );
$$;
REVOKE ALL ON FUNCTION public.okey_is_valid_pair(jsonb, jsonb)
  FROM PUBLIC, anon, authenticated;

NOTIFY pgrst, 'reload schema';

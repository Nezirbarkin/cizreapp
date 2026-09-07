-- =============================================================================
-- 101 Okey Plus — v2 / Adım 1: şema genişletme + kural doğrulayıcıların düzeltimi
-- -----------------------------------------------------------------------------
-- Bu migration, modülü *standart okey* kurallarından gerçek **101 Okey Plus**
-- kurallarına taşıyan serinin ilkidir (bkz. lib/okey/engine/RULES.md v2.0).
--
-- Başlıca değişiklikler:
--   1) Oyun modları: katlamasız/katlamalı  ×  eşsiz/eşli
--   2) Açılış takibi: masadaki en yüksek açılış (katlamalı baraj için)
--   3) Oyuncu durumu: çifte mi gitti, çiftle mi açtı (ceza hesabı için)
--   4) meld_type'a 'pair' eklenir (çift açılışı masaya konur)
--   5) Seri doğrulaması artık 12-13-1'i GEÇERLİ, 13-1-2'yi GEÇERSİZ sayar
--   6) Çift doğrulaması ve 13-1 puanlaması (1 = 1 puan) eklenir
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '5s';

-- -----------------------------------------------------------------------------
-- 1) Oda: oyun modları
-- -----------------------------------------------------------------------------
ALTER TABLE public.okey_rooms
  ADD COLUMN IF NOT EXISTS game_mode text NOT NULL DEFAULT 'katlamasiz',
  ADD COLUMN IF NOT EXISTS team_mode text NOT NULL DEFAULT 'essiz';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'okey_rooms_game_mode_check'
  ) THEN
    ALTER TABLE public.okey_rooms
      ADD CONSTRAINT okey_rooms_game_mode_check
      CHECK (game_mode IN ('katlamasiz', 'katlamali'));
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'okey_rooms_team_mode_check'
  ) THEN
    ALTER TABLE public.okey_rooms
      ADD CONSTRAINT okey_rooms_team_mode_check
      CHECK (team_mode IN ('essiz', 'esli'));
  END IF;
END;
$$;

COMMENT ON COLUMN public.okey_rooms.game_mode IS
  'katlamasiz = sabit 101/5çift barajı; katlamali = her açılış masadaki en yüksekten >=1 fazla olmalı (RULES.md §5).';
COMMENT ON COLUMN public.okey_rooms.team_mode IS
  'essiz = 4 kişi bireysel; esli = karşılıklı oturanlar takım (0-2 ve 1-3), eşi açınca diğer eş barajsız açar (RULES.md §5).';

-- -----------------------------------------------------------------------------
-- 2) Maç: katlamalı baraj takibi
-- -----------------------------------------------------------------------------
ALTER TABLE public.okey_matches
  ADD COLUMN IF NOT EXISTS highest_opening_points int NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS highest_opening_pairs int NOT NULL DEFAULT 0;

COMMENT ON COLUMN public.okey_matches.highest_opening_points IS
  'Katlamalı mod: bu elde şimdiye kadarki en yüksek seri açılış puanı; sonraki açılış bundan >=1 fazla olmalı.';
COMMENT ON COLUMN public.okey_matches.highest_opening_pairs IS
  'Katlamalı mod: bu elde şimdiye kadarki en yüksek çift açılış sayısı; sonraki çift açılış bundan >=1 fazla olmalı.';

-- -----------------------------------------------------------------------------
-- 3) Oyuncu eli: çift bilgisi (ceza hesabı için — RULES.md §7)
-- -----------------------------------------------------------------------------
ALTER TABLE public.okey_player_hands
  ADD COLUMN IF NOT EXISTS opened_with_pairs boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS went_for_pairs boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS opened_at_hand_no int;

COMMENT ON COLUMN public.okey_player_hands.opened_with_pairs IS
  'Oyuncu elini ÇİFT ile açtıysa true → bitiremezse elde kalanların 2 katı ceza (RULES.md §7).';
COMMENT ON COLUMN public.okey_player_hands.went_for_pairs IS
  'Oyuncu çifte gittiğini beyan ettiyse true → hiç açamazsa 404 ceza (RULES.md §7).';

-- -----------------------------------------------------------------------------
-- 4) meld_type: 'pair' eklenir
-- -----------------------------------------------------------------------------
ALTER TABLE public.okey_table_melds
  DROP CONSTRAINT IF EXISTS okey_table_melds_meld_type_check;
ALTER TABLE public.okey_table_melds
  ADD CONSTRAINT okey_table_melds_meld_type_check
  CHECK (meld_type IN ('run', 'set', 'pair'));

-- -----------------------------------------------------------------------------
-- 5) win_type: 101 Okey bitiş türleri
-- -----------------------------------------------------------------------------
ALTER TABLE public.okey_matches
  DROP CONSTRAINT IF EXISTS okey_matches_win_type_check;
ALTER TABLE public.okey_matches
  ADD CONSTRAINT okey_matches_win_type_check
  CHECK (win_type IS NULL OR win_type IN ('normal', 'okey', 'elden', 'cift', 'elden_okey'));

-- =============================================================================
-- KURAL DOĞRULAYICILAR
-- =============================================================================

-- -----------------------------------------------------------------------------
-- okey_expected_run_number: seride [p_index]. taşın olması gereken numara.
-- RULES.md §2: 13'ten sonra bir kez 1'e sarılabilir (12-13-1 geçerli),
-- 1'den sonra devam edilemez (13-1-2 geçersiz).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.okey_expected_run_number(p_start int, p_index int)
RETURNS int
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT CASE
    WHEN p_start + p_index <= 13 THEN p_start + p_index
    WHEN p_start + p_index = 14 THEN 1
    ELSE NULL
  END;
$$;
REVOKE ALL ON FUNCTION public.okey_expected_run_number(int, int) FROM PUBLIC, anon, authenticated;

-- -----------------------------------------------------------------------------
-- okey_find_run_start: geçerliyse serinin başlangıç numarası, değilse NULL
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

  -- Seri tek renk olmalı (jokerler hariç)
  FOR i IN 0 .. v_len - 1 LOOP
    v_tile := p_tiles -> i;
    IF public.okey_tile_is_joker(v_tile, p_okey_tile) THEN CONTINUE; END IF;
    IF v_color IS NULL THEN
      v_color := v_tile->>'color';
    ELSIF (v_tile->>'color') IS DISTINCT FROM v_color THEN
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
      IF (v_tile->>'number')::int IS DISTINCT FROM v_expected THEN
        v_ok := false;
        EXIT;
      END IF;
    END LOOP;
    IF v_ok THEN RETURN s; END IF;
  END LOOP;

  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION public.okey_find_run_start(jsonb, jsonb) FROM PUBLIC, anon, authenticated;

-- -----------------------------------------------------------------------------
-- okey_is_valid_run (yeniden tanımlanır: artık 12-13-1 geçerli)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.okey_is_valid_run(p_tiles jsonb, p_okey_tile jsonb)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT public.okey_find_run_start(p_tiles, p_okey_tile) IS NOT NULL;
$$;
REVOKE ALL ON FUNCTION public.okey_is_valid_run(jsonb, jsonb) FROM PUBLIC, anon, authenticated;

-- -----------------------------------------------------------------------------
-- okey_is_valid_pair: aynı renk + aynı rakam 2 taş (joker her taşla eşleşir)
-- -----------------------------------------------------------------------------
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
       OR (p_tiles -> 0) = (p_tiles -> 1)
     );
$$;
REVOKE ALL ON FUNCTION public.okey_is_valid_pair(jsonb, jsonb) FROM PUBLIC, anon, authenticated;

-- -----------------------------------------------------------------------------
-- okey_meld_points (yeniden tanımlanır: 13-1'de 1 = 1 puan)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.okey_meld_points(p_tiles jsonb, p_okey_tile jsonb)
RETURNS int
LANGUAGE plpgsql
IMMUTABLE
SET search_path = ''
AS $$
DECLARE
  v_len int := jsonb_array_length(p_tiles);
  v_start int;
  v_shared int;
  v_sum int := 0;
  v_tile jsonb;
  i int;
BEGIN
  v_start := public.okey_find_run_start(p_tiles, p_okey_tile);
  IF v_start IS NOT NULL THEN
    FOR i IN 0 .. v_len - 1 LOOP
      v_sum := v_sum + public.okey_expected_run_number(v_start, i);
    END LOOP;
    RETURN v_sum;
  END IF;

  IF public.okey_is_valid_set(p_tiles, p_okey_tile) THEN
    FOR i IN 0 .. v_len - 1 LOOP
      v_tile := p_tiles -> i;
      IF NOT public.okey_tile_is_joker(v_tile, p_okey_tile) THEN
        v_shared := (v_tile->>'number')::int;
        EXIT;
      END IF;
    END LOOP;
    IF v_shared IS NULL THEN v_shared := (p_okey_tile->>'number')::int; END IF;
    RETURN v_shared * v_len;
  END IF;

  RAISE EXCEPTION 'APP:invalid_meld' USING ERRCODE = '22023';
END;
$$;
REVOKE ALL ON FUNCTION public.okey_meld_points(jsonb, jsonb) FROM PUBLIC, anon, authenticated;

NOTIFY pgrst, 'reload schema';

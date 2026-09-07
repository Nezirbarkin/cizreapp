-- =============================================================================
-- 101 Okey modülü — Faz A / Adım 2: kural doğrulama yardımcı fonksiyonları
-- -----------------------------------------------------------------------------
-- RULES.md'deki (lib/okey/engine/RULES.md) kuralların PL/pgSQL karşılığı.
-- Bu fonksiyonlar tablo okumaz/yazmaz (yalnız parametre olarak verilen taş
-- listeleri üzerinde hesap yapar), bu yüzden SECURITY DEFINER değildir.
-- Yine de dış dünyaya (authenticated) açılmazlar — yalnızca aşağıdaki oyun
-- RPC'lerinden (aynı rol/sahiplik altında) çağrılırlar.
--
-- Taş JSON şekli (Dart OkeyTile.toMap() ile birebir):
--   {"color": "red"|"yellow"|"black"|"blue"|null, "number": int|null, "isFalseJoker": bool}
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '5s';

-- -----------------------------------------------------------------------------
-- okey_tile_is_joker: taş, o elin okey taşı için joker mi?
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.okey_tile_is_joker(p_tile jsonb, p_okey_tile jsonb)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT (p_tile->>'isFalseJoker')::boolean = true
     OR (
       (p_tile->>'color') = (p_okey_tile->>'color')
       AND (p_tile->>'number')::int = (p_okey_tile->>'number')::int
     );
$$;
REVOKE ALL ON FUNCTION public.okey_tile_is_joker(jsonb, jsonb) FROM PUBLIC, anon, authenticated;

-- -----------------------------------------------------------------------------
-- okey_is_valid_run: sıralı taş listesi geçerli bir per mi?
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.okey_is_valid_run(p_tiles jsonb, p_okey_tile jsonb)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
SET search_path = ''
AS $$
DECLARE
  v_len int := jsonb_array_length(p_tiles);
  v_target_color text;
  v_base int;
  v_idx int;
  v_tile jsonb;
  v_expected int;
BEGIN
  IF v_len < 3 OR v_len > 13 THEN RETURN false; END IF;

  FOR v_idx IN 0 .. v_len - 1 LOOP
    v_tile := p_tiles -> v_idx;
    IF public.okey_tile_is_joker(v_tile, p_okey_tile) THEN
      CONTINUE;
    END IF;
    IF v_target_color IS NULL THEN
      v_target_color := v_tile->>'color';
      v_base := (v_tile->>'number')::int - v_idx;
    ELSIF (v_tile->>'color') IS DISTINCT FROM v_target_color THEN
      RETURN false;
    END IF;
    v_expected := v_base + v_idx;
    IF (v_tile->>'number')::int IS DISTINCT FROM v_expected THEN
      RETURN false;
    END IF;
  END LOOP;

  IF v_base IS NOT NULL AND (v_base < 1 OR v_base + v_len - 1 > 13) THEN
    RETURN false;
  END IF;
  RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION public.okey_is_valid_run(jsonb, jsonb) FROM PUBLIC, anon, authenticated;

-- -----------------------------------------------------------------------------
-- okey_is_valid_set: taş listesi geçerli bir grup mu?
-- -----------------------------------------------------------------------------
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
    IF v_target_number IS NULL THEN
      v_target_number := (v_tile->>'number')::int;
    ELSIF (v_tile->>'number')::int IS DISTINCT FROM v_target_number THEN
      RETURN false;
    END IF;
    v_color := v_tile->>'color';
    IF v_color = ANY(v_used_colors) THEN RETURN false; END IF;
    v_used_colors := v_used_colors || v_color;
  END LOOP;
  RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION public.okey_is_valid_set(jsonb, jsonb) FROM PUBLIC, anon, authenticated;

-- -----------------------------------------------------------------------------
-- okey_is_valid_meld: per veya grup
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.okey_is_valid_meld(p_tiles jsonb, p_okey_tile jsonb)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT public.okey_is_valid_run(p_tiles, p_okey_tile)
      OR public.okey_is_valid_set(p_tiles, p_okey_tile);
$$;
REVOKE ALL ON FUNCTION public.okey_is_valid_meld(jsonb, jsonb) FROM PUBLIC, anon, authenticated;

-- -----------------------------------------------------------------------------
-- okey_meld_points: el açma (≥101) hesabı için bir meld'in puanı
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.okey_meld_points(p_tiles jsonb, p_okey_tile jsonb)
RETURNS int
LANGUAGE plpgsql
IMMUTABLE
SET search_path = ''
AS $$
DECLARE
  v_len int := jsonb_array_length(p_tiles);
  v_base int;
  v_shared int;
  v_sum int := 0;
  i int;
  v_tile jsonb;
BEGIN
  IF public.okey_is_valid_run(p_tiles, p_okey_tile) THEN
    FOR i IN 0 .. v_len - 1 LOOP
      v_tile := p_tiles -> i;
      IF NOT public.okey_tile_is_joker(v_tile, p_okey_tile) THEN
        v_base := (v_tile->>'number')::int - i;
        EXIT;
      END IF;
    END LOOP;
    IF v_base IS NULL THEN v_base := (p_okey_tile->>'number')::int; END IF;
    FOR i IN 0 .. v_len - 1 LOOP
      v_sum := v_sum + v_base + i;
    END LOOP;
    RETURN v_sum;
  ELSIF public.okey_is_valid_set(p_tiles, p_okey_tile) THEN
    FOR i IN 0 .. v_len - 1 LOOP
      v_tile := p_tiles -> i;
      IF NOT public.okey_tile_is_joker(v_tile, p_okey_tile) THEN
        v_shared := (v_tile->>'number')::int;
        EXIT;
      END IF;
    END LOOP;
    IF v_shared IS NULL THEN v_shared := (p_okey_tile->>'number')::int; END IF;
    RETURN v_shared * v_len;
  ELSE
    RAISE EXCEPTION 'APP:invalid_meld' USING ERRCODE = '22023';
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.okey_meld_points(jsonb, jsonb) FROM PUBLIC, anon, authenticated;

-- -----------------------------------------------------------------------------
-- okey_is_valid_pairs_hand: 14 taş 7 geçerli çift oluşturuyor mu?
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.okey_is_valid_pairs_hand(p_tiles jsonb, p_okey_tile jsonb)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
SET search_path = ''
AS $$
DECLARE
  v_len int := jsonb_array_length(p_tiles);
  v_non_jokers jsonb[] := ARRAY[]::jsonb[];
  v_jokers_count int := 0;
  v_used boolean[];
  v_unmatched int := 0;
  v_paired int;
  i int;
  j int;
  v_tile jsonb;
BEGIN
  IF v_len <> 14 THEN RETURN false; END IF;

  FOR i IN 0 .. v_len - 1 LOOP
    v_tile := p_tiles -> i;
    IF public.okey_tile_is_joker(v_tile, p_okey_tile) THEN
      v_jokers_count := v_jokers_count + 1;
    ELSE
      v_non_jokers := v_non_jokers || v_tile;
    END IF;
  END LOOP;

  IF array_length(v_non_jokers, 1) IS NULL THEN
    RETURN v_jokers_count % 2 = 0;
  END IF;

  v_used := array_fill(false, ARRAY[array_length(v_non_jokers, 1)]);
  FOR i IN 1 .. array_length(v_non_jokers, 1) LOOP
    IF v_used[i] THEN CONTINUE; END IF;
    v_paired := NULL;
    FOR j IN i + 1 .. array_length(v_non_jokers, 1) LOOP
      IF NOT v_used[j] AND v_non_jokers[j] = v_non_jokers[i] THEN
        v_paired := j;
        EXIT;
      END IF;
    END LOOP;
    IF v_paired IS NOT NULL THEN
      v_used[i] := true;
      v_used[v_paired] := true;
    ELSE
      v_used[i] := true;
      v_unmatched := v_unmatched + 1;
    END IF;
  END LOOP;

  IF v_jokers_count < v_unmatched THEN RETURN false; END IF;
  RETURN (v_jokers_count - v_unmatched) % 2 = 0;
END;
$$;
REVOKE ALL ON FUNCTION public.okey_is_valid_pairs_hand(jsonb, jsonb) FROM PUBLIC, anon, authenticated;

-- -----------------------------------------------------------------------------
-- okey_count_jokers / okey_tile_penalty_value / okey_hand_penalty_value
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.okey_count_jokers(p_tiles jsonb, p_okey_tile jsonb)
RETURNS int
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT count(*)::int FROM jsonb_array_elements(p_tiles) AS t
  WHERE public.okey_tile_is_joker(t, p_okey_tile);
$$;
REVOKE ALL ON FUNCTION public.okey_count_jokers(jsonb, jsonb) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.okey_tile_penalty_value(p_tile jsonb, p_okey_tile jsonb)
RETURNS int
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT CASE
    WHEN (p_tile->>'isFalseJoker')::boolean = true THEN (p_okey_tile->>'number')::int
    ELSE (p_tile->>'number')::int
  END;
$$;
REVOKE ALL ON FUNCTION public.okey_tile_penalty_value(jsonb, jsonb) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.okey_hand_penalty_value(p_tiles jsonb, p_okey_tile jsonb)
RETURNS int
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT COALESCE(sum(public.okey_tile_penalty_value(t, p_okey_tile)), 0)::int
  FROM jsonb_array_elements(p_tiles) AS t;
$$;
REVOKE ALL ON FUNCTION public.okey_hand_penalty_value(jsonb, jsonb) FROM PUBLIC, anon, authenticated;

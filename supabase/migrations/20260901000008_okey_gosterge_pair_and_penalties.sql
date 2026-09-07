-- =============================================================================
-- 101 Okey Plus — GÖSTERGE ÇİFTİ + OKEY ELDE KALMA CEZASI
-- -----------------------------------------------------------------------------
-- 1) GÖSTERGE ÇİFTİ (yeni kural)
--    Gösterge taşının bir kopyası ortada açık durduğu için oyunda YALNIZCA
--    BİR kopyası kalır — yani onun gerçek çiftini yapmak imkânsızdır. Bu
--    yüzden göstergeyle aynı taşı elinde tutan oyuncu, o TEK taşı başlı
--    başına bir ÇİFT olarak indirebilir.
--    Örnek: elinde 4 gerçek çift olan oyuncu, göstergeyle birlikte 5 çift
--    sayılır ve açabilir.
--
-- 2) GÖSTERGE ÇİFTİNE İŞLEME YAPILAMAZ
--    Bu çift tek taştan oluşur ve tamamlanamaz; üzerine taş eklenemez.
--    Ayrı bir tür (`gosterge`) olarak işaretlenir ki hem arayüz hem de
--    okey_add_to_meld bunu ayırt edebilsin.
--
-- 3) OKEY ELDE KALIRSA CEZA
--    Okey atmak zaten cezalıydı. Artık el bittiğinde okey HÂLÂ ELİNDEYSE de
--    ceza yazılır (varsayılan 101, admin panelinden ayarlanabilir).
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '10s';

-- -----------------------------------------------------------------------------
-- Ayar: okey elde kalma cezası
-- -----------------------------------------------------------------------------
ALTER TABLE public.okey_settings
  ADD COLUMN IF NOT EXISTS okey_in_hand_penalty int NOT NULL DEFAULT 101;

COMMENT ON COLUMN public.okey_settings.okey_in_hand_penalty IS
  'El bittiğinde okey taşı hâlâ elinde olan oyuncuya eklenen ceza puanı.';

-- -----------------------------------------------------------------------------
-- Yeni per türü: gösterge çifti
-- -----------------------------------------------------------------------------
ALTER TABLE public.okey_table_melds
  DROP CONSTRAINT IF EXISTS okey_table_melds_meld_type_check;
ALTER TABLE public.okey_table_melds
  ADD CONSTRAINT okey_table_melds_meld_type_check
  CHECK (meld_type IN ('run', 'set', 'pair', 'gosterge'));

-- -----------------------------------------------------------------------------
-- okey_is_gosterge_pair: tek taşlık grup, göstergenin ta kendisi mi?
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.okey_is_gosterge_pair(
  p_tiles jsonb,
  p_indicator_tile jsonb
)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT p_indicator_tile IS NOT NULL
     AND jsonb_array_length(p_tiles) = 1
     AND (p_tiles -> 0) = p_indicator_tile;
$$;
REVOKE ALL ON FUNCTION public.okey_is_gosterge_pair(jsonb, jsonb)
  FROM PUBLIC, anon, authenticated;

-- -----------------------------------------------------------------------------
-- okey_is_valid_pair_ex: normal çift VEYA gösterge çifti
--
-- Eski iki parametreli sürüm KORUNUR (başka yerler onu çağırıyor); bu üç
-- parametreli sürüm göstergeyi de bilir.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.okey_is_valid_pair_ex(
  p_tiles jsonb,
  p_okey_tile jsonb,
  p_indicator_tile jsonb
)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT public.okey_is_gosterge_pair(p_tiles, p_indicator_tile)
      OR public.okey_is_valid_pair(p_tiles, p_okey_tile);
$$;
REVOKE ALL ON FUNCTION public.okey_is_valid_pair_ex(jsonb, jsonb, jsonb)
  FROM PUBLIC, anon, authenticated;

-- -----------------------------------------------------------------------------
-- okey_lay_meld: çift açılışında GÖSTERGE ÇİFTİ de sayılır
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.okey_lay_meld(
  p_match_id uuid,
  p_groups jsonb,
  p_is_pairs boolean DEFAULT false
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid CONSTANT uuid := (SELECT auth.uid());
  v_match public.okey_matches%ROWTYPE;
  v_seat smallint;
  v_hand public.okey_player_hands%ROWTYPE;
  v_flat jsonb := '[]'::jsonb;
  v_group jsonb;
  v_points int := 0;
  v_pairs int := 0;
  v_remaining jsonb;
  v_tile jsonb;
  v_idx int;
  v_search int;
  v_req record;
  v_first_open boolean;
  i int;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501';
  END IF;
  IF jsonb_typeof(p_groups) <> 'array' OR jsonb_array_length(p_groups) = 0 THEN
    RAISE EXCEPTION 'APP:groups_required' USING ERRCODE = '22023';
  END IF;

  SELECT m.* INTO v_match FROM public.okey_matches AS m
  WHERE m.id = p_match_id FOR UPDATE;
  IF v_match.id IS NULL THEN
    RAISE EXCEPTION 'APP:not_found' USING ERRCODE = 'P0001';
  END IF;
  IF v_match.status <> 'in_progress' THEN
    RAISE EXCEPTION 'APP:match_finished' USING ERRCODE = 'P0001';
  END IF;

  SELECT rp.seat_no INTO v_seat FROM public.okey_room_players AS rp
  WHERE rp.room_id = v_match.room_id AND rp.user_id = v_uid;
  IF v_seat IS NULL THEN
    RAISE EXCEPTION 'APP:not_seated' USING ERRCODE = '42501';
  END IF;
  IF v_seat IS DISTINCT FROM v_match.turn_seat
     OR v_match.turn_phase <> 'discard' THEN
    RAISE EXCEPTION 'APP:not_your_turn' USING ERRCODE = '42501';
  END IF;

  SELECT h.* INTO v_hand FROM public.okey_player_hands AS h
  WHERE h.match_id = p_match_id AND h.seat_no = v_seat FOR UPDATE;
  IF v_hand.match_id IS NULL THEN
    RAISE EXCEPTION 'APP:hand_not_found' USING ERRCODE = 'P0001';
  END IF;

  v_first_open := NOT v_hand.is_opening_done;

  IF NOT v_first_open AND v_hand.opened_with_pairs <> p_is_pairs THEN
    RAISE EXCEPTION 'APP:opening_type_mismatch' USING ERRCODE = 'P0001';
  END IF;

  FOR i IN 0 .. jsonb_array_length(p_groups) - 1 LOOP
    v_group := p_groups -> i;
    IF p_is_pairs THEN
      -- GÖSTERGE ÇİFTİ de geçerli bir çifttir (tek taş, göstergenin eşi)
      IF NOT public.okey_is_valid_pair_ex(
               v_group, v_match.okey_tile, v_match.indicator_tile) THEN
        RAISE EXCEPTION 'APP:invalid_pair' USING ERRCODE = '22023';
      END IF;
      v_pairs := v_pairs + 1;
    ELSE
      IF NOT public.okey_is_valid_meld(v_group, v_match.okey_tile) THEN
        RAISE EXCEPTION 'APP:invalid_meld' USING ERRCODE = '22023';
      END IF;
      v_points := v_points + public.okey_meld_points(v_group, v_match.okey_tile);
    END IF;
    v_flat := v_flat || v_group;
  END LOOP;

  IF v_first_open THEN
    SELECT * INTO v_req FROM public.okey_required_opening(p_match_id, v_seat);
    IF p_is_pairs THEN
      IF v_pairs < v_req.min_pairs THEN
        RAISE EXCEPTION 'APP:pairs_below_threshold | gerekli: %, senin: %',
          v_req.min_pairs, v_pairs USING ERRCODE = 'P0001';
      END IF;
    ELSE
      IF v_points < v_req.min_points THEN
        RAISE EXCEPTION 'APP:points_below_threshold | gerekli: %, senin: %',
          v_req.min_points, v_points USING ERRCODE = 'P0001';
      END IF;
    END IF;
  END IF;

  v_remaining := v_hand.tiles;
  FOR i IN 0 .. jsonb_array_length(v_flat) - 1 LOOP
    v_tile := v_flat -> i;
    v_idx := NULL;
    FOR v_search IN 0 .. jsonb_array_length(v_remaining) - 1 LOOP
      IF v_remaining -> v_search = v_tile THEN
        v_idx := v_search;
        EXIT;
      END IF;
    END LOOP;
    IF v_idx IS NULL THEN
      RAISE EXCEPTION 'APP:tile_not_in_hand' USING ERRCODE = '22023';
    END IF;
    v_remaining := v_remaining - v_idx;
  END LOOP;

  UPDATE public.okey_player_hands
  SET tiles = v_remaining,
      is_opening_done = true,
      opened_with_pairs =
        CASE WHEN v_first_open THEN p_is_pairs ELSE opened_with_pairs END,
      opened_this_turn = CASE WHEN v_first_open THEN true ELSE opened_this_turn END,
      opened_at_hand_no = COALESCE(opened_at_hand_no, v_match.hand_no),
      updated_at = now()
  WHERE match_id = p_match_id AND seat_no = v_seat;

  FOR i IN 0 .. jsonb_array_length(p_groups) - 1 LOOP
    v_group := p_groups -> i;
    INSERT INTO public.okey_table_melds
      (match_id, hand_no, laid_by_seat, meld_type, tiles)
    VALUES (
      p_match_id, v_match.hand_no, v_seat,
      CASE
        -- Gösterge çifti AYRI türde işaretlenir: üzerine işleme yapılamaz
        WHEN public.okey_is_gosterge_pair(v_group, v_match.indicator_tile)
          THEN 'gosterge'
        WHEN p_is_pairs THEN 'pair'
        WHEN public.okey_is_valid_run(v_group, v_match.okey_tile) THEN 'run'
        ELSE 'set'
      END,
      v_group
    );
  END LOOP;

  IF v_first_open THEN
    UPDATE public.okey_matches
    SET highest_opening_points = GREATEST(highest_opening_points, v_points),
        highest_opening_pairs = GREATEST(highest_opening_pairs, v_pairs)
    WHERE id = p_match_id;
  END IF;

  INSERT INTO public.okey_moves (match_id, hand_no, seat_no, action)
  VALUES (p_match_id, v_match.hand_no, v_seat, 'lay_meld');
END;
$$;
REVOKE ALL ON FUNCTION public.okey_lay_meld(uuid, jsonb, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_lay_meld(uuid, jsonb, boolean) TO authenticated;

-- -----------------------------------------------------------------------------
-- okey_add_to_meld: GÖSTERGE ÇİFTİNE ve normal ÇİFTE işleme yapılamaz
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.okey_add_to_meld(
  p_match_id uuid,
  p_meld_id bigint,
  p_tile jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid CONSTANT uuid := (SELECT auth.uid());
  v_match public.okey_matches%ROWTYPE;
  v_seat smallint;
  v_hand public.okey_player_hands%ROWTYPE;
  v_meld public.okey_table_melds%ROWTYPE;
  v_new_tiles jsonb;
  v_remaining jsonb;
  v_idx int;
  i int;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501';
  END IF;

  SELECT m.* INTO v_match FROM public.okey_matches AS m
  WHERE m.id = p_match_id FOR UPDATE;
  IF v_match.id IS NULL THEN
    RAISE EXCEPTION 'APP:not_found' USING ERRCODE = 'P0001';
  END IF;
  IF v_match.status <> 'in_progress' THEN
    RAISE EXCEPTION 'APP:match_finished' USING ERRCODE = 'P0001';
  END IF;

  SELECT rp.seat_no INTO v_seat FROM public.okey_room_players AS rp
  WHERE rp.room_id = v_match.room_id AND rp.user_id = v_uid;
  IF v_seat IS NULL THEN
    RAISE EXCEPTION 'APP:not_seated' USING ERRCODE = '42501';
  END IF;
  IF v_seat IS DISTINCT FROM v_match.turn_seat
     OR v_match.turn_phase <> 'discard' THEN
    RAISE EXCEPTION 'APP:not_your_turn' USING ERRCODE = '42501';
  END IF;

  SELECT h.* INTO v_hand FROM public.okey_player_hands AS h
  WHERE h.match_id = p_match_id AND h.seat_no = v_seat FOR UPDATE;
  IF NOT v_hand.is_opening_done THEN
    RAISE EXCEPTION 'APP:opening_required' USING ERRCODE = 'P0001';
  END IF;

  SELECT tm.* INTO v_meld FROM public.okey_table_melds AS tm
  WHERE tm.id = p_meld_id AND tm.match_id = p_match_id FOR UPDATE;
  IF v_meld.id IS NULL THEN
    RAISE EXCEPTION 'APP:meld_not_found' USING ERRCODE = 'P0001';
  END IF;

  -- GÖSTERGE ÇİFTİ tamamlanamaz: üzerine taş EKLENEMEZ.
  IF v_meld.meld_type = 'gosterge' THEN
    RAISE EXCEPTION 'APP:gosterge_pair_not_processable' USING ERRCODE = 'P0001';
  END IF;
  -- Normal çiftler de per değildir; işleme yapılmaz.
  IF v_meld.meld_type = 'pair' THEN
    RAISE EXCEPTION 'APP:pair_not_processable' USING ERRCODE = 'P0001';
  END IF;

  v_remaining := v_hand.tiles;
  v_idx := NULL;
  FOR i IN 0 .. jsonb_array_length(v_remaining) - 1 LOOP
    IF v_remaining -> i = p_tile THEN
      v_idx := i;
      EXIT;
    END IF;
  END LOOP;
  IF v_idx IS NULL THEN
    RAISE EXCEPTION 'APP:tile_not_in_hand' USING ERRCODE = '22023';
  END IF;

  v_new_tiles := v_meld.tiles || jsonb_build_array(p_tile);
  IF NOT public.okey_is_valid_meld(v_new_tiles, v_match.okey_tile) THEN
    RAISE EXCEPTION 'APP:invalid_meld_after_add' USING ERRCODE = '22023';
  END IF;

  v_remaining := v_remaining - v_idx;

  UPDATE public.okey_player_hands
  SET tiles = v_remaining, updated_at = now()
  WHERE match_id = p_match_id AND seat_no = v_seat;

  UPDATE public.okey_table_melds
  SET tiles = v_new_tiles, updated_at = now()
  WHERE id = p_meld_id;

  INSERT INTO public.okey_moves (match_id, hand_no, seat_no, action, tile)
  VALUES (p_match_id, v_match.hand_no, v_seat, 'add_to_meld', p_tile);

  -- Eli boşaldıysa bitirdi (RULES.md §6) — atma ile aynı kural
  IF jsonb_array_length(v_remaining) = 0 THEN
    PERFORM public.okey_internal_finalize_hand(p_match_id, v_seat, NULL);
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.okey_add_to_meld(uuid, bigint, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_add_to_meld(uuid, bigint, jsonb) TO authenticated;

NOTIFY pgrst, 'reload schema';

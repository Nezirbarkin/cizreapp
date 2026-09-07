-- =============================================================================
-- 101 Okey Plus — GERÇEK BOT ZEKÂSI + OKEY ATMA CEZASI + EL SAYISI
-- -----------------------------------------------------------------------------
-- 1) BOTLAR EL AÇMIYORDU. Eski `okey_bot_take_turn` kendi yorumunda bunu
--    açıkça söylüyordu: "hiç per/grup açmaya/kazanmaya çalışmaz". Faz A'dan
--    kalma bir yer tutucuydu ve hiç geliştirilmemişti. Bot artık elindeki
--    perleri/grupları bulur, baraja ulaşıyorsa açar, işine yaramayan EN
--    YÜKSEK taşı atar ve okeyi asla atmaz.
--
-- 2) OKEY ATMA CEZASI. Okey taşını ıskartaya atmak artık cezalıdır; ceza
--    miktarı admin panelinden ayarlanabilir (varsayılan 101).
--
-- 3) EL SAYISI. Kaç el oynanacağı oda kurulurken belirlenir.
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '10s';

-- -----------------------------------------------------------------------------
-- Şema eklemeleri
-- -----------------------------------------------------------------------------
ALTER TABLE public.okey_settings
  ADD COLUMN IF NOT EXISTS okey_discard_penalty int NOT NULL DEFAULT 101;

COMMENT ON COLUMN public.okey_settings.okey_discard_penalty IS
  'Okey taşını ıskartaya atan oyuncuya el sonunda eklenen ceza puanı.';

ALTER TABLE public.okey_player_hands
  ADD COLUMN IF NOT EXISTS penalty_points int NOT NULL DEFAULT 0;

COMMENT ON COLUMN public.okey_player_hands.penalty_points IS
  'Bu el içinde toplanan ek cezalar (ör. okey atma). El sonunda skora eklenir.';

ALTER TABLE public.okey_rooms
  ADD COLUMN IF NOT EXISTS total_hands int NOT NULL DEFAULT 3;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'okey_rooms_total_hands_check'
  ) THEN
    ALTER TABLE public.okey_rooms
      ADD CONSTRAINT okey_rooms_total_hands_check
      CHECK (total_hands BETWEEN 1 AND 20);
  END IF;
END $$;

COMMENT ON COLUMN public.okey_rooms.total_hands IS
  'Maçın kaç el süreceği. Oda kurulurken seçilir.';

-- -----------------------------------------------------------------------------
-- okey_internal_best_meld: kalan taşlardan EN YÜKSEK PUANLI tek per/grubu bulur
--
-- Yalnızca DOĞAL taşlar kullanılır (okey/sahte joker hariç). Bot için bu
-- bilinçli bir sadeleştirme: jokerli kombinasyon arama kombinatoryal olarak
-- pahalı, kazancı ise küçük. Bot yine de baraja rahatça ulaşır.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.okey_internal_best_meld(
  p_tiles jsonb,
  p_okey_tile jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = ''
AS $$
DECLARE
  v_best jsonb := NULL;
  v_best_points int := 0;
  v_group jsonb;
  v_points int;
  v_color text;
  v_num int;
  v_run jsonb;
  v_len int;
  v_start int;
  v_i int;
  v_tile jsonb;
BEGIN
  IF p_tiles IS NULL OR jsonb_array_length(p_tiles) < 3 THEN
    RETURN NULL;
  END IF;

  -- ---- GRUPLAR: aynı sayı, farklı renkler (3 veya 4) ----
  FOR v_num IN 1 .. 13 LOOP
    v_group := '[]'::jsonb;
    FOREACH v_color IN ARRAY ARRAY['red', 'yellow', 'black', 'blue'] LOOP
      SELECT t INTO v_tile
      FROM jsonb_array_elements(p_tiles) AS t
      WHERE (t->>'number')::int = v_num
        AND t->>'color' = v_color
        AND NOT public.okey_tile_is_joker(t, p_okey_tile)
      LIMIT 1;
      IF v_tile IS NOT NULL THEN
        v_group := v_group || jsonb_build_array(v_tile);
      END IF;
      v_tile := NULL;
    END LOOP;

    IF jsonb_array_length(v_group) >= 3
       AND public.okey_is_valid_set(v_group, p_okey_tile) THEN
      v_points := public.okey_meld_points(v_group, p_okey_tile);
      IF v_points > v_best_points THEN
        v_best_points := v_points;
        v_best := v_group;
      END IF;
    END IF;
  END LOOP;

  -- ---- PERLER: aynı renk, ardışık sayılar (3+) ----
  FOREACH v_color IN ARRAY ARRAY['red', 'yellow', 'black', 'blue'] LOOP
    FOR v_start IN 1 .. 13 LOOP
      v_run := '[]'::jsonb;
      FOR v_i IN v_start .. 13 LOOP
        SELECT t INTO v_tile
        FROM jsonb_array_elements(p_tiles) AS t
        WHERE (t->>'number')::int = v_i
          AND t->>'color' = v_color
          AND NOT public.okey_tile_is_joker(t, p_okey_tile)
        LIMIT 1;
        EXIT WHEN v_tile IS NULL;
        v_run := v_run || jsonb_build_array(v_tile);
        v_tile := NULL;
      END LOOP;

      v_len := jsonb_array_length(v_run);
      IF v_len >= 3 AND public.okey_is_valid_run(v_run, p_okey_tile) THEN
        v_points := public.okey_meld_points(v_run, p_okey_tile);
        IF v_points > v_best_points THEN
          v_best_points := v_points;
          v_best := v_run;
        END IF;
      END IF;
    END LOOP;
  END LOOP;

  RETURN v_best;
END;
$$;
REVOKE ALL ON FUNCTION public.okey_internal_best_meld(jsonb, jsonb)
  FROM PUBLIC, anon, authenticated;

-- -----------------------------------------------------------------------------
-- okey_internal_find_melds: açgözlü olarak ardışık en iyi perleri toplar
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.okey_internal_find_melds(
  p_tiles jsonb,
  p_okey_tile jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = ''
AS $$
DECLARE
  v_remaining jsonb := COALESCE(p_tiles, '[]'::jsonb);
  v_groups jsonb := '[]'::jsonb;
  v_meld jsonb;
  v_tile jsonb;
  v_idx int;
  v_search int;
  v_scan int;
  v_guard int := 0;
BEGIN
  LOOP
    v_guard := v_guard + 1;
    EXIT WHEN v_guard > 8; -- 21 taşta en fazla 7 per olabilir; güvenlik freni

    v_meld := public.okey_internal_best_meld(v_remaining, p_okey_tile);
    EXIT WHEN v_meld IS NULL;

    v_groups := v_groups || jsonb_build_array(v_meld);

    -- Kullanılan taşları kalanlardan düş.
    --
    -- DİKKAT — PL/pgSQL TUZAĞI: `FOR v_idx IN ...` döngüsü v_idx adında YENİ
    -- ve döngüye ÖZEL bir değişken yaratır; dıştaki v_idx'i gölgeler ve
    -- döngü bitince dıştaki DEĞİŞMEMİŞ olur. Bu yüzden burada arama ayrı bir
    -- döngü değişkeniyle (v_scan) yapılır ve sonuç v_idx'e AÇIKÇA yazılır.
    -- İlk sürümde bu gölgeleme yüzünden taşlar hiç düşülmüyor, aynı per
    -- tekrar tekrar bulunuyor ve bot hiç açamıyordu.
    FOR v_search IN 0 .. jsonb_array_length(v_meld) - 1 LOOP
      v_tile := v_meld -> v_search;
      v_idx := NULL;
      FOR v_scan IN 0 .. jsonb_array_length(v_remaining) - 1 LOOP
        IF v_remaining -> v_scan = v_tile THEN
          v_idx := v_scan;
          EXIT;
        END IF;
      END LOOP;
      IF v_idx IS NOT NULL THEN
        v_remaining := v_remaining - v_idx;
      END IF;
    END LOOP;
  END LOOP;

  RETURN v_groups;
END;
$$;
REVOKE ALL ON FUNCTION public.okey_internal_find_melds(jsonb, jsonb)
  FROM PUBLIC, anon, authenticated;

-- -----------------------------------------------------------------------------
-- okey_internal_lay_groups_for_seat: bir koltuk ADINA per açar (auth YOK)
--
-- okey_lay_meld ile aynı işi yapar ama çağıranın kimliğine bakmaz; bot için.
-- Doğrulama yine tamdır: geçersiz grup veya baraj altı açılış reddedilir.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.okey_internal_lay_groups_for_seat(
  p_match_id uuid,
  p_seat smallint,
  p_groups jsonb
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_match public.okey_matches%ROWTYPE;
  v_hand public.okey_player_hands%ROWTYPE;
  v_req record;
  v_flat jsonb := '[]'::jsonb;
  v_group jsonb;
  v_points int := 0;
  v_remaining jsonb;
  v_tile jsonb;
  v_idx int;
  v_search int;
  v_first_open boolean;
  i int;
BEGIN
  IF p_groups IS NULL OR jsonb_array_length(p_groups) = 0 THEN
    RETURN false;
  END IF;

  SELECT m.* INTO v_match FROM public.okey_matches AS m WHERE m.id = p_match_id;
  IF v_match.id IS NULL OR v_match.status <> 'in_progress' THEN
    RETURN false;
  END IF;

  SELECT h.* INTO v_hand FROM public.okey_player_hands AS h
  WHERE h.match_id = p_match_id AND h.seat_no = p_seat FOR UPDATE;
  IF v_hand.match_id IS NULL THEN
    RETURN false;
  END IF;

  v_first_open := NOT v_hand.is_opening_done;

  -- Çiftle açmış bir el, seri açmaya geçemez
  IF NOT v_first_open AND v_hand.opened_with_pairs THEN
    RETURN false;
  END IF;

  FOR i IN 0 .. jsonb_array_length(p_groups) - 1 LOOP
    v_group := p_groups -> i;
    IF NOT public.okey_is_valid_meld(v_group, v_match.okey_tile) THEN
      RETURN false;
    END IF;
    v_points := v_points + public.okey_meld_points(v_group, v_match.okey_tile);
    v_flat := v_flat || v_group;
  END LOOP;

  -- İlk açılışta baraj kontrolü (RULES.md §3/§5)
  IF v_first_open THEN
    SELECT * INTO v_req FROM public.okey_required_opening(p_match_id, p_seat);
    IF v_points < v_req.min_points THEN
      RETURN false;
    END IF;
  END IF;

  -- Taşları elden düş
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
      RETURN false; -- taş elde değil: hiçbir şey yapma
    END IF;
    v_remaining := v_remaining - v_idx;
  END LOOP;

  UPDATE public.okey_player_hands
  SET tiles = v_remaining,
      is_opening_done = true,
      opened_with_pairs =
        CASE WHEN v_first_open THEN false ELSE opened_with_pairs END,
      opened_this_turn = CASE WHEN v_first_open THEN true ELSE opened_this_turn END,
      opened_at_hand_no = COALESCE(opened_at_hand_no, v_match.hand_no),
      updated_at = now()
  WHERE match_id = p_match_id AND seat_no = p_seat;

  FOR i IN 0 .. jsonb_array_length(p_groups) - 1 LOOP
    v_group := p_groups -> i;
    INSERT INTO public.okey_table_melds
      (match_id, hand_no, laid_by_seat, meld_type, tiles)
    VALUES (
      p_match_id, v_match.hand_no, p_seat,
      CASE WHEN public.okey_is_valid_run(v_group, v_match.okey_tile)
           THEN 'run' ELSE 'set' END,
      v_group
    );
  END LOOP;

  IF v_first_open THEN
    UPDATE public.okey_matches
    SET highest_opening_points = GREATEST(highest_opening_points, v_points)
    WHERE id = p_match_id;
  END IF;

  INSERT INTO public.okey_moves (match_id, hand_no, seat_no, action)
  VALUES (p_match_id, v_match.hand_no, p_seat, 'lay_meld');

  RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION public.okey_internal_lay_groups_for_seat(uuid, smallint, jsonb)
  FROM PUBLIC, anon, authenticated;

-- -----------------------------------------------------------------------------
-- okey_internal_bot_pick_discard: botun atacağı taşı seçer
--
-- Kural sırası:
--   1) OKEY ASLA ATILMAZ (hem değerli hem de artık cezalı).
--   2) Perlere girmeyen taşlar arasından EN YÜKSEK sayılı olan atılır
--      (el sonunda ceza taş değerlerinden hesaplandığı için).
--   3) Hepsi perlerdeyse en yüksek sayılı taş atılır.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.okey_internal_bot_pick_discard(
  p_tiles jsonb,
  p_okey_tile jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = ''
AS $$
DECLARE
  v_groups jsonb;
  v_used jsonb := '[]'::jsonb;
  v_candidate jsonb := NULL;
  v_best_num int := -1;
  v_tile jsonb;
  v_num int;
  i int;
  j int;
  v_in_meld boolean;
BEGIN
  IF p_tiles IS NULL OR jsonb_array_length(p_tiles) = 0 THEN
    RETURN NULL;
  END IF;

  v_groups := public.okey_internal_find_melds(p_tiles, p_okey_tile);
  FOR i IN 0 .. GREATEST(jsonb_array_length(v_groups) - 1, -1) LOOP
    v_used := v_used || (v_groups -> i);
  END LOOP;

  -- 1. tur: perlere girmeyen en yüksek taş
  FOR i IN 0 .. jsonb_array_length(p_tiles) - 1 LOOP
    v_tile := p_tiles -> i;
    CONTINUE WHEN public.okey_tile_is_joker(v_tile, p_okey_tile);

    v_in_meld := false;
    FOR j IN 0 .. GREATEST(jsonb_array_length(v_used) - 1, -1) LOOP
      IF v_used -> j = v_tile THEN
        v_in_meld := true;
        EXIT;
      END IF;
    END LOOP;
    CONTINUE WHEN v_in_meld;

    v_num := COALESCE((v_tile->>'number')::int, 0);
    IF v_num > v_best_num THEN
      v_best_num := v_num;
      v_candidate := v_tile;
    END IF;
  END LOOP;

  IF v_candidate IS NOT NULL THEN
    RETURN v_candidate;
  END IF;

  -- 2. tur: okey olmayan en yüksek taş
  FOR i IN 0 .. jsonb_array_length(p_tiles) - 1 LOOP
    v_tile := p_tiles -> i;
    CONTINUE WHEN public.okey_tile_is_joker(v_tile, p_okey_tile);
    v_num := COALESCE((v_tile->>'number')::int, 0);
    IF v_num > v_best_num THEN
      v_best_num := v_num;
      v_candidate := v_tile;
    END IF;
  END LOOP;

  -- Son çare: elde okeyden başka taş yoksa ilk taş
  RETURN COALESCE(v_candidate, p_tiles -> 0);
END;
$$;
REVOKE ALL ON FUNCTION public.okey_internal_bot_pick_discard(jsonb, jsonb)
  FROM PUBLIC, anon, authenticated;

-- -----------------------------------------------------------------------------
-- okey_bot_take_turn: ARTIK GERÇEKTEN OYNAR
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.okey_bot_take_turn(uuid);

CREATE FUNCTION public.okey_bot_take_turn(p_match_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid CONSTANT uuid := (SELECT auth.uid());
  v_match public.okey_matches%ROWTYPE;
  v_seat smallint;
  v_is_bot boolean;
  v_hand_tiles jsonb;
  v_groups jsonb;
  v_tile jsonb;
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
    RETURN;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.okey_room_players AS rp
    WHERE rp.room_id = v_match.room_id AND rp.user_id = v_uid
  ) THEN
    RAISE EXCEPTION 'APP:not_seated' USING ERRCODE = '42501';
  END IF;

  v_seat := v_match.turn_seat;

  SELECT rp.is_bot INTO v_is_bot FROM public.okey_room_players AS rp
  WHERE rp.room_id = v_match.room_id AND rp.seat_no = v_seat;
  IF NOT COALESCE(v_is_bot, false) THEN
    RETURN;
  END IF;

  -- 1) ÇEKME
  IF v_match.turn_phase = 'draw' THEN
    IF v_match.deck_remaining <= 0 THEN
      PERFORM public.okey_internal_finalize_hand(p_match_id, NULL, NULL);
      RETURN;
    END IF;
    PERFORM public.okey_internal_draw_for_seat(p_match_id, v_seat, 'deck');
    SELECT m.* INTO v_match FROM public.okey_matches AS m WHERE m.id = p_match_id;
  END IF;

  -- 2) AÇMA — elindeki perler baraja yetiyorsa aç
  SELECT h.tiles INTO v_hand_tiles FROM public.okey_player_hands AS h
  WHERE h.match_id = p_match_id AND h.seat_no = v_seat;

  v_groups := public.okey_internal_find_melds(v_hand_tiles, v_match.okey_tile);
  IF jsonb_array_length(COALESCE(v_groups, '[]'::jsonb)) > 0 THEN
    -- Baraj altındaysa fonksiyon false döner ve hiçbir şey değişmez
    PERFORM public.okey_internal_lay_groups_for_seat(p_match_id, v_seat, v_groups);
    SELECT h.tiles INTO v_hand_tiles FROM public.okey_player_hands AS h
    WHERE h.match_id = p_match_id AND h.seat_no = v_seat;
  END IF;

  -- 3) ATMA — okey asla atılmaz
  IF v_hand_tiles IS NOT NULL AND jsonb_array_length(v_hand_tiles) > 0 THEN
    v_tile := public.okey_internal_bot_pick_discard(v_hand_tiles, v_match.okey_tile);
    IF v_tile IS NOT NULL THEN
      PERFORM public.okey_internal_discard_for_seat(p_match_id, v_seat, v_tile);
    END IF;
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.okey_bot_take_turn(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_bot_take_turn(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';

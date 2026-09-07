-- =============================================================================
-- 101 Okey Plus — SERİ AÇANIN 3 ÇİFT HAKKI **TUR BAŞINA**DIR
-- -----------------------------------------------------------------------------
-- Kullanıcı düzeltmesi (2026-09-05): "seri açan biri tur başına 3 çift atar,
-- tur döndüğünde yine en fazla 3 çift atar."
--
-- 20260905000008 sınırı EL BAŞINA uygulamıştı: hak masadaki çiftlerden
-- sayıldığı için (okey_internal_pairs_laid_by) bir kez 3 çift indiren oyuncu
-- o el boyunca bir daha çift indiremiyordu. Doğrusu: sayaç HER TURDA sıfırdan
-- başlar.
--
-- SAYAÇ NEDEN `turn_token`E BAĞLI, AYRI BİR SIFIRLAMA KODUNA DEĞİL:
-- okey_matches.turn_token yalnızca sıra devrederken üretilir (tek yazan yer:
-- okey_internal_discard_for_seat) ve tur boyunca sabittir — yani turun
-- kimliğidir. Sayacı "hangi tur için sayıldığı" ile birlikte tutmak, sayacı
-- KENDİ KENDİNE sıfırlar: yeni turda token değişir, eski sayı düşer.
--
-- Alternatif, sayacı tur sonunda sıfırlamaktı (okey_internal_discard_for_seat
-- içindeki opened_this_turn/side_draw_tile temizliğinin yanına). Reddedildi:
-- o fonksiyonun ~200 satırlık gövdesini bu değişiklik için ileri taşımak
-- gerekirdi ve sıfırlamayı ATLAYAN her yol (el bitişi, deste bitişi,
-- gelecekte eklenecek bir tur sonu dalı) sessiz bir hata kaynağı olurdu.
-- Token karşılaştırması böyle bir yol bırakmaz.
--
-- okey_internal_pairs_laid_by DÜŞÜRÜLÜR: el başına sayım artık hiçbir kuralın
-- girdisi değil. Duran ölü bir yardımcı, bir sonraki okuyucuya "hak el
-- başınaymış" dedirtirdi.
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '10s';

-- -----------------------------------------------------------------------------
-- ŞEMA — turluk sayaç
-- -----------------------------------------------------------------------------
ALTER TABLE public.okey_player_hands
  ADD COLUMN IF NOT EXISTS series_pairs_turn_token uuid,
  ADD COLUMN IF NOT EXISTS series_pairs_turn_count smallint NOT NULL DEFAULT 0;

COMMENT ON COLUMN public.okey_player_hands.series_pairs_turn_token IS
  'series_pairs_turn_count HANGİ tur için sayıldı (okey_matches.turn_token). Token eskiyse sayaç 0 sayılır — tur başı sıfırlaması budur.';
COMMENT ON COLUMN public.okey_player_hands.series_pairs_turn_count IS
  'RULES.md §3: SERİ ile açmış koltuğun BU TURDA indirdiği çift sayısı (en çok okey_series_pairs_limit()).';

-- -----------------------------------------------------------------------------
-- okey_internal_series_pairs_this_turn: bu koltuk BU TURDA kaç çift indirdi?
-- Token eskiyse 0 döner.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.okey_internal_series_pairs_this_turn(
  p_match_id uuid,
  p_seat smallint
)
RETURNS int
LANGUAGE sql
STABLE
SET search_path = ''
AS $fn$
  SELECT COALESCE((
    SELECT CASE
             WHEN h.series_pairs_turn_token IS NOT DISTINCT FROM m.turn_token
               THEN h.series_pairs_turn_count
             ELSE 0
           END
    FROM public.okey_player_hands AS h
    JOIN public.okey_matches AS m ON m.id = h.match_id
    WHERE h.match_id = p_match_id AND h.seat_no = p_seat
  ), 0)::int;
$fn$;

COMMENT ON FUNCTION public.okey_internal_series_pairs_this_turn(uuid, smallint) IS
  'RULES.md §3: seri ile açan koltuğun bu TURDA indirdiği çift sayısı. Tur değişince (turn_token) kendiliğinden sıfırlanır.';

REVOKE ALL ON FUNCTION public.okey_internal_series_pairs_this_turn(uuid, smallint)
  FROM PUBLIC, anon;


-- -----------------------------------------------------------------------------
-- okey_lay_meld — gövde 20260905000008'den taşındı; fark: 3 çift hakkı EL
-- yerine TUR başına sayılır ve turluk sayaç yazılır.
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
AS $fn$
DECLARE
  v_uid CONSTANT uuid := (SELECT auth.uid());
  v_match public.okey_matches%ROWTYPE;
  v_seat smallint;
  v_hand public.okey_player_hands%ROWTYPE;
  v_flat jsonb := '[]'::jsonb;
  v_group jsonb;
  v_points int := 0;
  v_pairs int := 0;
  -- ANLIK PER PUANI ayrı bir sayaçtır ve v_points ile BİRLEŞTİRİLEMEZ
  -- (gerekçe: 20260905000001).
  v_open_points int := 0;
  v_remaining jsonb;
  v_tile jsonb;
  v_idx int;
  v_search int;
  v_req record;
  v_first_open boolean;
  -- Seri ile açmış elin ÇİFT indirmesi mi? (RULES.md §3)
  v_series_pairs boolean := false;
  v_already int := 0;
  v_limit int;
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
    -- ÇİFT açan SERİ indiremez: bu yön kapalı kalır (404 cezası ve çiftten
    -- bitiş ×2 çarpanı, çift açanın el boyunca çiftte kalmasına dayanır).
    IF v_hand.opened_with_pairs THEN
      RAISE EXCEPTION 'APP:opening_type_mismatch' USING ERRCODE = 'P0001';
    END IF;

    -- SERİ açan ÇİFT indirebilir — ama ancak masada çift açan biri varsa.
    IF NOT public.okey_internal_pairs_opener_exists(p_match_id, v_seat) THEN
      RAISE EXCEPTION 'APP:no_pairs_on_table' USING ERRCODE = 'P0001';
    END IF;
    v_series_pairs := true;
  END IF;

  -- Çiftle İLK açılış "çifte gidiyorum" beyanını gerektirir (RULES.md §7).
  -- Seri açanın SONRADAN çift indirmesi beyan İSTEMEZ: o oyuncu zaten
  -- açmıştır, yani 404'ün ("hiç açamayan") muhatabı değildir.
  IF v_first_open AND p_is_pairs AND NOT v_hand.went_for_pairs THEN
    RAISE EXCEPTION 'APP:pairs_declaration_required' USING ERRCODE = 'P0001';
  END IF;

  FOR i IN 0 .. jsonb_array_length(p_groups) - 1 LOOP
    v_group := p_groups -> i;
    IF p_is_pairs THEN
      IF NOT public.okey_is_valid_pair_ex(
               v_group, v_match.okey_tile, v_match.indicator_tile) THEN
        RAISE EXCEPTION 'APP:invalid_pair' USING ERRCODE = '22023';
      END IF;
      v_pairs := v_pairs + 1;
      v_open_points := v_open_points + public.okey_hand_penalty_value(
                         v_group, v_match.okey_tile);
    ELSE
      IF NOT public.okey_is_valid_meld(v_group, v_match.okey_tile) THEN
        RAISE EXCEPTION 'APP:invalid_meld' USING ERRCODE = '22023';
      END IF;
      v_points := v_points + public.okey_meld_points(v_group, v_match.okey_tile);
      v_open_points := v_open_points + public.okey_meld_points(
                         v_group, v_match.okey_tile);
    END IF;
    v_flat := v_flat || v_group;
  END LOOP;

  -- TUR BAŞINA 3 ÇİFT (RULES.md §3) — yalnızca SERİ ile açmış el için. Sayaç
  -- turun kimliğine bağlı; sıra döndüğünde hak yeniden 3'tür. Çift açanın
  -- indirebileceği çift sayısı sınırsızdır; onun eli zaten çifttir.
  IF v_series_pairs THEN
    v_limit := public.okey_series_pairs_limit();
    v_already := public.okey_internal_series_pairs_this_turn(p_match_id, v_seat);
    IF v_already + v_pairs > v_limit THEN
      RAISE EXCEPTION
        'APP:series_pairs_limit | tur sınırı: %, bu turda indirdiğin: %, denediğin: %',
        v_limit, v_already, v_pairs USING ERRCODE = 'P0001';
    END IF;
  END IF;

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

  -- RULES.md §6: bitiş yalnızca ATMA ile olur (bkz. 20260903000002).
  IF jsonb_array_length(v_remaining) = 0 THEN
    RAISE EXCEPTION 'APP:must_keep_discard_tile' USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.okey_player_hands
  SET tiles = v_remaining,
      is_opening_done = true,
      -- Seri açanın çift indirmesi AÇILIŞ TÜRÜNÜ DEĞİŞTİRMEZ: bu bayrak el
      -- sonu çarpanlarını ve 404'ü besler (okey_internal_finalize_hand).
      opened_with_pairs =
        CASE WHEN v_first_open THEN p_is_pairs ELSE opened_with_pairs END,
      opened_this_turn = CASE WHEN v_first_open THEN true ELSE opened_this_turn END,
      opened_at_hand_no = COALESCE(opened_at_hand_no, v_match.hand_no),
      series_pairs_turn_token =
        CASE WHEN v_series_pairs THEN v_match.turn_token
             ELSE series_pairs_turn_token END,
      series_pairs_turn_count =
        CASE WHEN v_series_pairs THEN (v_already + v_pairs)::smallint
             ELSE series_pairs_turn_count END,
      updated_at = now()
  WHERE match_id = p_match_id AND seat_no = v_seat;

  FOR i IN 0 .. jsonb_array_length(p_groups) - 1 LOOP
    v_group := p_groups -> i;
    INSERT INTO public.okey_table_melds
      (match_id, hand_no, laid_by_seat, meld_type, tiles)
    VALUES (
      p_match_id, v_match.hand_no, v_seat,
      CASE
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

  -- ANLIK PER PUANI: masaya serilen değer bu koltuğun sayacına yazılır.
  PERFORM public.okey_internal_add_open_points(
    p_match_id, v_seat, v_open_points);

  INSERT INTO public.okey_moves (match_id, hand_no, seat_no, action)
  VALUES (p_match_id, v_match.hand_no, v_seat, 'lay_meld');
END;
$fn$;

REVOKE ALL ON FUNCTION public.okey_lay_meld(uuid, jsonb, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_lay_meld(uuid, jsonb, boolean) TO authenticated;


-- -----------------------------------------------------------------------------
-- okey_internal_lay_pairs_for_seat — gövde 20260905000008'den taşındı;
-- fark: hak TUR başına sayılır, turluk sayaç yazılır.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.okey_internal_lay_pairs_for_seat(
  p_match_id uuid,
  p_seat smallint,
  p_groups jsonb
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_match public.okey_matches%ROWTYPE;
  v_hand public.okey_player_hands%ROWTYPE;
  v_req record;
  v_groups jsonb;
  v_flat jsonb := '[]'::jsonb;
  v_group jsonb;
  v_pairs int := 0;
  v_remaining jsonb;
  v_tile jsonb;
  v_idx int;
  v_search int;
  v_first_open boolean;
  v_series_pairs boolean := false;
  v_already int := 0;
  v_allowance int;
  v_hand_len int;
  v_tile_total int;
  v_points int := 0;
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
  v_groups := p_groups;

  IF v_first_open THEN
    -- Çiftle ilk açılış beyan ister (RULES.md §7).
    IF NOT v_hand.went_for_pairs THEN
      RETURN false;
    END IF;
  ELSIF NOT v_hand.opened_with_pairs THEN
    -- SERİ ile açmış koltuk: masada çift açan olmalı; hak TUR başınadır.
    IF NOT public.okey_internal_pairs_opener_exists(p_match_id, p_seat) THEN
      RETURN false;
    END IF;
    v_already := public.okey_internal_series_pairs_this_turn(p_match_id, p_seat);
    v_allowance := public.okey_series_pairs_limit() - v_already;
    IF v_allowance <= 0 THEN
      RETURN false;
    END IF;
    v_series_pairs := true;

    -- Kalan hakka göre buda: bot tüm çiftlerini birden gönderdiğinde çağrı
    -- tümden reddedilmesin, hakkı kadarı geçsin.
    WHILE jsonb_array_length(v_groups) > v_allowance LOOP
      v_groups := v_groups - (jsonb_array_length(v_groups) - 1);
    END LOOP;
  END IF;

  -- Elde atılacak en az 1 taş kalmalı (RULES.md §6) — sondan buda.
  v_hand_len := jsonb_array_length(v_hand.tiles);
  LOOP
    EXIT WHEN jsonb_array_length(v_groups) = 0;
    v_tile_total := 0;
    FOR i IN 0 .. jsonb_array_length(v_groups) - 1 LOOP
      v_tile_total := v_tile_total + jsonb_array_length(v_groups -> i);
    END LOOP;
    EXIT WHEN v_tile_total < v_hand_len;
    v_groups := v_groups - (jsonb_array_length(v_groups) - 1);
  END LOOP;

  IF jsonb_array_length(v_groups) = 0 THEN
    RETURN false;
  END IF;

  FOR i IN 0 .. jsonb_array_length(v_groups) - 1 LOOP
    v_group := v_groups -> i;
    IF NOT public.okey_is_valid_pair_ex(
             v_group, v_match.okey_tile, v_match.indicator_tile) THEN
      RETURN false;
    END IF;
    v_pairs := v_pairs + 1;
    v_points := v_points + public.okey_hand_penalty_value(
                  v_group, v_match.okey_tile);
    v_flat := v_flat || v_group;
  END LOOP;

  IF v_first_open THEN
    SELECT * INTO v_req FROM public.okey_required_opening(p_match_id, p_seat);
    IF v_pairs < v_req.min_pairs THEN
      RETURN false;
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
      RETURN false;
    END IF;
    v_remaining := v_remaining - v_idx;
  END LOOP;

  IF jsonb_array_length(v_remaining) = 0 THEN
    RETURN false;
  END IF;

  UPDATE public.okey_player_hands
  SET tiles = v_remaining,
      is_opening_done = true,
      -- Yalnızca İLK açılış türü belirler (bkz. okey_lay_meld).
      opened_with_pairs =
        CASE WHEN v_first_open THEN true ELSE opened_with_pairs END,
      opened_this_turn = CASE WHEN v_first_open THEN true ELSE opened_this_turn END,
      opened_at_hand_no = COALESCE(opened_at_hand_no, v_match.hand_no),
      series_pairs_turn_token =
        CASE WHEN v_series_pairs THEN v_match.turn_token
             ELSE series_pairs_turn_token END,
      series_pairs_turn_count =
        CASE WHEN v_series_pairs THEN (v_already + v_pairs)::smallint
             ELSE series_pairs_turn_count END,
      updated_at = now()
  WHERE match_id = p_match_id AND seat_no = p_seat;

  FOR i IN 0 .. jsonb_array_length(v_groups) - 1 LOOP
    v_group := v_groups -> i;
    INSERT INTO public.okey_table_melds
      (match_id, hand_no, laid_by_seat, meld_type, tiles)
    VALUES (
      p_match_id, v_match.hand_no, p_seat,
      CASE WHEN public.okey_is_gosterge_pair(v_group, v_match.indicator_tile)
           THEN 'gosterge' ELSE 'pair' END,
      v_group
    );
  END LOOP;

  IF v_first_open THEN
    UPDATE public.okey_matches
    SET highest_opening_pairs = GREATEST(highest_opening_pairs, v_pairs)
    WHERE id = p_match_id;
  END IF;

  -- ANLIK PER PUANI (bkz. okey_lay_meld).
  PERFORM public.okey_internal_add_open_points(p_match_id, p_seat, v_points);

  INSERT INTO public.okey_moves (match_id, hand_no, seat_no, action)
  VALUES (p_match_id, v_match.hand_no, p_seat, 'lay_meld');

  RETURN true;
END;
$fn$;

REVOKE ALL ON FUNCTION public.okey_internal_lay_pairs_for_seat(uuid, smallint, jsonb)
  FROM PUBLIC, anon, authenticated;


-- -----------------------------------------------------------------------------
-- okey_internal_can_lay_pair_with — gövde 20260905000008'den taşındı;
-- fark: hak TUR başına okunur.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.okey_internal_can_lay_pair_with(
  p_match_id uuid,
  p_seat smallint,
  p_tile jsonb
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SET search_path = ''
AS $fn$
DECLARE
  v_match public.okey_matches%ROWTYPE;
  v_hand public.okey_player_hands%ROWTYPE;
  v_copies int := 0;
  i int;
BEGIN
  SELECT m.* INTO v_match FROM public.okey_matches AS m WHERE m.id = p_match_id;
  IF v_match.id IS NULL THEN
    RETURN false;
  END IF;

  SELECT h.* INTO v_hand FROM public.okey_player_hands AS h
  WHERE h.match_id = p_match_id AND h.seat_no = p_seat;
  IF v_hand.match_id IS NULL OR NOT v_hand.is_opening_done THEN
    RETURN false;
  END IF;

  -- Seri ile açmışsa: masada çift olmalı ve BU TURKİ hakkı dolmamış olmalı.
  IF NOT v_hand.opened_with_pairs THEN
    IF NOT public.okey_internal_pairs_opener_exists(p_match_id, p_seat) THEN
      RETURN false;
    END IF;
    IF public.okey_internal_series_pairs_this_turn(p_match_id, p_seat)
       >= public.okey_series_pairs_limit() THEN
      RETURN false;
    END IF;
  END IF;

  -- Çift indirdikten sonra elde atılacak taş kalmalı (RULES.md §6):
  -- çekilen taşla birlikte el (n+1), çift 2 taş götürür -> n-1 >= 1.
  IF jsonb_array_length(COALESCE(v_hand.tiles, '[]'::jsonb)) < 2 THEN
    RETURN false;
  END IF;

  -- GÖSTERGE ÇİFTİ tek taştır: göstergenin kopyası tek başına indirilir
  -- (RULES.md §8).
  IF v_match.indicator_tile IS NOT NULL AND p_tile = v_match.indicator_tile THEN
    RETURN true;
  END IF;

  -- Normal çift: elde aynı taştan zaten bir kopya olmalı.
  FOR i IN 0 .. jsonb_array_length(v_hand.tiles) - 1 LOOP
    IF v_hand.tiles -> i = p_tile THEN
      v_copies := v_copies + 1;
    END IF;
  END LOOP;

  RETURN v_copies >= 1;
END;
$fn$;

REVOKE ALL ON FUNCTION public.okey_internal_can_lay_pair_with(uuid, smallint, jsonb)
  FROM PUBLIC, anon, authenticated;


-- -----------------------------------------------------------------------------
-- ÖLÜ YARDIMCI DÜŞÜRÜLÜR: el başına sayım artık hiçbir kuralın girdisi değil.
-- (Yukarıdaki üç fonksiyon onu çağıran son yerlerdi.)
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.okey_internal_pairs_laid_by(uuid, smallint);

NOTIFY pgrst, 'reload schema';

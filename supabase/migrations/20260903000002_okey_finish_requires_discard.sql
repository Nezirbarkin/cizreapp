-- =============================================================================
-- 101 Okey Plus — BİTİŞ YALNIZCA ATMA İLE OLUR (masa kilitlenmesi düzeltmesi)
-- -----------------------------------------------------------------------------
-- HATA (kritik): elin TAMAMINI yere sermek hiçbir yerde engellenmiyordu.
--
--   * okey_lay_meld: oyuncu ıstakadaki tüm taşları geçerli per olarak açarsa
--     eli 0 taşa iniyor. Fonksiyon bitişi TESPİT ETMİYOR (finalize çağırmıyor),
--     dolayısıyla maç 'in_progress' kalıyor. Atacak taş kalmadığı için
--     okey_take_turn_action ilerleyemiyor; okey_auto_advance ve
--     okey_auto_play_absent boş elde `RETURN false` diyor; okey_cleanup_stale_rooms
--     yalnızca MAÇI BİTMİŞ odayı kapatıyor. Sonuç: masa SONSUZA KADAR donuyor,
--     giriş ücretleri dağıtılmadan kilitleniyor.
--   * okey_internal_lay_groups_for_seat: aynı açık BOTLAR için de vardı — üç
--     taşı kalan açık bir bot bunları per olarak serince eli boşalıyor, sonra
--     atma adımı `length > 0` koşuluna takılıp hiç çalışmıyordu.
--   * okey_add_to_meld: son taşı bir pere İŞLEYİNCE eli bitmiş sayıp finalize
--     ediyordu. Bu RULES.md §6/§8'e aykırı ("son 1 taşı ıskartaya atarak
--     bitmek") ve okey ile bitiş (x2) çarpanını imkânsız kılıyordu. Botlar
--     bunu zaten yapmıyordu (okey_internal_bot_process_tiles içinde
--     `EXIT WHEN length <= 1` var) — yani insan ve bot FARKLI kural oynuyordu.
--
-- KURAL (RULES.md §6): bitiş, tüm taşları per/işleme olarak yere açıp
-- **son 1 taşı ıskartaya atmakla** olur. Dolayısıyla hiçbir açma/işleme
-- hamlesi eli tamamen boşaltamaz — elde her zaman atılacak bir taş kalmalıdır.
--
-- ÇÖZÜM: üç yolun üçünde de "elde en az 1 taş kalmalı" güvencesi.
--   - okey_lay_meld / okey_add_to_meld (insan): APP:must_keep_discard_tile
--   - okey_internal_lay_groups_for_seat (bot): eli boşaltacak son grubu
--     LİSTEDEN DÜŞER ve kalanı açar. Bot için hata fırlatmak yerine budamak
--     doğrudur; aksi halde eli tamamen perlerden oluşan bir bot hiç açamaz.
--     Gruplar okey_internal_find_melds'ten puanı AZALAN sırada geldiği için
--     düşülen grup her zaman en düşük değerli olandır.
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '10s';

-- -----------------------------------------------------------------------------
-- okey_lay_meld — gövde 20260901000008'den aynen taşındı; TEK fark, taşlar
-- elden düşüldükten sonraki "en az 1 taş kalmalı" kontrolü.
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

  -- YENİ — RULES.md §6: bitiş yalnızca ATMA ile olur. Eli tamamen yere
  -- sermek bitiş DEĞİLDİR; elde atılacak en az bir taş kalmalıdır. Bu kontrol
  -- olmadan maç 'in_progress' kalıp masayı kalıcı olarak kilitliyordu.
  IF jsonb_array_length(v_remaining) = 0 THEN
    RAISE EXCEPTION 'APP:must_keep_discard_tile' USING ERRCODE = 'P0001';
  END IF;

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
-- okey_internal_lay_groups_for_seat (BOT) — gövde 20260901000001'den taşındı;
-- fark: eli boşaltacak gruplar listeden BUDANIR.
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
  v_groups jsonb;
  v_flat jsonb := '[]'::jsonb;
  v_group jsonb;
  v_points int := 0;
  v_remaining jsonb;
  v_tile jsonb;
  v_idx int;
  v_search int;
  v_first_open boolean;
  v_hand_len int;
  v_tile_total int;
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

  -- YENİ — RULES.md §6: elde atılacak en az 1 taş kalmalı. Eli boşaltacak
  -- kadar grup varsa SONDAN başlayarak budanır (gruplar puanı azalan sırada
  -- geldiği için en düşük değerli grup düşer).
  v_hand_len := jsonb_array_length(v_hand.tiles);
  v_groups := p_groups;
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

  IF jsonb_array_length(v_remaining) = 0 THEN
    RETURN false; -- budamaya rağmen boşalıyorsa hiç açma (savunma amaçlı)
  END IF;

  UPDATE public.okey_player_hands
  SET tiles = v_remaining,
      is_opening_done = true,
      opened_with_pairs =
        CASE WHEN v_first_open THEN false ELSE opened_with_pairs END,
      opened_this_turn = CASE WHEN v_first_open THEN true ELSE opened_this_turn END,
      opened_at_hand_no = COALESCE(opened_at_hand_no, v_match.hand_no),
      updated_at = now()
  WHERE match_id = p_match_id AND seat_no = p_seat;

  FOR i IN 0 .. jsonb_array_length(v_groups) - 1 LOOP
    v_group := v_groups -> i;
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
-- okey_add_to_meld — gövde 20260902000005'ten taşındı; fark: son taşı işleyip
-- bitirme YOLU KAPATILDI (bitiş yalnızca atma ile olur).
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

  IF v_meld.meld_type = 'gosterge' THEN
    RAISE EXCEPTION 'APP:gosterge_pair_not_processable' USING ERRCODE = 'P0001';
  END IF;
  IF v_meld.meld_type = 'pair' THEN
    RAISE EXCEPTION 'APP:pair_not_processable' USING ERRCODE = 'P0001';
  END IF;

  -- YENİ — RULES.md §6: son taş İŞLENEREK bitilemez; elde atılacak bir taş
  -- kalmalıdır. Önce burada eli boşalan oyuncu "kazandı" sayılıyordu; bu hem
  -- kurala hem de botun kendi davranışına aykırıydı (bkz.
  -- okey_internal_bot_process_tiles: `EXIT WHEN length <= 1`).
  --
  -- SIRA ÖNEMLİ: bu kontrol HEDEF PER doğrulandıktan SONRA gelir. Aksi halde
  -- elinde tek taş kalan oyuncu bir çifte/göstergeye dokunduğunda "atılacak
  -- taş bırak" hatası alır ve asıl sebebi (o pere zaten işleme yapılamaz)
  -- hiç öğrenemezdi.
  IF jsonb_array_length(v_hand.tiles) <= 1 THEN
    RAISE EXCEPTION 'APP:must_keep_discard_tile' USING ERRCODE = 'P0001';
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

  v_new_tiles := public.okey_internal_extend_meld(
    v_meld.tiles, p_tile, v_match.okey_tile);
  IF v_new_tiles IS NULL THEN
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
END;
$$;
REVOKE ALL ON FUNCTION public.okey_add_to_meld(uuid, bigint, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_add_to_meld(uuid, bigint, jsonb) TO authenticated;

NOTIFY pgrst, 'reload schema';

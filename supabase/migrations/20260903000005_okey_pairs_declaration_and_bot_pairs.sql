-- =============================================================================
-- 101 Okey Plus — "ÇİFTE GİDİYORUM" BEYANI ARTIK GERÇEK + BOTLAR ÇİFTLE AÇAR
-- -----------------------------------------------------------------------------
-- 1) BEYAN ÖLÜ ÖZELLİKTİ
--    okey_set_went_for_pairs hiçbir sıra/aşama kontrolü yapmıyordu ve değer
--    serbestçe geri alınabiliyordu. Oyuncu istediği an `false` gönderip
--    RULES.md §7'nin 404 cezasından kaçabiliyordu. Üstelik çiftle açmak bu
--    bayrağı HİÇ gerektirmiyordu — yani beyanın oyuncuya tek etkisi ceza
--    riskiydi; hiçbir rasyonel oyuncu işaretlemezdi.
--
--    ÇÖZÜM (uygulama kararı, RULES.md §7'ye işlendi):
--      * Beyan, o el içinde GERİ ALINAMAZ (false -> true tek yön).
--      * ÇİFT ile İLK AÇILIŞ, beyan edilmiş olmayı ŞART koşar.
--    Böylece beyan gerçek bir taahhüt olur: çifte gidip açamazsan 404,
--    ama çiftle açma hakkını da yalnızca beyan eden kazanır.
--    Beyan SERİ ile açmayı engellemez — seriyle açan oyuncu zaten "hiç
--    açamayan" olmadığı için 404 işlemez.
--
-- 2) BOTLAR ÇİFTLE AÇAMIYORDU
--    Bot yalnızca seri/grupla açıyordu; 5 çifti olan bir bot hiç açamayıp
--    her el 202 (ya da beyan etseydi 404) yiyordu. Artık bot da çift arar.
--    ADİL OLSUN DİYE: bot da beyanı ÖNCEDEN yapar — turun BAŞINDA (daha taş
--    çekmeden, açıp açamayacağını bilmeden) seri ile açılış menzilde değilse
--    ve çift sayısı barajın 1 altındaysa beyan eder. Yani bot da 404 riskini
--    gerçekten üstlenir; "başaracağını görünce beyan etme" kaçamağı yoktur.
--
-- 3) BAYAT BOT TETİKLEMESİ (yarış durumu)
--    Masadaki DÖRT istemci de okey_bot_take_turn çağırabiliyor ve RPC hangi
--    koltuk için çağrıldığını sormadan "sırası gelen" koltuğu oynatıyordu.
--    İki istemcinin bayat zamanlayıcısı aynı anda ateşlerse SIRADAKİ bot
--    gecikmesiz (anında) oynuyordu. Artık istemci gördüğü turn_token'ı
--    gönderir; token eskimişse RPC sessizce hiçbir şey yapmaz.
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '10s';

-- -----------------------------------------------------------------------------
-- okey_set_went_for_pairs: geri alınamaz beyan + tam doğrulama
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.okey_set_went_for_pairs(uuid, boolean);

CREATE FUNCTION public.okey_set_went_for_pairs(p_match_id uuid, p_value boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid CONSTANT uuid := (SELECT auth.uid());
  v_match public.okey_matches%ROWTYPE;
  v_hand public.okey_player_hands%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501';
  END IF;

  SELECT m.* INTO v_match FROM public.okey_matches AS m WHERE m.id = p_match_id;
  IF v_match.id IS NULL THEN
    RAISE EXCEPTION 'APP:not_found' USING ERRCODE = 'P0001';
  END IF;
  IF v_match.status <> 'in_progress' THEN
    RAISE EXCEPTION 'APP:match_finished' USING ERRCODE = 'P0001';
  END IF;

  SELECT h.* INTO v_hand FROM public.okey_player_hands AS h
  WHERE h.match_id = p_match_id AND h.user_id = v_uid FOR UPDATE;
  IF v_hand.match_id IS NULL THEN
    RAISE EXCEPTION 'APP:not_seated' USING ERRCODE = '42501';
  END IF;
  IF v_hand.is_opening_done THEN
    RAISE EXCEPTION 'APP:cannot_change_after_opening' USING ERRCODE = 'P0001';
  END IF;

  -- GERİ ALINAMAZ: beyan bir taahhüttür. Geri alınabilseydi 404 cezası
  -- (RULES.md §7) hiçbir zaman uygulanamazdı — oyuncu el bitmeden önce
  -- işareti kaldırırdı.
  IF NOT p_value THEN
    IF v_hand.went_for_pairs THEN
      RAISE EXCEPTION 'APP:pairs_declaration_locked' USING ERRCODE = 'P0001';
    END IF;
    RETURN; -- zaten false: yapacak bir şey yok
  END IF;

  UPDATE public.okey_player_hands
  SET went_for_pairs = true, updated_at = now()
  WHERE match_id = p_match_id AND seat_no = v_hand.seat_no;
END;
$$;
REVOKE ALL ON FUNCTION public.okey_set_went_for_pairs(uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_set_went_for_pairs(uuid, boolean) TO authenticated;

COMMENT ON FUNCTION public.okey_set_went_for_pairs(uuid, boolean) IS
  'RULES.md §7 "çifte gidiyorum" beyanı. O el içinde GERİ ALINAMAZ ve çiftle ilk açılışın ön koşuludur.';

-- -----------------------------------------------------------------------------
-- okey_lay_meld — gövde 20260903000002'den taşındı; fark: ÇİFT ile ilk açılış
-- beyan şartına bağlandı.
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

  -- YENİ: çiftle İLK açılış "çifte gidiyorum" beyanını gerektirir.
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

  -- RULES.md §6: bitiş yalnızca ATMA ile olur (bkz. 20260903000002).
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
-- okey_internal_find_pairs: elden çift gruplarını çıkarır (bot için)
--
-- Yalnızca BİREBİR AYNI taşlar eşleştirilir (aynı renk + aynı rakam, ya da iki
-- sahte okey). Joker "her taşla çift olur" esnekliği BİLEREK kullanılmaz:
-- okeyi çiftte harcamak, onu perde/işlemede kullanmaktan neredeyse her zaman
-- kötüdür. Ayrıca GÖSTERGE ÇİFTİ (tek taş) de eklenir — göstergenin bir
-- kopyası ortada açık durduğu için ikinci kopyası hiç yoktur, bu yüzden o tek
-- taş başlı başına bir çifttir (RULES.md §8).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.okey_internal_find_pairs(
  p_tiles jsonb,
  p_okey_tile jsonb,
  p_indicator_tile jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = ''
AS $$
DECLARE
  v_groups jsonb := '[]'::jsonb;
  v_row record;
  i int;
BEGIN
  IF p_tiles IS NULL OR jsonb_array_length(p_tiles) = 0 THEN
    RETURN v_groups;
  END IF;

  -- Gösterge çifti: elde göstergenin kopyası varsa TEK taş olarak indirilir.
  IF p_indicator_tile IS NOT NULL
     AND p_tiles @> jsonb_build_array(p_indicator_tile) THEN
    v_groups := v_groups || jsonb_build_array(jsonb_build_array(p_indicator_tile));
  END IF;

  FOR v_row IN
    SELECT t.value AS tile, count(*)::int AS n
    FROM jsonb_array_elements(p_tiles) AS t
    WHERE t.value IS DISTINCT FROM p_indicator_tile
    GROUP BY t.value
    HAVING count(*) >= 2
  LOOP
    FOR i IN 1 .. (v_row.n / 2) LOOP
      v_groups := v_groups
        || jsonb_build_array(jsonb_build_array(v_row.tile, v_row.tile));
    END LOOP;
  END LOOP;

  RETURN v_groups;
END;
$$;
REVOKE ALL ON FUNCTION public.okey_internal_find_pairs(jsonb, jsonb, jsonb)
  FROM PUBLIC, anon, authenticated;

-- -----------------------------------------------------------------------------
-- okey_internal_lay_pairs_for_seat: bir koltuk ADINA çift indirir (bot için).
-- okey_lay_meld(p_is_pairs => true) ile aynı doğrulamayı yapar, kimliğe bakmaz.
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
AS $$
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

  -- Seriyle açmış bir el çiftle devam edemez; çiftle ilk açılış beyan ister.
  IF NOT v_first_open AND NOT v_hand.opened_with_pairs THEN
    RETURN false;
  END IF;
  IF v_first_open AND NOT v_hand.went_for_pairs THEN
    RETURN false;
  END IF;

  -- Elde atılacak en az 1 taş kalmalı (RULES.md §6) — sondan buda.
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
    IF NOT public.okey_is_valid_pair_ex(
             v_group, v_match.okey_tile, v_match.indicator_tile) THEN
      RETURN false;
    END IF;
    v_pairs := v_pairs + 1;
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
      opened_with_pairs = true,
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

  INSERT INTO public.okey_moves (match_id, hand_no, seat_no, action)
  VALUES (p_match_id, v_match.hand_no, p_seat, 'lay_meld');

  RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION public.okey_internal_lay_pairs_for_seat(uuid, smallint, jsonb)
  FROM PUBLIC, anon, authenticated;

-- -----------------------------------------------------------------------------
-- okey_internal_bot_maybe_declare_pairs: bot, ÖNCEDEN "çifte gidiyorum" der
--
-- Turun BAŞINDA, daha taş çekmeden çağrılır. Koşullar:
--   * el henüz açılmamış ve beyan edilmemiş
--   * seri ile açılış ŞU AN menzilde değil (bulunan perlerin toplamı baraj altı)
--   * çift sayısı barajın en fazla 1 altında
-- Yani bot, başaracağını bilmeden taahhüt eder ve 404 riskini üstlenir.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.okey_internal_bot_maybe_declare_pairs(
  p_match_id uuid,
  p_seat smallint
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
  v_points int := 0;
  v_pairs int;
  i int;
BEGIN
  SELECT m.* INTO v_match FROM public.okey_matches AS m WHERE m.id = p_match_id;
  IF v_match.id IS NULL THEN RETURN false; END IF;

  SELECT h.* INTO v_hand FROM public.okey_player_hands AS h
  WHERE h.match_id = p_match_id AND h.seat_no = p_seat FOR UPDATE;
  IF v_hand.match_id IS NULL
     OR v_hand.is_opening_done
     OR v_hand.went_for_pairs THEN
    RETURN false;
  END IF;

  SELECT * INTO v_req FROM public.okey_required_opening(p_match_id, p_seat);

  v_groups := public.okey_internal_find_melds(v_hand.tiles, v_match.okey_tile);
  FOR i IN 0 .. GREATEST(jsonb_array_length(COALESCE(v_groups, '[]'::jsonb)) - 1, -1) LOOP
    v_points := v_points + public.okey_meld_points(v_groups -> i, v_match.okey_tile);
  END LOOP;
  IF v_points >= v_req.min_points THEN
    RETURN false; -- seriyle zaten açabiliyor: çifte gitmesi anlamsız
  END IF;

  v_pairs := jsonb_array_length(public.okey_internal_find_pairs(
    v_hand.tiles, v_match.okey_tile, v_match.indicator_tile));
  IF v_pairs < v_req.min_pairs - 1 THEN
    RETURN false;
  END IF;

  UPDATE public.okey_player_hands
  SET went_for_pairs = true, updated_at = now()
  WHERE match_id = p_match_id AND seat_no = p_seat;

  RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION public.okey_internal_bot_maybe_declare_pairs(uuid, smallint)
  FROM PUBLIC, anon, authenticated;

-- -----------------------------------------------------------------------------
-- okey_bot_take_turn — gövde 20260902000004'ten taşındı. Farklar:
--   * p_expected_turn_token: bayat tetikleme sessizce yok sayılır
--   * çekme kararı okey_internal_bot_wants_side_draw ile (yandan çekme cezası)
--   * BEYAN -> ÇEK -> AÇ (seri, olmazsa çift) -> İŞLE -> AT
-- -----------------------------------------------------------------------------
-- Eski TEK parametreli imza düşürülür (yeni imzada varsayılan değer var;
-- ikisi yan yana kalırsa 1 argümanlı çağrılar "function is not unique" verir).
-- CREATE OR REPLACE: dosya yeniden çalıştırılabilir olsun.
DROP FUNCTION IF EXISTS public.okey_bot_take_turn(uuid);

CREATE OR REPLACE FUNCTION public.okey_bot_take_turn(
  p_match_id uuid,
  p_expected_turn_token uuid DEFAULT NULL
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
  v_prev_seat smallint;
  v_is_bot boolean;
  v_hand public.okey_player_hands%ROWTYPE;
  v_hand_tiles jsonb;
  v_groups jsonb;
  v_tile jsonb;
  v_pile jsonb;
  v_top jsonb;
  v_source text;
  v_opened boolean;
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

  -- BAYAT TETİKLEME KORUMASI: istemci hangi sıra için tetiklediğini söyler.
  -- Sıra o an başkasına geçmişse hiçbir şey yapılmaz (hata da değildir —
  -- başka bir istemci zaten oynatmıştır).
  IF p_expected_turn_token IS NOT NULL
     AND p_expected_turn_token IS DISTINCT FROM v_match.turn_token THEN
    RETURN;
  END IF;

  v_seat := v_match.turn_seat;

  SELECT rp.is_bot INTO v_is_bot FROM public.okey_room_players AS rp
  WHERE rp.room_id = v_match.room_id AND rp.seat_no = v_seat;
  IF NOT COALESCE(v_is_bot, false) THEN
    RETURN;
  END IF;

  -- 0) BEYAN — taş çekmeden ÖNCE (gerçek taahhüt)
  PERFORM public.okey_internal_bot_maybe_declare_pairs(p_match_id, v_seat);

  -- 1) ÇEKME — soldakinin ıskartası GERÇEKTEN işe yarıyorsa oradan
  IF v_match.turn_phase = 'draw' THEN
    v_source := 'deck';
    v_prev_seat := (v_seat + 3) % 4;
    v_pile := v_match.discard_piles -> v_prev_seat::text;

    IF v_pile IS NOT NULL AND jsonb_array_length(v_pile) > 0 THEN
      v_top := v_pile -> (jsonb_array_length(v_pile) - 1);
      IF public.okey_internal_bot_wants_side_draw(p_match_id, v_seat, v_top) THEN
        v_source := 'discard';
      END IF;
    END IF;

    IF v_source = 'deck' AND v_match.deck_remaining <= 0 THEN
      PERFORM public.okey_internal_finalize_hand(p_match_id, NULL, NULL);
      RETURN;
    END IF;

    PERFORM public.okey_internal_draw_for_seat(p_match_id, v_seat, v_source);
    SELECT m.* INTO v_match FROM public.okey_matches AS m WHERE m.id = p_match_id;
  END IF;

  -- 2) AÇMA / EK PER-ÇİFT
  SELECT h.* INTO v_hand FROM public.okey_player_hands AS h
  WHERE h.match_id = p_match_id AND h.seat_no = v_seat;
  v_hand_tiles := v_hand.tiles;

  IF v_hand.is_opening_done AND v_hand.opened_with_pairs THEN
    PERFORM public.okey_internal_lay_pairs_for_seat(
      p_match_id, v_seat,
      public.okey_internal_find_pairs(
        v_hand_tiles, v_match.okey_tile, v_match.indicator_tile));
  ELSE
    v_groups := public.okey_internal_find_melds(v_hand_tiles, v_match.okey_tile);
    v_opened := false;
    IF jsonb_array_length(COALESCE(v_groups, '[]'::jsonb)) > 0 THEN
      v_opened := public.okey_internal_lay_groups_for_seat(
        p_match_id, v_seat, v_groups);
    END IF;

    -- Seri ile açılamadıysa ve beyanı varsa çiftle dener
    IF NOT v_opened AND NOT v_hand.is_opening_done AND v_hand.went_for_pairs THEN
      PERFORM public.okey_internal_lay_pairs_for_seat(
        p_match_id, v_seat,
        public.okey_internal_find_pairs(
          v_hand_tiles, v_match.okey_tile, v_match.indicator_tile));
    END IF;
  END IF;

  -- 3) İŞLEME — açık perlere taş ekle
  PERFORM public.okey_internal_bot_process_tiles(p_match_id, v_seat);

  -- El bu arada bitmiş olabilir
  SELECT m.* INTO v_match FROM public.okey_matches AS m WHERE m.id = p_match_id;
  IF v_match.status <> 'in_progress' THEN
    RETURN;
  END IF;

  -- 4) ATMA — okey asla atılmaz
  SELECT h.tiles INTO v_hand_tiles FROM public.okey_player_hands AS h
  WHERE h.match_id = p_match_id AND h.seat_no = v_seat;

  IF v_hand_tiles IS NOT NULL AND jsonb_array_length(v_hand_tiles) > 0 THEN
    v_tile := public.okey_internal_bot_pick_discard(v_hand_tiles, v_match.okey_tile);
    IF v_tile IS NOT NULL THEN
      PERFORM public.okey_internal_discard_for_seat(p_match_id, v_seat, v_tile);
    END IF;
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.okey_bot_take_turn(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_bot_take_turn(uuid, uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';

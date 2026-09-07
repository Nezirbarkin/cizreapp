-- =============================================================================
-- 101 Okey Plus — SERİ AÇAN OYUNCU DA ÇİFT İNDİREBİLİR (en çok 3)
-- -----------------------------------------------------------------------------
-- Kullanıcı isteği (2026-09-05), iki madde:
--
--  1) "Seri açan biri, masada çift indirmiş biri varsa, en çok 3 çift atma
--     hakkına sahiptir."
--  2) "Seri açan veya çift açmış biri yandan taş çekip çift indirebilir."
--
-- ESKİ DURUM: okey_lay_meld, ilk açılış türünü elin GERİ KALANI için de
-- kilitliyordu (APP:opening_type_mismatch). Yani seriyle açan oyuncu o elde
-- hiç çift indiremiyordu — madde 1 kâğıt üzerinde bile yoktu, madde 2'nin
-- "seri açan" yarısı da uygulanamıyordu: yandan çektiği taşla çift indirmek
-- imkânsız olduğu için taş "kullanılmadı" sayılıp +101 yazılıyordu.
--
-- YENİ DURUM (RULES.md §3'e işlendi):
--   * ÇİFT açan hâlâ SERİ indiremez — bu yön KAPALI kalır. 404 cezası
--     ("çifte gidip açamayan") ve çiftten bitiş ×2 çarpanı, çift açan
--     oyuncunun el boyunca çiftte kalmasına dayanır.
--   * SERİ açan ÇİFT indirebilir, iki şartla:
--       a) masada BAŞKA bir koltuğun indirdiği en az bir çift olmalı
--          (meld_type 'pair' ya da 'gosterge'),
--       b) o elde indirdiği çift sayısı 3'ü GEÇMEMELİ.
--
-- (a) NEDEN "MASADAKİ ÇİFT", "opened_with_pairs" DEĞİL: okey_player_hands'i
-- RLS gereği yalnızca sahibi okuyabilir (bkz. 20260830000001) — rakibin
-- opened_with_pairs değeri istemciye KAPALI. Masadaki çiftler ise herkese
-- açık. Ölçüt ikisinde aynı olmasaydı ÇİFT AÇ düğmesi, sunucunun kabul
-- edeceği bir hamlede kapalı (ya da tersi) kalırdı — bu depoda tekrar tekrar
-- düzeltilen hata sınıfı tam olarak budur.
--
-- Ölçüt kendi kendini besleyemez: masadaki İLK çift zorunlu olarak çiftle
-- açan bir oyuncudan gelir (seri açan, ortada bir çift görmeden indiremez).
--
-- (b) SINIR NEDEN TÜRETİLİYOR: her el YENİ bir okey_matches satırıdır
-- (bkz. 20260830000011), dolayısıyla okey_table_melds satırları zaten el
-- başına ayrıdır ve "bu elde kaç çift indirdim" masadan doğrudan sayılır.
-- Ayrı bir sayaç sütunu, elden ele sıfırlanması gereken ikinci bir durum
-- yaratırdı.
--
-- MADDE 2 İÇİN AYRICA BİR ŞEY GEREKMEZ: yandan çekilen taşın "kullanıldı mı"
-- ölçütü, taşın eldeki KOPYA SAYISININ azalmasıdır (20260903000003 ->
-- okey_internal_discard_for_seat). Çift indirmek taşı elden çıkardığı için
-- ceza zaten yazılmaz. Madde 2'nin eksik yarısı madde 1'di; o kapanınca
-- ikisi de yürürlüğe girer. Botun ÇEKME kararı da (aşağıda) buna göre
-- genişletildi.
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '10s';

-- -----------------------------------------------------------------------------
-- YARDIMCILAR
-- -----------------------------------------------------------------------------

-- Seri ile açmış bir koltuğun bir elde indirebileceği EN ÇOK çift sayısı.
-- Tek yerde durur ki sunucunun üç ayrı yolu (oyuncu RPC'si, bot yolu, botun
-- yandan çekme kararı) aynı sayıyı kullansın. İstemcideki eşi:
-- OkeyGameProvider.seriesPairsLimit.
CREATE OR REPLACE FUNCTION public.okey_series_pairs_limit()
RETURNS int
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $fn$ SELECT 3 $fn$;

COMMENT ON FUNCTION public.okey_series_pairs_limit() IS
  'RULES.md §3: seri ile açan oyuncunun bir elde indirebileceği en çok çift sayısı.';

-- Masada, p_seat DIŞINDA bir koltuğun indirdiği çift var mı?
CREATE OR REPLACE FUNCTION public.okey_internal_pairs_opener_exists(
  p_match_id uuid,
  p_seat smallint
)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = ''
AS $fn$
  SELECT EXISTS (
    SELECT 1 FROM public.okey_table_melds AS tm
    WHERE tm.match_id = p_match_id
      AND tm.laid_by_seat IS DISTINCT FROM p_seat
      AND tm.meld_type IN ('pair', 'gosterge')
  );
$fn$;

COMMENT ON FUNCTION public.okey_internal_pairs_opener_exists(uuid, smallint) IS
  'RULES.md §3: seri ile açan oyuncunun çift indirebilmesinin ön şartı — masada başkasının indirdiği bir çift.';

-- p_seat bu elde masaya kaç çift indirdi? (gösterge çifti dahil)
CREATE OR REPLACE FUNCTION public.okey_internal_pairs_laid_by(
  p_match_id uuid,
  p_seat smallint
)
RETURNS int
LANGUAGE sql
STABLE
SET search_path = ''
AS $fn$
  SELECT count(*)::int FROM public.okey_table_melds AS tm
  WHERE tm.match_id = p_match_id
    AND tm.laid_by_seat = p_seat
    AND tm.meld_type IN ('pair', 'gosterge');
$fn$;

REVOKE ALL ON FUNCTION public.okey_internal_pairs_opener_exists(uuid, smallint)
  FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.okey_internal_pairs_laid_by(uuid, smallint)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_series_pairs_limit() TO authenticated;


-- -----------------------------------------------------------------------------
-- okey_lay_meld — gövde 20260905000001'den taşındı; TEK fark: seri ile açmış
-- bir el, şartları sağlıyorsa çift indirebilir.
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
  v_already int;
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

  -- 3 ÇİFT SINIRI (RULES.md §3) — yalnızca SERİ ile açmış el için. Çift açan
  -- oyuncunun indirebileceği çift sayısı sınırsızdır; onun eli zaten çifttir.
  IF v_series_pairs THEN
    v_limit := public.okey_series_pairs_limit();
    v_already := public.okey_internal_pairs_laid_by(p_match_id, v_seat);
    IF v_already + v_pairs > v_limit THEN
      RAISE EXCEPTION
        'APP:series_pairs_limit | sınır: %, indirdiğin: %, denediğin: %',
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
-- okey_internal_lay_pairs_for_seat — gövde 20260905000001'den taşındı.
-- Farklar:
--   * seri ile açmış koltuk da çift indirebilir (şartlar okey_lay_meld ile
--     birebir aynı),
--   * grup listesi KALAN HAKKA GÖRE BUDANIR — bot tüm çiftlerini birden
--     gönderdiğinde çağrı tümden reddedilmesin, 3'e kadar olanı geçsin,
--   * opened_with_pairs artık koşulsuz true YAZILMIYOR. Eskiden yazıyordu;
--     seri açan koltuk çift indirebilir olunca bu, oyuncunun açılış türünü
--     sessizce "çift"e çevirip el sonunda yanlış çarpan/ceza uygulardı.
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
    -- SERİ ile açmış koltuk: masada çift açan olmalı ve 3 çift sınırı geçerli.
    IF NOT public.okey_internal_pairs_opener_exists(p_match_id, p_seat) THEN
      RETURN false;
    END IF;
    v_allowance := public.okey_series_pairs_limit()
                 - public.okey_internal_pairs_laid_by(p_match_id, p_seat);
    IF v_allowance <= 0 THEN
      RETURN false;
    END IF;

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
-- okey_internal_can_lay_pair_with: p_tile yandan alınırsa ÇİFT olarak
-- indirilebilir mi? (RULES.md §4 madde 2 — botun çekme kararı için)
--
-- Sadece bir ipucudur; gerçek doğrulama okey_internal_lay_pairs_for_seat'te.
-- Amaç dar: bot, o turda gerçekten indirebileceği bir taşı alsın, yoksa
-- §4'ün +101 cezasına düşer.
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

  -- Seri ile açmışsa: masada çift olmalı ve hakkı dolmamış olmalı.
  IF NOT v_hand.opened_with_pairs THEN
    IF NOT public.okey_internal_pairs_opener_exists(p_match_id, p_seat) THEN
      RETURN false;
    END IF;
    IF public.okey_internal_pairs_laid_by(p_match_id, p_seat)
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
-- okey_internal_bot_wants_side_draw — gövde 20260903000003'ten taşındı;
-- fark: ELİ AÇIK koltuk için taş, masadaki bir pere işlenebiliyorsa YA DA
-- çift olarak indirilebiliyorsa alınır (RULES.md §4 madde 2). Eskiden yalnızca
-- işleme bakılıyordu; çift indirebilecek bot taşı hiç almıyordu.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.okey_internal_bot_wants_side_draw(
  p_match_id uuid,
  p_seat smallint,
  p_candidate jsonb
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SET search_path = ''
AS $fn$
DECLARE
  v_match public.okey_matches%ROWTYPE;
  v_hand public.okey_player_hands%ROWTYPE;
  v_req record;
  v_groups jsonb;
  v_points int := 0;
  v_uses boolean := false;
  v_group jsonb;
  i int;
  j int;
BEGIN
  SELECT m.* INTO v_match FROM public.okey_matches AS m WHERE m.id = p_match_id;
  SELECT h.* INTO v_hand FROM public.okey_player_hands AS h
  WHERE h.match_id = p_match_id AND h.seat_no = p_seat;
  IF v_hand.match_id IS NULL THEN
    RETURN false;
  END IF;

  IF v_hand.is_opening_done THEN
    IF public.okey_internal_discard_tile_usable(p_match_id, p_seat, p_candidate)
    THEN
      RETURN true;
    END IF;
    RETURN public.okey_internal_can_lay_pair_with(p_match_id, p_seat, p_candidate);
  END IF;

  v_groups := public.okey_internal_find_melds(
    COALESCE(v_hand.tiles, '[]'::jsonb) || jsonb_build_array(p_candidate),
    v_match.okey_tile
  );
  IF v_groups IS NULL OR jsonb_array_length(v_groups) = 0 THEN
    RETURN false;
  END IF;

  FOR i IN 0 .. jsonb_array_length(v_groups) - 1 LOOP
    v_group := v_groups -> i;
    v_points := v_points + public.okey_meld_points(v_group, v_match.okey_tile);
    FOR j IN 0 .. jsonb_array_length(v_group) - 1 LOOP
      IF v_group -> j = p_candidate THEN
        v_uses := true;
      END IF;
    END LOOP;
  END LOOP;

  IF NOT v_uses THEN
    RETURN false;
  END IF;

  SELECT * INTO v_req FROM public.okey_required_opening(p_match_id, p_seat);

  RETURN v_points >= v_req.min_points
     AND public.okey_internal_bot_wants_discard(
           v_hand.tiles, p_candidate, v_match.okey_tile);
END;
$fn$;

REVOKE ALL ON FUNCTION public.okey_internal_bot_wants_side_draw(uuid, smallint, jsonb)
  FROM PUBLIC, anon, authenticated;


-- -----------------------------------------------------------------------------
-- okey_bot_take_turn — gövde 20260905000005'ten taşındı; fark: SERİ ile açmış
-- bot da, ek perlerini indirdikten sonra çift indirmeyi dener. Hakkı yoksa
-- okey_internal_lay_pairs_for_seat zaten false döner — kural tek yerde durur.
--
-- RULES.md §8: "Botlar gerçek oyuncularla aynı kurallara tabidir ve aynı
-- hamleleri yapar." Bu satır olmasaydı yeni hak yalnızca insanlarda olurdu.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.okey_bot_take_turn(
  p_match_id uuid,
  p_expected_turn_token uuid DEFAULT NULL
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

  -- BAYAT TETİKLEME KORUMASI (bkz. 20260903000005).
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

    -- YENİ (RULES.md §3): eli SERİ ile açık bot, masada çift varsa 3'e kadar
    -- çift de indirir. El bu arada değişmiş olabilir — taşlar yeniden okunur.
    SELECT h.* INTO v_hand FROM public.okey_player_hands AS h
    WHERE h.match_id = p_match_id AND h.seat_no = v_seat;
    IF v_hand.is_opening_done AND NOT v_hand.opened_with_pairs THEN
      PERFORM public.okey_internal_lay_pairs_for_seat(
        p_match_id, v_seat,
        public.okey_internal_find_pairs(
          v_hand.tiles, v_match.okey_tile, v_match.indicator_tile));
    END IF;
  END IF;

  -- 3) İŞLEME — açık perlere taş ekle
  PERFORM public.okey_internal_bot_process_tiles(p_match_id, v_seat);

  -- El bu arada bitmiş olabilir
  SELECT m.* INTO v_match FROM public.okey_matches AS m WHERE m.id = p_match_id;
  IF v_match.status <> 'in_progress' THEN
    RETURN;
  END IF;

  -- 4) ATMA — okey asla atılmaz, İŞLEK TAŞ da son çare dışında atılmaz
  SELECT h.tiles INTO v_hand_tiles FROM public.okey_player_hands AS h
  WHERE h.match_id = p_match_id AND h.seat_no = v_seat;

  IF v_hand_tiles IS NOT NULL AND jsonb_array_length(v_hand_tiles) > 0 THEN
    v_tile := public.okey_internal_bot_pick_discard(
      v_hand_tiles, v_match.okey_tile, p_match_id);
    IF v_tile IS NOT NULL THEN
      PERFORM public.okey_internal_discard_for_seat(p_match_id, v_seat, v_tile);
    END IF;
  END IF;
END;
$fn$;

REVOKE ALL ON FUNCTION public.okey_bot_take_turn(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_bot_take_turn(uuid, uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';

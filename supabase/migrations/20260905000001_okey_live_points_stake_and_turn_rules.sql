-- =============================================================================
-- 101 Okey Plus — ANLIK PER PUANI, MASA PUANI ÇARPANI ve TUR SONU KURALLARI
-- -----------------------------------------------------------------------------
-- Kullanıcı isteği (2026-09-05), sekiz maddenin sunucuya bakan yüzü:
--
--  1) ANLIK PUAN (madde 1 ve 3) — her koltuğun MASAYA AÇTIĞI toplam puan
--     artık okey_matches.open_points içinde tutulur ve masadaki herkes
--     görür. Per açmak da (lay_meld) işlemek de (add_to_meld) bu sayaçı
--     büyütür; "oyuncu işlek attığında puanına göster" tam olarak budur.
--
--     NEDEN TÜRETİLMİYOR: bir per masaya konduktan sonra BAŞKA oyuncular
--     ona taş işleyebiliyor. okey_table_melds yalnızca peri KİMİN açtığını
--     biliyor, sonradan hangi taşı kimin eklediğini bilmiyor — dolayısıyla
--     "kim ne kadar açtı" masadaki perlerden geriye doğru hesaplanamaz.
--     Sayaç, puanın kazanıldığı ANDA yazılmak zorunda.
--
--     NEDEN okey_matches ÜZERİNDE: okey_player_hands'i RLS gereği yalnızca
--     sahibi okuyabilir (hile önlemenin kilit noktası, bkz. 20260830000001).
--     Rakibin anlık puanı orada dursaydı masada hiç görünmezdi.
--
--  2) YANDAN TAŞ ÇEKME SERBEST (madde 6) — 20260902000004'ün getirdiği
--     "kullanamayacaksan hiç alamazsın" KAPISI kaldırıldı. RULES.md §4 zaten
--     İKİ katmanlı bir çözüm tarif ediyor ve ikinci katman (tur sonunda taşı
--     kullanmadıysan +101, bkz. side_draw_penalty) 20260903000003'te
--     kodlandı. İki katman birlikte çalışınca oyuncu hamleyi hiç
--     yapamıyordu; oysa doğru olan, kuralın kendi dediği gibi, hamleyi
--     ENGELLEMEK değil CEZALANDIRMAK.
--
--  3) DESTE BİTİNCE EL, O ATIŞLA BİTER (madde 7) — eskiden el ancak sıradaki
--     oyuncu boş desteden çekmeye ÇALIŞINCA kapanıyordu: son taş atıldıktan
--     sonra masa bir tur daha dönüyor, oyuncular neden bittiğini anlamıyordu.
--     Artık deste tükendiyse atışın kendisi eli bitirir.
--
--  4) MASA PUANI = GİRİŞ PUANI × EL SAYISI (madde 5) — okey_rooms.table_stake
--     üretilmiş (generated) bir sütun olarak eklendi; tahsilat, pot ve bakiye
--     kontrolleri artık onu kullanır. Üretilmiş sütun bilerek seçildi: iki
--     çarpanı da satırın kendisi taşıdığı için "1500 mü 500 mü" ikilemi
--     yapısal olarak imkânsız.
--
--  5) MAÇ SONU ÖDEMESİ GÖRÜNÜR (madde 4) — okey_match_payouts, maç bitince
--     kimin ne ödediğini ve ne kazandığını koltuk koltuk döndürür. Veri
--     zaten okey_point_transactions defterinde vardı ama istemci onu
--     okuyamıyordu (defter satırları başka kullanıcıları da içeriyor).
--
-- Fonksiyon gövdeleri, aksi belirtilmedikçe bir ÖNCEKİ sürümden birebir
-- taşındı; her birinin başında farkı yazıyor.
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '10s';

-- -----------------------------------------------------------------------------
-- ŞEMA
-- -----------------------------------------------------------------------------

-- Koltuk -> bu elde MASAYA AÇILAN toplam puan. Herkes görür (okey_matches
-- zaten masadaki dört koltuğun da okuyabildiği ortak durumdur).
ALTER TABLE public.okey_matches
  ADD COLUMN IF NOT EXISTS open_points jsonb NOT NULL
  DEFAULT '{"0": 0, "1": 0, "2": 0, "3": 0}'::jsonb;

COMMENT ON COLUMN public.okey_matches.open_points IS
  'Koltuk -> bu elde masaya açılan/işlenen toplam puan (anlık per puanı). Per açınca ve taş işleyince artar. Ceza puanı DEĞİLDİR (o okey_matches.scores).';

-- MASA PUANI = giriş puanı × oynanacak el sayısı.
--
-- Üretilmiş sütun: entry_fee (el başına puan) ile total_hands aynı satırda
-- durduğu için çarpımın elle güncellenmesi gereken bir kopyası olmaz.
ALTER TABLE public.okey_rooms
  ADD COLUMN IF NOT EXISTS table_stake int
  GENERATED ALWAYS AS (entry_fee * total_hands) STORED;

COMMENT ON COLUMN public.okey_rooms.table_stake IS
  'Masaya girmenin GERÇEK bedeli: entry_fee (el başına puan) × total_hands. Tahsilat, pot ve bakiye kontrolleri bunu kullanır.';

-- -----------------------------------------------------------------------------
-- okey_internal_add_open_points: anlık per puanı sayacını büyütür
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.okey_internal_add_open_points(
  p_match_id uuid,
  p_seat smallint,
  p_points int
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF p_points IS NULL OR p_points = 0 THEN
    RETURN;
  END IF;

  UPDATE public.okey_matches
  SET open_points = jsonb_set(
        COALESCE(open_points, '{}'::jsonb),
        ARRAY[p_seat::text],
        to_jsonb(
          COALESCE((open_points ->> p_seat::text)::int, 0) + p_points
        )
      )
  WHERE id = p_match_id;
END;
$$;
REVOKE ALL ON FUNCTION public.okey_internal_add_open_points(uuid, smallint, int)
  FROM PUBLIC, anon, authenticated;


-- -----------------------------------------------------------------------------
-- okey_lay_meld — gövde 20260903000005'ten taşındı; fark: açılan perlerin
-- toplam değeri ANLIK PUAN sayacına yazılır.
--
-- Çift dalında da puan toplanır ama AYRI bir sayaca (v_open_points): baraj
-- ve katlamalı modun highest_opening_points'i yalnızca SERİ puanını
-- (v_points) görür, çiftin taş değerleri oraya hiç ulaşmaz.
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
  -- ANLIK PER PUANI ayrı bir sayaçtır ve v_points ile BİRLEŞTİRİLEMEZ.
  --
  -- v_points, katlamalı modun barajını besleyen SERİ puanıdır
  -- (highest_opening_points). Çiftle açan bir oyuncunun taş değerleri
  -- oraya yazılırsa, masadaki herkesin SERİ barajı sessizce yükselir —
  -- oysa çift açılışının seri barajıyla hiçbir ilgisi yok (RULES.md §3/§5).
  v_open_points int := 0;
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
      -- Çiftin "puanı" barajda sayılmaz (baraj çift ADEDİdir) ama anlık
      -- puan göstergesi masaya SERİLEN değeri anlatır; çift de taşlarının
      -- değeri kadar masaya yatar. Bu yüzden AYRI sayaca yazılır.
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

  -- ANLIK PER PUANI: masaya serilen değer bu koltuğun sayacına yazılır.
  PERFORM public.okey_internal_add_open_points(
    p_match_id, v_seat, v_open_points);

  INSERT INTO public.okey_moves (match_id, hand_no, seat_no, action)
  VALUES (p_match_id, v_match.hand_no, v_seat, 'lay_meld');
END;
$$;

REVOKE ALL ON FUNCTION public.okey_lay_meld(uuid, jsonb, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_lay_meld(uuid, jsonb, boolean) TO authenticated;


-- -----------------------------------------------------------------------------
-- okey_internal_lay_groups_for_seat — gövde 20260903000002'den taşındı;
-- fark: anlık puan sayacı (botun açtığı perler de masada puan olarak görünür).
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

  -- ANLIK PER PUANI (bkz. okey_lay_meld): bot da aynı sayacı büyütür.
  PERFORM public.okey_internal_add_open_points(p_match_id, p_seat, v_points);

  INSERT INTO public.okey_moves (match_id, hand_no, seat_no, action)
  VALUES (p_match_id, v_match.hand_no, p_seat, 'lay_meld');

  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.okey_internal_lay_groups_for_seat(uuid, smallint, jsonb)
  FROM PUBLIC, anon, authenticated;


-- -----------------------------------------------------------------------------
-- okey_internal_lay_pairs_for_seat — gövde 20260903000005'ten taşındı;
-- fark: anlık puan sayacı.
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

  -- ANLIK PER PUANI (bkz. okey_lay_meld).
  PERFORM public.okey_internal_add_open_points(p_match_id, p_seat, v_points);

  INSERT INTO public.okey_moves (match_id, hand_no, seat_no, action)
  VALUES (p_match_id, v_match.hand_no, p_seat, 'lay_meld');

  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.okey_internal_lay_pairs_for_seat(uuid, smallint, jsonb)
  FROM PUBLIC, anon, authenticated;


-- -----------------------------------------------------------------------------
-- okey_add_to_meld — gövde 20260903000002'den taşındı; fark: işlenen taşın
-- değeri İŞLEYEN koltuğun anlık puanına eklenir.
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

  -- ANLIK PER PUANI: İŞLENEN taşın değeri işleyen koltuğa yazılır — peri
  -- kimin açtığından bağımsız (kullanıcı: "oyuncu işlek attığında puanına
  -- göster").
  PERFORM public.okey_internal_add_open_points(
    p_match_id, v_seat,
    public.okey_tile_penalty_value(p_tile, v_match.okey_tile));

  INSERT INTO public.okey_moves (match_id, hand_no, seat_no, action, tile)
  VALUES (p_match_id, v_match.hand_no, v_seat, 'add_to_meld', p_tile);
END;
$$;

REVOKE ALL ON FUNCTION public.okey_add_to_meld(uuid, bigint, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_add_to_meld(uuid, bigint, jsonb) TO authenticated;


-- -----------------------------------------------------------------------------
-- okey_internal_bot_process_tiles — gövde 20260902000005'ten taşındı;
-- fark: anlık puan sayacı.
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.okey_internal_bot_process_tiles(
  p_match_id uuid,
  p_seat smallint
)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_match public.okey_matches%ROWTYPE;
  v_hand public.okey_player_hands%ROWTYPE;
  v_meld public.okey_table_melds%ROWTYPE;
  v_tile jsonb;
  v_new_tiles jsonb;
  v_processed int := 0;
  v_progress boolean := true;
  v_idx int;
  i int;
  v_guard int := 0;
BEGIN
  SELECT m.* INTO v_match FROM public.okey_matches AS m WHERE m.id = p_match_id;
  IF v_match.id IS NULL OR v_match.status <> 'in_progress' THEN
    RETURN 0;
  END IF;

  SELECT h.* INTO v_hand FROM public.okey_player_hands AS h
  WHERE h.match_id = p_match_id AND h.seat_no = p_seat;
  IF v_hand.match_id IS NULL OR NOT v_hand.is_opening_done THEN
    RETURN 0; -- açmadan işleme yapılamaz
  END IF;

  -- Bir tur boyunca işleyebildiği sürece devam et
  WHILE v_progress LOOP
    v_progress := false;
    v_guard := v_guard + 1;
    EXIT WHEN v_guard > 25; -- güvenlik freni

    SELECT h.* INTO v_hand FROM public.okey_player_hands AS h
    WHERE h.match_id = p_match_id AND h.seat_no = p_seat;
    EXIT WHEN v_hand.tiles IS NULL OR jsonb_array_length(v_hand.tiles) = 0;

    -- ATILACAK BİR TAŞ KALMALI: eli tamamen boşaltmak bitiş demektir ve
    -- bitiş yalnızca ATMA ile olur (RULES.md §6). Bu yüzden son taş
    -- işlenmez; bot onu atarak bitirir.
    EXIT WHEN jsonb_array_length(v_hand.tiles) <= 1;

    FOR v_meld IN
      SELECT tm.* FROM public.okey_table_melds AS tm
      WHERE tm.match_id = p_match_id
        AND tm.hand_no = v_match.hand_no
        AND tm.meld_type IN ('run', 'set')   -- çiftlere işleme yok
      ORDER BY tm.id
    LOOP
      FOR i IN 0 .. jsonb_array_length(v_hand.tiles) - 1 LOOP
        v_tile := v_hand.tiles -> i;

        -- Okey işlenebilir ama elde tutmak da cezalı; yine de en son çare
        -- olarak değerlendirilir (doğal taşlar önce denendiği için sıra
        -- doğal olarak onlara gelir).
        v_new_tiles := public.okey_internal_extend_meld(
          v_meld.tiles, v_tile, v_match.okey_tile);
        CONTINUE WHEN v_new_tiles IS NULL;

        -- Taşı elden düş
        v_idx := i;
        UPDATE public.okey_player_hands
        SET tiles = tiles - v_idx, updated_at = now()
        WHERE match_id = p_match_id AND seat_no = p_seat;

        UPDATE public.okey_table_melds
        SET tiles = v_new_tiles, updated_at = now()
        WHERE id = v_meld.id;

        -- ANLIK PER PUANI (bkz. okey_add_to_meld).
        PERFORM public.okey_internal_add_open_points(
          p_match_id, p_seat,
          public.okey_tile_penalty_value(v_tile, v_match.okey_tile));

        INSERT INTO public.okey_moves
          (match_id, hand_no, seat_no, action, tile)
        VALUES (p_match_id, v_match.hand_no, p_seat, 'add_to_meld', v_tile);

        v_processed := v_processed + 1;
        v_progress := true;
        EXIT; -- eli değişti, baştan tara
      END LOOP;

      EXIT WHEN v_progress;
    END LOOP;
  END LOOP;

  RETURN v_processed;
END;
$$;

REVOKE ALL ON FUNCTION public.okey_internal_bot_process_tiles(uuid, smallint)
  FROM PUBLIC, anon, authenticated;


-- -----------------------------------------------------------------------------
-- okey_internal_draw_for_seat — gövde 20260903000003'ten taşındı; fark:
-- yandan (soldakinin ıskartasından) çekme KAPISI kaldırıldı.
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.okey_internal_draw_for_seat(
  p_match_id uuid,
  p_seat smallint,
  p_source text -- 'deck' | 'discard'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_match public.okey_matches%ROWTYPE;
  v_drawn jsonb;
  v_deck jsonb;
  v_prev_seat smallint;
  v_prev_pile jsonb;
  v_side_count int;
BEGIN
  SELECT m.* INTO v_match FROM public.okey_matches AS m WHERE m.id = p_match_id;

  IF p_source = 'deck' THEN
    IF v_match.deck_remaining <= 0 THEN
      -- RULES.md kapsamı dışı köşe durum: deste bitti, el kazanansız kapanır
      PERFORM public.okey_internal_finalize_hand(p_match_id, NULL, NULL);
      RETURN NULL;
    END IF;

    SELECT d.remaining_deck INTO v_deck FROM public.okey_match_decks AS d
    WHERE d.match_id = p_match_id FOR UPDATE;

    v_drawn := v_deck -> 0;
    v_deck := v_deck - 0;

    UPDATE public.okey_match_decks SET remaining_deck = v_deck WHERE match_id = p_match_id;
    UPDATE public.okey_matches
    SET deck_remaining = deck_remaining - 1, turn_phase = 'discard'
    WHERE id = p_match_id;

    INSERT INTO public.okey_moves (match_id, hand_no, seat_no, action, tile)
    VALUES (p_match_id, v_match.hand_no, p_seat, 'draw_deck', v_drawn);
  ELSE
    v_prev_seat := (p_seat + 3) % 4;
    v_prev_pile := v_match.discard_piles -> v_prev_seat::text;
    IF v_prev_pile IS NULL OR jsonb_array_length(v_prev_pile) = 0 THEN
      RAISE EXCEPTION 'APP:discard_pile_empty' USING ERRCODE = 'P0001';
    END IF;

    v_drawn := v_prev_pile -> (jsonb_array_length(v_prev_pile) - 1);

    -- YANDAN ÇEKME ARTIK ENGELLENMEZ (kullanıcı isteği 2026-09-05).
    --
    -- Burada 20260902000004'ten kalan bir kapı vardı: taş "işine yaramıyorsa"
    -- APP:discard_tile_not_usable ile hamle hiç yapılmıyordu. Ama RULES.md §4
    -- iki katmanlı bir çözüm tarif ediyor ve İKİNCİ katman (taşı o turda
    -- kullanmazsan tur sonunda +101, bkz. okey_internal_discard_for_seat
    -- içindeki side_draw_penalty) 20260903000003'te kodlandı. İkisi birlikte
    -- çalışınca oyuncu hamleyi hiç YAPAMIYORDU — oysa kuralın kendi dediği
    -- "engelleme, cezalandır". Kapı kalktı; ceza yerinde duruyor.
    v_prev_pile := v_prev_pile - (jsonb_array_length(v_prev_pile) - 1);

    UPDATE public.okey_matches
    SET discard_piles = jsonb_set(discard_piles, ARRAY[v_prev_seat::text], v_prev_pile),
        turn_phase = 'discard'
    WHERE id = p_match_id;

    INSERT INTO public.okey_moves (match_id, hand_no, seat_no, action, tile)
    VALUES (p_match_id, v_match.hand_no, p_seat, 'draw_discard', v_drawn);
  END IF;

  UPDATE public.okey_player_hands
  SET tiles = tiles || jsonb_build_array(v_drawn),
      -- Desteden çekmek yandan çekme izini SİLER (aynı turda ikisi olmaz ama
      -- önceki turdan kalıntı kalmasın diye kesin temizlik).
      side_draw_tile = CASE WHEN p_source = 'discard' THEN v_drawn ELSE NULL END,
      side_draw_count = NULL,
      updated_at = now()
  WHERE match_id = p_match_id AND seat_no = p_seat;

  IF p_source = 'discard' THEN
    SELECT count(*)::int INTO v_side_count
    FROM public.okey_player_hands AS h,
         LATERAL jsonb_array_elements(h.tiles) AS t
    WHERE h.match_id = p_match_id AND h.seat_no = p_seat AND t = v_drawn;

    UPDATE public.okey_player_hands
    SET side_draw_count = v_side_count
    WHERE match_id = p_match_id AND seat_no = p_seat;
  END IF;

  RETURN v_drawn;
END;
$$;

REVOKE ALL ON FUNCTION public.okey_internal_draw_for_seat(uuid, smallint, text)
  FROM PUBLIC, anon, authenticated;


-- -----------------------------------------------------------------------------
-- okey_internal_discard_for_seat — gövde 20260903000003'ten taşındı; fark:
-- deste tükendiyse el, sıra devretmeden BU ATIŞLA kapanır.
--
-- DİKKAT: v_match fonksiyonun başında okundu; deste sayacı bu tur içinde
-- yalnızca ÇEKERKEN azalır ve çekme atmadan ÖNCE olur — dolayısıyla buradaki
-- deck_remaining, bu turun çekişini zaten içeriyor.
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.okey_internal_discard_for_seat(
  p_match_id uuid,
  p_seat smallint,
  p_tile jsonb,
  p_is_auto boolean DEFAULT false
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_match public.okey_matches%ROWTYPE;
  v_room public.okey_rooms%ROWTYPE;
  v_tiles jsonb;
  v_idx int;
  i int;
  v_pile jsonb;
  v_next_seat smallint;
  v_is_open boolean;
  v_penalty int;
  v_meld RECORD;
  v_was_processable boolean := false;
  v_side_tile jsonb;
  v_side_count int;
  v_cur_count int;
BEGIN
  SELECT m.* INTO v_match FROM public.okey_matches AS m WHERE m.id = p_match_id;
  SELECT r.* INTO v_room FROM public.okey_rooms AS r WHERE r.id = v_match.room_id;

  SELECT h.tiles, h.is_opening_done, h.side_draw_tile, h.side_draw_count
    INTO v_tiles, v_is_open, v_side_tile, v_side_count
  FROM public.okey_player_hands AS h
  WHERE h.match_id = p_match_id AND h.seat_no = p_seat FOR UPDATE;

  v_idx := NULL;
  FOR i IN 0 .. jsonb_array_length(v_tiles) - 1 LOOP
    IF v_tiles -> i = p_tile THEN
      v_idx := i;
      EXIT;
    END IF;
  END LOOP;
  IF v_idx IS NULL THEN
    RAISE EXCEPTION 'APP:tile_not_in_hand' USING ERRCODE = '22023';
  END IF;

  -- İŞLEK TAŞI ATMA CEZASI ("Hatalı hamle", RULES.md §7) ---------------------
  -- Otomatik hamlede yazılmaz: atılan taşı oyuncu seçmedi.
  --
  -- OKEY ATILDIĞINDA DA YAZILMAZ: okey neredeyse her zaman bir pere
  -- işlenebilir, dolayısıyla okey atan oyuncu hem okey_discard_penalty hem
  -- mistake_discard_penalty yiyip TEK hamle için 202 ödüyordu. Aynı hatanın
  -- iki kez cezalandırılması yerine DAHA ÖZEL kural (okey cezası, RULES.md §8)
  -- geçerlidir.
  IF v_is_open AND NOT p_is_auto
     AND NOT public.okey_tile_is_joker(p_tile, v_match.okey_tile) THEN
    FOR v_meld IN
      SELECT tm.tiles FROM public.okey_table_melds AS tm
      WHERE tm.match_id = p_match_id
        AND tm.meld_type NOT IN ('pair', 'gosterge')
    LOOP
      IF public.okey_internal_extend_meld(
        v_meld.tiles, p_tile, v_match.okey_tile
      ) IS NOT NULL THEN
        v_was_processable := true;
        EXIT;
      END IF;
    END LOOP;
  END IF;

  IF v_was_processable THEN
    SELECT COALESCE(s.mistake_discard_penalty, 101) INTO v_penalty
    FROM public.okey_settings AS s WHERE s.id = true;

    IF COALESCE(v_penalty, 0) > 0 THEN
      UPDATE public.okey_player_hands
      SET penalty_points = penalty_points + v_penalty
      WHERE match_id = p_match_id AND seat_no = p_seat;
    END IF;
  END IF;

  -- YANDAN ÇEKİLEN TAŞ KULLANILMADIYSA CEZA (RULES.md §4/§7) ----------------
  -- v_tiles = ATMA ÖNCESİ el. Taşın kopya sayısı çekme anındakinden AZALMADIYSA
  -- taş perlere girmemiş / işlenmemiş demektir. Taşı ıskartaya atmak da
  -- "kullanmak" sayılmaz (o durumda sayı bu noktada hâlâ eski değerdedir).
  IF v_side_tile IS NOT NULL AND v_side_count IS NOT NULL THEN
    v_cur_count := 0;
    FOR i IN 0 .. jsonb_array_length(v_tiles) - 1 LOOP
      IF v_tiles -> i = v_side_tile THEN
        v_cur_count := v_cur_count + 1;
      END IF;
    END LOOP;

    IF v_cur_count >= v_side_count THEN
      SELECT COALESCE(s.side_draw_penalty, 101) INTO v_penalty
      FROM public.okey_settings AS s WHERE s.id = true;

      IF COALESCE(v_penalty, 0) > 0 THEN
        UPDATE public.okey_player_hands
        SET penalty_points = penalty_points + v_penalty
        WHERE match_id = p_match_id AND seat_no = p_seat;
      END IF;
    END IF;
  END IF;

  v_tiles := v_tiles - v_idx;

  UPDATE public.okey_player_hands SET tiles = v_tiles, updated_at = now()
  WHERE match_id = p_match_id AND seat_no = p_seat;

  -- OKEY ATMA CEZASI --------------------------------------------------------
  -- Otomatik hamlede yazılmaz (bkz. yukarıdaki gerekçe).
  IF NOT p_is_auto
     AND public.okey_tile_is_joker(p_tile, v_match.okey_tile) THEN
    SELECT COALESCE(s.okey_discard_penalty, 101) INTO v_penalty
    FROM public.okey_settings AS s WHERE s.id = true;

    IF COALESCE(v_penalty, 0) > 0 THEN
      UPDATE public.okey_player_hands
      SET penalty_points = penalty_points + v_penalty
      WHERE match_id = p_match_id AND seat_no = p_seat;
    END IF;
  END IF;

  v_pile := COALESCE(v_match.discard_piles -> p_seat::text, '[]'::jsonb)
            || jsonb_build_array(p_tile);

  UPDATE public.okey_matches
  SET discard_piles = jsonb_set(discard_piles, ARRAY[p_seat::text], v_pile)
  WHERE id = p_match_id;

  INSERT INTO public.okey_moves (match_id, hand_no, seat_no, action, tile)
  VALUES (
    p_match_id, v_match.hand_no, p_seat,
    CASE WHEN p_is_auto THEN 'timeout_auto_discard' ELSE 'discard' END,
    p_tile
  );

  -- RULES.md §6: eli boşaldıysa ve el açılmışsa oyuncu BİTİRDİ
  IF jsonb_array_length(v_tiles) = 0 AND v_is_open THEN
    PERFORM public.okey_internal_finalize_hand(p_match_id, p_seat, p_tile);
    RETURN;
  END IF;

  UPDATE public.okey_player_hands
  SET opened_this_turn = false,
      side_draw_tile = NULL,
      side_draw_count = NULL
  WHERE match_id = p_match_id AND seat_no = p_seat;

  -- DESTE BİTTİYSE EL BURADA KAPANIR (kullanıcı isteği 2026-09-05:
  -- "taşları bittiğinde son kişi taş attığı gibi oyun bitsin").
  --
  -- Eskiden el ancak SIRADAKİ oyuncu boş desteden çekmeye çalışınca
  -- kapanıyordu (bkz. okey_internal_draw_for_seat). Yani son taş atıldıktan
  -- sonra masa bir tur daha dönüyor, oyuncular elin neden ve ne zaman
  -- bittiğini göremiyordu. Sıra devretmeden kapatmak hem kuralı hem de
  -- masadaki algıyı düzeltir.
  IF v_match.deck_remaining <= 0 THEN
    PERFORM public.okey_internal_finalize_hand(p_match_id, NULL, NULL);
    RETURN;
  END IF;

  v_next_seat := (p_seat + 1) % 4;
  UPDATE public.okey_matches
  SET turn_seat = v_next_seat,
      turn_phase = 'draw',
      turn_token = gen_random_uuid(),
      turn_deadline = now() + make_interval(secs => v_room.turn_seconds)
  WHERE id = p_match_id;
END;
$$;

REVOKE ALL ON FUNCTION public.okey_internal_discard_for_seat(uuid, smallint, jsonb, boolean)
  FROM PUBLIC, anon, authenticated;


-- -----------------------------------------------------------------------------
-- okey_internal_collect_entry_fees — gövde 20260901000010'dan taşındı; fark:
-- tahsil edilen tutar MASA PUANIDIR (giriş puanı × el sayısı).
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.okey_internal_collect_entry_fees(p_room_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_room public.okey_rooms%ROWTYPE;
  v_player record;
BEGIN
  SELECT r.* INTO v_room FROM public.okey_rooms AS r
  WHERE r.id = p_room_id FOR UPDATE;

  -- Ücretsiz masa ya da zaten tahsil edilmişse hiçbir şey yapma
  IF v_room.id IS NULL OR v_room.table_stake <= 0 OR v_room.entry_fee_collected THEN
    RETURN;
  END IF;

  FOR v_player IN
    SELECT rp.user_id FROM public.okey_room_players AS rp
    WHERE rp.room_id = p_room_id AND rp.user_id IS NOT NULL
  LOOP
    PERFORM public.okey_internal_add_points(
      v_player.user_id, -v_room.table_stake, 'entry_fee',
      p_room_id::text || ':' || v_player.user_id::text
    );
  END LOOP;

  UPDATE public.okey_rooms SET entry_fee_collected = true WHERE id = p_room_id;
END;
$$;

REVOKE ALL ON FUNCTION public.okey_internal_collect_entry_fees(uuid)
  FROM PUBLIC, anon, authenticated;


-- -----------------------------------------------------------------------------
-- okey_internal_award_match — gövde 20260903000006'dan taşındı; fark: pot
-- MASA PUANINDAN hesaplanır (giriş puanı × el sayısı). Tahsilat da aynı
-- tutardan yapıldığı için pot ile kasa birebir tutar.
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.okey_internal_award_match(
  p_room_id uuid,
  p_final_scores jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_room public.okey_rooms%ROWTYPE;
  v_seat int;
  v_score int;
  v_best int;
  v_player record;
  v_winner_seats int[] := ARRAY[]::int[];
  v_winner_users uuid[] := ARRAY[]::uuid[];
  v_team_a int;
  v_team_b int;
  v_human_count int;
  v_pot_gross bigint := 0;
  v_commission bigint := 0;
  v_pot_net bigint := 0;
  v_percent int;
  v_share bigint;
  v_remainder bigint;
  v_uid uuid;
  v_i int;
BEGIN
  SELECT r.* INTO v_room FROM public.okey_rooms AS r WHERE r.id = p_room_id;
  IF v_room.id IS NULL THEN RETURN; END IF;

  -- KAZANAN(LAR) — beraberlikte HEPSİ kazanır, pot aralarında paylaşılır.
  IF v_room.team_mode = 'esli' THEN
    v_team_a := COALESCE((p_final_scores ->> '0')::int, 0)
              + COALESCE((p_final_scores ->> '2')::int, 0);
    v_team_b := COALESCE((p_final_scores ->> '1')::int, 0)
              + COALESCE((p_final_scores ->> '3')::int, 0);
    IF v_team_a = v_team_b THEN
      v_winner_seats := ARRAY[0, 1, 2, 3]; -- berabere: giriş ücreti iadesi
    ELSIF v_team_a < v_team_b THEN
      v_winner_seats := ARRAY[0, 2];
    ELSE
      v_winner_seats := ARRAY[1, 3];
    END IF;
  ELSE
    v_best := NULL;
    FOR v_seat IN 0..3 LOOP
      v_score := COALESCE((p_final_scores ->> v_seat::text)::int, 0);
      IF v_best IS NULL OR v_score < v_best THEN
        v_best := v_score;
      END IF;
    END LOOP;
    FOR v_seat IN 0..3 LOOP
      IF COALESCE((p_final_scores ->> v_seat::text)::int, 0) = v_best THEN
        v_winner_seats := v_winner_seats || v_seat;
      END IF;
    END LOOP;
  END IF;

  FOREACH v_seat IN ARRAY v_winner_seats LOOP
    SELECT rp.user_id INTO v_uid FROM public.okey_room_players AS rp
    WHERE rp.room_id = p_room_id AND rp.seat_no = v_seat;
    IF v_uid IS NOT NULL THEN
      v_winner_users := v_winner_users || v_uid;
    END IF;
  END LOOP;

  -- POT (yalnızca ÜCRETLİ masada ve giriş tahsil edilmişse)
  IF v_room.table_stake > 0 AND v_room.entry_fee_collected THEN
    SELECT count(*)::int INTO v_human_count FROM public.okey_room_players AS rp
    WHERE rp.room_id = p_room_id AND rp.user_id IS NOT NULL;

    v_pot_gross := v_room.table_stake::bigint * COALESCE(v_human_count, 0);

    SELECT COALESCE(s.commission_percent, 0) INTO v_percent
    FROM public.okey_settings AS s WHERE s.id = true;

    v_commission := (v_pot_gross * COALESCE(v_percent, 0)) / 100;
    v_pot_net := v_pot_gross - v_commission;

    IF v_commission > 0 THEN
      INSERT INTO public.okey_house_revenue (source, amount, room_id, ref)
      VALUES ('commission', v_commission, p_room_id, p_room_id::text)
      ON CONFLICT DO NOTHING;
    END IF;

    IF array_length(v_winner_users, 1) IS NOT NULL AND v_pot_net > 0 THEN
      v_share := v_pot_net / array_length(v_winner_users, 1);
      v_remainder := v_pot_net - (v_share * array_length(v_winner_users, 1));

      FOR v_i IN 1 .. array_length(v_winner_users, 1) LOOP
        PERFORM public.okey_internal_add_points(
          v_winner_users[v_i],
          v_share + CASE WHEN v_i = 1 THEN v_remainder ELSE 0 END,
          'match_win',
          p_room_id::text || ':' || v_winner_users[v_i]::text
        );
      END LOOP;
    ELSIF v_pot_net > 0 THEN
      -- Kazananların tamamı BOT: pot kimseye gitmiyor. Yok saymak yerine
      -- deftere yazılır ki dolaşımdan çıkan puan raporlarda görünsün.
      INSERT INTO public.okey_house_revenue (source, amount, room_id, ref)
      VALUES ('unclaimed_pot', v_pot_net, p_room_id, p_room_id::text)
      ON CONFLICT DO NOTHING;
    END IF;
  END IF;

  -- İSTATİSTİKLER / SKOR TABLOSU
  FOR v_player IN
    SELECT rp.user_id, rp.seat_no FROM public.okey_room_players AS rp
    WHERE rp.room_id = p_room_id AND rp.user_id IS NOT NULL
  LOOP
    v_score := COALESCE((p_final_scores ->> v_player.seat_no::text)::int, 0);

    INSERT INTO public.okey_stats AS st (
      user_id, matches_played, matches_won, total_points_won, best_match_score
    ) VALUES (
      v_player.user_id, 1,
      CASE WHEN v_player.seat_no = ANY(v_winner_seats) THEN 1 ELSE 0 END,
      CASE WHEN v_player.seat_no = ANY(v_winner_seats)
                AND array_length(v_winner_users, 1) IS NOT NULL
           THEN v_pot_net / array_length(v_winner_users, 1) ELSE 0 END,
      v_score
    )
    ON CONFLICT (user_id) DO UPDATE SET
      matches_played = st.matches_played + 1,
      matches_won = st.matches_won + EXCLUDED.matches_won,
      total_points_won = st.total_points_won + EXCLUDED.total_points_won,
      best_match_score = LEAST(
        COALESCE(st.best_match_score, EXCLUDED.best_match_score),
        EXCLUDED.best_match_score
      ),
      updated_at = now();
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION public.okey_internal_award_match(uuid, jsonb)
  FROM PUBLIC, anon, authenticated;


-- -----------------------------------------------------------------------------
-- create_okey_room — gövde 20260901000012'den taşındı; fark: bakiye kontrolü
-- MASA PUANINA (giriş × el) bakar.
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.create_okey_room(
  p_is_private boolean DEFAULT false,
  p_game_mode text DEFAULT 'katlamasiz',
  p_team_mode text DEFAULT 'essiz',
  p_assist_mode text DEFAULT 'yardimli',
  p_total_hands int DEFAULT 3,
  p_entry_fee int DEFAULT 100
)
RETURNS public.okey_rooms
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  v_uid CONSTANT uuid := (SELECT auth.uid());
  v_room public.okey_rooms%ROWTYPE;
  v_join_code text;
  v_settings public.okey_settings%ROWTYPE;
  v_wallet public.okey_wallets%ROWTYPE;
  v_room_fee int;
  v_entry int;
  v_min_entry int;
  v_needed bigint;
  v_seat smallint;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501';
  END IF;
  IF public.okey_is_banned(v_uid) THEN
    RAISE EXCEPTION 'APP:okey_banned' USING ERRCODE = '42501';
  END IF;
  IF p_game_mode NOT IN ('katlamasiz', 'katlamali') THEN
    RAISE EXCEPTION 'APP:invalid_game_mode' USING ERRCODE = '22023';
  END IF;
  IF p_team_mode NOT IN ('essiz', 'esli') THEN
    RAISE EXCEPTION 'APP:invalid_team_mode' USING ERRCODE = '22023';
  END IF;
  IF p_assist_mode NOT IN ('yardimli', 'yardimsiz') THEN
    RAISE EXCEPTION 'APP:invalid_assist_mode' USING ERRCODE = '22023';
  END IF;
  IF COALESCE(p_total_hands, 3) < 1 OR COALESCE(p_total_hands, 3) > 20 THEN
    RAISE EXCEPTION 'APP:invalid_total_hands' USING ERRCODE = '22023';
  END IF;

  SELECT s.* INTO v_settings FROM public.okey_settings AS s WHERE s.id = true;
  v_room_fee := COALESCE(v_settings.room_creation_fee, 0);
  v_min_entry := GREATEST(COALESCE(v_settings.min_entry_fee, 100), 1);

  -- MASA SADECE PUANLA AÇILIR: alt sınırın altı reddedilir
  v_entry := COALESCE(p_entry_fee, 0);
  IF v_entry < v_min_entry THEN
    RAISE EXCEPTION 'APP:entry_fee_too_low | en az: %', v_min_entry
      USING ERRCODE = '22023';
  END IF;

  -- Kurucu hem oda ücretini hem KENDİ MASA PUANINI karşılayabilmeli.
  -- Masa puanı el başına puanın el sayısıyla ÇARPIMIDIR (kullanıcı isteği
  -- 2026-09-05): 3 el × 500 = 1500.
  v_needed := v_room_fee::bigint
            + v_entry::bigint * GREATEST(COALESCE(p_total_hands, 3), 1)::bigint;
  IF v_needed > 0 THEN
    v_wallet := public.okey_internal_ensure_wallet(v_uid);
    IF v_wallet.points < v_needed THEN
      RAISE EXCEPTION 'APP:insufficient_points | mevcut: %, gerekli: %',
        v_wallet.points, v_needed USING ERRCODE = 'P0001';
    END IF;
  END IF;

  IF p_is_private THEN
    v_join_code := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
  END IF;

  INSERT INTO public.okey_rooms (
    created_by, is_private, join_code, max_score, turn_seconds,
    game_mode, team_mode, assist_mode, entry_fee, total_hands
  ) VALUES (
    v_uid, p_is_private, v_join_code,
    COALESCE(v_settings.default_max_score, 101),
    COALESCE(v_settings.default_turn_seconds, 20),
    p_game_mode, p_team_mode, p_assist_mode,
    v_entry,
    COALESCE(p_total_hands, 3)
  ) RETURNING * INTO v_room;

  IF v_room_fee > 0 THEN
    PERFORM public.okey_internal_add_points(
      v_uid, -v_room_fee, 'room_fee', v_room.id::text
    );
    INSERT INTO public.okey_house_revenue (source, amount, room_id, user_id, ref)
    VALUES ('room_fee', v_room_fee, v_room.id, v_uid, v_room.id::text)
    ON CONFLICT DO NOTHING;
  END IF;

  FOR v_seat IN 0..3 LOOP
    INSERT INTO public.okey_room_players
      (room_id, seat_no, user_id, joined_at, is_ready)
    VALUES (
      v_room.id, v_seat,
      CASE WHEN v_seat = 0 THEN v_uid ELSE NULL END,
      CASE WHEN v_seat = 0 THEN now() ELSE NULL END,
      false
    );
  END LOOP;

  RETURN v_room;
END;
$$;

REVOKE ALL ON FUNCTION public.create_okey_room(boolean, text, text, text, int, int)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_okey_room(boolean, text, text, text, int, int)
  TO authenticated;


-- -----------------------------------------------------------------------------
-- join_okey_room — gövde 20260901000010'dan taşındı; fark: bakiye kontrolü
-- MASA PUANINA bakar.
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.join_okey_room(
  p_room_id uuid DEFAULT NULL,
  p_join_code text DEFAULT NULL
)
RETURNS TABLE(r_room_id uuid, r_seat_no smallint)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid CONSTANT uuid := (SELECT auth.uid());
  v_room public.okey_rooms%ROWTYPE;
  v_seat smallint;
  v_wallet public.okey_wallets%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501';
  END IF;
  IF public.okey_is_banned(v_uid) THEN
    RAISE EXCEPTION 'APP:okey_banned' USING ERRCODE = '42501';
  END IF;
  IF p_room_id IS NULL AND p_join_code IS NULL THEN
    RAISE EXCEPTION 'APP:room_or_code_required' USING ERRCODE = '22023';
  END IF;

  SELECT r.* INTO v_room FROM public.okey_rooms AS r
  WHERE (p_room_id IS NOT NULL AND r.id = p_room_id)
     OR (p_join_code IS NOT NULL AND r.join_code = upper(p_join_code))
  FOR UPDATE;

  IF v_room.id IS NULL THEN
    RAISE EXCEPTION 'APP:not_found' USING ERRCODE = 'P0001';
  END IF;
  IF v_room.status <> 'waiting' THEN
    RAISE EXCEPTION 'APP:room_not_joinable' USING ERRCODE = 'P0001';
  END IF;

  SELECT rp.seat_no INTO v_seat FROM public.okey_room_players AS rp
  WHERE rp.room_id = v_room.id AND rp.user_id = v_uid;
  IF v_seat IS NOT NULL THEN
    RETURN QUERY SELECT v_room.id, v_seat;
    RETURN;
  END IF;

  -- ÜCRETLİ MASA: MASA PUANINI (giriş × el) karşılayabilmeli
  IF v_room.table_stake > 0 THEN
    v_wallet := public.okey_internal_ensure_wallet(v_uid);
    IF v_wallet.points < v_room.table_stake THEN
      RAISE EXCEPTION 'APP:insufficient_points | mevcut: %, gerekli: %',
        v_wallet.points, v_room.table_stake USING ERRCODE = 'P0001';
    END IF;
  END IF;

  SELECT rp.seat_no INTO v_seat FROM public.okey_room_players AS rp
  WHERE rp.room_id = v_room.id AND rp.user_id IS NULL AND NOT rp.is_bot
  ORDER BY rp.seat_no LIMIT 1 FOR UPDATE;

  IF v_seat IS NULL THEN
    RAISE EXCEPTION 'APP:room_full' USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.okey_room_players
  SET user_id = v_uid, joined_at = now(), is_ready = false, left_at = NULL
  WHERE room_id = v_room.id AND seat_no = v_seat;

  RETURN QUERY SELECT v_room.id, v_seat;
END;
$$;

REVOKE ALL ON FUNCTION public.join_okey_room(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.join_okey_room(uuid, text) TO authenticated;


-- -----------------------------------------------------------------------------
-- okey_match_payouts: maç bitince KİM NE KAZANDI (kullanıcı isteği, madde 4)
--
-- Veri zaten okey_point_transactions defterinde vardı, ama defter satırları
-- başka kullanıcılara da ait olduğu için istemci onu doğrudan okuyamaz.
-- Bu RPC yalnızca O ODANIN hareketlerini, koltuk koltuk özetler.
--
-- Yalnızca masada oturan biri çağırabilir — izleyicinin kimin ne kazandığını
-- görmesi için bir sebep yok.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.okey_match_payouts(uuid);

CREATE FUNCTION public.okey_match_payouts(p_room_id uuid)
RETURNS TABLE(
  seat_no smallint,
  user_id uuid,
  stake bigint,
  won bigint,
  net bigint
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid CONSTANT uuid := (SELECT auth.uid());
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.okey_room_players AS rp
    WHERE rp.room_id = p_room_id AND rp.user_id = v_uid
  ) THEN
    RAISE EXCEPTION 'APP:not_seated' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    rp.seat_no,
    rp.user_id,
    COALESCE((
      SELECT -SUM(t.amount) FROM public.okey_point_transactions AS t
      WHERE t.reason = 'entry_fee'
        AND t.ref = p_room_id::text || ':' || rp.user_id::text
    ), 0)::bigint,
    COALESCE((
      SELECT SUM(t.amount) FROM public.okey_point_transactions AS t
      WHERE t.reason = 'match_win'
        AND t.ref = p_room_id::text || ':' || rp.user_id::text
    ), 0)::bigint,
    COALESCE((
      SELECT SUM(t.amount) FROM public.okey_point_transactions AS t
      WHERE t.reason IN ('entry_fee', 'match_win')
        AND t.ref = p_room_id::text || ':' || rp.user_id::text
    ), 0)::bigint
  FROM public.okey_room_players AS rp
  WHERE rp.room_id = p_room_id
  ORDER BY rp.seat_no;
END;
$$;
REVOKE ALL ON FUNCTION public.okey_match_payouts(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_match_payouts(uuid) TO authenticated;

COMMENT ON FUNCTION public.okey_match_payouts(uuid) IS
  'Maç sonu ödeme özeti: koltuk başına ödenen masa puanı, kazanılan pot payı ve net. Yalnızca o odada oturan kullanıcı çağırabilir.';

NOTIFY pgrst, 'reload schema';

-- =============================================================================
-- 101 Okey — BOTLAR İŞLEK TAŞ ATMAZ (kullanıcı isteği, 2026-09-05:
-- "robot oyuncular işlek taş atmasın")
-- -----------------------------------------------------------------------------
-- ## Ne kaçırılmıştı
--
-- 20260903000001 (işlek taş cezası) şu notu düşüyordu: "Botlar bundan
-- ETKİLENMEZ: okey_bot_take_turn her zaman ÖNCE okey_internal_bot_process_tiles
-- ile işleyebildiği HER taşı işler, ancak SONRA atar — yani atma anında
-- elinde işlenebilir bir taş kalmaz."
--
-- Bu, botun eli AÇIKKEN doğru. Ama işleme yapabilmenin ön koşulu açmaktır
-- (`okey_internal_bot_process_tiles` açık olmayan eli hemen 0 ile döndürür).
-- Eli HENÜZ AÇILMAMIŞ bir bot — ki bir elin ilk turlarında dört botun dördü
-- de böyledir — masadaki açık perlere işlenebilecek taşları hiç süzmeden
-- atıyordu. Sonuç: masadaki insan oyuncu, botların önüne attığı taşlarla
-- perlerini bedavaya büyütüyor; masa "botlar bana taş servis ediyor" gibi
-- görünüyordu.
--
-- İkinci, daha ince durum: eli açık bir bot elinde TEK taş kalınca işlemeyi
-- durdurur (bitiş yalnızca ATMA ile olur, RULES.md §6). O son taş işlenebilir
-- bir taşsa yine ıskartaya gidiyordu.
--
-- ## Yeni kural
--
-- Atılacak taş seçilirken masadaki AÇIK PERLER de okunur. Bir taş herhangi
-- bir açık pere (her iki uçtan) eklenebiliyorsa "işlek"tir ve SON ÇARE
-- dışında atılmaz: bot önce işlek olmayan taşlar arasından en zayıfını arar,
-- ancak elindeki her taş işlekse (nadir) o zaman aralarından en zayıfını atar
-- — bir taş atmak zorunludur, tur kilitlenemez.
--
-- Botun kendi puan hesabı (per/grup adaylığı) DEĞİŞMEDİ; işleklik yalnızca
-- adayları iki kümeye ayıran bir ÖN ELEMEDİR.
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '10s';

-- Eski 2 parametreli imza düşürülür: yeni imzada üçüncü parametrenin
-- varsayılanı var; ikisi yan yana kalırsa 2 argümanlı çağrılar
-- "function is not unique" hatası verir.
DROP FUNCTION IF EXISTS public.okey_internal_bot_pick_discard(jsonb, jsonb);
DROP FUNCTION IF EXISTS public.okey_internal_bot_pick_discard(jsonb, jsonb, uuid);

CREATE FUNCTION public.okey_internal_bot_pick_discard(
  p_tiles jsonb,
  p_okey_tile jsonb,
  p_match_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_groups jsonb;
  v_used jsonb := '[]'::jsonb;
  v_tile jsonb;
  v_other jsonb;
  v_num int;
  v_color text;
  v_potential int;
  v_is_live boolean;
  v_meld RECORD;

  -- İŞLEK OLMAYAN en zayıf aday (tercih edilen)
  v_safe_potential int := NULL;
  v_safe_num int := -1;
  v_safe jsonb := NULL;

  -- İŞLEK en zayıf aday (yalnızca başka çare yoksa)
  v_live_potential int := NULL;
  v_live_num int := -1;
  v_live jsonb := NULL;

  v_in_meld boolean;
  i int;
  j int;
BEGIN
  IF p_tiles IS NULL OR jsonb_array_length(p_tiles) = 0 THEN
    RETURN NULL;
  END IF;

  -- Tamamlanmış perlerdeki taşlar dokunulmazdır
  v_groups := public.okey_internal_find_melds(p_tiles, p_okey_tile);
  FOR i IN 0 .. GREATEST(jsonb_array_length(COALESCE(v_groups, '[]'::jsonb)) - 1, -1) LOOP
    v_used := v_used || (v_groups -> i);
  END LOOP;

  FOR i IN 0 .. jsonb_array_length(p_tiles) - 1 LOOP
    v_tile := p_tiles -> i;

    -- OKEY ASLA ATILMAZ (hem değerli hem de atmak cezalı)
    CONTINUE WHEN public.okey_tile_is_joker(v_tile, p_okey_tile);

    -- Tamamlanmış perin parçasıysa atma
    v_in_meld := false;
    FOR j IN 0 .. GREATEST(jsonb_array_length(v_used) - 1, -1) LOOP
      IF v_used -> j = v_tile THEN
        v_in_meld := true;
        EXIT;
      END IF;
    END LOOP;
    CONTINUE WHEN v_in_meld;

    v_num := COALESCE((v_tile->>'number')::int, 0);
    v_color := v_tile->>'color';
    v_potential := 0;

    -- Elde bu taşla EŞLEŞEBİLECEK başka taş var mı?
    FOR j IN 0 .. jsonb_array_length(p_tiles) - 1 LOOP
      CONTINUE WHEN i = j;
      v_other := p_tiles -> j;
      CONTINUE WHEN public.okey_tile_is_joker(v_other, p_okey_tile);

      -- Grup adayı: aynı sayı, FARKLI renk
      IF (v_other->>'number')::int = v_num
         AND v_other->>'color' IS DISTINCT FROM v_color THEN
        v_potential := v_potential + v_num;
      END IF;

      -- Per adayı: aynı renk, komşu sayı
      IF v_other->>'color' = v_color
         AND abs((v_other->>'number')::int - v_num) = 1 THEN
        v_potential := v_potential + v_num;
      END IF;
    END LOOP;

    -- İŞLEK Mİ? Masadaki açık bir pere (çift/gösterge hariç) eklenebiliyorsa
    -- evet. Maç kimliği verilmemişse (saf çağrı/test) bu eleme yapılmaz ve
    -- davranış eski haliyle aynı kalır.
    v_is_live := false;
    IF p_match_id IS NOT NULL THEN
      FOR v_meld IN
        SELECT tm.tiles FROM public.okey_table_melds AS tm
        WHERE tm.match_id = p_match_id
          AND tm.meld_type NOT IN ('pair', 'gosterge')
      LOOP
        IF public.okey_internal_extend_meld(
          v_meld.tiles, v_tile, p_okey_tile
        ) IS NOT NULL THEN
          v_is_live := true;
          EXIT;
        END IF;
      END LOOP;
    END IF;

    -- En düşük potansiyelli taşı seç; eşitlikte sayısı en yüksek olanı.
    -- İki havuz ayrı tutulur: işlek taşlar ancak işlek olmayan hiç aday
    -- kalmadığında yarışır.
    IF v_is_live THEN
      IF v_live_potential IS NULL
         OR v_potential < v_live_potential
         OR (v_potential = v_live_potential AND v_num > v_live_num) THEN
        v_live_potential := v_potential;
        v_live_num := v_num;
        v_live := v_tile;
      END IF;
    ELSE
      IF v_safe_potential IS NULL
         OR v_potential < v_safe_potential
         OR (v_potential = v_safe_potential AND v_num > v_safe_num) THEN
        v_safe_potential := v_potential;
        v_safe_num := v_num;
        v_safe := v_tile;
      END IF;
    END IF;
  END LOOP;

  IF v_safe IS NOT NULL THEN
    RETURN v_safe;
  END IF;
  -- Elindeki atılabilir her taş işlek: bir taş atmak ZORUNLU, en zayıfı gider.
  IF v_live IS NOT NULL THEN
    RETURN v_live;
  END IF;

  -- Her taş bir perde: okey olmayan, İŞLEK OLMAYAN en yüksek taşı at.
  -- (Perleri bozmak zorunda kalınan bu uç durumda bile rakibin perine
  -- yarayacak taşı vermemeye çalışılır.)
  v_safe_num := -1;
  v_live_num := -1;
  FOR i IN 0 .. jsonb_array_length(p_tiles) - 1 LOOP
    v_tile := p_tiles -> i;
    CONTINUE WHEN public.okey_tile_is_joker(v_tile, p_okey_tile);
    v_num := COALESCE((v_tile->>'number')::int, 0);

    v_is_live := false;
    IF p_match_id IS NOT NULL THEN
      FOR v_meld IN
        SELECT tm.tiles FROM public.okey_table_melds AS tm
        WHERE tm.match_id = p_match_id
          AND tm.meld_type NOT IN ('pair', 'gosterge')
      LOOP
        IF public.okey_internal_extend_meld(
          v_meld.tiles, v_tile, p_okey_tile
        ) IS NOT NULL THEN
          v_is_live := true;
          EXIT;
        END IF;
      END LOOP;
    END IF;

    IF v_is_live THEN
      IF v_num > v_live_num THEN
        v_live_num := v_num;
        v_live := v_tile;
      END IF;
    ELSE
      IF v_num > v_safe_num THEN
        v_safe_num := v_num;
        v_safe := v_tile;
      END IF;
    END IF;
  END LOOP;

  -- Son çare: elde okeyden başka taş yok
  RETURN COALESCE(v_safe, v_live, p_tiles -> 0);
END;
$$;
REVOKE ALL ON FUNCTION public.okey_internal_bot_pick_discard(jsonb, jsonb, uuid)
  FROM PUBLIC, anon, authenticated;

COMMENT ON FUNCTION public.okey_internal_bot_pick_discard(jsonb, jsonb, uuid) IS
  'Botun atacağı taşı seçer. Masadaki açık perlere İŞLENEBİLEN ("işlek") taşlar son çare dışında atılmaz; p_match_id verilmezse bu eleme yapılmaz.';


-- -----------------------------------------------------------------------------
-- okey_bot_take_turn — gövde 20260903000005'ten taşındı. TEK fark: atma
-- adımı maç kimliğini de veriyor, böylece işlek taş elemesi devreye giriyor.
-- -----------------------------------------------------------------------------

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

  -- BAYAT TETİKLEME KORUMASI
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
$$;
REVOKE ALL ON FUNCTION public.okey_bot_take_turn(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_bot_take_turn(uuid, uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';

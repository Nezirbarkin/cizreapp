-- =============================================================================
-- 101 Okey — GÖSTERGE ÇİFTİ YALNIZCA ÇİFTLE AÇANA
-- (kullanıcı isteği, 2026-09-07)
-- -----------------------------------------------------------------------------
-- Gösterge çifti tek taşlıktır: masada duran gösterge, oyuncunun elindeki
-- TEK kopyayla eşleşir ve bir çift sayılır. Yani diğer çiftlerin yarısı
-- kadar taşa mal olur — çiftle açmanın kendine has ödülü.
--
-- 20260905000008 ile SERİ açan koltuklar da (masada çift açan varsa, tur
-- başına sınırlı) çift indirebiliyor. O hak gösterge çiftini de kapsıyordu:
-- seriyle açan bir oyuncu, çift açmanın riskini hiç almadan onun en ucuz
-- ödülünü toplayabiliyordu. Artık gösterge çifti yalnızca ÇİFTLE AÇANIN.
--
-- ## Neden gövde CANLIDAN alındı
--
-- okey_internal_lay_pairs_for_seat son günlerde iki kez güncellendi
-- (seri açanın çift hakkı ve o hakkın tur başına sınırı). Gövdeyi bir göç
-- dosyasından kopyalamak o çalışmayı sessizce geri almak olurdu; tanım
-- pg_get_functiondef ile canlı şemadan alındı ve üzerine yalnızca bu kural
-- eklendi.
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '10s';

CREATE OR REPLACE FUNCTION public.okey_internal_lay_pairs_for_seat(p_match_id uuid, p_seat smallint, p_groups jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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

    -- GÖSTERGE ÇİFTİ YALNIZCA ÇİFTLE AÇANA (kullanıcı isteği, 2026-09-07:
    -- "gösterge yalnızca çift açan kişi gösterge+bir taşla ancak çift
    -- indirebilir").
    --
    -- Gösterge çifti tek taşlıktır: masadaki gösterge, elindeki tek kopyayla
    -- eşleşir. Bu yüzden diğer çiftlerin yarısı kadar taşa mal olur —
    -- çiftle açmanın kendine has ödülüdür. SERİ ile açmış bir koltuk da
    -- kullanabilseydi, çift açmanın riskini almadan onun en ucuz ödülünü
    -- toplardı.
    --
    -- İzin ölçütü: bu çağrı ÇİFTLE AÇILIŞ mı (v_first_open — bu fonksiyon
    -- yalnızca çift yolundadır), yoksa koltuk zaten çiftle mi açmış.
    IF public.okey_is_gosterge_pair(v_group, v_match.indicator_tile)
       AND NOT (v_first_open OR COALESCE(v_hand.opened_with_pairs, false)) THEN
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
$function$;

NOTIFY pgrst, 'reload schema';

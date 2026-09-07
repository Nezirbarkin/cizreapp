-- =============================================================================
-- 101 Okey Plus — OKEY ÇALMA (RULES.md §4)
-- -----------------------------------------------------------------------------
-- EKSİK ÖZELLİK: RULES.md §4 ve §8 "okey çalma"yı tanımlıyordu ama hiçbir yerde
-- uygulanmamıştı — ne bir RPC ne de istemci aksiyonu vardı.
--
--   "Yerdeki bir seride okeyin yerine geçen GERÇEK TAŞ elinde varsa, sıran
--    geldiğinde o taşı yere koyup okeyi eline alabilirsin."
--
-- KURAL AYRINTILARI (uygulama kararları, RULES.md'ye de işlendi):
--   * Masadaki bir pere dokunmak İŞLEME yetkisi ister → eli AÇIK olmayan
--     oyuncu okey çalamaz (okey_add_to_meld ile aynı ön koşul).
--   * Yalnızca 'run' ve 'set' perlerinden çalınabilir. 'pair'/'gosterge'
--     perlerine zaten işleme yapılamaz.
--   * Yerine konan taş, peri GEÇERLİ bırakmalıdır (okey_is_valid_meld).
--     Pozisyon korunur: joker hangi sıradaysa yeni taş oraya yazılır, böylece
--     serinin sırası bozulmaz.
--   * SAHTE OKEY ÇALINAMAZ: okey_tile_is_joker sahte okeyi joker saymaz
--     (bkz. 20260902000001), o yüzden sahte okey perde normal bir taştır.
--   * El boyutu değişmez (bir taş gider, okey gelir) → "elde atılacak taş
--     kalmalı" kuralı (20260903000002) burada kendiliğinden korunur.
--   * Çalınan okey elde tutulursa el sonunda okey_in_hand_penalty işler —
--     yani okey çalmak bedava değildir, işlemek/atmak gerekir.
--
-- BOTLAR: okey çalmayı KULLANMAZ (bilinçli sadeleştirme). Bot zaten okeyi
-- asla atmaz ve elindeki taşları perlere işler; çalma, botun kazanma şansını
-- artırmayan ama karar ağacını belirgin biçimde büyüten bir hamledir.
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '10s';

-- -----------------------------------------------------------------------------
-- Yeni hamle türü: okey çalma
-- -----------------------------------------------------------------------------
ALTER TABLE public.okey_moves
  DROP CONSTRAINT IF EXISTS okey_moves_action_check;
ALTER TABLE public.okey_moves
  ADD CONSTRAINT okey_moves_action_check
  CHECK (action IN (
    'draw_deck', 'draw_discard', 'discard',
    'lay_meld', 'add_to_meld', 'declare_win', 'timeout_auto_discard',
    'steal_okey'
  ));

-- -----------------------------------------------------------------------------
-- okey_steal_joker: masadaki bir perde joker olarak duran OKEY taşını,
-- onun yerine geçen gerçek taşı koyarak ele alır.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.okey_steal_joker(
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
  v_joker jsonb := NULL;
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
  IF v_hand.match_id IS NULL THEN
    RAISE EXCEPTION 'APP:hand_not_found' USING ERRCODE = 'P0001';
  END IF;
  IF NOT v_hand.is_opening_done THEN
    RAISE EXCEPTION 'APP:opening_required' USING ERRCODE = 'P0001';
  END IF;

  SELECT tm.* INTO v_meld FROM public.okey_table_melds AS tm
  WHERE tm.id = p_meld_id AND tm.match_id = p_match_id FOR UPDATE;
  IF v_meld.id IS NULL THEN
    RAISE EXCEPTION 'APP:meld_not_found' USING ERRCODE = 'P0001';
  END IF;
  IF v_meld.meld_type NOT IN ('run', 'set') THEN
    RAISE EXCEPTION 'APP:pair_not_processable' USING ERRCODE = 'P0001';
  END IF;

  -- Konacak taş gerçekten elimde mi?
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

  -- Perdeki her joker konumu denenir: yerine p_tile konunca per hâlâ
  -- geçerliyse o konum kullanılır. (Bir perde en fazla 2 okey bulunabilir.)
  FOR i IN 0 .. jsonb_array_length(v_meld.tiles) - 1 LOOP
    CONTINUE WHEN NOT public.okey_tile_is_joker(
      v_meld.tiles -> i, v_match.okey_tile);

    v_new_tiles := jsonb_set(v_meld.tiles, ARRAY[i::text], p_tile);
    IF public.okey_is_valid_meld(v_new_tiles, v_match.okey_tile) THEN
      v_joker := v_meld.tiles -> i;
      EXIT;
    END IF;
    v_new_tiles := NULL;
  END LOOP;

  IF v_joker IS NULL THEN
    -- Ya perde okey yok, ya da elimdeki taş onun yerine geçmiyor.
    RAISE EXCEPTION 'APP:no_stealable_joker' USING ERRCODE = 'P0001';
  END IF;

  -- Takas: taş perde, okey elde.
  v_remaining := (v_remaining - v_idx) || jsonb_build_array(v_joker);

  UPDATE public.okey_player_hands
  SET tiles = v_remaining, updated_at = now()
  WHERE match_id = p_match_id AND seat_no = v_seat;

  UPDATE public.okey_table_melds
  SET tiles = v_new_tiles, updated_at = now()
  WHERE id = p_meld_id;

  INSERT INTO public.okey_moves (match_id, hand_no, seat_no, action, tile)
  VALUES (p_match_id, v_match.hand_no, v_seat, 'steal_okey', p_tile);
END;
$$;
REVOKE ALL ON FUNCTION public.okey_steal_joker(uuid, bigint, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_steal_joker(uuid, bigint, jsonb) TO authenticated;

COMMENT ON FUNCTION public.okey_steal_joker(uuid, bigint, jsonb) IS
  'RULES.md §4 okey çalma: masadaki bir perde joker duran okey taşını, yerine geçen gerçek taşı koyarak ele alır. Eli açık olmayan oyuncu kullanamaz.';

NOTIFY pgrst, 'reload schema';

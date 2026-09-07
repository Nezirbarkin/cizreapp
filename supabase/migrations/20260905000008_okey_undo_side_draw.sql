-- =============================================================================
-- 101 Okey — YANDAN ALINAN TAŞI GERİ KOYMA (kullanıcı isteği, 2026-09-05:
-- "yandan taş aldım, vazgeçtim diyelim; taşı geri yerine bırakamıyorum,
--  desteden çekeyim")
-- -----------------------------------------------------------------------------
-- ## Neden gerekli
--
-- Soldaki oyuncunun ıskartasından taş almak GERİ ALINAMAZ bir hamleydi. Taşı
-- aldıktan sonra fikir değiştiren oyuncunun tek çıkışı onu geri ATMAKTI — ki
-- o da "yandan aldığın taşı kullanmadın" cezası (+101) demek. Yani küçük bir
-- yanlış dokunuşun bedeli, elin tamamını kaybettirebilecek bir cezaydı.
--
-- Artık taş, HİÇBİR ŞEY YAPILMADIYSA yerine konabilir: ıskartanın en üstüne
-- geri gider, sıra 'çekme' aşamasına döner ve oyuncu desteden çeker.
--
-- ## Hangi koşullarda
--
--   * Yalnızca YANDAN çekilen taş için. Desteden çekilen taş geri konamaz:
--     destenin en üstünü görüp geri koymak, sıradaki taşı BİLMEK demektir —
--     tek başına bir hile kanalı.
--   * Taş hâlâ elde ve o turda BAŞKA hiçbir hamle yapılmamış olmalı (per
--     açma, işleme, okey çalma). Ölçüt okey_moves'tur: çekme hamlesinden
--     SONRA bu koltuğa ait başka bir hamle varsa geri alma kapanır.
--   * TUR BAŞINA BİR KEZ. İkinci bir geri alma, aynı taşı al-bırak
--     döngüsüyle süreyi eritmenin (ve masaya realtime çöp üretmenin) yolu
--     olurdu.
--
-- ## Süre SIFIRLANMAZ
--
-- turn_deadline'a dokunulmaz. Geri alma sırayı yeniden başlatsaydı, süresi
-- dolmak üzere olan oyuncu her seferinde taş alıp geri koyarak sonsuza kadar
-- bekleyebilirdi.
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '10s';

-- Geri almanın hangi TURDA kullanıldığı. Turun kimliği turn_token'dır;
-- aynı tokenle ikinci kez geri alma kabul edilmez.
ALTER TABLE public.okey_player_hands
  ADD COLUMN IF NOT EXISTS side_draw_undone_token uuid;

COMMENT ON COLUMN public.okey_player_hands.side_draw_undone_token IS
  'Yandan alınan taşın geri konduğu turun turn_token''ı. Aynı turda ikinci bir geri alma reddedilir.';

-- Geri alma da bir hamledir ve deftere yazılır: masadaki diğer oyuncular
-- ıskartanın neden geri dolduğunu görebilmeli.
ALTER TABLE public.okey_moves
  DROP CONSTRAINT IF EXISTS okey_moves_action_check;
ALTER TABLE public.okey_moves
  ADD CONSTRAINT okey_moves_action_check
  CHECK (action IN (
    'draw_deck', 'draw_discard', 'discard',
    'lay_meld', 'add_to_meld', 'declare_win', 'timeout_auto_discard',
    'steal_okey', 'undo_draw_discard'
  ));

-- -----------------------------------------------------------------------------
-- okey_can_undo_side_draw — arayüz düğmeyi buna göre gösterir/gizler
--
-- Neden ayrı bir sorgu: istemci koşulları kendi hesaplasaydı (elimde mi, bu
-- turda başka hamle yaptım mı) kural iki yerde yaşardı ve ikisi kaçınılmaz
-- olarak ayrışırdı. Düğmenin görünürlüğü de, işlemin kendisi de AYNI
-- gerçeği okur.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.okey_can_undo_side_draw(uuid);

CREATE FUNCTION public.okey_can_undo_side_draw(p_match_id uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid CONSTANT uuid := (SELECT auth.uid());
  v_match public.okey_matches%ROWTYPE;
  v_seat smallint;
  v_hand public.okey_player_hands%ROWTYPE;
  v_draw_id bigint;
  i int;
  v_has boolean := false;
BEGIN
  IF v_uid IS NULL THEN RETURN false; END IF;

  SELECT m.* INTO v_match FROM public.okey_matches AS m WHERE m.id = p_match_id;
  IF v_match.id IS NULL OR v_match.status <> 'in_progress' THEN RETURN false; END IF;
  IF v_match.turn_phase <> 'discard' THEN RETURN false; END IF;

  SELECT rp.seat_no INTO v_seat FROM public.okey_room_players AS rp
  WHERE rp.room_id = v_match.room_id AND rp.user_id = v_uid;
  IF v_seat IS NULL OR v_seat IS DISTINCT FROM v_match.turn_seat THEN
    RETURN false;
  END IF;

  SELECT h.* INTO v_hand FROM public.okey_player_hands AS h
  WHERE h.match_id = p_match_id AND h.seat_no = v_seat;
  IF v_hand.match_id IS NULL OR v_hand.side_draw_tile IS NULL THEN
    RETURN false;
  END IF;
  IF v_hand.side_draw_undone_token IS NOT DISTINCT FROM v_match.turn_token THEN
    RETURN false; -- tur başına bir kez
  END IF;

  -- Taş hâlâ elde mi?
  FOR i IN 0 .. jsonb_array_length(v_hand.tiles) - 1 LOOP
    IF v_hand.tiles -> i = v_hand.side_draw_tile THEN
      v_has := true;
      EXIT;
    END IF;
  END LOOP;
  IF NOT v_has THEN RETURN false; END IF;

  -- Çekmeden SONRA başka hamle yapıldı mı?
  SELECT max(mv.id) INTO v_draw_id FROM public.okey_moves AS mv
  WHERE mv.match_id = p_match_id AND mv.hand_no = v_match.hand_no
    AND mv.seat_no = v_seat AND mv.action = 'draw_discard';
  IF v_draw_id IS NULL THEN RETURN false; END IF;

  RETURN NOT EXISTS (
    SELECT 1 FROM public.okey_moves AS mv
    WHERE mv.match_id = p_match_id AND mv.seat_no = v_seat AND mv.id > v_draw_id
  );
END;
$$;
REVOKE ALL ON FUNCTION public.okey_can_undo_side_draw(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_can_undo_side_draw(uuid) TO authenticated;

COMMENT ON FUNCTION public.okey_can_undo_side_draw(uuid) IS
  'Yandan alınan taş şu an yerine konabilir mi? Arayüz "geri koy" düğmesini buna göre gösterir.';

-- -----------------------------------------------------------------------------
-- okey_undo_side_draw — taşı ıskartaya geri koyar, sırayı çekme aşamasına alır
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.okey_undo_side_draw(uuid);

CREATE FUNCTION public.okey_undo_side_draw(p_match_id uuid)
RETURNS public.okey_matches
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid CONSTANT uuid := (SELECT auth.uid());
  v_match public.okey_matches%ROWTYPE;
  v_seat smallint;
  v_prev_seat smallint;
  v_hand public.okey_player_hands%ROWTYPE;
  v_tile jsonb;
  v_idx int;
  v_draw_id bigint;
  v_pile jsonb;
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
  IF v_seat IS DISTINCT FROM v_match.turn_seat THEN
    RAISE EXCEPTION 'APP:not_your_turn' USING ERRCODE = '42501';
  END IF;
  IF v_match.turn_phase <> 'discard' THEN
    RAISE EXCEPTION 'APP:wrong_phase' USING ERRCODE = '22023';
  END IF;

  SELECT h.* INTO v_hand FROM public.okey_player_hands AS h
  WHERE h.match_id = p_match_id AND h.seat_no = v_seat FOR UPDATE;

  -- YALNIZCA YANDAN ÇEKİLEN TAŞ. Desteden çekilen taş geri konamaz: üstünü
  -- görüp geri koymak sıradaki taşı bilmek demektir.
  IF v_hand.match_id IS NULL OR v_hand.side_draw_tile IS NULL THEN
    RAISE EXCEPTION 'APP:no_side_draw' USING ERRCODE = 'P0001';
  END IF;
  IF v_hand.side_draw_undone_token IS NOT DISTINCT FROM v_match.turn_token THEN
    RAISE EXCEPTION 'APP:undo_already_used' USING ERRCODE = 'P0001';
  END IF;

  v_tile := v_hand.side_draw_tile;

  -- Taş hâlâ elde mi?
  v_idx := NULL;
  FOR i IN 0 .. jsonb_array_length(v_hand.tiles) - 1 LOOP
    IF v_hand.tiles -> i = v_tile THEN
      v_idx := i;
      EXIT;
    END IF;
  END LOOP;
  IF v_idx IS NULL THEN
    RAISE EXCEPTION 'APP:tile_not_in_hand' USING ERRCODE = '22023';
  END IF;

  -- Çekmeden SONRA başka bir hamle yapıldıysa geri alma kapanır: per açıldıysa
  -- ya da taş işlendiyse masa artık o çekmenin üstüne kurulmuştur.
  SELECT max(mv.id) INTO v_draw_id FROM public.okey_moves AS mv
  WHERE mv.match_id = p_match_id AND mv.hand_no = v_match.hand_no
    AND mv.seat_no = v_seat AND mv.action = 'draw_discard';
  IF v_draw_id IS NULL THEN
    RAISE EXCEPTION 'APP:no_side_draw' USING ERRCODE = 'P0001';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.okey_moves AS mv
    WHERE mv.match_id = p_match_id AND mv.seat_no = v_seat AND mv.id > v_draw_id
  ) THEN
    RAISE EXCEPTION 'APP:undo_too_late' USING ERRCODE = 'P0001';
  END IF;

  -- 1) Taşı elden düş
  UPDATE public.okey_player_hands
  SET tiles = tiles - v_idx,
      side_draw_tile = NULL,
      side_draw_count = NULL,
      side_draw_undone_token = v_match.turn_token,
      updated_at = now()
  WHERE match_id = p_match_id AND seat_no = v_seat;

  -- 2) Iskartanın EN ÜSTÜNE geri koy — alındığı yer orasıydı.
  v_prev_seat := (v_seat + 3) % 4;
  v_pile := COALESCE(v_match.discard_piles -> v_prev_seat::text, '[]'::jsonb)
            || jsonb_build_array(v_tile);

  -- 3) Sıra ÇEKME aşamasına döner; süre SIFIRLANMAZ (bkz. dosya başlığı) ve
  --    turn_token da değişmez — tur aynı turdur, yalnızca aşama geri alındı.
  UPDATE public.okey_matches
  SET discard_piles = jsonb_set(
        discard_piles, ARRAY[v_prev_seat::text], v_pile),
      turn_phase = 'draw'
  WHERE id = p_match_id;

  INSERT INTO public.okey_moves (match_id, hand_no, seat_no, action, tile)
  VALUES (p_match_id, v_match.hand_no, v_seat, 'undo_draw_discard', v_tile);

  SELECT m.* INTO v_match FROM public.okey_matches AS m WHERE m.id = p_match_id;
  RETURN v_match;
END;
$$;
REVOKE ALL ON FUNCTION public.okey_undo_side_draw(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_undo_side_draw(uuid) TO authenticated;

COMMENT ON FUNCTION public.okey_undo_side_draw(uuid) IS
  'Yandan alınan taşı ıskartanın üstüne geri koyar ve sırayı çekme aşamasına döndürür. Tur başına bir kez; taş elde ve o turda başka hamle yapılmamış olmalı. Süreyi sıfırlamaz.';

NOTIFY pgrst, 'reload schema';

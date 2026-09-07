-- =============================================================================
-- 101 Okey Plus — SERİ, ÖNÜNDEN de UZATILABİLİR (yalnızca sonundan değil)
-- -----------------------------------------------------------------------------
-- BULUNAN HATA (kullanıcı örneğiyle ortaya çıktı): "Elimde Siyah 2 var ve
-- işlek — masadaki ıskartada Siyah 3 varsa, önce 2'yi işleyip sonra yandan
-- 3'ü alıp yanına koyabilmeliyim" diye bir istek geldi. Araştırınca ortaya
-- çıktı: okey_add_to_meld, okey_internal_bot_process_tiles VE istemcideki
-- OkeyGameProvider._isProcessableTile/processableTileIndices HEP AYNI
-- deseni kullanıyordu:
--
--     v_new_tiles := v_meld.tiles || jsonb_build_array(p_tile);  -- SONA EKLE
--
-- Ama okey_is_valid_run (ve Dart'taki eşi OkeyMeldValidator._matchesRunFrom)
-- POZİSYON TABANLI çalışır: dizideki i'inci taşın beklenen sayı olmasını
-- ister, dizi SIRALI DEĞİLSE (ör. seri "4-5-6" iken önüne "3" eklenip "4-5-6-3"
-- oluşursa) geçersiz sayar — 3'ün seriyi GERÇEKTE "3-4-5-6" yaparak
-- uzattığını hiç görmez. Yani bir seriyi SADECE en yüksek uçtan uzatmak
-- işliyordu; en düşük uçtan (bir alt sayıyla) uzatmak sessizce reddediliyordu.
-- Bu, gerçek 101 Okey'de tamamen geçerli bir hamle ve oyunu gereksiz yere
-- kısıtlıyordu.
--
-- ÇÖZÜM: tek bir yardımcı fonksiyon (okey_internal_extend_meld) hem SONA
-- EKLEMEYİ hem ÖNE EKLEMEYİ dener, hangisi geçerliyse onu döner. Grup
-- (set) türü perlerde zaten sıra önemsiz olduğu için bu değişiklik onları
-- etkilemez — sadece seri (run) uzatmalarını düzeltir.
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '10s';

-- -----------------------------------------------------------------------------
-- okey_internal_extend_meld: [p_tile] [p_meld_tiles]'a eklenince hâlâ geçerli
-- bir per/grup mu? Öyleyse DOĞRU SIRADAKİ yeni taş dizisini döner (sona ya da
-- öne eklenmiş) — değilse NULL.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.okey_internal_extend_meld(
  p_meld_tiles jsonb,
  p_tile jsonb,
  p_okey_tile jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = ''
AS $$
DECLARE
  v_appended jsonb;
  v_prepended jsonb;
BEGIN
  -- Önce SONA ekleme denenir (en yaygın durum, mevcut davranışla uyumlu).
  v_appended := p_meld_tiles || jsonb_build_array(p_tile);
  IF public.okey_is_valid_meld(v_appended, p_okey_tile) THEN
    RETURN v_appended;
  END IF;

  -- Olmadıysa ÖNE ekleme denenir (serinin alt ucundan uzatma).
  v_prepended := jsonb_build_array(p_tile) || p_meld_tiles;
  IF public.okey_is_valid_meld(v_prepended, p_okey_tile) THEN
    RETURN v_prepended;
  END IF;

  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION public.okey_internal_extend_meld(jsonb, jsonb, jsonb)
  FROM PUBLIC, anon, authenticated;

-- -----------------------------------------------------------------------------
-- okey_add_to_meld: artık okey_internal_extend_meld kullanır.
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

  -- GÖSTERGE ÇİFTİ tamamlanamaz: üzerine taş EKLENEMEZ.
  IF v_meld.meld_type = 'gosterge' THEN
    RAISE EXCEPTION 'APP:gosterge_pair_not_processable' USING ERRCODE = 'P0001';
  END IF;
  -- Normal çiftler de per değildir; işleme yapılmaz.
  IF v_meld.meld_type = 'pair' THEN
    RAISE EXCEPTION 'APP:pair_not_processable' USING ERRCODE = 'P0001';
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

  -- Hem sona hem öne ekleme denenir — bir seri her iki uçtan da uzatılabilir.
  v_new_tiles := public.okey_internal_extend_meld(v_meld.tiles, p_tile, v_match.okey_tile);
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

  -- Eli boşaldıysa bitirdi (RULES.md §6) — atma ile aynı kural
  IF jsonb_array_length(v_remaining) = 0 THEN
    PERFORM public.okey_internal_finalize_hand(p_match_id, v_seat, NULL);
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.okey_add_to_meld(uuid, bigint, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_add_to_meld(uuid, bigint, jsonb) TO authenticated;

-- -----------------------------------------------------------------------------
-- okey_internal_bot_process_tiles: aynı düzeltme, bot için.
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
-- okey_internal_discard_tile_usable: yandan çekme kontrolü de aynı düzeltmeyi
-- kullanır — bir taş masadaki bir seriyi ÖNÜNDEN uzatabiliyorsa da alınabilir.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.okey_internal_discard_tile_usable(
  p_match_id uuid,
  p_seat smallint,
  p_candidate jsonb
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SET search_path = ''
AS $$
DECLARE
  v_match public.okey_matches%ROWTYPE;
  v_hand public.okey_player_hands%ROWTYPE;
  v_meld RECORD;
BEGIN
  SELECT m.* INTO v_match FROM public.okey_matches AS m WHERE m.id = p_match_id;
  SELECT h.* INTO v_hand FROM public.okey_player_hands AS h
  WHERE h.match_id = p_match_id AND h.seat_no = p_seat;

  IF v_hand.is_opening_done THEN
    -- Eli açık: taş yalnızca masadaki açık bir pere (çift/gösterge hariç)
    -- işlenebiliyorsa alınabilir (her iki uçtan uzatma dahil).
    FOR v_meld IN
      SELECT tm.tiles FROM public.okey_table_melds AS tm
      WHERE tm.match_id = p_match_id
        AND tm.meld_type NOT IN ('pair', 'gosterge')
    LOOP
      IF public.okey_internal_extend_meld(
        v_meld.tiles, p_candidate, v_match.okey_tile
      ) IS NOT NULL THEN
        RETURN true;
      END IF;
    END LOOP;
    RETURN false;
  ELSE
    -- Eli henüz açık değil: taş elin per potansiyelini artırıyorsa alınabilir.
    RETURN public.okey_internal_bot_wants_discard(
      v_hand.tiles, p_candidate, v_match.okey_tile
    );
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.okey_internal_discard_tile_usable(uuid, smallint, jsonb)
  FROM PUBLIC, anon, authenticated;

NOTIFY pgrst, 'reload schema';

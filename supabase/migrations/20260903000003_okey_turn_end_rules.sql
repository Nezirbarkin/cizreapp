-- =============================================================================
-- 101 Okey Plus — TUR SONU KURALLARI
--   1) YANDAN ÇEKİLEN TAŞ KULLANILMAK ZORUNDA (RULES.md §4 + §7)
--   2) OTOMATİK (süre dolumu / kopmuş oyuncu) HAMLELER CEZA YAZMAZ
--   3) Otomatik atma artık günlüğe 'timeout_auto_discard' olarak düşer
-- -----------------------------------------------------------------------------
-- 1) YANDAN ÇEKME
--    RULES.md §4: soldaki oyuncunun attığı taşı almak için
--      - elin açık DEĞİLSE: AYNI TURDA elini açmalısın ve alınan taş açtığın
--        perlerden birinde KULLANILMALIDIR,
--      - elin açıksa: taş masadaki açık bir pere İŞLENEBİLMELİ; ele saklanamaz.
--    20260902000004 yalnızca ÇEKME ANINDAKİ "işine yarar mı" kapısını koydu;
--    taşın gerçekten KULLANILDIĞINI hiçbir yer denetlemiyordu. Yani oyuncu
--    yandan taş çekip hiç açmadan turunu bitirebiliyor, ya da eli açıkken
--    taşı işlemeden elinde saklayabiliyordu.
--
--    Yaptırım olarak HAMLEYİ ENGELLEMEK yanlış olurdu: tur bitemeyeceği için
--    masa kilitlenirdi. Bunun yerine RULES.md §7'nin kendi çözümü uygulanır —
--    "Hatalı hamle: açamayacağı halde yandan taş çekmek → +101". Ceza tur
--    sonunda, taş hâlâ elde duruyorsa yazılır.
--
--    NASIL ÖLÇÜLÜR: çekme anında taşın eldeki KOPYA SAYISI kaydedilir
--    (side_draw_count). Tur sonunda sayı azalmamışsa taş kullanılmamıştır.
--    Sayı karşılaştırması, aynı taştan iki kopyası olan oyuncuda yanlış ceza
--    yazılmasını önler (birini perde kullanıp diğerini elde tutabilir).
--    Taşın ıskartaya atılması "kullanmak" SAYILMAZ — atma, taşı zaten elde
--    tutmakla aynı sonucu doğurur.
--
-- 2) OTOMATİK HAMLELERDE CEZA YOK
--    okey_auto_advance / okey_auto_play_absent, oyuncunun SEÇMEDİĞİ bir taşı
--    onun adına atıyor (desteden çekileni geri atıyor). Bu taş okey çıkarsa
--    okey_discard_penalty, masaya işlenebilir bir taş çıkarsa
--    mistake_discard_penalty yazılıyordu — yani bağlantısı kopan ya da süresi
--    dolan oyuncu, HİÇ YAPMADIĞI bir hamle yüzünden +101 yiyordu.
--    Artık otomatik atmalarda bu iki ceza atlanır.
--
--    YANDAN ÇEKME CEZASI OTOMATİKTE DE İŞLER: o taşı yandan çekmek oyuncunun
--    KENDİ kararıydı; süre dolması bu kararı geri almaz.
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '10s';

-- -----------------------------------------------------------------------------
-- Şema: yandan çekilen taşın izi + ceza ayarı
-- -----------------------------------------------------------------------------
ALTER TABLE public.okey_player_hands
  ADD COLUMN IF NOT EXISTS side_draw_tile jsonb,
  ADD COLUMN IF NOT EXISTS side_draw_count int;

COMMENT ON COLUMN public.okey_player_hands.side_draw_tile IS
  'Bu TURDA soldaki oyuncunun ıskartasından alınan taş (yoksa NULL). Tur sonunda kullanılıp kullanılmadığı denetlenir (RULES.md §4).';
COMMENT ON COLUMN public.okey_player_hands.side_draw_count IS
  'side_draw_tile çekildiği anda o taştan elde kaç kopya olduğu. Tur sonunda sayı azalmamışsa taş kullanılmamıştır.';

ALTER TABLE public.okey_settings
  ADD COLUMN IF NOT EXISTS side_draw_penalty int NOT NULL DEFAULT 101;

COMMENT ON COLUMN public.okey_settings.side_draw_penalty IS
  'Soldan aldığı taşı o turda kullanmayan oyuncuya el sonunda eklenen ceza (RULES.md §7 "Açamayacağı halde yandan taş çekmek").';

-- -----------------------------------------------------------------------------
-- okey_internal_draw_for_seat — gövde 20260902000004'ten taşındı; fark:
-- yandan çekilen taşın izi (side_draw_tile / side_draw_count) kaydedilir,
-- desteden çekildiğinde temizlenir.
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

    -- RULES.md §4: taş işine yaramıyorsa hiç alınmaz — ıskartada kalır.
    IF NOT public.okey_internal_discard_tile_usable(p_match_id, p_seat, v_drawn) THEN
      RAISE EXCEPTION 'APP:discard_tile_not_usable' USING ERRCODE = '22023';
    END IF;

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
-- okey_internal_discard_for_seat — gövde 20260903000001'den taşındı.
-- Farklar: p_is_auto parametresi (otomatik hamlelerde ceza yazılmaz ve hamle
-- 'timeout_auto_discard' olarak günlüğe düşer) + yandan çekme cezası.
--
-- ESKİ 3 PARAMETRELİ SÜRÜM DÜŞÜRÜLÜR: varsayılan değerli 4. parametre
-- eklendiğinde iki imza yan yana kalırsa 3 argümanlı çağrılar
-- "function is not unique" hatası verir.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.okey_internal_discard_for_seat(uuid, smallint, jsonb);

-- CREATE OR REPLACE (düz CREATE değil): bu dosya yeniden çalıştırılabilir
-- olmalı — yukarıdaki DROP yalnızca ESKİ 3 parametreli imzayı hedefler,
-- 4 parametreli sürüm zaten varsa düz CREATE "already exists" ile patlardı.
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
-- okey_internal_bot_wants_side_draw: bot soldan taş almalı mı?
--
-- NEDEN AYRI BİR ÖLÇÜT: yandan çekme artık CEZALI (taş kullanılmazsa +101).
-- Botun eski ölçütü (okey_internal_discard_tile_usable) eli AÇIK OLMAYAN bir
-- koltuk için yalnızca "elin per potansiyelini artırır mı" diye bakıyordu;
-- bu, açmaya yetmeyen bir taşı da "işine yarar" sayıp botu her turda cezaya
-- sokardı. Artık:
--   * Eli AÇIKSA: taş masadaki bir pere işlenebiliyorsa alınır — bot zaten
--     aynı turda okey_internal_bot_process_tiles ile onu işler.
--   * Eli AÇIK DEĞİLSE: yalnızca o taşla BU TURDA açılabiliyorsa alınır
--     (taş bulunan perlerden birinde yer almalı ve toplam baraja ulaşmalı).
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
AS $$
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
    RETURN public.okey_internal_discard_tile_usable(p_match_id, p_seat, p_candidate);
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

  -- okey_internal_bot_wants_discard AYRICA sorulur çünkü ÇEKME KAPISI
  -- (okey_internal_draw_for_seat -> okey_internal_discard_tile_usable) eli
  -- açık olmayan koltuk için TAM OLARAK onu kullanır. Bu ölçüt oradakinden
  -- KESİN OLARAK DAHA DAR olmalı; aksi halde bot "alayım" deyip kapıdan
  -- reddedilir ve PERFORM edilen çağrı botun TÜM turunu (açma/işleme/atma)
  -- istisnayla çökertir.
  RETURN v_points >= v_req.min_points
     AND public.okey_internal_bot_wants_discard(
           v_hand.tiles, p_candidate, v_match.okey_tile);
END;
$$;
REVOKE ALL ON FUNCTION public.okey_internal_bot_wants_side_draw(uuid, smallint, jsonb)
  FROM PUBLIC, anon, authenticated;

-- -----------------------------------------------------------------------------
-- okey_auto_advance — gövde 20260831000011'den taşındı; fark: atmalar
-- p_is_auto = true ile yapılır.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.okey_auto_advance(uuid);

CREATE FUNCTION public.okey_auto_advance(p_match_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid CONSTANT uuid := (SELECT auth.uid());
  v_match public.okey_matches%ROWTYPE;
  v_seat smallint;
  v_drawn jsonb;
  v_hand_tiles jsonb;
  v_last_draw jsonb;
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
    RETURN false;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.okey_room_players AS rp
    WHERE rp.room_id = v_match.room_id AND rp.user_id = v_uid
  ) THEN
    RAISE EXCEPTION 'APP:not_seated' USING ERRCODE = '42501';
  END IF;

  -- SÜREYİ SUNUCU DOĞRULAR — istemcinin beyanına güvenilmez
  IF v_match.turn_deadline IS NULL OR now() < v_match.turn_deadline THEN
    RETURN false;
  END IF;

  v_seat := v_match.turn_seat;

  IF v_match.turn_phase = 'draw' THEN
    IF v_match.deck_remaining <= 0 THEN
      PERFORM public.okey_internal_finalize_hand(p_match_id, NULL, NULL);
      RETURN true;
    END IF;

    v_drawn := public.okey_internal_draw_for_seat(p_match_id, v_seat, 'deck');
    IF v_drawn IS NULL THEN
      RETURN true;
    END IF;

    -- Oyuncunun eli DEĞİŞMEZ: az önce çekilen taş geri atılır
    PERFORM public.okey_internal_discard_for_seat(p_match_id, v_seat, v_drawn, true);
    RETURN true;
  END IF;

  SELECT h.tiles INTO v_hand_tiles FROM public.okey_player_hands AS h
  WHERE h.match_id = p_match_id AND h.seat_no = v_seat;

  IF v_hand_tiles IS NULL OR jsonb_array_length(v_hand_tiles) = 0 THEN
    RETURN false;
  END IF;

  SELECT mv.tile INTO v_last_draw
  FROM public.okey_moves AS mv
  WHERE mv.match_id = p_match_id
    AND mv.hand_no = v_match.hand_no
    AND mv.seat_no = v_seat
    AND mv.action IN ('draw_deck', 'draw_discard')
  ORDER BY mv.id DESC
  LIMIT 1;

  IF v_last_draw IS NOT NULL AND v_hand_tiles @> jsonb_build_array(v_last_draw) THEN
    PERFORM public.okey_internal_discard_for_seat(p_match_id, v_seat, v_last_draw, true);
  ELSE
    PERFORM public.okey_internal_discard_for_seat(p_match_id, v_seat, v_hand_tiles -> 0, true);
  END IF;

  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.okey_auto_advance(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_auto_advance(uuid) TO authenticated;

COMMENT ON FUNCTION public.okey_auto_advance(uuid) IS
  'Sıra süresi dolduysa o koltuk adına desteden çekip ÇEKİLEN TAŞI atar. Süreyi sunucu doğrular. Otomatik atma olduğu için okey/işlek taş cezası yazılmaz.';

-- -----------------------------------------------------------------------------
-- okey_auto_play_absent — gövde 20260831000002'den taşındı; fark: atmalar
-- p_is_auto = true ile yapılır.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.okey_auto_play_absent(uuid);

CREATE FUNCTION public.okey_auto_play_absent(p_match_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid CONSTANT uuid := (SELECT auth.uid());
  v_match public.okey_matches%ROWTYPE;
  v_seat smallint;
  v_drawn jsonb;
  v_tiles jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501';
  END IF;

  SELECT m.* INTO v_match FROM public.okey_matches AS m
  WHERE m.id = p_match_id FOR UPDATE;
  IF v_match.id IS NULL OR v_match.status <> 'in_progress' THEN
    RETURN false;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.okey_room_players AS rp
    WHERE rp.room_id = v_match.room_id AND rp.user_id = v_uid
  ) THEN
    RAISE EXCEPTION 'APP:not_seated' USING ERRCODE = '42501';
  END IF;

  v_seat := v_match.turn_seat;

  IF NOT public.okey_seat_is_absent(v_match.room_id, v_seat, 30) THEN
    RETURN false;
  END IF;

  IF v_match.turn_phase = 'draw' THEN
    IF v_match.deck_remaining <= 0 THEN
      PERFORM public.okey_internal_finalize_hand(p_match_id, NULL, NULL);
      RETURN true;
    END IF;
    v_drawn := public.okey_internal_draw_for_seat(p_match_id, v_seat, 'deck');
    IF v_drawn IS NOT NULL THEN
      PERFORM public.okey_internal_discard_for_seat(p_match_id, v_seat, v_drawn, true);
      RETURN true;
    END IF;
    RETURN false;
  END IF;

  SELECT h.tiles INTO v_tiles FROM public.okey_player_hands AS h
  WHERE h.match_id = p_match_id AND h.seat_no = v_seat;
  IF v_tiles IS NOT NULL AND jsonb_array_length(v_tiles) > 0 THEN
    PERFORM public.okey_internal_discard_for_seat(p_match_id, v_seat, v_tiles -> 0, true);
    RETURN true;
  END IF;

  RETURN false;
END;
$$;
REVOKE ALL ON FUNCTION public.okey_auto_play_absent(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_auto_play_absent(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';

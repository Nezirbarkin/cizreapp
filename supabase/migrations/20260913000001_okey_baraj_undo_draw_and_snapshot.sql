-- =============================================================================
-- 101 OKEY — ÜÇ DÜZELTME (kullanıcı isteği, 2026-09-13)
--
--  1) KATLAMALI + EŞLİ BARAJI. Eşi açmış oyuncunun barajı SIFIRLANIYORDU
--     (min_points = 0): masada gerçekten olan şey buydu — 9 Eylül'deki
--     katlamalı+eşli masada açılışlar 120 → 78 → 126 → 60 puanla geçti, yani
--     iki oyuncu "her per"le açtı. Kullanıcının tarifi:
--
--        "A ve B eşli, C ve D eşli. C 120 açtı → D 101 açabilir,
--         A ve B 121 açması lazım."
--
--     Yani eşin açması barajı KALDIRMAZ, TABANA indirir (101 puan / 5 çift).
--
--  2) GERİ KONAN TAŞ AYNI TURDA TEKRAR ALINAMAZ. okey_undo_side_draw taşı
--     ıskartanın üstüne koyup sırayı 'çekme'ye döndürüyor — ve oyuncu aynı
--     taşı hemen yeniden alabiliyordu. Geri alma tur başına bir kez olduğu
--     için bu, "al → geri koy → yine al" ile kendini tuzağa düşürmenin
--     yoluydu: ikinci alıştan sonra vazgeçme hakkı kalmıyor.
--
--  3) TEK TURDA TAZELEME (performans). Masa her realtime olayında BEŞ-YEDİ
--     ayrı ağ turu atıyordu (maç, el, perler, taş sayıları, hamleler, geri
--     koyma hakkı, barajlar). Hepsi tek bir okuma; tek RPC'de dönüyor.
--     Fonksiyon SECURITY INVOKER'dır — maç/el/per satırları çağıranın kendi
--     RLS'i altında okunur, yani izleyici ne görüyorsa onu görür.
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '10s';

-- -----------------------------------------------------------------------------
-- 1) okey_required_opening — EŞLİ İSTİSNASI ARTIK TABANA İNDİRİR
--
-- Eski gövde `RETURN QUERY SELECT 0, 1` diyordu: tek bir per (hatta tek çift)
-- yeterliydi. Yeni gövde katlamalı barajı hesaplar, sonra eş açmışsa o barajı
-- TABANLA sınırlar (LEAST). Katlamasız modda taban zaten 101/5 olduğu için
-- orada davranış DEĞİŞMEZ; değişen yalnızca katlamalı masadaki eştir.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.okey_required_opening(
  p_match_id uuid,
  p_seat smallint
)
RETURNS TABLE(min_points int, min_pairs int)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_match public.okey_matches%ROWTYPE;
  v_room public.okey_rooms%ROWTYPE;
  v_partner_open boolean := false;
  -- TABAN BARAJ (RULES.md §3): her modda geçerli alt sınır.
  v_base_points CONSTANT int := 101;
  v_base_pairs CONSTANT int := 5;
  v_points int;
  v_pairs int;
BEGIN
  SELECT m.* INTO v_match FROM public.okey_matches AS m WHERE m.id = p_match_id;
  SELECT r.* INTO v_room FROM public.okey_rooms AS r WHERE r.id = v_match.room_id;

  IF v_room.game_mode = 'katlamali' THEN
    v_points := GREATEST(v_base_points, v_match.highest_opening_points + 1);
    v_pairs := GREATEST(v_base_pairs, v_match.highest_opening_pairs + 1);
  ELSE
    v_points := v_base_points;
    v_pairs := v_base_pairs;
  END IF;

  -- EŞLİ MOD (RULES.md §5): eşim açtıysa KATLAMA bana işlemez — tabandan
  -- açarım. Barajın tamamen kalkması değil: "her per"le açmak yok.
  IF v_room.team_mode = 'esli' THEN
    SELECT h.is_opening_done INTO v_partner_open
    FROM public.okey_player_hands AS h
    WHERE h.match_id = p_match_id AND h.seat_no = ((p_seat + 2) % 4)::smallint;
    IF COALESCE(v_partner_open, false) THEN
      v_points := LEAST(v_points, v_base_points);
      v_pairs := LEAST(v_pairs, v_base_pairs);
    END IF;
  END IF;

  RETURN QUERY SELECT v_points, v_pairs;
END;
$$;
REVOKE ALL ON FUNCTION public.okey_required_opening(uuid, smallint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_required_opening(uuid, smallint) TO authenticated;

COMMENT ON FUNCTION public.okey_required_opening(uuid, smallint) IS
  'Bu koltuğun açma barajı. Katlamalıda masadaki en yüksek açılış + 1; eşli modda eşi açmışsa TABAN (101 puan / 5 çift) — sıfır değil.';


-- -----------------------------------------------------------------------------
-- 2) okey_internal_draw_for_seat — GERİ KONAN TAŞ O TURDA BİR DAHA ALINAMAZ
--
-- Gövde 20260905000001'den taşındı; tek fark 'discard' dalının başındaki
-- kapıdır.
--
-- Ölçüt `side_draw_undone_token`: okey_undo_side_draw taşı geri koyarken o
-- turun kimliğini (turn_token) oraya yazıyor ve turn_token'a DOKUNMUYOR —
-- tur aynı turdur, yalnızca aşama geri alındı. Dolayısıyla "bu turda geri
-- koydum mu?" sorusu tek bir karşılaştırmadır ve sıra devredince
-- (okey_internal_discard_for_seat yeni token üretir) hak kendiliğinden geri
-- gelir; ayrı bir sıfırlama adımı YOKTUR.
--
-- Kapı burada, okey_take_turn_action'da DEĞİL: yandan çekmenin tek geçiş yeri
-- burasıdır (v1, v2 ve bot yolu hep buradan geçer), kural da tek yerde kalır.
-- Botlar etkilenmez — geri koyma hamlesi yalnızca insanda vardır, bot için
-- token asla eşleşmez.
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
  v_undone_token uuid;
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
    -- YENİ: bu turda yandan aldığı taşı GERİ KOYDUYSA, yan artık kapalıdır.
    SELECT h.side_draw_undone_token INTO v_undone_token
    FROM public.okey_player_hands AS h
    WHERE h.match_id = p_match_id AND h.seat_no = p_seat;
    IF v_undone_token IS NOT NULL
       AND v_undone_token IS NOT DISTINCT FROM v_match.turn_token THEN
      RAISE EXCEPTION 'APP:side_draw_undone' USING ERRCODE = 'P0001';
    END IF;

    v_prev_seat := (p_seat + 3) % 4;
    v_prev_pile := v_match.discard_piles -> v_prev_seat::text;
    IF v_prev_pile IS NULL OR jsonb_array_length(v_prev_pile) = 0 THEN
      RAISE EXCEPTION 'APP:discard_pile_empty' USING ERRCODE = 'P0001';
    END IF;

    v_drawn := v_prev_pile -> (jsonb_array_length(v_prev_pile) - 1);

    -- YANDAN ÇEKME ENGELLENMEZ (kullanıcı isteği 2026-09-05): taşı almak her
    -- zaman mümkündür, kullanmayan RULES.md §4'ün +101 cezasını öder.
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
-- 3) okey_match_snapshot — MASANIN TAMAMI TEK OKUMADA
--
-- İstemci her tazelemede şunları ayrı ayrı çekiyordu:
--   okey_matches · okey_player_hands · okey_table_melds ·
--   get_match_seat_tile_counts · okey_moves · okey_can_undo_side_draw ·
--   okey_match_barajs
--
-- Yedi HTTP turu. Paralel gitseler bile her biri kendi TLS/PostgREST/plan
-- maliyetini ödüyor ve toplam gecikme en yavaş turdan aşağı inemiyordu;
-- mobil ağda tek tur ~80-250 ms. Bu fonksiyon hepsini tek sorgu planında
-- toplar.
--
-- GÜVENLİK — SECURITY INVOKER (varsayılan) BİLEREK seçildi: maç, el ve per
-- satırları çağıranın KENDİ RLS'i altında okunur. Başkasının eli bu yoldan
-- da görünmez; istemci ne görebiliyorsa onu görür. Yalnızca zaten
-- SECURITY DEFINER olan üç yardımcı (taş sayıları, geri koyma hakkı,
-- barajlar) kendi tanımlarıyla çalışır — onlar bugün de aynı şekilde
-- çağrılıyor.
--
-- p_after_move_id NULL ise yalnızca SON hamle döner (masaya ilk girişte
-- "nereden devam ediyorum" işareti); doluysa ondan sonraki en çok 6 hamle
-- eskiden yeniye sıralı döner — istemcideki getMovesSince ile aynı sözleşme.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.okey_match_snapshot(uuid, bigint);

CREATE FUNCTION public.okey_match_snapshot(
  p_match_id uuid,
  p_after_move_id bigint DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = ''
AS $$
DECLARE
  v_uid CONSTANT uuid := (SELECT auth.uid());
  v_match jsonb;
  v_hand jsonb;
  v_melds jsonb;
  v_counts jsonb;
  v_moves jsonb;
  v_barajs jsonb;
  v_seat smallint;
  v_req record;
  v_required jsonb := NULL;
BEGIN
  SELECT to_jsonb(m) INTO v_match
  FROM public.okey_matches AS m WHERE m.id = p_match_id;
  IF v_match IS NULL THEN
    RAISE EXCEPTION 'APP:not_found' USING ERRCODE = 'P0001';
  END IF;

  -- AÇMA BARAJI da bu pakete girer. İstemci katlamalı formülü kendi
  -- hesaplayabiliyor ama EŞLİ modda hesaplayamaz: eşimin is_opening_done
  -- değeri RLS gereği bana kapalı. Eskiden o tek durum için her tazelemede
  -- AYRI bir RPC turu atılıyordu.
  SELECT rp.seat_no INTO v_seat
  FROM public.okey_room_players AS rp
  WHERE rp.room_id = (v_match ->> 'room_id')::uuid AND rp.user_id = v_uid;

  IF v_seat IS NOT NULL THEN
    SELECT * INTO v_req FROM public.okey_required_opening(p_match_id, v_seat);
    v_required := jsonb_build_object(
      'min_points', v_req.min_points, 'min_pairs', v_req.min_pairs);
  END IF;

  -- KENDİ ELİM. RLS zaten sahibinden başkasına vermez; user_id koşulu
  -- izleyicinin (koltuksuz oyuncunun) boş el almasını garanti eder.
  SELECT to_jsonb(h) INTO v_hand
  FROM (
    SELECT ph.tiles, ph.is_opening_done, ph.opened_with_pairs,
           ph.went_for_pairs, ph.penalty_points,
           ph.series_pairs_turn_token, ph.series_pairs_turn_count,
           ph.side_draw_undone_token
    FROM public.okey_player_hands AS ph
    WHERE ph.match_id = p_match_id AND ph.user_id = v_uid
  ) AS h;

  SELECT COALESCE(jsonb_agg(to_jsonb(tm) ORDER BY tm.id), '[]'::jsonb)
  INTO v_melds
  FROM public.okey_table_melds AS tm WHERE tm.match_id = p_match_id;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'seat_no', c.seat_no, 'tile_count', c.tile_count)), '[]'::jsonb)
  INTO v_counts
  FROM public.get_match_seat_tile_counts(p_match_id) AS c;

  IF p_after_move_id IS NULL THEN
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
             'id', q.id, 'seat_no', q.seat_no,
             'action', q.action, 'tile', q.tile)), '[]'::jsonb)
    INTO v_moves
    FROM (
      SELECT mv.id, mv.seat_no, mv.action, mv.tile
      FROM public.okey_moves AS mv
      WHERE mv.match_id = p_match_id
      ORDER BY mv.id DESC LIMIT 1
    ) AS q;
  ELSE
    -- SONDAN al, sonra eskiden yeniye sırala: uzun bir kopmanın ardından en
    -- ESKİ hamleleri oynatmak masanın ŞU ANKİ halini hiç göstermezdi.
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
             'id', q.id, 'seat_no', q.seat_no,
             'action', q.action, 'tile', q.tile
           ) ORDER BY q.id), '[]'::jsonb)
    INTO v_moves
    FROM (
      SELECT mv.id, mv.seat_no, mv.action, mv.tile
      FROM public.okey_moves AS mv
      WHERE mv.match_id = p_match_id AND mv.id > p_after_move_id
      ORDER BY mv.id DESC LIMIT 6
    ) AS q;
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'seat_no', b.seat_no, 'kind', b.kind)), '[]'::jsonb)
  INTO v_barajs
  FROM public.okey_match_barajs(p_match_id) AS b;

  RETURN jsonb_build_object(
    'match', v_match,
    'hand', v_hand,
    'melds', v_melds,
    'counts', v_counts,
    'moves', v_moves,
    'barajs', v_barajs,
    'required_opening', v_required,
    'can_undo_side_draw', public.okey_can_undo_side_draw(p_match_id)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.okey_match_snapshot(uuid, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_match_snapshot(uuid, bigint) TO authenticated;

COMMENT ON FUNCTION public.okey_match_snapshot(uuid, bigint) IS
  'Masanın tamamı tek okumada: maç, kendi elim, masadaki perler, taş sayıları, son hamleler, barajlar, açma barajım, geri koyma hakkı. SECURITY INVOKER — RLS çağıranın kendi hakkıyla uygulanır.';

NOTIFY pgrst, 'reload schema';

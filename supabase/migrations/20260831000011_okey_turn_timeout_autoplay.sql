-- =============================================================================
-- 101 Okey Plus — Süre dolunca otomatik oynatma (çek + çektiğini at)
-- -----------------------------------------------------------------------------
-- İSTENEN DAVRANIŞ:
--   Sıra süresi dolduğunda oyuncu adına desteden taş ÇEKİLİR ve ÇEKİLEN TAŞ
--   DOĞRUDAN ATILIR. Böylece oyuncunun mevcut eli hiç değişmez; yalnızca sıra
--   ilerler.
--
-- ÖNCEKİ DURUM (iki ayrı kusur):
--   1) `okey_auto_advance` desteden çekiyor, ama sonra elin İLK taşını
--      (`tiles -> 0`) atıyordu. Bu, oyuncunun elindeki gerçek bir taşı
--      kaybettiriyordu — istenenin tam tersi.
--   2) Bu fonksiyon istemci tarafından HİÇ ÇAĞRILMIYORDU; yani pratikte süre
--      dolduğunda hiçbir şey olmuyor, masa bekliyordu.
--
-- GÜVENLİK: Süreyi her zaman SUNUCU doğrular (`now() > turn_deadline`).
-- Çağıranın "süre doldu" beyanına asla güvenilmez; masadaki herhangi bir
-- oyuncu tetikleyebilir ama yalnızca gerçekten dolmuşsa iş yapılır.
--
-- YARIŞ DURUMU: Maç satırı `FOR UPDATE` ile kilitlenir. Dört istemci aynı anda
-- tetiklerse ilki sırayı ilerletip yeni bir `turn_deadline` yazar; diğerleri
-- kilidi aldıklarında `now() < turn_deadline` görüp sessizce çıkar. Yani sıra
-- tek adım ilerler, dört adım değil.
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '5s';

-- Dönüş tipi void -> boolean değiştiği için önce düşürülmeli
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

  -- Çağıran bu masada oturuyor olmalı
  IF NOT EXISTS (
    SELECT 1 FROM public.okey_room_players AS rp
    WHERE rp.room_id = v_match.room_id AND rp.user_id = v_uid
  ) THEN
    RAISE EXCEPTION 'APP:not_seated' USING ERRCODE = '42501';
  END IF;

  -- SÜREYİ SUNUCU DOĞRULAR — istemcinin beyanına güvenilmez
  IF v_match.turn_deadline IS NULL OR now() < v_match.turn_deadline THEN
    RETURN false; -- henüz dolmadı, sessizce yok say
  END IF;

  v_seat := v_match.turn_seat;

  -- ---------------------------------------------------------------------
  -- ÇEKME AŞAMASI: desteden çek, ÇEKTİĞİN TAŞI DOĞRUDAN AT
  -- ---------------------------------------------------------------------
  IF v_match.turn_phase = 'draw' THEN
    IF v_match.deck_remaining <= 0 THEN
      -- Deste bitti: el kazanansız kapanır (RULES.md köşe durumu)
      PERFORM public.okey_internal_finalize_hand(p_match_id, NULL, NULL);
      RETURN true;
    END IF;

    v_drawn := public.okey_internal_draw_for_seat(p_match_id, v_seat, 'deck');
    IF v_drawn IS NULL THEN
      -- draw_for_seat deste bitince eli kendisi kapatır ve NULL döner
      RETURN true;
    END IF;

    -- Oyuncunun eli DEĞİŞMEZ: az önce çekilen taş geri atılır
    PERFORM public.okey_internal_discard_for_seat(p_match_id, v_seat, v_drawn);
    RETURN true;
  END IF;

  -- ---------------------------------------------------------------------
  -- ATMA AŞAMASI: oyuncu taşı çekmiş ama atmadan süresi dolmuş.
  -- Aynı mantık: bu turda ÇEKTİĞİ taşı at, eli olduğu gibi kalsın.
  -- ---------------------------------------------------------------------
  SELECT h.tiles INTO v_hand_tiles FROM public.okey_player_hands AS h
  WHERE h.match_id = p_match_id AND h.seat_no = v_seat;

  IF v_hand_tiles IS NULL OR jsonb_array_length(v_hand_tiles) = 0 THEN
    RETURN false;
  END IF;

  -- Bu elde bu koltuğun EN SON çektiği taş
  SELECT mv.tile INTO v_last_draw
  FROM public.okey_moves AS mv
  WHERE mv.match_id = p_match_id
    AND mv.hand_no = v_match.hand_no
    AND mv.seat_no = v_seat
    AND mv.action IN ('draw_deck', 'draw_discard')
  ORDER BY mv.id DESC
  LIMIT 1;

  -- Çektiği taş hâlâ elindeyse onu at; değilse (perlere işlemişse) elin ilk
  -- taşını at — sıra her hâlükârda ilerlemeli, masa kilitlenmemeli.
  IF v_last_draw IS NOT NULL AND v_hand_tiles @> jsonb_build_array(v_last_draw) THEN
    PERFORM public.okey_internal_discard_for_seat(p_match_id, v_seat, v_last_draw);
  ELSE
    PERFORM public.okey_internal_discard_for_seat(p_match_id, v_seat, v_hand_tiles -> 0);
  END IF;

  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.okey_auto_advance(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_auto_advance(uuid) TO authenticated;

COMMENT ON FUNCTION public.okey_auto_advance(uuid) IS
  'Sıra süresi dolduysa o koltuk adına desteden taş çeker ve ÇEKTİĞİ TAŞI atar (el değişmez). Süreyi sunucu doğrular; masadaki herhangi bir oyuncu tetikleyebilir.';

NOTIFY pgrst, 'reload schema';

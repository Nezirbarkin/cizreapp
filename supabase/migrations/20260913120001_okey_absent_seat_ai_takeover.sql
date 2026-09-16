-- =============================================================================
-- 101 Okey — UZUN SÜRE KAYIP OYUNCUNUN KOLTUĞU YAPAY ZEKÂYA DEVREDİLİR
-- -----------------------------------------------------------------------------
-- ŞİKAYET (kullanıcı, 2026-09-13): "okey 101 de oyuncu çıktığındada oyun
-- devam edilsin bot veya gercek kişiler ise de aynı şekilde".
--
-- ÖLÇÜLEN SORUN: okey_auto_play_absent (20260831000002 / 20260903000003)
-- sırası gelen koltuk için YALNIZCA O TEK TURU oynatıyordu (desteden çek,
-- ÇEKTİĞİN TAŞI DOĞRUDAN GERİ AT) — oyuncu bir daha hiç dönmese bile HER
-- turda aynı zayıf hamle tekrarlanıyor; koltuk asla açmıyor, asla işlemiyor,
-- elini hiç iyileştirmiyordu. Daha kötüsü, bu devri tetikleyen mekanizma
-- TAMAMEN İSTEMCİ TARAFLI (bkz. 20260908180001 yorumu: "projede zamanlanmış
-- iş (pg_cron) yok; tetik istemciden gelir"): masada BAŞKA hiçbir gerçek
-- oyuncu kalmadıysa (yalnızca botlarla oynayan TEK insan çıktıysa) kimsenin
-- istemcisi okey_auto_play_absent / okey_bot_take_turn ÇAĞIRMAZ ve masa
-- SONSUZA KADAR "sırası bekleniyor" durumunda asılı kalır — oyuncunun
-- ekranında bu, bitmeyen bir "düşünüyor" nabzı (isThinking) olarak görülür.
--
-- ÇÖZÜM: bir koltuk yeterince uzun süredir (90 sn — tek turu kurtaran 30 sn
-- eşiğinin üstünde, yaklaşık bir tam masa turu kadar) HİÇ görünmüyorsa
-- is_ai_controlled = true işaretlenir ve o turdan itibaren GERÇEK BOT YAPAY
-- ZEKÂSIYLA (okey_bot_take_turn — açar, işler, akıllıca atar) oynatılır.
-- Bundan sonra masadaki HERHANGİ bağlı istemci (tıpkı sıradan bir bot
-- koltuğu gibi) bu turu tetikleyebilir (bkz. OkeyGameProvider
-- _maybeScheduleBotTurn), dolayısıyla "masadaki tek insan da oydu" tıkanması
-- da çözülür: kalan oyuncular onun turunu da bot zamanlayıcısıyla sürükler.
--
-- BİLEREK is_bot BAYRAĞI DEĞİL, AYRI BİR is_ai_controlled SÜTUNU:
-- is_bot, ekonomi tarafında (20260908190001 "BOT KOLTUKLARI DA POTA
-- KATILIR") "bu koltuğun cüzdanı yok; kaybederse payını KASA fonlar,
-- kazanırsa payı hiç BASILMAZ" anlamına geliyor. Gerçek bir oyuncunun
-- koltuğunu is_bot = true yapsaydık: (a) o el kazanırsa GERÇEK CÜZDANINA
-- ÖDEME YAPILMAZDI (bot kazancı basılmıyor), (b) kaybederse zaten girişte
-- kendi cüzdanından alınmış girişin ÜSTÜNE bir de kasa "bot payı" pota
-- eklerdi — parası olan gerçek bir oyuncuyu sessizce ekonomiden düşürür ve
-- defteri bozardı. is_ai_controlled yalnızca "bu turu kim seçiyor" sorusuna
-- cevap verir, "kim kazanır/öder" sorusuna DOKUNMAZ — ekonomi tarafı hiçbir
-- değişiklik görmeden bu koltuğu hep GERÇEK oyuncu olarak işlemeye devam
-- eder.
--
-- KİMLİK GİZLİ KALIR: user_id ve profil değişmez; istemci tarafında
-- OkeyRoomSeat.displayLabel zaten önce gerçek profili kullanıyor (bkz.
-- lib/okey/models/okey_models.dart) — masadaki diğerleri hiçbir şey fark
-- etmez, koltuk sanki oyuncu hâlâ oradaymış gibi akmaya devam eder.
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '10s';

ALTER TABLE public.okey_room_players
  ADD COLUMN IF NOT EXISTS is_ai_controlled boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.okey_room_players.is_ai_controlled IS
  'Gerçek oyuncu uzun süredir (>=90 sn) hiç görünmediği için turu bot yapay zekâsına devredildi. is_bot''tan AYRIDIR: ekonomi (cüzdan/pot/ödeme, bkz. 20260908190001) bu koltuğu hâlâ GERÇEK bir oyuncu sayar, yalnızca hamleyi kimin seçtiği değişir.';

-- -----------------------------------------------------------------------------
-- okey_auto_play_absent — 90 sn+ mutlak sessizlikte koltuğu KALICI olarak
-- AI'ya devreder ve o turu doğrudan gerçek bot yapay zekâsıyla (aç/işle/at)
-- oynatır; 30-89 sn arası davranış (tek turluk zayıf düşüş) değişmedi.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.okey_auto_play_absent(p_match_id uuid)
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

  -- YENİ: 90 sn+ süredir hiç görünmüyorsa koltuk KALICI olarak AI'ya
  -- devredilir (bkz. dosya başındaki gerekçe) ve bu tur doğrudan gerçek bot
  -- yapay zekâsıyla oynanır — aşağıdaki zayıf "çekip geri at" düşüşüne hiç
  -- gerek kalmaz. is_bot DEĞİŞMEZ (ekonomi etkilenmez).
  IF public.okey_seat_is_absent(v_match.room_id, v_seat, 90) THEN
    UPDATE public.okey_room_players
    SET is_ai_controlled = true
    WHERE room_id = v_match.room_id AND seat_no = v_seat
      AND NOT is_bot AND NOT is_ai_controlled;

    PERFORM public.okey_bot_take_turn(p_match_id, v_match.turn_token);
    RETURN true;
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

-- -----------------------------------------------------------------------------
-- okey_bot_take_turn — gövde 20260905000008'den taşındı; TEK fark: giriş
-- kapısı artık is_bot VEYA is_ai_controlled koltuğu oynatıyor (yukarıdaki
-- yeni devir sonrası aynı zengin yapay zekâ AI-devir koltuğu için de çalışır).
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
  v_is_ai_controlled boolean;
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

  SELECT rp.is_bot, rp.is_ai_controlled INTO v_is_bot, v_is_ai_controlled
  FROM public.okey_room_players AS rp
  WHERE rp.room_id = v_match.room_id AND rp.seat_no = v_seat;
  IF NOT (COALESCE(v_is_bot, false) OR COALESCE(v_is_ai_controlled, false)) THEN
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

    -- (RULES.md §3): eli SERİ ile açık bot, masada çift varsa 3'e kadar
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

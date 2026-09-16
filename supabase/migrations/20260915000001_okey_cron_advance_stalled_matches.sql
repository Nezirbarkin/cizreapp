-- =============================================================================
-- 101 Okey — SUNUCU TARAFLI SIRA İLERLETME (istemcisiz masalar artık asılı kalmıyor)
-- -----------------------------------------------------------------------------
-- ŞİKAYET (kullanıcı, 2026-09-15): "okey 101 oyunu oyuncu çıktığında oyun
-- devam edemiyor". Bu, 20260913120001'in çözmeye çalıştığı SORUNUN AYNISI —
-- ama canlıda hâlâ oluyor. Kanıt: okey_matches içinde status='in_progress'
-- VE turn_deadline'ı geçmiş kayıtlar tarandığında, BUGÜN (2026-09-15) dahil
-- her gün yeni "asılı" maç birikiyor (bugün 4, dün 3, 13'ünde 1 — fix'ten
-- SONRA bile) — hepsi turn_seat=0'da, ilk elin ilk turunda, hiç ilerlemeden
-- günlerce/haftalarca donuk duruyor.
--
-- GERÇEK KÖK NEDEN: okey_auto_advance / okey_auto_play_absent / okey_bot_take_turn
-- ÜÇÜ DE yalnızca BAĞLI bir istemcinin yerel zamanlayıcısı (OkeyGameProvider
-- ._maybeAutoAdvance / ._maybeScheduleBotTurn) tetiklediğinde çalışır — projede
-- bunları tetikleyen bir pg_cron işi HİÇ YOKTU. 20260913120001 "istemci
-- tetiklediğinde ne oynanacağını" düzeltti (kalıcı AI devri) ama "hiç istemci
-- kalmadıysa" sorusuna dokunmadı: sırası gelen koltuğun oyuncusu (özellikle
-- 3 bota karşı TEK insan) uygulamayı kapatınca, o maçın ekranını açık tutan
-- SIFIR istemci kalır — ne tur süresi zamanlayıcısı ne kalp atışı ne bot
-- zamanlayıcısı BİR DAHA HİÇ çalışmaz; masa sonsuza kadar donuk kalır.
-- Aynı kök neden 20260904000004'te "terk edilmiş masalar" olarak da tespit
-- edilmişti (o göç yalnızca ODAYI 'abandoned' işaretliyor, MAÇI bitirmiyor —
-- bkz. okey_cleanup_stale_rooms, o da yalnızca istemci tetikler).
-- Projede pg_cron/pg_net zaten VAR ve kullanılıyor (smm-order-status-check,
-- process-notification-outbox, bot_* iş kuyrukları) — yok denen altyapı
-- değil, yalnızca Okey'in tur ilerletmesine hiç bağlanmamış.
--
-- ÇÖZÜM (iki parça):
--
-- 1) SUNUCU TARAFLI SÜPÜRÜCÜ — her 30 saniyede bir pg_cron, turn_deadline'ı
--    geçmiş TÜM 'in_progress' maçları tarar ve HİÇBİR istemciye ihtiyaç
--    duymadan ilerletir: koltuk bot/AI-devirliyse tam bot yapay zekâsıyla
--    (aç/işle/at), değilse ve 90 sn+ kayıpsa koltuğu kalıcı AI'ya devredip
--    yine tam yapay zekâyla, aksi halde (süresi dolmuş ama henüz "kayıp"
--    sayılmayan normal zaman aşımı) mevcut zayıf "çek-geri at" düşüşüyle —
--    istemcinin yaptığıyla BİREBİR AYNI mantık. Bunun için okey_bot_take_turn
--    ve okey_auto_advance'in gövdeleri auth/yetki kontrollerinden arındırılmış
--    ayrı fonksiyonlara taşındı (_body) — hem istemci RPC'si hem süpürücü
--    AYNI gövdeyi çağırır, davranış ayrışmaz. Bir el böyle bitince
--    okey_internal_finalize_hand zaten otomatik start_okey_hand çağırıp bir
--    sonraki eli kendiliğinden dağıtıyor (bkz. 20260906000006) — yani
--    süpürücü yalnızca İLK tıkanan turu açması yeterli, oturumun geri kalanı
--    server-side zaten kendiliğinden akıyor.
--
-- 2) "MASADAN AYRIL" ARTIK SUNUCUYA HABER VERİYOR — oyun ekranındaki bu
--    düğme (bkz. lib/okey/widgets/okey_table_settings_dialog.dart,
--    lib/okey/screens/okey_game_screen.dart onLeaveTable) şimdiye kadar
--    SADECE istemci tarafında lobiye dönüyordu; sunucu hiçbir şey öğrenmiyor,
--    koltuk normal bir bağlantı kopması gibi 90 sn+ "acaba kayıp mı"
--    belirsizliğine bırakılıyordu. Yeni okey_leave_match_seat RPC'si, oyuncu
--    bilinçli olarak "Evet, ayrıl" dediği anda koltuğu KALICI olarak AI'ya
--    devrediyor ve sırası oysa turu hemen oynatıyor — diğer oyuncular
--    beklemeden devam ediyor.
--
-- Süpürücü ayrıca okey_cleanup_stale_rooms'u da (20260904000004, o da
-- yalnızca istemci tetikliyordu) zamanlıyor — aynı hata sınıfının ikinci
-- belirtisi (terk edilmiş masalar "canlı masalar — izle" listesinde takılı
-- kalıyordu).
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '10s';

-- -----------------------------------------------------------------------------
-- 0) Süpürücünün WHERE'i için: in_progress + geçmiş turn_deadline ucuz taransın
-- -----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_okey_matches_in_progress_deadline
  ON public.okey_matches (turn_deadline)
  WHERE status = 'in_progress';

-- -----------------------------------------------------------------------------
-- okey_bot_take_turn_body — 20260913120001'deki okey_bot_take_turn'ün
-- GÖVDESİ (auth/koltuk/token kontrollerinden sonraki kısım), tek başına
-- çağrılabilir hâle getirildi. p_match_id KİLİTLİ VARSAYILIR (çağıran zaten
-- FOR UPDATE ile satırı almış olmalı). Yalnızca sistem içi çağıranlar için —
-- authenticated/anon'a GRANT YOK, dışarıdan RPC olarak çağrılamaz.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.okey_bot_take_turn_body(p_match_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
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
  SELECT m.* INTO v_match FROM public.okey_matches AS m WHERE m.id = p_match_id;
  IF v_match.id IS NULL OR v_match.status <> 'in_progress' THEN
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

    -- Eli SERİ ile açık bot, masada çift varsa çift de indirir. El bu
    -- arada değişmiş olabilir — taşlar yeniden okunur.
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

REVOKE ALL ON FUNCTION public.okey_bot_take_turn_body(uuid) FROM PUBLIC, anon, authenticated;

-- okey_bot_take_turn — ince kabuk: auth/koltuk/bayat-token kontrolü, sonra
-- gövdeyi çağırır. Dışarıya bakan davranış DEĞİŞMEDİ.
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

  PERFORM public.okey_bot_take_turn_body(p_match_id);
END;
$fn$;

REVOKE ALL ON FUNCTION public.okey_bot_take_turn(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_bot_take_turn(uuid, uuid) TO authenticated;

-- -----------------------------------------------------------------------------
-- okey_auto_advance_body — okey_auto_advance'in (20260903000003) auth/süre
-- kontrolünden SONRAKİ gövdesi. Aynı sistem-içi-yalnız kural.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.okey_auto_advance_body(p_match_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_match public.okey_matches%ROWTYPE;
  v_seat smallint;
  v_drawn jsonb;
  v_hand_tiles jsonb;
  v_last_draw jsonb;
BEGIN
  SELECT m.* INTO v_match FROM public.okey_matches AS m WHERE m.id = p_match_id;
  IF v_match.id IS NULL OR v_match.status <> 'in_progress' THEN
    RETURN;
  END IF;

  v_seat := v_match.turn_seat;

  IF v_match.turn_phase = 'draw' THEN
    IF v_match.deck_remaining <= 0 THEN
      PERFORM public.okey_internal_finalize_hand(p_match_id, NULL, NULL);
      RETURN;
    END IF;

    v_drawn := public.okey_internal_draw_for_seat(p_match_id, v_seat, 'deck');
    IF v_drawn IS NULL THEN
      RETURN;
    END IF;

    -- Oyuncunun eli DEĞİŞMEZ: az önce çekilen taş geri atılır
    PERFORM public.okey_internal_discard_for_seat(p_match_id, v_seat, v_drawn, true);
    RETURN;
  END IF;

  SELECT h.tiles INTO v_hand_tiles FROM public.okey_player_hands AS h
  WHERE h.match_id = p_match_id AND h.seat_no = v_seat;

  IF v_hand_tiles IS NULL OR jsonb_array_length(v_hand_tiles) = 0 THEN
    RETURN;
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
END;
$fn$;

REVOKE ALL ON FUNCTION public.okey_auto_advance_body(uuid) FROM PUBLIC, anon, authenticated;

-- okey_auto_advance — ince kabuk: auth/koltuk/süre kontrolü, sonra gövde.
-- Dışarıya bakan davranış DEĞİŞMEDİ.
CREATE OR REPLACE FUNCTION public.okey_auto_advance(p_match_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid CONSTANT uuid := (SELECT auth.uid());
  v_match public.okey_matches%ROWTYPE;
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

  PERFORM public.okey_auto_advance_body(p_match_id);
  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.okey_auto_advance(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_auto_advance(uuid) TO authenticated;

COMMENT ON FUNCTION public.okey_auto_advance(uuid) IS
  'Sıra süresi dolduysa o koltuk adına desteden çekip ÇEKİLEN TAŞI atar. Süreyi sunucu doğrular. Otomatik atma olduğu için okey/işlek taş cezası yazılmaz.';

-- -----------------------------------------------------------------------------
-- okey_cron_advance_stalled_matches — HİÇBİR istemciye ihtiyaç duymadan,
-- turn_deadline'ı geçmiş TÜM in_progress maçları ilerletir. Yalnızca pg_cron
-- çağırır: auth.uid() gerektirmez, authenticated/anon'a GRANT YOK.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.okey_cron_advance_stalled_matches()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_match public.okey_matches%ROWTYPE;
  v_seat smallint;
  v_is_bot boolean;
  v_is_ai_controlled boolean;
BEGIN
  FOR v_match IN
    SELECT m.* FROM public.okey_matches AS m
    WHERE m.status = 'in_progress'
      AND m.turn_deadline IS NOT NULL
      AND m.turn_deadline < now() - interval '2 seconds'
    ORDER BY m.turn_deadline
    FOR UPDATE SKIP LOCKED
  LOOP
    BEGIN
      -- Kilit alındıktan sonra tekrar doğrula: bağlı bir istemci tam bu
      -- sırada ilerletmiş olabilir (SKIP LOCKED yalnızca AYNI ANDA kilitli
      -- olanı atlar, döngü başlarken bekleyip sonra boşalanı değil).
      IF v_match.status <> 'in_progress'
         OR v_match.turn_deadline IS NULL
         OR v_match.turn_deadline >= now() THEN
        CONTINUE;
      END IF;

      v_seat := v_match.turn_seat;

      SELECT rp.is_bot, rp.is_ai_controlled INTO v_is_bot, v_is_ai_controlled
      FROM public.okey_room_players AS rp
      WHERE rp.room_id = v_match.room_id AND rp.seat_no = v_seat;

      IF COALESCE(v_is_bot, false) OR COALESCE(v_is_ai_controlled, false) THEN
        -- Zaten bot/AI-devir koltuk: tam yapay zekâ ile oyna (aç/işle/at).
        PERFORM public.okey_bot_take_turn_body(v_match.id);
      ELSIF public.okey_seat_is_absent(v_match.room_id, v_seat, 90) THEN
        -- 90 sn+ hiç görünmüyor: koltuğu kalıcı AI'ya devret (bkz.
        -- 20260913120001) ve bu turu doğrudan tam yapay zekâyla oyna.
        UPDATE public.okey_room_players
        SET is_ai_controlled = true
        WHERE room_id = v_match.room_id AND seat_no = v_seat
          AND NOT is_bot AND NOT is_ai_controlled;
        PERFORM public.okey_bot_take_turn_body(v_match.id);
      ELSE
        -- Süresi dolmuş ama henüz "kayıp" sayılmayan normal zaman aşımı:
        -- istemcinin okey_auto_advance'i çağırdığındaki AYNI zayıf düşüş.
        PERFORM public.okey_auto_advance_body(v_match.id);
      END IF;
    EXCEPTION WHEN OTHERS THEN
      -- Bir maçtaki beklenmedik hata (ör. yarış koşulu) süpürücünün diğer
      -- maçları ilerletmesini ENGELLEMEMELİ.
      RAISE WARNING 'okey_cron_advance_stalled_matches: match % failed: %',
        v_match.id, SQLERRM;
    END;
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION public.okey_cron_advance_stalled_matches()
  FROM PUBLIC, anon, authenticated;

-- Her 30 saniyede bir çalışır — turn_seconds'la (tipik 15-45 sn) aynı
-- büyüklük mertebesinde, hiç istemci yokken bile masayı makul bir gecikmeyle
-- ilerletir. Bağlı istemciler zaten VARSA onlar bu süpürücüden çok daha
-- hızlı (saniyeler içinde) tetikler; bu yalnızca güvenlik ağı. cron.schedule
-- aynı isimle çağrıldığında işi GÜNCELLER (yeniden göç uygulamak güvenli).
SELECT cron.schedule(
  'okey-advance-stalled-matches',
  '30 seconds',
  $$SELECT public.okey_cron_advance_stalled_matches();$$
);

-- Aynı hata sınıfının ikinci belirtisi (20260904000004): terk edilmiş
-- ODALAR yalnızca lobi açıldığında/admin panelinden temizleniyordu. 5 dk'da
-- bir yeterli — eşik zaten 30 dk (okey_idle_room_interval).
SELECT cron.schedule(
  'okey-cleanup-stale-rooms',
  '*/5 * * * *',
  $$SELECT public.okey_cleanup_stale_rooms();$$
);

-- -----------------------------------------------------------------------------
-- okey_leave_match_seat — "Masadan ayrıl" artık sunucuya haber veriyor.
-- Bilinçli çıkışta 90 sn'lik "kayıp mı?" belirsizliğini beklemeye gerek yok:
-- oyuncu KESİNLİKLE gitti. Koltuk kalıcı olarak AI'ya devredilir (is_bot
-- DEĞİŞMEZ — bkz. 20260913120001, ekonomi/pot payı etkilenmez) ve sırası
-- oysa turu hemen oynatılır.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.okey_leave_match_seat(p_match_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid CONSTANT uuid := (SELECT auth.uid());
  v_match public.okey_matches%ROWTYPE;
  v_seat smallint;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501';
  END IF;

  SELECT m.* INTO v_match FROM public.okey_matches AS m
  WHERE m.id = p_match_id FOR UPDATE;
  IF v_match.id IS NULL THEN
    RAISE EXCEPTION 'APP:not_found' USING ERRCODE = 'P0001';
  END IF;

  SELECT rp.seat_no INTO v_seat FROM public.okey_room_players AS rp
  WHERE rp.room_id = v_match.room_id AND rp.user_id = v_uid;
  IF v_seat IS NULL THEN
    RAISE EXCEPTION 'APP:not_seated' USING ERRCODE = '42501';
  END IF;

  UPDATE public.okey_room_players
  SET is_ai_controlled = true
  WHERE room_id = v_match.room_id AND seat_no = v_seat
    AND NOT is_bot AND NOT is_ai_controlled;

  IF v_match.status = 'in_progress' AND v_match.turn_seat = v_seat THEN
    PERFORM public.okey_bot_take_turn_body(p_match_id);
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.okey_leave_match_seat(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_leave_match_seat(uuid) TO authenticated;

COMMENT ON FUNCTION public.okey_leave_match_seat(uuid) IS
  'Oyuncu maç sırasında "Masadan ayrıl" dediğinde çağrılır: koltuğu kalıcı AI''ya devreder (ekonomi etkilenmez) ve sırası oysa turu hemen oynatır. leave_okey_room''un aksine in_progress maçlarda da çalışır.';

NOTIFY pgrst, 'reload schema';

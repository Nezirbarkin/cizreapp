-- =============================================================================
-- 101 Okey — SENKRON DÜZELTMELERİ (Görev 1.6, 2026-09-27)
-- -----------------------------------------------------------------------------
-- 1) okey_match_snapshot artık SUNUCU SAATİNİ de döndürür ('server_now').
--    Sıra süresi (okey_matches.turn_deadline) sunucu saatiyle yazılır; istemci
--    ise sayacı ve "süre doldu, otomatik oyna" kararını CİHAZ saatiyle
--    veriyordu. Cihaz saati kaymışsa sayaç yanlış gösteriyor, otomatik oynatma
--    çağrısı erken (sunucu reddeder, o sıra için bir daha denenmez) ya da geç
--    gidiyordu. İstemci her masa okumasında farkı ölçüp düzeltir
--    (lib/okey/engine/okey_server_clock.dart). Gövdenin geri kalanı canlıdaki
--    tanımla BİREBİR aynıdır.
--
-- 2) okey_auto_advance: koltuk kontrolü satır KİLİDİNDEN ÖNCE yapılır.
--    İzleyici istemcileri de süre dolunca bu RPC'yi çağırıyordu; fonksiyon
--    ÖNCE maç satırını FOR UPDATE ile kilitleyip SONRA 'not_seated'
--    veriyordu, istemci de hatada her saniye yeniden deniyordu: her izleyici,
--    sıra geçene kadar saniyede bir canlı maç satırını kilitliyor, oyuncuların
--    hamle RPC'leri bu kilidi bekliyordu. Artık koltuksuz çağıran kilit almadan
--    reddedilir (istemci de artık izleyicideyken çağırmıyor). Koltuğu olan
--    çağıranın davranışı DEĞİŞMEZ.
--
-- Canlı test: supabase/tests/manual/okey_sync_fixes_test.sql
-- =============================================================================

BEGIN;

SET LOCAL lock_timeout = '10s';

-- -----------------------------------------------------------------------------
-- 1) Masa okuması + sunucu saati
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.okey_match_snapshot(p_match_id uuid, p_after_move_id bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
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
    'can_undo_side_draw', public.okey_can_undo_side_draw(p_match_id),
    -- İstemci cihaz saatinin sunucudan farkını bununla ölçer.
    'server_now', now()
  );
END;
$function$;

-- -----------------------------------------------------------------------------
-- 2) Süre dolunca otomatik oynatma: koltuk kontrolü KİLİTTEN ÖNCE
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.okey_auto_advance(p_match_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_uid CONSTANT uuid := (SELECT auth.uid());
  v_room_id uuid;
  v_match public.okey_matches%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501';
  END IF;

  -- KİLİTSİZ ÖN KONTROL: masada koltuğu olmayan (izleyici) çağıran, maç
  -- satırını kilitlemeden reddedilir. room_id hiç değişmediği için kilitsiz
  -- okuma güvenlidir.
  SELECT m.room_id INTO v_room_id FROM public.okey_matches AS m
  WHERE m.id = p_match_id;

  IF v_room_id IS NULL THEN
    RAISE EXCEPTION 'APP:not_found' USING ERRCODE = 'P0001';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.okey_room_players AS rp
    WHERE rp.room_id = v_room_id AND rp.user_id = v_uid
  ) THEN
    RAISE EXCEPTION 'APP:not_seated' USING ERRCODE = '42501';
  END IF;

  SELECT m.* INTO v_match FROM public.okey_matches AS m
  WHERE m.id = p_match_id FOR UPDATE;

  IF v_match.id IS NULL THEN
    RAISE EXCEPTION 'APP:not_found' USING ERRCODE = 'P0001';
  END IF;
  IF v_match.status <> 'in_progress' THEN
    RETURN false;
  END IF;

  -- SÜREYİ SUNUCU DOĞRULAR — istemcinin beyanına güvenilmez
  IF v_match.turn_deadline IS NULL OR now() < v_match.turn_deadline THEN
    RETURN false;
  END IF;

  PERFORM public.okey_auto_advance_body(p_match_id);
  RETURN true;
END;
$function$;

NOTIFY pgrst, 'reload schema';

COMMIT;

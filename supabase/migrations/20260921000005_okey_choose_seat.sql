-- =============================================================================
-- 101 Okey — KOLTUK SEÇİMİ (bekleme odasında)
-- -----------------------------------------------------------------------------
-- Kullanıcı isteği (2026-09-21): "oyuncular istediği (eşli) kişinin karşısında
-- oturabilsin".
--
-- ## Sorun
--
-- join_okey_room oyuncuyu HER ZAMAN en düşük numaralı boş koltuğa oturtuyordu
-- ve oturduktan sonra yerini değiştirmenin hiçbir yolu yoktu. Eşli modda
-- takımlar KARŞILIKLI koltuklardır (0-2 ve 1-3, bkz. RULES.md §5), yani
-- "kiminle eş olacağım" sorusunun cevabı tamamen katılma SIRASINA bağlıydı:
-- masayı kuran, davet ettiği arkadaşıyla (koltuk 0 ve 1) daima RAKİP oluyordu.
--
-- ## Çözüm
--
-- okey_choose_seat(oda, koltuk): oturduğum koltuktan, aynı odadaki BOŞ bir
-- koltuğa geç. Yalnızca bekleme aşamasında çalışır (oyun başlayınca koltuk
-- numarası el dağıtımına ve sıra düzenine işlenmiştir).
--
-- ## Bilinçli kısıtlar
--
--  * YALNIZCA BOŞ KOLTUK. Başka bir insanın yerini onun onayı olmadan
--    değiştirmek, bekleme odasını "kim kimi kaydırdı" kavgasına çevirir.
--    Botla dolu koltuk da alınamaz (bkz. join_okey_room: aynı ölçüt).
--  * HAZIR İŞARETİ DÜŞER. Herkes hazırken biri sessizce başka koltuğa geçip
--    eşini değiştirebilir ve el, o kişinin haberi olmadan başlayabilirdi.
--    Geçen oyuncu yeniden "hazırım" der.
--  * ODA KİLİDİ. join/leave/hazır/bot-doldur ile AYNI kilit (okey_rooms satırı,
--    FOR UPDATE): iki kişi aynı boş koltuğa aynı anda geçmeye çalışırsa
--    biri kazanır, öbürü APP:seat_taken alır — koltuk asla iki kez dolmaz.
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '10s';

CREATE OR REPLACE FUNCTION public.okey_choose_seat(
  p_room_id uuid,
  p_seat_no smallint
)
RETURNS smallint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid CONSTANT uuid := (SELECT auth.uid());
  v_room public.okey_rooms%ROWTYPE;
  v_from public.okey_room_players%ROWTYPE;
  v_target public.okey_room_players%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501';
  END IF;
  IF p_seat_no IS NULL OR p_seat_no < 0 OR p_seat_no > 3 THEN
    RAISE EXCEPTION 'APP:invalid_seat' USING ERRCODE = '22023';
  END IF;

  SELECT r.* INTO v_room FROM public.okey_rooms AS r
  WHERE r.id = p_room_id FOR UPDATE;
  IF v_room.id IS NULL THEN
    RAISE EXCEPTION 'APP:not_found' USING ERRCODE = 'P0001';
  END IF;
  IF v_room.status <> 'waiting' THEN
    RAISE EXCEPTION 'APP:room_not_waiting' USING ERRCODE = 'P0001';
  END IF;

  SELECT rp.* INTO v_from FROM public.okey_room_players AS rp
  WHERE rp.room_id = p_room_id AND rp.user_id = v_uid;
  IF v_from.room_id IS NULL THEN
    RAISE EXCEPTION 'APP:not_seated' USING ERRCODE = '42501';
  END IF;

  -- Zaten orada oturuyorum: yapılacak bir şey yok (hazır işareti de KORUNUR).
  IF v_from.seat_no = p_seat_no THEN
    RETURN p_seat_no;
  END IF;

  SELECT rp.* INTO v_target FROM public.okey_room_players AS rp
  WHERE rp.room_id = p_room_id AND rp.seat_no = p_seat_no FOR UPDATE;
  IF v_target.room_id IS NULL
     OR v_target.user_id IS NOT NULL
     OR v_target.is_bot THEN
    RAISE EXCEPTION 'APP:seat_taken' USING ERRCODE = 'P0001';
  END IF;

  -- (room_id, user_id) BENZERSİZ: yeni koltuğa yazmadan ÖNCE eskisi boşalır.
  -- Boşalan koltuk leave_okey_room'un bıraktığı hale gelir.
  UPDATE public.okey_room_players
  SET user_id = NULL, is_ready = false, left_at = now()
  WHERE room_id = p_room_id AND seat_no = v_from.seat_no;

  -- Katılma anı ve son görülme TAŞINIR: bunlar koltuğun değil oyuncunun
  -- bilgisidir (kim önce geldi, ne zaman göründü).
  UPDATE public.okey_room_players
  SET user_id = v_uid,
      joined_at = COALESCE(v_from.joined_at, now()),
      last_seen_at = v_from.last_seen_at,
      is_ready = false,
      left_at = NULL
  WHERE room_id = p_room_id AND seat_no = p_seat_no;

  RETURN p_seat_no;
END;
$$;

REVOKE ALL ON FUNCTION public.okey_choose_seat(uuid, smallint)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_choose_seat(uuid, smallint)
  TO authenticated;

COMMENT ON FUNCTION public.okey_choose_seat(uuid, smallint) IS
  'Bekleme odasinda oturdugum koltuktan ayni odadaki BOS bir koltuga gecer. Eslinde karsi koltuk es olur (0-2, 1-3). Hazir isareti duser; oda kilidi join/leave ile ortaktir.';

NOTIFY pgrst, 'reload schema';

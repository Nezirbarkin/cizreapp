-- =============================================================================
-- 101 Okey — OTOMATİK EŞLEŞTİRME (kullanıcı isteği, 2026-09-07:
-- "masa açmada otomatik eşleştirme ekle ve botlar da eklensin")
-- -----------------------------------------------------------------------------
-- Bugün masaya oturmanın iki yolu var: lobiden AÇIK BİR MASA seçmek ya da
-- kendi masanı KURUP beklemek. İkisi de oyuncuya bir karar yüklüyor —
-- "hangi masa?" ve "kaç kişi bekleyeceğim?". Otomatik eşleştirme bu kararı
-- kaldırır: tek dokunuş, oyuncu ya var olan bir masaya oturur ya da yeni bir
-- masa açılır.
--
-- ## Eşleştirme ölçütü: AYNI MASA AYARLARI
--
-- Mod (katlamalı/katlamasız), takım (eşli/eşsiz), yardım ve EL SAYISI
-- birebir uymalı; giriş çipi ise oyuncunun istediğinden DÜŞÜK OLMAMALI ama
-- yüksek olabiliyor — çünkü daha pahalı bir masaya oturmak bir tercih değil,
-- oyuncunun kaldırabileceği bir yük meselesi ve bakiyesi zaten kontrol
-- ediliyor. Ayarları eşleşmeyen masaya oturtmak "hızlı" değil, YANLIŞ oyun
-- olurdu.
--
-- ## Botlar: HEMEN DEĞİL, SÜRE DOLUNCA
--
-- Eşleşir eşleşmez botlarla doldurmak, otomatik eşleştirmeyi anlamsız
-- kılardı: masa hep botla dolar, iki insan hiç karşılaşmazdı. Bunun yerine
-- yeni kurulan masaya bir SON TARİH yazılır (okey_rooms.auto_fill_bots_at);
-- o an gelene kadar masa insanlara açık kalır, geldiğinde boş koltuklar
-- botlarla dolar ve oyun başlar.
--
-- Süreyi SUNUCU doğrular (bkz. okey_maybe_autofill_bots): istemci "vakit
-- geldi" diye yalan söylerse hiçbir şey olmaz. Bu, sıra süresi otomatik
-- oynatmasıyla (okey_auto_advance) aynı desen — projede zamanlanmış iş
-- (pg_cron) yok, tetik istemciden gelir ama karar sunucunundur.
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '10s';

ALTER TABLE public.okey_rooms
  ADD COLUMN IF NOT EXISTS auto_fill_bots_at timestamptz;

COMMENT ON COLUMN public.okey_rooms.auto_fill_bots_at IS
  'Otomatik eşleştirmeyle kurulan masada boş koltukların botlarla doldurulacağı an. NULL ise otomatik doldurma yok (elle kurulan masalar).';

-- -----------------------------------------------------------------------------
-- okey_quick_match — uygun masaya otur, yoksa kur
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.okey_quick_match(text, text, text, int, int, int);

CREATE FUNCTION public.okey_quick_match(
  p_game_mode text DEFAULT 'katlamasiz',
  p_team_mode text DEFAULT 'essiz',
  p_assist_mode text DEFAULT 'yardimli',
  p_total_hands int DEFAULT 3,
  p_entry_fee int DEFAULT 100,
  p_bot_wait_seconds int DEFAULT 25
)
RETURNS TABLE(room_id uuid, seat_no smallint, created boolean)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid CONSTANT uuid := (SELECT auth.uid());
  v_room public.okey_rooms%ROWTYPE;
  v_new public.okey_rooms%ROWTYPE;
  v_wallet public.okey_wallets%ROWTYPE;
  v_seat smallint;
  v_wait int;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501';
  END IF;
  IF public.okey_is_banned(v_uid) THEN
    RAISE EXCEPTION 'APP:okey_banned' USING ERRCODE = '42501';
  END IF;

  v_wallet := public.okey_internal_ensure_wallet(v_uid);
  v_wait := LEAST(GREATEST(COALESCE(p_bot_wait_seconds, 25), 5), 120);

  -- 1) ZATEN OTURDUĞUM BİR MASA VAR MI? Otomatik eşleştirme ikinci bir masa
  --    açmamalı: oyuncu iki masada birden oynayamaz ve açılan masa boş
  --    beklerken çip bloke ederdi.
  SELECT r.* INTO v_room
  FROM public.okey_rooms AS r
  JOIN public.okey_room_players AS rp ON rp.room_id = r.id
  WHERE rp.user_id = v_uid
    AND r.status IN ('waiting', 'in_progress')
  ORDER BY r.created_at DESC
  LIMIT 1;

  IF v_room.id IS NOT NULL THEN
    SELECT rp.seat_no INTO v_seat FROM public.okey_room_players AS rp
    WHERE rp.room_id = v_room.id AND rp.user_id = v_uid;
    RETURN QUERY SELECT v_room.id, v_seat, false;
    RETURN;
  END IF;

  -- 2) UYGUN AÇIK MASA — en DOLUSU önce: eşleştirmenin işi masaları
  --    birleştirmek, yenilerini çoğaltmak değil. Yarı dolu bir masaya
  --    oturmak, boş bir masada beklemekten her zaman iyidir.
  SELECT r.* INTO v_room
  FROM public.okey_rooms AS r
  WHERE r.status = 'waiting'
    AND NOT r.is_private
    AND r.game_mode = p_game_mode
    AND r.team_mode = p_team_mode
    AND r.assist_mode = p_assist_mode
    AND r.total_hands = COALESCE(p_total_hands, 3)
    AND r.entry_fee >= COALESCE(p_entry_fee, 0)
    AND r.table_stake <= v_wallet.points
    -- Boş (bot olmayan) koltuğu kalmış olmalı.
    AND EXISTS (
      SELECT 1 FROM public.okey_room_players AS rp
      WHERE rp.room_id = r.id AND rp.user_id IS NULL AND NOT rp.is_bot
    )
    -- Botla dolmuş masaya eşleştirme YOK: orada zaten oyun başlamak üzere.
    AND NOT EXISTS (
      SELECT 1 FROM public.okey_room_players AS rp
      WHERE rp.room_id = r.id AND rp.is_bot
    )
  ORDER BY (
    SELECT count(*) FROM public.okey_room_players AS rp
    WHERE rp.room_id = r.id AND rp.user_id IS NOT NULL
  ) DESC, r.created_at ASC
  LIMIT 1;

  IF v_room.id IS NOT NULL THEN
    SELECT j.r_seat_no INTO v_seat
    FROM public.join_okey_room(v_room.id, NULL) AS j;
    RETURN QUERY SELECT v_room.id, v_seat, false;
    RETURN;
  END IF;

  -- 3) YOKSA KUR. create_okey_room oda ücretini alır, bakiyeyi doğrular ve
  --    kurucuyu 0. koltuğa oturtur.
  SELECT * INTO v_new FROM public.create_okey_room(
    false, p_game_mode, p_team_mode, p_assist_mode,
    p_total_hands, p_entry_fee
  );

  -- BOT SON TARİHİ yalnızca otomatik eşleştirmeyle kurulan masaya yazılır:
  -- elle masa kuran oyuncu arkadaşlarını bekliyor olabilir, onun masasını
  -- botlarla doldurmak istemediği bir oyunu başlatmak olurdu.
  UPDATE public.okey_rooms
  SET auto_fill_bots_at = now() + make_interval(secs => v_wait)
  WHERE id = v_new.id;

  SELECT rp.seat_no INTO v_seat FROM public.okey_room_players AS rp
  WHERE rp.room_id = v_new.id AND rp.user_id = v_uid;

  RETURN QUERY SELECT v_new.id, v_seat, true;
END;
$$;
REVOKE ALL ON FUNCTION
  public.okey_quick_match(text, text, text, int, int, int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION
  public.okey_quick_match(text, text, text, int, int, int) TO authenticated;

COMMENT ON FUNCTION public.okey_quick_match(text, text, text, int, int, int) IS
  'Otomatik eşleştirme: aynı ayarlara sahip en dolu açık masaya oturtur, yoksa yeni masa kurar ve bot son tarihi yazar. Oyuncunun zaten bir masası varsa onu döndürür.';

-- -----------------------------------------------------------------------------
-- okey_maybe_autofill_bots — süre dolduysa boş koltukları botlarla doldur
--
-- İstemci tetikler, SUNUCU doğrular (bkz. dosya başlığı). Masadaki herkes
-- çağırabilir; son tarih geçmediyse ya da masa zaten doluysa hiçbir şey
-- yapmaz ve false döner.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.okey_maybe_autofill_bots(uuid);

CREATE FUNCTION public.okey_maybe_autofill_bots(p_room_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid CONSTANT uuid := (SELECT auth.uid());
  v_room public.okey_rooms%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501';
  END IF;

  SELECT r.* INTO v_room FROM public.okey_rooms AS r
  WHERE r.id = p_room_id FOR UPDATE;
  IF v_room.id IS NULL OR v_room.status <> 'waiting' THEN
    RETURN false;
  END IF;
  IF v_room.auto_fill_bots_at IS NULL OR now() < v_room.auto_fill_bots_at THEN
    RETURN false;
  END IF;

  -- Yalnızca o masadakiler tetikleyebilir.
  IF NOT EXISTS (
    SELECT 1 FROM public.okey_room_players AS rp
    WHERE rp.room_id = p_room_id AND rp.user_id = v_uid
  ) THEN
    RETURN false;
  END IF;

  -- Boş koltuk kalmadıysa yapacak bir şey yok (masa insanlarla dolmuş).
  IF NOT EXISTS (
    SELECT 1 FROM public.okey_room_players AS rp
    WHERE rp.room_id = p_room_id AND rp.user_id IS NULL AND NOT rp.is_bot
  ) THEN
    UPDATE public.okey_rooms SET auto_fill_bots_at = NULL WHERE id = p_room_id;
    RETURN false;
  END IF;

  -- SON TARİH ÖNCE SİLİNİR: dört istemci aynı anda tetiklerse ikincisi bu
  -- satırı görüp geri döner (satır zaten FOR UPDATE ile kilitli).
  UPDATE public.okey_rooms SET auto_fill_bots_at = NULL WHERE id = p_room_id;

  PERFORM public.okey_fill_with_bots(p_room_id);
  RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION public.okey_maybe_autofill_bots(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_maybe_autofill_bots(uuid) TO authenticated;

COMMENT ON FUNCTION public.okey_maybe_autofill_bots(uuid) IS
  'Otomatik eşleştirme masasında süre dolduysa boş koltukları botlarla doldurur. Süreyi sunucu doğrular; erken çağrı hiçbir şey yapmaz.';

NOTIFY pgrst, 'reload schema';

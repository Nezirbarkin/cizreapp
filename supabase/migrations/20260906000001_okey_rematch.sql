-- =============================================================================
-- 101 Okey — AYNI MASAYLA YENİDEN OYNA (kullanıcı isteği, 2026-09-06)
-- -----------------------------------------------------------------------------
-- Maç bitince oda da kapanıyor (okey_rooms.status = 'finished'). Yani birlikte
-- oynamaktan memnun dört kişinin tekrar buluşmasının tek yolu, birinin lobiden
-- yeni masa açıp diğer üçünün onu bulmasıydı — pratikte masa dağılıyordu.
--
-- ## Neden yeni bir ODA, eskisini yeniden açmak değil
--
-- Biten oda bir DEFTERDİR: skorları, ödemeleri (okey_match_payouts o odanın
-- hareketlerini okur), maçları ve hediyeleri ona bağlı. Aynı odayı sıfırlayıp
-- yeniden başlatmak, biten maçın kaydını geçmişe dönük bozardı — oyuncu maç
-- sonu ekranına geri döndüğünde başka bir maçın rakamlarını görürdü.
--
-- Bu yüzden REMATCH = AYNI AYARLARLA YENİ ODA, eskisine `rematch_of` ile
-- bağlı. Masa aynı masa gibi davranır (aynı el sayısı, aynı giriş puanı, aynı
-- mod), defter ise ayrı kalır.
--
-- ## Buluşma noktası: TEK oda
--
-- Dört oyuncu da "yeniden oyna"ya basınca dört ayrı oda açılsaydı hiçbiri
-- diğerini bulamazdı. Bu yüzden ilk basan odayı KURAR, sonrakiler aynı odaya
-- KATILIR: `rematch_of` üzerindeki KISMİ TEKİL İNDEKS bunu veritabanı
-- düzeyinde garanti eder — aynı anda basan iki oyuncudan biri indeksten döner
-- ve var olan odaya katılır.
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '10s';

ALTER TABLE public.okey_rooms
  ADD COLUMN IF NOT EXISTS rematch_of uuid
    REFERENCES public.okey_rooms(id) ON DELETE SET NULL;

COMMENT ON COLUMN public.okey_rooms.rematch_of IS
  'Bu oda hangi biten odanın "yeniden oyna"sıysa onun kimliği. Aynı masanın tekrar buluşma noktası.';

-- BİR BİTEN ODANIN EN FAZLA BİR REMATCH ODASI OLUR.
--
-- Kısmi indeks (WHERE rematch_of IS NOT NULL) çünkü normal odaların hepsinde
-- bu alan NULL'dur ve NULL'lar tekillik kuralına girmemelidir.
CREATE UNIQUE INDEX IF NOT EXISTS uq_okey_rooms_rematch_of
  ON public.okey_rooms (rematch_of) WHERE rematch_of IS NOT NULL;

-- -----------------------------------------------------------------------------
-- okey_rematch_room — aynı ayarlarla yeni masa; ilk basan kurar, diğerleri katılır
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.okey_rematch_room(uuid);

CREATE FUNCTION public.okey_rematch_room(p_room_id uuid)
RETURNS TABLE(room_id uuid, seat_no smallint, created boolean)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid CONSTANT uuid := (SELECT auth.uid());
  v_old public.okey_rooms%ROWTYPE;
  v_new public.okey_rooms%ROWTYPE;
  v_existing public.okey_rooms%ROWTYPE;
  v_seat smallint;
  v_min_entry int;
  v_created boolean := false;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501';
  END IF;

  -- ESKİ ODAYI KİLİTLE: "önce bakan kurar, sonrakiler katılır" yarışı
  -- burada serileşir.
  SELECT r.* INTO v_old FROM public.okey_rooms AS r
  WHERE r.id = p_room_id FOR UPDATE;
  IF v_old.id IS NULL THEN
    RAISE EXCEPTION 'APP:not_found' USING ERRCODE = 'P0001';
  END IF;

  -- YALNIZCA O MASADA OTURANLAR. Biten bir odanın kimliğini eline geçiren
  -- herkes aynı ayarlarla masa açabilseydi, bu bir "rematch" değil kısayol
  -- bir oda üreteci olurdu.
  IF NOT EXISTS (
    SELECT 1 FROM public.okey_room_players AS rp
    WHERE rp.room_id = p_room_id AND rp.user_id = v_uid
  ) THEN
    RAISE EXCEPTION 'APP:not_seated' USING ERRCODE = '42501';
  END IF;

  -- 1) ZATEN KURULMUŞ MU?
  SELECT r.* INTO v_existing FROM public.okey_rooms AS r
  WHERE r.rematch_of = p_room_id;

  IF v_existing.id IS NOT NULL THEN
    -- Masa çoktan başladıysa ya da dağıldıysa yeniden buluşma yeri kalmadı:
    -- oyuncuyu boş bir odaya göndermek yerine açıkça söylenir.
    IF v_existing.status <> 'waiting' THEN
      RAISE EXCEPTION 'APP:rematch_already_started' USING ERRCODE = 'P0001';
    END IF;
    SELECT j.r_seat_no INTO v_seat
    FROM public.join_okey_room(v_existing.id, v_existing.join_code) AS j;
    RETURN QUERY SELECT v_existing.id, v_seat, false;
    RETURN;
  END IF;

  -- 2) KUR — aynı ayarlar. create_okey_room oda ücretini alır, bakiyeyi
  --    doğrular ve kurucuyu 0. koltuğa oturtur; hepsi tek yerde kalsın diye
  --    burada tekrarlanmaz.
  --
  -- GİRİŞ PUANI BUGÜNÜN ALT SINIRINA ÇEKİLİR: eski masa, alt sınır
  -- yükselmeden önce (ya da ücretsiz masaların olduğu dönemde) kurulmuş
  -- olabilir. Ayarı olduğu gibi geçirmek, o masaların "yeniden oyna"sını
  -- APP:entry_fee_too_low ile kalıcı olarak imkânsız kılardı.
  SELECT COALESCE(s.min_entry_fee, 100) INTO v_min_entry
  FROM public.okey_settings AS s WHERE s.id = true;

  SELECT * INTO v_new FROM public.create_okey_room(
    v_old.is_private,
    v_old.game_mode,
    v_old.team_mode,
    v_old.assist_mode,
    v_old.total_hands,
    GREATEST(COALESCE(v_old.entry_fee, 0), GREATEST(COALESCE(v_min_entry, 100), 1))
  );

  UPDATE public.okey_rooms SET rematch_of = p_room_id WHERE id = v_new.id;
  v_created := true;

  SELECT rp.seat_no INTO v_seat FROM public.okey_room_players AS rp
  WHERE rp.room_id = v_new.id AND rp.user_id = v_uid;

  RETURN QUERY SELECT v_new.id, v_seat, v_created;
END;
$$;
REVOKE ALL ON FUNCTION public.okey_rematch_room(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_rematch_room(uuid) TO authenticated;

COMMENT ON FUNCTION public.okey_rematch_room(uuid) IS
  'Biten bir masanın "yeniden oyna"sı: aynı ayarlarla yeni oda. İlk çağıran kurar, sonrakiler aynı odaya katılır (rematch_of tekil indeksi). Yalnızca o masada oturmuş oyuncular çağırabilir.';

-- -----------------------------------------------------------------------------
-- okey_rematch_room_of — masadakiler "birisi kurdu mu" diye bakar
--
-- Neden ayrı bir okuma: maç sonu ekranı düğmeyi "YENİDEN OYNA" mı yoksa
-- "MASAYA KATIL" mı diye yazacağını bilmeli. Basmadan önce öğrenilmezse
-- oyuncu her seferinde oda kurduğunu sanır.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.okey_rematch_room_of(uuid);

CREATE FUNCTION public.okey_rematch_room_of(p_room_id uuid)
RETURNS TABLE(room_id uuid, status text, seated_count int)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid CONSTANT uuid := (SELECT auth.uid());
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.okey_room_players AS rp
    WHERE rp.room_id = p_room_id AND rp.user_id = v_uid
  ) THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT r.id, r.status,
         (SELECT count(*)::int FROM public.okey_room_players AS rp
           WHERE rp.room_id = r.id AND rp.user_id IS NOT NULL)
  FROM public.okey_rooms AS r
  WHERE r.rematch_of = p_room_id;
END;
$$;
REVOKE ALL ON FUNCTION public.okey_rematch_room_of(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_rematch_room_of(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';

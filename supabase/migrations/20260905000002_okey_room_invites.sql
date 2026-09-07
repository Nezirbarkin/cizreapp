-- =============================================================================
-- 101 Okey — ARKADAŞ DAVETİ ve DAVET BİLDİRİMİ
-- -----------------------------------------------------------------------------
-- Kullanıcı isteği (2026-09-05): "arkadaşını davet etme özelliği koy ve davet
-- eden kişiye bildirim gitmeli."
--
-- Bildirim İKİ YÖNE de akar — istek iki türlü okunabildiği için ikisi de
-- kuruldu ve ikisi de tek başına anlamlı:
--
--   * DAVET EDİLENE  → 'okey_invite'          (masaya çağrı)
--   * DAVET EDENE    → 'okey_invite_accepted' / 'okey_invite_declined'
--                       (arkadaşı masaya oturduğunda / oturmadığında)
--
-- Bildirimler public.notifications'a YAZILARAK gönderilir; oradaki
-- notifications_outbox_trigger her satırı push kuyruğuna alır (bkz.
-- 20260817000002 ve process-notification-outbox). Yani ayrı bir push yolu
-- açmaya gerek yoktur — tabloya yazmak cihaz bildirimini de doğurur.
-- push_delivery_policy.ts'teki tür→tercih haritasında bu türler yoktur;
-- haritada olmayan tür push'a AÇIK kabul edilir (varsayılan davranış).
--
-- -----------------------------------------------------------------------------
-- KİMİ DAVET EDEBİLİRİM: yalnızca TAKİP ETTİĞİM kişileri.
--
-- Bu, özelliğin spam kapısına dönüşmemesinin tek koruması: davet, bildirim
-- (ve push) üretiyor; herkesin herkese davet atabildiği bir uçta bu doğrudan
-- taciz aracı olurdu. "Arkadaş" bu kod tabanında zaten KARŞILIKLI TAKİP
-- demek (bkz. okey_profile_card.friends_count) — karşılıklı takip, tek yönlü
-- takibi zaten içerdiği için kontrolün kendisi "davet eden, davet edileni
-- takip ediyor mu" sorusuna indirgenir. Liste yine de arkadaşları (karşılıklı)
-- başa alır ve is_friend bayrağıyla ayırt eder.
--
-- MİSAFİR (anonim) kullanıcılar davet EDİLEMEZ: kalıcı hesapları,
-- dolayısıyla push cihaz kaydı ve takip ilişkisi yoktur.
--
-- -----------------------------------------------------------------------------
-- KABUL, MASAYA OTURMAKTIR — ayrı bir "onayladım" adımı değil.
--
-- okey_accept_room_invite, join_okey_room'u ÇAĞIRIR ve ancak oturma
-- başarılıysa daveti 'accepted' yapıp davet edeni haberdar eder. Sıra tersine
-- olsaydı (önce kabul, sonra istemci oturmayı dener) masa dolduğunda ya da
-- puan yetmediğinde davet eden "kabul etti" bildirimi alır, arkadaşı ise
-- masada olmazdı. Tek işlemde yapılması bu ikiliği baştan siler.
--
-- join_okey_room SECURITY DEFINER olmasına rağmen auth.uid()'i doğru okur:
-- auth.uid() JWT talebini GUC'ten okur, çalışan rolden değil.
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '5s';

-- -----------------------------------------------------------------------------
-- 1) TABLO
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.okey_room_invites (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id      uuid NOT NULL REFERENCES public.okey_rooms(id) ON DELETE CASCADE,
  inviter_id   uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  invitee_id   uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  status       text NOT NULL DEFAULT 'pending'
               CHECK (status IN ('pending', 'accepted', 'declined')),
  created_at   timestamptz NOT NULL DEFAULT NOW(),
  responded_at timestamptz,
  CONSTRAINT okey_room_invites_not_self CHECK (inviter_id <> invitee_id)
);

COMMENT ON TABLE public.okey_room_invites IS
  'Bir masaya yapilan arkadas davetleri. Yazma YALNIZCA okey_invite_to_room / okey_accept_room_invite / okey_decline_room_invite RPC leri uzerinden olur; tabloda yazma politikasi bilerek yoktur.';

-- Aynı masaya aynı kişiye TEK satır: reddedilen davet yeniden gönderilince
-- ikinci bir satır değil, aynı satır tazelenir (bkz. okey_invite_to_room).
CREATE UNIQUE INDEX IF NOT EXISTS okey_room_invites_room_invitee_key
  ON public.okey_room_invites (room_id, invitee_id);
CREATE INDEX IF NOT EXISTS okey_room_invites_invitee_idx
  ON public.okey_room_invites (invitee_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS okey_room_invites_inviter_idx
  ON public.okey_room_invites (inviter_id, created_at DESC);

ALTER TABLE public.okey_room_invites ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS okey_room_invites_select ON public.okey_room_invites;
CREATE POLICY okey_room_invites_select ON public.okey_room_invites
  FOR SELECT TO authenticated
  USING (
    inviter_id = (SELECT auth.uid())
    OR invitee_id = (SELECT auth.uid())
  );

-- INSERT/UPDATE/DELETE politikası YOK: davet üretmek, kabul etmek ve
-- reddetmek doğrulama gerektirir (takip ilişkisi, masa durumu, boş koltuk,
-- hız sınırı) ve bunların hepsi RPC'lerin içindedir.
GRANT SELECT ON public.okey_room_invites TO authenticated;

-- -----------------------------------------------------------------------------
-- 1b) ÖNKOŞUL DÜZELTMESİ: dedup_notification() SABİT search_path ister
-- -----------------------------------------------------------------------------
-- Bu göçün BULDUĞU, önceden var olan bir kırık: notifications tablosundaki
-- BEFORE INSERT trigger'ı `dedup_notification()` ne search_path'ini
-- sabitliyor ne de tabloyu şemasıyla yazıyordu. Trigger fonksiyonu ÇAĞIRANIN
-- search_path'iyle çalıştığı için, `SET search_path = ''` olan herhangi bir
-- fonksiyondan notifications'a INSERT etmek şu hatayla düşüyordu:
--
--   42P01: relation "notifications" does not exist
--   CONTEXT: PL/pgSQL function dedup_notification() line 8
--
-- Yani bildirim yazan HER güvenli (search_path'i kilitli) fonksiyon bu
-- duvara çarpar; aşağıdaki davet RPC'leri de çarpıyordu. Düzeltme iki
-- kuşaklı: search_path artık sabit VE tablo tam adıyla yazılıyor.
--
-- Gövde bunun dışında bir önceki sürümden birebir taşındı.
CREATE OR REPLACE FUNCTION public.dedup_notification()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  -- Aynı kullanıcı + entity + tip için varolan bildirimi sil. Okunmuş
  -- olsa bile: tekil kısıt (idx_notifications_user_entity_type) yüzünden
  -- eski satır dururken INSERT 23505 veriyor ve eylem geri alınıyordu.
  -- Sil-yenile: tekrar eden eylem bildirimi taze/okunmamış yeniler.
  IF NEW.entity_id IS NOT NULL THEN
    DELETE FROM public.notifications
    WHERE user_id = NEW.user_id
      AND entity_id = NEW.entity_id
      AND type = NEW.type
      AND id != NEW.id;
  END IF;

  RETURN NEW;
END;
$$;

-- -----------------------------------------------------------------------------
-- 2) DAVET EDİLEBİLİR ARKADAŞ LİSTESİ
-- -----------------------------------------------------------------------------
-- Neden SECURITY DEFINER: liste, davet edilecek kişinin okey cüzdanını
-- (puan) ve masadaki koltuk durumunu okur; ikisi de istemcinin RLS altında
-- göremeyeceği satırlardır. Dışarı yalnızca ad/avatar/puan gibi profil
-- kartında zaten görünen alanlar çıkar.
DROP FUNCTION IF EXISTS public.okey_invitable_friends(uuid, text, int);
CREATE FUNCTION public.okey_invitable_friends(
  p_room_id uuid,
  p_search  text DEFAULT NULL,
  p_limit   int  DEFAULT 50
)
RETURNS TABLE (
  user_id      uuid,
  display_name text,
  avatar_url   text,
  points       int,
  is_friend    boolean,
  in_room      boolean,
  invited      boolean
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid CONSTANT uuid := (SELECT auth.uid());
  v_q   text := NULLIF(btrim(COALESCE(p_search, '')), '');
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501';
  END IF;
  -- Masaya oturmayan biri o masaya davet edemez; listesini de görmemeli.
  IF NOT public.is_seated_in_okey_room(p_room_id) THEN
    RAISE EXCEPTION 'APP:not_in_room' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    p.id,
    COALESCE(NULLIF(p.full_name, ''), p.username, 'Oyuncu'),
    p.avatar_url,
    COALESCE(w.points, 0)::int,
    -- Karşılıklı takip mi (gerçek "arkadaş") — liste bunları başa alır.
    EXISTS (
      SELECT 1 FROM public.follows AS b
      WHERE b.follower_id = p.id AND b.following_id = v_uid
    ),
    -- Zaten bu masada oturuyor: davet düğmesi kapanır.
    EXISTS (
      SELECT 1 FROM public.okey_room_players AS rp
      WHERE rp.room_id = p_room_id AND rp.user_id = p.id
    ),
    -- Bu masa için bekleyen daveti var: düğme "Davet edildi"ye döner.
    EXISTS (
      SELECT 1 FROM public.okey_room_invites AS i
      WHERE i.room_id = p_room_id
        AND i.invitee_id = p.id
        AND i.status = 'pending'
    )
  FROM public.follows AS f
  JOIN public.profiles AS p ON p.id = f.following_id
  JOIN auth.users AS u ON u.id = p.id
  LEFT JOIN public.okey_wallets AS w ON w.user_id = p.id
  WHERE f.follower_id = v_uid
    -- Misafir hesap davet edilemez (kalıcı hesabı ve cihaz kaydı yok).
    AND COALESCE(u.is_anonymous, false) = false
    AND u.deleted_at IS NULL
    AND p.status <> 'deleted'::public.user_status
    AND (
      v_q IS NULL
      OR COALESCE(p.full_name, '') ILIKE '%' || v_q || '%'
      OR COALESCE(p.username, '') ILIKE '%' || v_q || '%'
    )
  ORDER BY
    EXISTS (
      SELECT 1 FROM public.follows AS b
      WHERE b.follower_id = p.id AND b.following_id = v_uid
    ) DESC,
    COALESCE(NULLIF(p.full_name, ''), p.username, 'Oyuncu') ASC
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 50), 1), 100);
END;
$$;
REVOKE ALL ON FUNCTION public.okey_invitable_friends(uuid, text, int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_invitable_friends(uuid, text, int) TO authenticated;

COMMENT ON FUNCTION public.okey_invitable_friends(uuid, text, int) IS
  'Bekleme odasindaki oyuncunun davet edebilecegi kisiler: TAKIP ETTIKLERI. Karsilikli takip edenler (arkadaslar) basta doner. Misafir/silinmis hesaplar listelenmez.';

-- -----------------------------------------------------------------------------
-- 3) DAVET GÖNDER
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.okey_invite_to_room(uuid, uuid);
CREATE FUNCTION public.okey_invite_to_room(
  p_room_id    uuid,
  p_invitee_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid CONSTANT uuid := (SELECT auth.uid());
  v_room         public.okey_rooms%ROWTYPE;
  v_invite_id    uuid;
  v_inviter_name text;
  v_inviter_av   text;
  v_free_seats   int;
  v_recent       int;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501';
  END IF;
  IF p_invitee_id IS NULL OR p_invitee_id = v_uid THEN
    RAISE EXCEPTION 'APP:invalid_invitee' USING ERRCODE = '22023';
  END IF;
  IF public.okey_is_banned(v_uid) THEN
    RAISE EXCEPTION 'APP:okey_banned' USING ERRCODE = '42501';
  END IF;
  IF NOT public.is_seated_in_okey_room(p_room_id) THEN
    RAISE EXCEPTION 'APP:not_in_room' USING ERRCODE = '42501';
  END IF;

  SELECT r.* INTO v_room FROM public.okey_rooms AS r WHERE r.id = p_room_id;
  IF v_room.id IS NULL THEN
    RAISE EXCEPTION 'APP:not_found' USING ERRCODE = 'P0001';
  END IF;
  IF v_room.status <> 'waiting' THEN
    RAISE EXCEPTION 'APP:room_not_joinable' USING ERRCODE = 'P0001';
  END IF;

  -- Boş koltuk YOKSA davet anlamsızdır: davet edilen geldiğinde oturacağı
  -- yer olmaz ve bildirim boşa gitmiş olur.
  SELECT count(*)::int INTO v_free_seats
  FROM public.okey_room_players AS rp
  WHERE rp.room_id = p_room_id AND rp.user_id IS NULL AND NOT rp.is_bot;
  IF v_free_seats = 0 THEN
    RAISE EXCEPTION 'APP:room_full' USING ERRCODE = 'P0001';
  END IF;

  -- Yalnızca TAKİP EDİLEN kişi davet edilebilir (spam koruması; başlıktaki
  -- gerekçeye bakınız).
  IF NOT EXISTS (
    SELECT 1 FROM public.follows AS f
    WHERE f.follower_id = v_uid AND f.following_id = p_invitee_id
  ) THEN
    RAISE EXCEPTION 'APP:not_following' USING ERRCODE = '42501';
  END IF;

  IF EXISTS (
    SELECT 1 FROM auth.users AS u
    WHERE u.id = p_invitee_id
      AND (COALESCE(u.is_anonymous, false) OR u.deleted_at IS NOT NULL)
  ) THEN
    RAISE EXCEPTION 'APP:invitee_not_invitable' USING ERRCODE = 'P0001';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.okey_room_players AS rp
    WHERE rp.room_id = p_room_id AND rp.user_id = p_invitee_id
  ) THEN
    RAISE EXCEPTION 'APP:already_seated' USING ERRCODE = 'P0001';
  END IF;

  -- Aynı kişiye ard arda davet = ard arda push. Bir dakikalık sessizlik
  -- penceresi, düğmeye iki kez basmayı da kötüye kullanmayı da keser.
  IF EXISTS (
    SELECT 1 FROM public.okey_room_invites AS i
    WHERE i.room_id = p_room_id
      AND i.invitee_id = p_invitee_id
      AND i.status = 'pending'
      AND i.created_at > NOW() - INTERVAL '1 minute'
  ) THEN
    RAISE EXCEPTION 'APP:invite_already_sent' USING ERRCODE = 'P0001';
  END IF;

  -- Saatlik üst sınır: tek bir hesap, takip ettiği herkese sürekli davet
  -- yağdıramasın.
  SELECT count(*)::int INTO v_recent
  FROM public.okey_room_invites AS i
  WHERE i.inviter_id = v_uid AND i.created_at > NOW() - INTERVAL '1 hour';
  IF v_recent >= 40 THEN
    RAISE EXCEPTION 'APP:invite_rate_limited' USING ERRCODE = 'P0001';
  END IF;

  SELECT COALESCE(NULLIF(p.full_name, ''), p.username, 'Bir oyuncu'), p.avatar_url
    INTO v_inviter_name, v_inviter_av
  FROM public.profiles AS p WHERE p.id = v_uid;
  v_inviter_name := COALESCE(v_inviter_name, 'Bir oyuncu');

  INSERT INTO public.okey_room_invites (room_id, inviter_id, invitee_id, status)
  VALUES (p_room_id, v_uid, p_invitee_id, 'pending')
  ON CONFLICT (room_id, invitee_id) DO UPDATE
    SET inviter_id   = EXCLUDED.inviter_id,
        status       = 'pending',
        created_at   = NOW(),
        responded_at = NULL
  RETURNING id INTO v_invite_id;

  -- BİLDİRİM (davet edilene). notifications'a yazmak push'u da doğurur.
  -- entity_id = oda kimliği: aynı masaya ikinci bir davet, dedup_notification
  -- sayesinde eskisinin yerine geçer (iki kart birikmez).
  INSERT INTO public.notifications (
    user_id, type, title, content,
    actor_id, actor_name, actor_avatar,
    entity_id, entity_type, metadata
  ) VALUES (
    p_invitee_id,
    'okey_invite',
    '101 Okey daveti',
    v_inviter_name || ' seni 101 Okey masasına davet etti.',
    v_uid, v_inviter_name, v_inviter_av,
    p_room_id::text, 'okey_room',
    jsonb_build_object(
      'room_id',     p_room_id::text,
      'invite_id',   v_invite_id::text,
      'join_code',   v_room.join_code,
      'table_stake', v_room.table_stake,
      'total_hands', v_room.total_hands,
      'game_mode',   v_room.game_mode,
      'team_mode',   v_room.team_mode
    )
  );

  RETURN v_invite_id;
END;
$$;
REVOKE ALL ON FUNCTION public.okey_invite_to_room(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_invite_to_room(uuid, uuid) TO authenticated;

COMMENT ON FUNCTION public.okey_invite_to_room(uuid, uuid) IS
  'Bekleme odasindaki oyuncu, TAKIP ETTIGI bir kullaniciyi masaya davet eder. Davet edilene okey_invite bildirimi (ve push) gider.';

-- -----------------------------------------------------------------------------
-- 4) BANA GELEN AÇIK DAVETLER
-- -----------------------------------------------------------------------------
-- Yalnızca HÂLÂ GEÇERLİ davetler döner: masa hâlâ bekliyor, boş koltuk var
-- ve davet bayatlamamış. Süresi geçmiş daveti listede tutmak, dokununca
-- "masa başladı" hatası veren ölü bir kart demek olurdu.
DROP FUNCTION IF EXISTS public.okey_my_room_invites();
CREATE FUNCTION public.okey_my_room_invites()
RETURNS TABLE (
  invite_id      uuid,
  room_id        uuid,
  inviter_id     uuid,
  inviter_name   text,
  inviter_avatar text,
  table_stake    int,
  total_hands    int,
  game_mode      text,
  team_mode      text,
  assist_mode    text,
  seated_count   int,
  created_at     timestamptz
)
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

  RETURN QUERY
  SELECT
    i.id,
    r.id,
    i.inviter_id,
    COALESCE(NULLIF(p.full_name, ''), p.username, 'Bir oyuncu'),
    p.avatar_url,
    r.table_stake::int,
    r.total_hands::int,
    r.game_mode,
    r.team_mode,
    r.assist_mode,
    (SELECT count(*)::int FROM public.okey_room_players AS rp
      WHERE rp.room_id = r.id AND (rp.user_id IS NOT NULL OR rp.is_bot)),
    i.created_at
  FROM public.okey_room_invites AS i
  JOIN public.okey_rooms AS r ON r.id = i.room_id
  LEFT JOIN public.profiles AS p ON p.id = i.inviter_id
  WHERE i.invitee_id = v_uid
    AND i.status = 'pending'
    AND i.created_at > NOW() - INTERVAL '2 hours'
    AND r.status = 'waiting'
    AND EXISTS (
      SELECT 1 FROM public.okey_room_players AS rp
      WHERE rp.room_id = r.id AND rp.user_id IS NULL AND NOT rp.is_bot
    )
  ORDER BY i.created_at DESC
  LIMIT 20;
END;
$$;
REVOKE ALL ON FUNCTION public.okey_my_room_invites() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_my_room_invites() TO authenticated;

COMMENT ON FUNCTION public.okey_my_room_invites() IS
  'Bana gelen ve HALA GECERLI masa davetleri (masa bekliyor, bos koltuk var, davet 2 saatten yeni).';

-- -----------------------------------------------------------------------------
-- 5) DAVETİ KABUL ET = MASAYA OTUR
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.okey_accept_room_invite(uuid);
CREATE FUNCTION public.okey_accept_room_invite(p_invite_id uuid)
RETURNS TABLE (r_room_id uuid, r_seat_no smallint)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid CONSTANT uuid := (SELECT auth.uid());
  v_invite public.okey_room_invites%ROWTYPE;
  v_seat   smallint;
  v_name   text;
  v_avatar text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501';
  END IF;

  SELECT i.* INTO v_invite
  FROM public.okey_room_invites AS i
  WHERE i.id = p_invite_id
  FOR UPDATE;

  IF v_invite.id IS NULL OR v_invite.invitee_id <> v_uid THEN
    RAISE EXCEPTION 'APP:invite_not_found' USING ERRCODE = 'P0001';
  END IF;
  IF v_invite.status <> 'pending' THEN
    RAISE EXCEPTION 'APP:invite_already_answered' USING ERRCODE = 'P0001';
  END IF;

  -- ÖNCE OTUR. join_okey_room masa durumunu, boş koltuğu, puan yeterliliğini
  -- ve yasaklıyı kendi kontrol eder; başarısız olursa buradan da hata çıkar
  -- ve davet 'pending' kalır — davet eden yanlışlıkla "kabul etti"
  -- bildirimi ALMAZ.
  SELECT j.r_seat_no INTO v_seat
  FROM public.join_okey_room(p_room_id => v_invite.room_id) AS j;

  UPDATE public.okey_room_invites
  SET status = 'accepted', responded_at = NOW()
  WHERE id = v_invite.id;

  SELECT COALESCE(NULLIF(p.full_name, ''), p.username, 'Arkadaşın'), p.avatar_url
    INTO v_name, v_avatar
  FROM public.profiles AS p WHERE p.id = v_uid;
  v_name := COALESCE(v_name, 'Arkadaşın');

  -- BİLDİRİM (davet EDENE) — istenen "davet eden kişiye bildirim gitmeli"
  -- maddesi tam olarak budur.
  --
  -- entity_id = DAVET kimliği, oda kimliği değil: dedup_notification aynı
  -- (user_id, entity_id, type) üçlüsünü siler; oda kimliği kullanılsaydı
  -- ikinci arkadaşın kabulü, birincinin bildirimini yok ederdi. Yönlendirme
  -- için gereken oda kimliği metadata'da taşınır.
  INSERT INTO public.notifications (
    user_id, type, title, content,
    actor_id, actor_name, actor_avatar,
    entity_id, entity_type, metadata
  ) VALUES (
    v_invite.inviter_id,
    'okey_invite_accepted',
    'Davetin kabul edildi',
    v_name || ' davetini kabul etti ve masaya oturdu.',
    v_uid, v_name, v_avatar,
    v_invite.id::text, 'okey_room_invite',
    jsonb_build_object(
      'room_id',   v_invite.room_id::text,
      'invite_id', v_invite.id::text,
      'seat_no',   v_seat
    )
  );

  RETURN QUERY SELECT v_invite.room_id, v_seat;
END;
$$;
REVOKE ALL ON FUNCTION public.okey_accept_room_invite(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_accept_room_invite(uuid) TO authenticated;

COMMENT ON FUNCTION public.okey_accept_room_invite(uuid) IS
  'Daveti kabul eder: join_okey_room ile masaya OTURUR, sonra daveti accepted yapar ve davet edene okey_invite_accepted bildirimi gonderir. Oturma basarisizsa davet pending kalir.';

-- -----------------------------------------------------------------------------
-- 6) DAVETİ REDDET
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.okey_decline_room_invite(uuid);
CREATE FUNCTION public.okey_decline_room_invite(p_invite_id uuid)
RETURNS void
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid CONSTANT uuid := (SELECT auth.uid());
  v_invite public.okey_room_invites%ROWTYPE;
  v_name   text;
  v_avatar text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501';
  END IF;

  SELECT i.* INTO v_invite
  FROM public.okey_room_invites AS i
  WHERE i.id = p_invite_id
  FOR UPDATE;

  IF v_invite.id IS NULL OR v_invite.invitee_id <> v_uid THEN
    RAISE EXCEPTION 'APP:invite_not_found' USING ERRCODE = 'P0001';
  END IF;
  IF v_invite.status <> 'pending' THEN
    RETURN;  -- Zaten yanıtlanmış; ikinci ret sessizce yutulur.
  END IF;

  UPDATE public.okey_room_invites
  SET status = 'declined', responded_at = NOW()
  WHERE id = v_invite.id;

  SELECT COALESCE(NULLIF(p.full_name, ''), p.username, 'Arkadaşın'), p.avatar_url
    INTO v_name, v_avatar
  FROM public.profiles AS p WHERE p.id = v_uid;
  v_name := COALESCE(v_name, 'Arkadaşın');

  INSERT INTO public.notifications (
    user_id, type, title, content,
    actor_id, actor_name, actor_avatar,
    entity_id, entity_type, metadata
  ) VALUES (
    v_invite.inviter_id,
    'okey_invite_declined',
    'Davet reddedildi',
    v_name || ' şu an masaya katılamıyor.',
    v_uid, v_name, v_avatar,
    v_invite.id::text, 'okey_room_invite',
    jsonb_build_object(
      'room_id',   v_invite.room_id::text,
      'invite_id', v_invite.id::text
    )
  );
END;
$$;
REVOKE ALL ON FUNCTION public.okey_decline_room_invite(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_decline_room_invite(uuid) TO authenticated;

COMMENT ON FUNCTION public.okey_decline_room_invite(uuid) IS
  'Daveti reddeder ve davet edene okey_invite_declined bildirimi gonderir.';

NOTIFY pgrst, 'reload schema';

-- =============================================================================
-- 101 Okey — BOT HESAPLARI MASAYA GELİYOR + MASA AÇILINCA KENDİLİĞİNDEN DOLUYOR
-- -----------------------------------------------------------------------------
-- Kullanıcı isteği (2026-09-08):
--   "bot hesapları okey 101 oyuna dahil et. oyuncu masa açtığında botlar
--    otomatik 1 dakika içerisinde masaya otursunlar. (mevcut botlar var
--    profilli vs)"
--
-- İki ayrı eksik vardı:
--
-- 1) İKİ AYRI BOT DÜNYASI. Uygulamanın sosyal tarafında adı, fotoğrafı,
--    biyografisi olan gerçek `profiles` satırları (is_bot = true) var
--    (bkz. 20260908130001). Okey masasındaki botlar ise bambaşka bir
--    havuzdan, `okey_bot_profiles`'tan besleniyordu: admin aynı kimlikleri
--    bir kez daha, elle girmek zorundaydı. Girmediyse masadaki botun adı
--    "Bot 3", fotoğrafı da yoktu.
--
--    Artık `okey_bot_profiles` satırı bir bot hesabına BAĞLANABİLİYOR
--    (`bot_account_id`) ve havuz o hesaplardan kendiliğinden besleniyor.
--    Elle girilmiş eski profiller olduğu gibi kalır — bağlantısı olmayan
--    satırlara dokunulmaz.
--
--    NEDEN AYNA, NEDEN BOT DOĞRUDAN KOLTUĞA OTURTULMADI: bot hesaplarının
--    `auth.users` satırı var, yani teknik olarak `okey_room_players.user_id`
--    alanına yazılabilirlerdi. Ama o zaman her bot için okey cüzdanı, masa
--    puanı ödemesi, kazanç dağıtımı, sıralama tablosu ve ban denetimi
--    gerekirdi — botlar ekonomiye gerçek oyuncu gibi girerdi. Koltuk yine
--    `is_bot = true` kalıyor (ekonomi dışı), yalnız KİMLİĞİ gerçek bir
--    profilden geliyor.
--
-- 2) MASA BOŞ BEKLİYORDU. Bot son tarihi (`auto_fill_bots_at`) yalnız
--    otomatik eşleştirmeyle kurulan masalara yazılıyordu; "MASA AÇ" ile
--    kurulan masa, sahibi "botlarla doldur"a basana kadar boş kalıyordu.
--    Artık AÇIK (gizli olmayan) her masaya bir süre yazılıyor ve botlar o
--    sürenin içinde TEK TEK oturuyor.
--
--    NEDEN GİZLİ MASALAR HARİÇ: gizli masa, davet koduyla arkadaş çağırmak
--    için var (bkz. okey_invite_service). Bir dakika sonra botlarla dolarsa
--    davet edilen arkadaş masayı oynanır bulmaz — davet özelliği kendi
--    kendini iptal ederdi. Gizli masada botlar yine "botlarla doldur" ile
--    çağrılabilir.
--
--    NEDEN HEPSİ BİRDEN DEĞİL, TEK TEK: süre dolunca üç koltuğu birden
--    doldurmak "üç kişi aynı anda geldi" demek olurdu; masaya bakan oyuncu
--    bunun bir otomasyon olduğunu anında anlardı. Botlar pencereyi eşit
--    bölen anlarda (60 sn için ~15/30/45. saniyeler) birer birer oturur;
--    arada gerçek bir oyuncu gelirse onun koltuğu bota gitmez, çünkü hedef
--    DOLU KOLTUK SAYISIDIR, bot sayısı değil.
--
--    NEDEN "HAZIRIM" ZORLANMIYOR: eli başlatmak masa puanını cüzdandan
--    düşürür. `okey_fill_with_bots` çağıranı otomatik hazır sayıyor (oraya
--    basmak zaten "başlayalım" demek), ama bir YOKLAMA aynı şey değil:
--    oyuncunun ekranı açık diye onun adına oyunu başlatmak, sormadan çip
--    harcamak olurdu. Botlar oturur, el oyuncu HAZIRIM'a basınca başlar.
--
-- ZAMANLAMA: projede zamanlanmış iş (pg_cron) yok; tetik istemciden gelir,
-- karar sunucunundur (bkz. 20260907000004 ve okey_auto_advance). Saatini
-- ileri alan bir cihaz masayı erken dolduramaz.
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '10s';

-- -----------------------------------------------------------------------------
-- 1) AYAR: masa açıldıktan kaç saniye içinde botlar otursun
-- -----------------------------------------------------------------------------
ALTER TABLE public.okey_settings
  ADD COLUMN IF NOT EXISTS bot_autoseat_seconds int NOT NULL DEFAULT 60;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'okey_settings_bot_autoseat_seconds_check'
  ) THEN
    ALTER TABLE public.okey_settings
      ADD CONSTRAINT okey_settings_bot_autoseat_seconds_check
      CHECK (bot_autoseat_seconds >= 0 AND bot_autoseat_seconds <= 3600);
  END IF;
END $$;

COMMENT ON COLUMN public.okey_settings.bot_autoseat_seconds IS
  'Elle kurulan AÇIK masada boş koltukların botlarla dolması için tanınan süre (saniye). Botlar bu pencerede tek tek oturur. 0 = otomatik oturma kapalı.';

-- -----------------------------------------------------------------------------
-- 2) BOT KİMLİĞİ ARTIK BİR BOT HESABINA BAĞLANABİLİR
-- -----------------------------------------------------------------------------
ALTER TABLE public.okey_bot_profiles
  ADD COLUMN IF NOT EXISTS bot_account_id uuid
  REFERENCES public.profiles(id) ON DELETE CASCADE;

COMMENT ON COLUMN public.okey_bot_profiles.bot_account_id IS
  'Bu okey kimliğinin beslendiği bot hesabı (profiles.is_bot = true). NULL ise admin panelinden elle girilmiş bağımsız bir kimliktir.';

-- Bir bot hesabı masada iki ayrı kimlik olarak görünemez.
CREATE UNIQUE INDEX IF NOT EXISTS uq_okey_bot_profiles_bot_account
  ON public.okey_bot_profiles (bot_account_id)
  WHERE bot_account_id IS NOT NULL;

-- -----------------------------------------------------------------------------
-- 3) BOT HESAPLARINI OKEY KİMLİK HAVUZUNA AYNALA
--
-- Tembel çalışır: koltuğa bot oturtulacağı anda çağrılır. Ayrı bir
-- zamanlanmış iş ya da trigger kurulmadı çünkü havuz yalnızca bot otururken
-- okunuyor — arada güncel olup olmaması kimseyi ilgilendirmiyor.
--
-- Hiçbir şey değişmediyse HİÇBİR SATIR YAZILMAZ (IS DISTINCT FROM): fonksiyon
-- her el başında çağrılabilir olsun diye.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.okey_internal_sync_bot_account_profiles()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_bot record;
  v_name text;
  v_candidate text;
  v_suffix int;
BEGIN
  -- 3a) BAĞLI KİMLİKLERİ TAZELE — fotoğraf hesabından okunur. Admin bir botun
  --     fotoğrafını değiştirdiğinde masadaki kimlik de değişsin diye.
  --
  -- ETKİNLİK YALNIZ KAPATILIR, AÇILMAZ (`bp.is_active AND ...`). Okey admin
  -- panelinde kimlik başına bir "aktif" anahtarı var; koşulsuz atansaydı bu
  -- senkron her bot oturuşunda onu geri açar, yani admin bir botu masadan
  -- çıkaramazdı. Şimdi iki kapı da kapatabiliyor: okey kimliğinin anahtarı
  -- ya da bot hesabının kendisi (bot_accounts.is_active).
  --
  -- Bunun bilinen tek yan etkisi: okey panelinden SİLİNEN bağlı bir kimlik,
  -- bir sonraki bot oturuşunda yeniden aynalanır. Bir botu masadan kalıcı
  -- olarak çıkarmanın yolu silmek değil, "aktif" anahtarını kapatmaktır.
  UPDATE public.okey_bot_profiles AS bp
  SET avatar_url = NULLIF(btrim(COALESCE(p.avatar_url, '')), ''),
      is_active = bp.is_active AND COALESCE(ba.is_active, true) AND p.is_bot
  FROM public.profiles AS p
  LEFT JOIN public.bot_accounts AS ba ON ba.id = p.id
  WHERE bp.bot_account_id = p.id
    AND (
      bp.avatar_url IS DISTINCT FROM NULLIF(btrim(COALESCE(p.avatar_url, '')), '')
      OR (bp.is_active AND NOT (COALESCE(ba.is_active, true) AND p.is_bot))
    );

  -- 3a-2) AD DA TAZELENİR — AMA YALNIZCA ÇAKIŞMIYORSA.
  --
  -- Ad benzersiz (uq_okey_bot_profiles_name) ve 2-24 karakter olmak zorunda.
  -- Koşulsuz güncellenseydi, iki botun adı aynı olduğu gün bu fonksiyon
  -- benzersizlik ihlaliyle patlar ve BOT OTURTMA akışını komple durdururdu.
  -- Çakışan ad, kimliğin kuruluşunda verilen (numaralandırılmış) adıyla
  -- kalır.
  UPDATE public.okey_bot_profiles AS bp
  SET display_name = left(btrim(COALESCE(p.full_name, p.username)), 24)
  FROM public.profiles AS p
  WHERE bp.bot_account_id = p.id
    AND COALESCE(p.full_name, p.username) IS NOT NULL
    AND length(btrim(left(btrim(COALESCE(p.full_name, p.username)), 24))) BETWEEN 2 AND 24
    AND bp.display_name IS DISTINCT FROM left(btrim(COALESCE(p.full_name, p.username)), 24)
    AND NOT EXISTS (
      SELECT 1 FROM public.okey_bot_profiles AS other
      WHERE other.id <> bp.id
        AND lower(btrim(other.display_name))
            = lower(btrim(left(btrim(COALESCE(p.full_name, p.username)), 24)))
    );

  -- 3b) HENÜZ KİMLİĞİ OLMAYAN BOT HESAPLARI için satır aç.
  FOR v_bot IN
    SELECT p.id,
           NULLIF(btrim(COALESCE(p.full_name, '')), '') AS full_name,
           NULLIF(btrim(COALESCE(p.username, '')), '') AS username,
           NULLIF(btrim(COALESCE(p.avatar_url, '')), '') AS avatar_url
    FROM public.profiles AS p
    LEFT JOIN public.bot_accounts AS ba ON ba.id = p.id
    WHERE p.is_bot
      AND COALESCE(ba.is_active, true)
      AND NOT EXISTS (
        SELECT 1 FROM public.okey_bot_profiles AS bp WHERE bp.bot_account_id = p.id
      )
  LOOP
    -- Ad kısıtı: 2-24 karakter ve benzersiz (uq_okey_bot_profiles_name).
    -- Ad soyad yoksa kullanıcı adına düşülür; ikisi de yoksa bu hesap okey
    -- havuzuna girmez (adsız bir oyuncu masada "Bot" kadar ele verici olurdu).
    v_name := left(COALESCE(v_bot.full_name, v_bot.username, ''), 24);
    CONTINUE WHEN length(btrim(v_name)) < 2;

    -- Aynı ad başka bir kimlikte kullanılıyorsa numaralandır. Sessizce
    -- atlansaydı, ad benzerliği yüzünden bazı botlar masaya hiç çıkamazdı.
    v_candidate := v_name;
    v_suffix := 1;
    WHILE EXISTS (
      SELECT 1 FROM public.okey_bot_profiles AS bp
      WHERE lower(btrim(bp.display_name)) = lower(btrim(v_candidate))
    ) AND v_suffix <= 20 LOOP
      v_suffix := v_suffix + 1;
      v_candidate := left(v_name, 21) || ' ' || v_suffix::text;
    END LOOP;
    CONTINUE WHEN v_suffix > 20;

    INSERT INTO public.okey_bot_profiles
      (display_name, avatar_url, is_active, bot_account_id)
    VALUES (v_candidate, v_bot.avatar_url, true, v_bot.id)
    ON CONFLICT DO NOTHING;
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION public.okey_internal_sync_bot_account_profiles()
  FROM PUBLIC, anon, authenticated;

COMMENT ON FUNCTION public.okey_internal_sync_bot_account_profiles() IS
  'Aktif bot hesaplarını (profiles.is_bot) okey bot kimlik havuzuna aynalar. Elle girilmiş (bot_account_id IS NULL) kimliklere dokunmaz.';

-- -----------------------------------------------------------------------------
-- 4) KOLTUĞA KİMLİK ATAMA — önce havuzu tazele
--
-- Gövde 20260901000006'dan; tek fark baştaki senkron çağrısı.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.okey_internal_assign_bot_profiles(p_room_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_seat record;
  v_profile uuid;
BEGIN
  -- Havuz bot hesaplarından beslenir (kullanıcı isteği: "bot hesapları okey
  -- 101 oyuna dahil et"). Hata masayı kilitlemesin: kimliksiz bot, hiç
  -- oturmayan bottan iyidir — o zaman eski davranışla "Bot N" görünür.
  BEGIN
    PERFORM public.okey_internal_sync_bot_account_profiles();
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  FOR v_seat IN
    SELECT rp.seat_no FROM public.okey_room_players AS rp
    WHERE rp.room_id = p_room_id AND rp.is_bot AND rp.bot_profile_id IS NULL
    ORDER BY rp.seat_no
  LOOP
    SELECT bp.id INTO v_profile
    FROM public.okey_bot_profiles AS bp
    WHERE bp.is_active
      AND bp.id NOT IN (
        SELECT rp2.bot_profile_id FROM public.okey_room_players AS rp2
        WHERE rp2.room_id = p_room_id AND rp2.bot_profile_id IS NOT NULL
      )
    ORDER BY random()
    LIMIT 1;

    EXIT WHEN v_profile IS NULL; -- havuz tükendi, kalanlar profilsiz kalır

    UPDATE public.okey_room_players
    SET bot_profile_id = v_profile
    WHERE room_id = p_room_id AND seat_no = v_seat.seat_no;

    v_profile := NULL;
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION public.okey_internal_assign_bot_profiles(uuid)
  FROM PUBLIC, anon, authenticated;

-- -----------------------------------------------------------------------------
-- 5) TEK BİR BOTU OTURT
--
-- `okey_fill_with_bots`ten ayrı bir fonksiyon: o, boş koltukların HEPSİNİ
-- doldurur ve çağıranı hazır sayar (düğmeye basmak "başlayalım" demektir).
-- Otomatik oturmada ikisi de yanlış olurdu (bkz. dosya başlığı).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.okey_internal_seat_one_bot(p_room_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_seat smallint;
BEGIN
  -- En küçük numaralı boş koltuk: masa soldan sağa dolar, rastgele boşluk
  -- bırakmaz.
  SELECT rp.seat_no INTO v_seat
  FROM public.okey_room_players AS rp
  WHERE rp.room_id = p_room_id AND rp.user_id IS NULL AND NOT rp.is_bot
  ORDER BY rp.seat_no
  LIMIT 1;

  IF v_seat IS NULL THEN
    RETURN false;
  END IF;

  UPDATE public.okey_room_players
  SET is_bot = true, is_ready = true, joined_at = now()
  WHERE room_id = p_room_id AND seat_no = v_seat;

  PERFORM public.okey_internal_assign_bot_profiles(p_room_id);
  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.okey_internal_seat_one_bot(uuid)
  FROM PUBLIC, anon, authenticated;

-- -----------------------------------------------------------------------------
-- 6) MASA KURULURKEN SON TARİH YAZILIR
--
-- Gövde 20260905000001'den; tek fark sondaki UPDATE.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_okey_room(
  p_is_private boolean DEFAULT false,
  p_game_mode text DEFAULT 'katlamasiz',
  p_team_mode text DEFAULT 'essiz',
  p_assist_mode text DEFAULT 'yardimli',
  p_total_hands int DEFAULT 3,
  p_entry_fee int DEFAULT 100
)
RETURNS public.okey_rooms
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  v_uid CONSTANT uuid := (SELECT auth.uid());
  v_room public.okey_rooms%ROWTYPE;
  v_join_code text;
  v_settings public.okey_settings%ROWTYPE;
  v_wallet public.okey_wallets%ROWTYPE;
  v_room_fee int;
  v_entry int;
  v_min_entry int;
  v_needed bigint;
  v_seat smallint;
  v_autoseat int;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501';
  END IF;
  IF public.okey_is_banned(v_uid) THEN
    RAISE EXCEPTION 'APP:okey_banned' USING ERRCODE = '42501';
  END IF;
  IF p_game_mode NOT IN ('katlamasiz', 'katlamali') THEN
    RAISE EXCEPTION 'APP:invalid_game_mode' USING ERRCODE = '22023';
  END IF;
  IF p_team_mode NOT IN ('essiz', 'esli') THEN
    RAISE EXCEPTION 'APP:invalid_team_mode' USING ERRCODE = '22023';
  END IF;
  IF p_assist_mode NOT IN ('yardimli', 'yardimsiz') THEN
    RAISE EXCEPTION 'APP:invalid_assist_mode' USING ERRCODE = '22023';
  END IF;
  IF COALESCE(p_total_hands, 3) < 1 OR COALESCE(p_total_hands, 3) > 20 THEN
    RAISE EXCEPTION 'APP:invalid_total_hands' USING ERRCODE = '22023';
  END IF;

  SELECT s.* INTO v_settings FROM public.okey_settings AS s WHERE s.id = true;
  v_room_fee := COALESCE(v_settings.room_creation_fee, 0);
  v_min_entry := GREATEST(COALESCE(v_settings.min_entry_fee, 100), 1);

  -- MASA SADECE PUANLA AÇILIR: alt sınırın altı reddedilir
  v_entry := COALESCE(p_entry_fee, 0);
  IF v_entry < v_min_entry THEN
    RAISE EXCEPTION 'APP:entry_fee_too_low | en az: %', v_min_entry
      USING ERRCODE = '22023';
  END IF;

  -- Kurucu hem oda ücretini hem KENDİ MASA PUANINI karşılayabilmeli.
  v_needed := v_room_fee::bigint
            + v_entry::bigint * GREATEST(COALESCE(p_total_hands, 3), 1)::bigint;
  IF v_needed > 0 THEN
    v_wallet := public.okey_internal_ensure_wallet(v_uid);
    IF v_wallet.points < v_needed THEN
      RAISE EXCEPTION 'APP:insufficient_points | mevcut: %, gerekli: %',
        v_wallet.points, v_needed USING ERRCODE = 'P0001';
    END IF;
  END IF;

  IF p_is_private THEN
    v_join_code := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
  END IF;

  INSERT INTO public.okey_rooms (
    created_by, is_private, join_code, max_score, turn_seconds,
    game_mode, team_mode, assist_mode, entry_fee, total_hands
  ) VALUES (
    v_uid, p_is_private, v_join_code,
    COALESCE(v_settings.default_max_score, 101),
    COALESCE(v_settings.default_turn_seconds, 20),
    p_game_mode, p_team_mode, p_assist_mode,
    v_entry,
    COALESCE(p_total_hands, 3)
  ) RETURNING * INTO v_room;

  IF v_room_fee > 0 THEN
    PERFORM public.okey_internal_add_points(
      v_uid, -v_room_fee, 'room_fee', v_room.id::text
    );
    INSERT INTO public.okey_house_revenue (source, amount, room_id, user_id, ref)
    VALUES ('room_fee', v_room_fee, v_room.id, v_uid, v_room.id::text)
    ON CONFLICT DO NOTHING;
  END IF;

  FOR v_seat IN 0..3 LOOP
    INSERT INTO public.okey_room_players
      (room_id, seat_no, user_id, joined_at, is_ready)
    VALUES (
      v_room.id, v_seat,
      CASE WHEN v_seat = 0 THEN v_uid ELSE NULL END,
      CASE WHEN v_seat = 0 THEN now() ELSE NULL END,
      false
    );
  END LOOP;

  -- BOTLAR YOLDA (kullanıcı isteği, 2026-09-08). Gizli masa hariç: orası
  -- davet edilen arkadaşın yeri (bkz. dosya başlığı).
  v_autoseat := COALESCE(v_settings.bot_autoseat_seconds, 60);
  IF NOT p_is_private AND v_autoseat > 0 THEN
    UPDATE public.okey_rooms
    SET auto_fill_bots_at = now() + make_interval(secs => v_autoseat)
    WHERE id = v_room.id
    RETURNING * INTO v_room;
  END IF;

  RETURN v_room;
END;
$$;

REVOKE ALL ON FUNCTION public.create_okey_room(boolean, text, text, text, int, int)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_okey_room(boolean, text, text, text, int, int)
  TO authenticated;

-- -----------------------------------------------------------------------------
-- 7) KADEMELİ OTURMA
--
-- Her yoklamada çağrılır. Karar sunucunun: pencerede ne kadar yol alındıysa
-- masada o kadar DOLU koltuk olmalı.
--
--   ilerleme = (şimdi − kuruluş) / (son tarih − kuruluş)
--   hedef    = ceil(ilerleme × 4), en az 1
--
-- 60 saniyelik pencerede bu, ~15/30/45. saniyelerde birer bot demektir.
-- Hedef DOLU KOLTUK sayısı olduğu için, arada gerçek bir oyuncu oturursa o
-- turda bot gelmez — insan her zaman botun yerine geçer.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.okey_maybe_autofill_bots(p_room_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid CONSTANT uuid := (SELECT auth.uid());
  v_room public.okey_rooms%ROWTYPE;
  v_window double precision;
  v_progress double precision;
  v_target int;
  v_occupied int;
  v_all_ready boolean;
  v_seated boolean := false;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501';
  END IF;

  SELECT r.* INTO v_room FROM public.okey_rooms AS r
  WHERE r.id = p_room_id FOR UPDATE;
  IF v_room.id IS NULL OR v_room.status <> 'waiting' THEN
    RETURN false;
  END IF;
  IF v_room.auto_fill_bots_at IS NULL THEN
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

  -- PENCEREDE NEREDEYİZ. Son tarih geçmişse ilerleme 1'dir: kalan koltuklar
  -- bu çağrıda dolar.
  v_window := GREATEST(
    EXTRACT(EPOCH FROM (v_room.auto_fill_bots_at - v_room.created_at)),
    1
  );
  v_progress := LEAST(
    GREATEST(EXTRACT(EPOCH FROM (now() - v_room.created_at)) / v_window, 0),
    1
  );
  v_target := GREATEST(ceil(v_progress * 4)::int, 1);

  SELECT count(*)::int INTO v_occupied
  FROM public.okey_room_players AS rp
  WHERE rp.room_id = p_room_id AND (rp.user_id IS NOT NULL OR rp.is_bot);

  WHILE v_occupied < v_target LOOP
    EXIT WHEN NOT public.okey_internal_seat_one_bot(p_room_id);
    v_occupied := v_occupied + 1;
    v_seated := true;
  END LOOP;

  IF NOT v_seated THEN
    RETURN false;
  END IF;

  -- Masa dolduysa süre işini bitirmiştir.
  IF v_occupied >= 4 THEN
    UPDATE public.okey_rooms SET auto_fill_bots_at = NULL WHERE id = p_room_id;
  END IF;

  -- EL YALNIZ HERKES HAZIRSA BAŞLAR. Botlar her zaman hazırdır; insanın
  -- yerine "hazırım" demek, sormadan masa puanı harcamak olurdu.
  SELECT bool_and(rp.is_ready) FILTER (
    WHERE rp.user_id IS NOT NULL OR rp.is_bot
  ) INTO v_all_ready
  FROM public.okey_room_players AS rp
  WHERE rp.room_id = p_room_id;

  IF v_occupied >= 4 AND COALESCE(v_all_ready, false) THEN
    PERFORM public.start_okey_hand(p_room_id);
  END IF;

  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.okey_maybe_autofill_bots(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_maybe_autofill_bots(uuid) TO authenticated;

COMMENT ON FUNCTION public.okey_maybe_autofill_bots(uuid) IS
  'Masa açıldıktan sonraki pencerede boş koltuklara TEK TEK bot oturtur; süreyi ve sayıyı sunucu hesaplar. El, ancak tüm koltuklar dolu ve herkes hazırsa başlar.';

-- -----------------------------------------------------------------------------
-- 8) MEVCUT BOT HESAPLARINI HAVUZA AL (tek seferlik tohumlama)
--
-- Fonksiyon zaten her bot oturuşunda çalışıyor; bu çağrı yalnız migration
-- uygulanır uygulanmaz admin panelinde havuzun dolu görünmesi için.
-- -----------------------------------------------------------------------------
DO $$
BEGIN
  PERFORM public.okey_internal_sync_bot_account_profiles();
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'bot kimlik havuzu tohumlanamadı: %', SQLERRM;
END $$;

NOTIFY pgrst, 'reload schema';

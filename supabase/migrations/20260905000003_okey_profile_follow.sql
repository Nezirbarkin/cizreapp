-- =============================================================================
-- 101 Okey — PROFİL KARTINDAN TAKİP ET (kullanıcı isteği, 2026-09-05:
-- "profil tıkladığında takip et butonu da koy")
-- -----------------------------------------------------------------------------
-- Masada bir oyuncuya dokununca açılan kart (bkz. okey_profile_card) şimdiye
-- kadar SADECE OKUYORDU: takipçi sayısını gösteriyor ama takip etmenin bir
-- yolunu sunmuyordu. Oysa masada tanıştığın biri, uygulamanın geri kalanında
-- arayıp bulman gereken biri olmamalı.
--
-- ## Neden bir RPC, doğrudan `follows` insert'i değil
--
-- Uygulamada takip iki farklı yoldan yürür ve hangisinin geçerli olduğunu
-- HEDEF PROFİL belirler:
--
--   * `profile_is_public = true`  → doğrudan `follows` satırı
--   * `profile_is_public = false` → `follow_requests` satırı (onay bekler;
--     kabul edilince SQL trigger'ı `follows`'a kendisi yazar)
--
-- Bu ayrım istemci tarafında dört ayrı ekranda tekrar tekrar yazılmış
-- durumda (profile_screen, user_profile_screen, followers_screen,
-- members_screen) ve her biri kendi yorumuyla. Okey masasında beşincisini
-- yazmak yerine karar SUNUCUYA alınıyor: istemci "takip et" der, hangi yolun
-- işlediğini sunucu söyler.
--
-- ## Gizlilik
--
-- Fonksiyon yalnızca ÇAĞIRANIN KENDİ takip ilişkisini değiştirir; p_user_id
-- başka birinin adına takip ettirmek için kullanılamaz (follower_id her zaman
-- auth.uid()). Bot koltuklarının kullanıcı kimliği yoktur — kart onlarda
-- düğmeyi hiç göstermez, sunucu da NULL geldiğinde hata verir.
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '5s';

-- -----------------------------------------------------------------------------
-- okey_profile_follow — takip et / takibi bırak
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.okey_profile_follow(uuid, boolean);

CREATE FUNCTION public.okey_profile_follow(
  p_user_id uuid,
  p_follow boolean DEFAULT true
)
RETURNS TABLE(
  is_following boolean,
  is_requested boolean,
  followers_count int
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_me CONSTANT uuid := (SELECT auth.uid());
  v_public boolean;
BEGIN
  IF v_me IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501';
  END IF;
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'APP:user_required' USING ERRCODE = '22023';
  END IF;
  IF p_user_id = v_me THEN
    RAISE EXCEPTION 'APP:cannot_follow_self' USING ERRCODE = 'P0001';
  END IF;

  SELECT COALESCE(p.profile_is_public, true) INTO v_public
  FROM public.profiles AS p WHERE p.id = p_user_id;

  IF v_public IS NULL THEN
    RAISE EXCEPTION 'APP:profile_not_found' USING ERRCODE = 'P0001';
  END IF;

  IF p_follow THEN
    IF v_public THEN
      INSERT INTO public.follows (follower_id, following_id)
      VALUES (v_me, p_user_id)
      ON CONFLICT DO NOTHING;
    ELSE
      -- GİZLİ HESAP: doğrudan takip YOK, istek var. Reddedilmiş/eski bir
      -- istek varsa yeniden "pending"e çekilir — kullanıcı ikinci kez
      -- denediğinde sessizce hiçbir şey olmaması en kötü sonuçtur.
      INSERT INTO public.follow_requests AS fr (follower_id, following_id, status)
      VALUES (v_me, p_user_id, 'pending')
      ON CONFLICT (follower_id, following_id) DO UPDATE
        SET status = 'pending', updated_at = now()
        WHERE fr.status <> 'accepted';
    END IF;
  ELSE
    -- TAKİBİ BIRAK: hem ilişkiyi hem de BEKLEYEN isteği kaldır. İkincisi
    -- olmazsa, gizli bir hesaba istek gönderip vazgeçen oyuncu isteği geri
    -- alamıyordu (düğme "bekliyor" yazmaya devam ediyordu).
    DELETE FROM public.follows AS f
    WHERE f.follower_id = v_me AND f.following_id = p_user_id;

    DELETE FROM public.follow_requests AS r
    WHERE r.follower_id = v_me AND r.following_id = p_user_id
      AND r.status = 'pending';
  END IF;

  RETURN QUERY
  SELECT
    EXISTS (
      SELECT 1 FROM public.follows AS f
      WHERE f.follower_id = v_me AND f.following_id = p_user_id
    ),
    EXISTS (
      SELECT 1 FROM public.follow_requests AS r
      WHERE r.follower_id = v_me AND r.following_id = p_user_id
        AND r.status = 'pending'
    ),
    (SELECT count(*)::int FROM public.follows AS f
      WHERE f.following_id = p_user_id);
END;
$$;

REVOKE ALL ON FUNCTION public.okey_profile_follow(uuid, boolean)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_profile_follow(uuid, boolean)
  TO authenticated;

COMMENT ON FUNCTION public.okey_profile_follow(uuid, boolean) IS
  'Okey profil kartındaki TAKİP ET/BIRAK düğmesi. Hedef profil gizliyse takip yerine istek oluşturur. follower_id her zaman auth.uid()''tir.';


-- -----------------------------------------------------------------------------
-- okey_profile_card — düğmenin DOĞRU durumu göstermesi için iki alan daha
--
-- Kart zaten `is_following` döndürüyordu ama gizli hesaplarda bu tek başına
-- yetmiyor: istek gönderilmiş ama henüz onaylanmamışsa düğme "TAKİP ET"
-- yazmaya devam eder ve oyuncu isteği tekrar tekrar gönderirdi.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.okey_profile_card(uuid, uuid);

CREATE FUNCTION public.okey_profile_card(
  p_user_id uuid DEFAULT NULL,
  p_bot_profile_id uuid DEFAULT NULL
)
RETURNS TABLE(
  user_id uuid,
  display_name text,
  avatar_url text,
  points int,
  matches_played int,
  matches_won int,
  hands_played int,
  hands_won int,
  best_match_score int,
  followers_count int,
  following_count int,
  friends_count int,
  is_following boolean,
  is_self boolean,
  is_follow_requested boolean,
  is_private boolean
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_me uuid := (SELECT auth.uid());
  v_seed bigint;
BEGIN
  IF v_me IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  -- ---- GERÇEK KULLANICI ----------------------------------------------
  IF p_user_id IS NOT NULL THEN
    RETURN QUERY
    SELECT
      p.id,
      COALESCE(NULLIF(p.full_name, ''), p.username, 'Oyuncu'),
      p.avatar_url,
      COALESCE(w.points, 0)::int,
      COALESCE(s.matches_played, 0),
      COALESCE(s.matches_won, 0),
      COALESCE(s.hands_played, 0),
      COALESCE(s.hands_won, 0),
      s.best_match_score,
      (SELECT count(*)::int FROM public.follows f
        WHERE f.following_id = p.id),
      (SELECT count(*)::int FROM public.follows f
        WHERE f.follower_id = p.id),
      -- Arkadaş = karşılıklı takip.
      (SELECT count(*)::int FROM public.follows a
        JOIN public.follows b
          ON b.follower_id = a.following_id AND b.following_id = a.follower_id
        WHERE a.follower_id = p.id),
      EXISTS (
        SELECT 1 FROM public.follows f
        WHERE f.follower_id = v_me AND f.following_id = p.id
      ),
      p.id = v_me,
      EXISTS (
        SELECT 1 FROM public.follow_requests r
        WHERE r.follower_id = v_me AND r.following_id = p.id
          AND r.status = 'pending'
      ),
      NOT COALESCE(p.profile_is_public, true)
    FROM public.profiles AS p
    LEFT JOIN public.okey_stats AS s ON s.user_id = p.id
    LEFT JOIN public.okey_wallets AS w ON w.user_id = p.id
    WHERE p.id = p_user_id;
    RETURN;
  END IF;

  -- ---- BOT -------------------------------------------------------------
  -- Bot koltuğunun kullanıcı kimliği yoktur; kart takip düğmesini hiç
  -- göstermez (user_id NULL). İstatistikler profil id'sinden TÜRETİLEN
  -- sabit bir tohumla üretilir — bkz. 20260904000005.
  IF p_bot_profile_id IS NOT NULL THEN
    v_seed := abs(hashtext(p_bot_profile_id::text));

    RETURN QUERY
    SELECT
      NULL::uuid,
      b.display_name,
      b.avatar_url,
      (500 + (v_seed % 9500))::int,                       -- puan
      (60 + (v_seed % 340))::int,                          -- oynanan maç
      ((60 + (v_seed % 340)) * (42 + (v_seed % 18)) / 100)::int, -- kazanılan
      ((60 + (v_seed % 340)) * 9)::int,                    -- oynanan el
      ((60 + (v_seed % 340)) * 3)::int,                    -- kazanılan el
      (-(101 + (v_seed % 120)))::int,                      -- en iyi skor
      (5 + (v_seed % 240))::int,                           -- takipçi
      (5 + (v_seed % 180))::int,                           -- takip
      (2 + (v_seed % 60))::int,                            -- arkadaş
      false,
      false,
      false,
      false
    FROM public.okey_bot_profiles AS b
    WHERE b.id = p_bot_profile_id;
    RETURN;
  END IF;

  RAISE EXCEPTION 'user_or_bot_required';
END;
$$;
REVOKE ALL ON FUNCTION public.okey_profile_card(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_profile_card(uuid, uuid) TO authenticated;

COMMENT ON FUNCTION public.okey_profile_card(uuid, uuid) IS
  'Masada/skor tablosunda bir oyuncuya dokununca açılan profil kartı. Ad, avatar, okey puanı, maç istatistikleri, takip SAYILARI ve TAKİP DURUMU (takip ediyor mu / istek bekliyor mu) döner. Bot profilleri id''den türeyen SABİT istatistiklerle döner.';

NOTIFY pgrst, 'reload schema';

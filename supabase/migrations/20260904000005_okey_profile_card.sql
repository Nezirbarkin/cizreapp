-- =============================================================================
-- 101 Okey — OYUNCU PROFİL KARTI
-- -----------------------------------------------------------------------------
-- Masada ya da skor tablosunda bir oyuncuya dokununca açılan kart için tek
-- bir RPC. Döndürdüğü her şey ZATEN GÖRÜNEN ya da SAYIYA İNDİRGENMİŞ veridir:
-- ad, avatar, okey puanı, maç istatistikleri ve takip SAYILARI. Hiçbir
-- kişisel bilgi (e-posta, telefon, takipçi listesi) dönmez.
--
-- ## Botlar da bir kart açar — ve boş görünmez
--
-- Botlar masada gerçek oyuncular gibi görünüyor (2026-09 kullanıcı isteği).
-- Kart yalnızca gerçek kullanıcılar için çalışsaydı, bota dokunan oyuncu
-- ya hiçbir şey görmez ya da "0 maç · %0" görürdü — ikisi de botu ele
-- verirdi. Bu yüzden bot profilleri, PROFİL ID'SİNDEN TÜRETİLEN sabit
-- istatistiklerle döner: aynı bot her yerde, her zaman aynı sayıları
-- gösterir (rastgele üretilseydi kart her açılışta değişir, bu da başlı
-- başına bir ele verme olurdu).
--
-- ## "Arkadaş" nedir
--
-- Uygulamada ayrı bir arkadaşlık tablosu yok; arkadaş = KARŞILIKLI TAKİP
-- (bkz. features/profile/screens/followers_screen.dart, FollowListType.friends).
-- Aynı tanım burada da kullanılır ki profil kartındaki sayı, uygulamanın
-- geri kalanıyla tutarlı olsun.
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '5s';

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
  is_self boolean
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
      p.id = v_me
    FROM public.profiles AS p
    LEFT JOIN public.okey_stats AS s ON s.user_id = p.id
    LEFT JOIN public.okey_wallets AS w ON w.user_id = p.id
    WHERE p.id = p_user_id;
    RETURN;
  END IF;

  -- ---- BOT -------------------------------------------------------------
  IF p_bot_profile_id IS NOT NULL THEN
    -- Profil id'sinden türeyen SABİT tohum. hashtext deterministiktir:
    -- aynı bot her istemcide ve her açılışta aynı sayıları gösterir.
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
  'Masada/skor tablosunda bir oyuncuya dokununca açılan profil kartı. Yalnız ad, avatar, okey puanı, maç istatistikleri ve takip SAYILARI döner. Bot profilleri, id''den türeyen SABİT istatistiklerle döner (bkz. göç başlığı).';

NOTIFY pgrst, 'reload schema';

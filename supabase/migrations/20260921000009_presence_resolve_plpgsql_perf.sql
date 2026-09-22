-- =============================================================================
-- 20260921000009_presence_resolve_plpgsql_perf.sql
-- -----------------------------------------------------------------------------
-- `presence_resolve` (20260921000008) aynı kuralları uyguluyor ama LANGUAGE sql +
-- SECURITY DEFINER + `SET search_path` olduğu için HER ÇAĞRIDA yeniden planlanıyordu:
-- canlıda çağrı başına ~5 ms, 173 satırlık `public_profiles_chat` görünümü ~415 ms.
-- (Ölçüm: cfg okuma 0,1 ms, engel araması 0,015 ms — maliyet fonksiyon gövdesinin
-- planlanmasıydı.)
--
-- PL/pgSQL planlarını oturum boyunca önbelleğe alır, ayrıca ucuz kapıları (hayalet,
-- kapalı özellik, "hiçbir şey görünmez") ilişki sorgularından ÖNCE değerlendirip
-- erken çıkabilir. Davranış BİREBİR aynıdır: supabase/tests/manual/
-- chat_presence_and_typing_test.sql (101 kontrol) bu gövdeyle de geçer.
--
-- İmza, dönüş şekli, yetkiler ve güvenlik özellikleri değişmez; yalnız gövde.
-- =============================================================================

begin;

SET LOCAL lock_timeout = '10s';

CREATE OR REPLACE FUNCTION public.presence_resolve(
  p_target  uuid,
  p_context text DEFAULT 'chat'
)
RETURNS TABLE (can_see_online boolean, online boolean, last_seen timestamptz)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_viewer         uuid := (SELECT auth.uid());
  v_cfg            jsonb;
  v_is_online      boolean;
  v_seen_at        timestamptz;
  v_ghost          boolean;
  v_online_pref    boolean;
  v_seen_pref      boolean;
  v_friends_only   boolean;
  v_public         boolean;
  v_self           boolean;
  v_see_online     boolean;
  v_see_seen       boolean;
  v_blocked        boolean := false;
  v_viewer_follows boolean := false;
  v_target_follows boolean := false;
BEGIN
  IF p_target IS NULL THEN
    RETURN;
  END IF;

  SELECT p.is_online,
         p.last_seen,
         COALESCE(p.is_ghost_mode, false),
         COALESCE(p.is_online_enabled, true),
         COALESCE(p.show_last_seen, true),
         COALESCE(p.last_seen_friends_only, false),
         COALESCE(p.profile_is_public, true)
    INTO v_is_online, v_seen_at, v_ghost, v_online_pref, v_seen_pref,
         v_friends_only, v_public
  FROM public.profiles p
  WHERE p.id = p_target;

  -- Hedef yoksa satır YOK (görünümlerde LEFT JOIN LATERAL bunu "gizli" sayar).
  IF NOT FOUND THEN
    RETURN;
  END IF;

  -- Varsayılan cevap: hiçbir şey görünmez.
  can_see_online := false;
  online         := false;
  last_seen      := NULL;

  -- Oturumsuz görüntüleyici (anon): hiçbir şey.
  IF v_viewer IS NULL THEN
    RETURN NEXT;
    RETURN;
  END IF;

  v_self := (v_viewer = p_target);

  IF v_self THEN
    -- Kişi kendi durumunu (hayalet, gizli, admin kapalı olsa da) görür.
    v_see_online := true;
    v_see_seen   := true;
  ELSE
    -- Hayalet modu: çevrimiçi de son görülme de gizli. Ucuz kapı: ilişki
    -- sorgularına hiç girmeden çık.
    IF v_ghost THEN
      RETURN NEXT;
      RETURN;
    END IF;

    v_cfg := public.chat_presence_cfg();

    v_see_online := (v_cfg ->> 'online')::boolean AND v_online_pref;
    v_see_seen   := (v_cfg ->> 'last_seen')::boolean
                    AND CASE WHEN p_context = 'profile'
                             THEN (v_cfg ->> 'last_seen_in_profile')::boolean
                             ELSE (v_cfg ->> 'last_seen_in_chat')::boolean END
                    AND v_seen_pref;

    -- Admin ya da kullanıcı her ikisini de kapatmışsa ilişki sorgusu gereksiz.
    IF NOT v_see_online AND NOT v_see_seen THEN
      RETURN NEXT;
      RETURN;
    END IF;

    -- Engel (iki yönde).
    SELECT EXISTS (
      SELECT 1 FROM public.blocked_users b
      WHERE (b.blocker_id = v_viewer AND b.blocked_id = p_target)
         OR (b.blocker_id = p_target AND b.blocked_id = v_viewer)
    ) INTO v_blocked;
    IF v_blocked THEN
      RETURN NEXT;
      RETURN;
    END IF;

    -- Gizli hesap: yalnız takip edenler görür. "Yalnız arkadaşlar" için de
    -- görüntüleyicinin takibi gerekir.
    IF NOT v_public OR v_friends_only THEN
      SELECT EXISTS (
        SELECT 1 FROM public.follows f
        WHERE f.follower_id = v_viewer AND f.following_id = p_target
      ) INTO v_viewer_follows;
    END IF;
    IF NOT v_public AND NOT v_viewer_follows THEN
      RETURN NEXT;
      RETURN;
    END IF;

    -- "Yalnız arkadaşlar": karşılıklı takip (yalnız son görülmeyi kısıtlar,
    -- çevrimiçi izni kalır).
    IF v_friends_only THEN
      SELECT EXISTS (
        SELECT 1 FROM public.follows f
        WHERE f.follower_id = p_target AND f.following_id = v_viewer
      ) INTO v_target_follows;
      IF NOT (v_viewer_follows AND v_target_follows) THEN
        v_see_seen := false;
      END IF;
    END IF;
  END IF;

  can_see_online := v_see_online;

  -- 3 dakika = PrivacyService.activeThreshold (2 dk'lık nabız + tolerans).
  online := v_see_online
            AND COALESCE(v_is_online, false)
            AND v_seen_at IS NOT NULL
            AND v_seen_at > now() - interval '3 minutes';

  IF v_cfg IS NULL THEN
    v_cfg := public.chat_presence_cfg();
  END IF;

  -- "Çevrimdışı görün" diyen biri şu an aktifse, son görülmesi "az önce"
  -- diyerek onu ele vermesin: taze nabız varken gizli tutulur.
  IF v_see_seen
     AND v_seen_at IS NOT NULL
     AND v_seen_at > now() - make_interval(days => (v_cfg ->> 'last_seen_max_days')::integer)
     AND (v_online_pref OR v_self OR v_seen_at <= now() - interval '3 minutes') THEN
    last_seen := v_seen_at;
  END IF;

  RETURN NEXT;
  RETURN;
END;
$fn$;

-- CREATE OR REPLACE yetkileri korur; yine de niyeti açıkça yaz.
REVOKE ALL ON FUNCTION public.presence_resolve(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.presence_resolve(uuid, text)
  TO anon, authenticated, service_role;

commit;

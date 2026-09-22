-- =============================================================================
-- claim_username: change_my_username ile aynı ayrılmış ad kuralları
-- =============================================================================
-- 20260920000002 change_my_username, resmi görünen adları (destek, support, ...)
-- yalnızca admin'e bırakıyor ve silinen_ önekini reddediyor (admin_delete_user
-- silinen hesapları 'silinen_<id>' adına çeviriyor). OAuth sonrası İLK seçim
-- yolu olan claim_username ise yalnızca misafir_ önekini reddediyordu; yani
-- kuralı atlamanın en kolay yolu yeni bir Google hesabıyla ilk seçimde
-- "destek" almaktı. Bu göç iki yolu aynı politikaya getirir.
--
-- NOT: ayrılmış ad listesi iki fonksiyonda ayrı ayrı yazılı. Birini
-- değiştirirsen diğerini de değiştir.
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '5s';

CREATE OR REPLACE FUNCTION public.claim_username(p_username text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid            uuid := auth.uid();
  v_username       text := LOWER(TRIM(p_username));
  v_needs_username boolean;
  v_is_admin       boolean;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'claim_username: not authenticated'
      USING ERRCODE = '28000';
  END IF;

  IF v_username !~ '^[a-z0-9._-]{3,20}$' THEN
    RAISE EXCEPTION 'claim_username: invalid format'
      USING ERRCODE = '22023';
  END IF;

  IF v_username LIKE 'misafir\_%' ESCAPE '\'
     OR v_username LIKE 'silinen\_%' ESCAPE '\' THEN
    RAISE EXCEPTION 'claim_username: reserved prefix'
      USING ERRCODE = '22023';
  END IF;

  SELECT needs_username, (role::text = 'admin')
    INTO v_needs_username, v_is_admin
  FROM public.profiles
  WHERE id = v_uid
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'claim_username: profile not found'
      USING ERRCODE = 'P0002';
  END IF;

  IF NOT v_needs_username THEN
    RAISE EXCEPTION 'claim_username: username already set'
      USING ERRCODE = '22023';
  END IF;

  -- Resmi görünen adların taklidi: yalnızca admin bu adları alabilir
  -- (change_my_username ile aynı liste ve aynı muafiyet).
  IF NOT COALESCE(v_is_admin, false)
     AND v_username = ANY (ARRAY['admin', 'administrator', 'cizreapp', 'destek', 'support', 'moderator', 'system', 'yonetici']) THEN
    RAISE EXCEPTION 'claim_username: reserved name'
      USING ERRCODE = '22023';
  END IF;

  BEGIN
    UPDATE public.profiles
      SET username = v_username, needs_username = false, updated_at = NOW()
    WHERE id = v_uid;
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'claim_username: username taken'
      USING ERRCODE = '23505';
  END;
END;
$$;

REVOKE ALL ON FUNCTION public.claim_username(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.claim_username(text) TO authenticated;

COMMENT ON FUNCTION public.claim_username(text) IS
  'Google/Apple kaydından sonra tek seferlik gerçek kullanıcı adı seçimi. Yalnız profiles.needs_username=true iken çalışır; genel rename RPC''si değildir (o change_my_username). Ayrılmış ad/önek kuralları change_my_username ile aynıdır.';

NOTIFY pgrst, 'reload schema';

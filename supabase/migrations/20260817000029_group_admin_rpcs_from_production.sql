-- =============================================================================
-- Admin grup yonetimi RPC'leri — uretimden geri alinip migration'a baglandi
-- =============================================================================
-- NEDEN
--   Asagidaki 7 fonksiyon CANLI veritabaninda vardi ama supabase/migrations/
--   altinda TANIMLARI YOKTU (elle SQL Editor'den olusturulmuslar). Sonuc:
--   `supabase db reset` ile kurulan her ortamda (yerel, CI, staging) admin
--   panelinin "Gruplar" sekmesi komple calismiyordu; Dart tarafi RPC 42883
--   alip RLS'e takilan fallback dallarina dusuyordu.
--
--   Govdeler 2026-08-16'da uretimden pg_get_functiondef() ile alindi, yani
--   bu dosya tahmin degil, calisan sistemin aynasidir.
--
-- URETIMDEKI HALINE GORE IKI DAVRANIS DUZELTMESI YAPILDI
--
--   1) "her zaman true" sorunu.
--      admin_update_group / admin_delete_group / admin_remove_group_member /
--      admin_change_member_role uretimde UPDATE/DELETE'ten sonra kosulsuz
--      `RETURN true` yapiyordu. Hicbir satir etkilenmese bile (grup silinmis,
--      kullanici zaten uye degil, yanlis id) fonksiyon "basarili" donuyor,
--      admin panelinde "Üye çıkarıldı" / "Rol: admin" yesil bildirimi
--      cikiyor ama hicbir sey degismiyordu. Artik GET DIAGNOSTICS ROW_COUNT
--      ile gercek sonuc donuyor.
--
--      Istemci tarafi bu sozlesmeye 2026-08-16'da hazirlandi: Dart kodu
--      artik `false` donusunu hata olarak gosteriyor
--      (groups_management_content.dart). Yani bu degisiklik sahte basari
--      bildirimlerini gercek hata mesajina cevirir.
--
--   2) admin_change_member_role rol dogrulamasi yapmiyordu.
--      p_new_role serbest metindi; yazim hatasi veya kotu niyetli bir cagri
--      group_members.role'u 'xyz' yapabilirdi. Artik yalniz
--      admin/moderator/member kabul edilir (arayuzun sundugu uc deger).
--
-- BILINEN SINIRLAMA (bilerek DEGISTIRILMEDI)
--   admin_update_group COALESCE(p_name, name) kalibiyla calisir: NULL
--   gonderilen alan "degistirme" anlamina gelir. Bu yuzden bir grubun
--   aciklamasi RPC uzerinden BOSALTILAMAZ (Dart bos aciklama icin null
--   gonderiyor, RPC eski degeri koruyor). Semantigi burada degistirmek
--   "kismi guncelleme" sozlesmesini bozardi; duzeltilecekse istemcinin bos
--   string gondermesi ya da ayri bir p_clear_description bayragi eklenmesi
--   gerekir.
--
-- IDEMPOTENT
--   Tumu CREATE OR REPLACE. Uretimde imzalar birebir ayni oldugu icin
--   yalniz govdeler guncellenir, yetkiler korunur. Yine de yetkiler acikca
--   tekrar verilir (bkz. 20260817000020 — bu repoda yetkiler defalarca
--   kayboldu).
-- =============================================================================

SET search_path = public, pg_temp;

-- -----------------------------------------------------------------------------
-- 1) Listeleme
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_get_all_groups()
RETURNS SETOF public.groups
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_is_admin BOOLEAN;
BEGIN
  SELECT (role = 'admin') INTO v_is_admin FROM profiles WHERE id = auth.uid();
  IF NOT COALESCE(v_is_admin, false) THEN
    RAISE EXCEPTION 'Yetkisiz: Admin değilsiniz';
  END IF;

  RETURN QUERY SELECT * FROM groups ORDER BY created_at DESC;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 2) Olusturma
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_create_group(
  p_name            text,
  p_description     text    DEFAULT NULL::text,
  p_is_private      boolean DEFAULT false,
  p_is_discoverable boolean DEFAULT true,
  p_avatar_url      text    DEFAULT NULL::text,
  p_created_by      uuid    DEFAULT NULL::uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_is_admin BOOLEAN;
  v_group_id UUID;
BEGIN
  SELECT (role = 'admin') INTO v_is_admin FROM profiles WHERE id = auth.uid();
  IF NOT COALESCE(v_is_admin, false) THEN
    RAISE EXCEPTION 'Yetkisiz: Admin değilsiniz';
  END IF;

  INSERT INTO groups (
    name, description, is_private, is_discoverable, avatar_url,
    created_by, member_count
  )
  VALUES (
    p_name, p_description, p_is_private, p_is_discoverable, p_avatar_url,
    COALESCE(p_created_by, auth.uid()), 0
  )
  RETURNING id INTO v_group_id;

  RETURN v_group_id;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 3) Guncelleme  (DEGISIKLIK: gercek ROW_COUNT doner)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_update_group(
  p_group_id        uuid,
  p_name            text    DEFAULT NULL::text,
  p_description     text    DEFAULT NULL::text,
  p_is_private      boolean DEFAULT NULL::boolean,
  p_is_discoverable boolean DEFAULT NULL::boolean,
  p_avatar_url      text    DEFAULT NULL::text,
  p_member_count    integer DEFAULT NULL::integer
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_is_admin BOOLEAN;
  v_rows     INTEGER;
BEGIN
  SELECT (role = 'admin') INTO v_is_admin FROM profiles WHERE id = auth.uid();
  IF NOT COALESCE(v_is_admin, false) THEN
    RAISE EXCEPTION 'Yetkisiz: Admin değilsiniz';
  END IF;

  UPDATE groups SET
    name            = COALESCE(p_name, name),
    description     = COALESCE(p_description, description),
    is_private      = COALESCE(p_is_private, is_private),
    is_discoverable = COALESCE(p_is_discoverable, is_discoverable),
    avatar_url      = COALESCE(p_avatar_url, avatar_url),
    member_count    = COALESCE(p_member_count, member_count),
    updated_at      = NOW()
  WHERE id = p_group_id;

  GET DIAGNOSTICS v_rows = ROW_COUNT;
  RETURN v_rows > 0;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 4) Silme  (DEGISIKLIK: gercek ROW_COUNT doner)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_delete_group(p_group_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_is_admin BOOLEAN;
  v_rows     INTEGER;
BEGIN
  SELECT (role = 'admin') INTO v_is_admin FROM profiles WHERE id = auth.uid();
  IF NOT COALESCE(v_is_admin, false) THEN
    RAISE EXCEPTION 'Yetkisiz: Admin değilsiniz';
  END IF;

  -- Bagli kayitlar once: FK'lar ON DELETE CASCADE olmayabilir.
  DELETE FROM group_join_requests WHERE group_id = p_group_id;
  DELETE FROM group_messages      WHERE group_id = p_group_id;
  DELETE FROM group_members       WHERE group_id = p_group_id;

  DELETE FROM groups WHERE id = p_group_id;
  GET DIAGNOSTICS v_rows = ROW_COUNT;

  -- Grup zaten yoksa false doner; istemci "Grup silinemedi" gosterir.
  RETURN v_rows > 0;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 5) Uye listesi
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_get_group_members(p_group_id uuid)
RETURNS TABLE(
  id              uuid,
  group_id        uuid,
  user_id         uuid,
  role            text,
  joined_at       timestamp with time zone,
  user_full_name  text,
  user_avatar_url text,
  user_username   text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_is_admin BOOLEAN;
BEGIN
  SELECT (p.role = 'admin') INTO v_is_admin FROM profiles p WHERE p.id = auth.uid();
  IF NOT COALESCE(v_is_admin, false) THEN
    RAISE EXCEPTION 'Yetkisiz: Admin değilsiniz';
  END IF;

  RETURN QUERY
  SELECT
    gm.id,
    gm.group_id,
    gm.user_id,
    gm.role,
    gm.joined_at,
    p.full_name  AS user_full_name,
    p.avatar_url AS user_avatar_url,
    p.username   AS user_username
  FROM group_members gm
  LEFT JOIN profiles p ON p.id = gm.user_id
  WHERE gm.group_id = p_group_id
  ORDER BY
    CASE gm.role
      WHEN 'admin'     THEN 1
      WHEN 'moderator' THEN 2
      ELSE 3
    END,
    gm.joined_at;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 6) Uye cikarma  (DEGISIKLIK: gercek ROW_COUNT doner)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_remove_group_member(
  p_group_id uuid,
  p_user_id  uuid
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_is_admin BOOLEAN;
  v_removed  INTEGER;
  v_count    INTEGER;
BEGIN
  SELECT (role = 'admin') INTO v_is_admin FROM profiles WHERE id = auth.uid();
  IF NOT COALESCE(v_is_admin, false) THEN
    RAISE EXCEPTION 'Yetkisiz: Admin değilsiniz';
  END IF;

  DELETE FROM group_members
  WHERE group_id = p_group_id AND user_id = p_user_id;
  GET DIAGNOSTICS v_removed = ROW_COUNT;

  -- Sayac her durumda gercek satir sayisiyla esitlenir: gecmiste istemci
  -- tarafi elle +1/-1 yaptigi icin kaymis kayitlar bu yolla da duzelir.
  SELECT COUNT(*) INTO v_count FROM group_members WHERE group_id = p_group_id;
  UPDATE groups SET member_count = v_count, updated_at = NOW()
  WHERE id = p_group_id;

  RETURN v_removed > 0;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 7) Rol degistirme  (DEGISIKLIK: rol dogrulamasi + gercek ROW_COUNT)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_change_member_role(
  p_group_id uuid,
  p_user_id  uuid,
  p_new_role text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_is_admin BOOLEAN;
  v_rows     INTEGER;
BEGIN
  SELECT (role = 'admin') INTO v_is_admin FROM profiles WHERE id = auth.uid();
  IF NOT COALESCE(v_is_admin, false) THEN
    RAISE EXCEPTION 'Yetkisiz: Admin değilsiniz';
  END IF;

  -- Uretimdeki surum serbest metin kabul ediyordu: yazim hatasi veya elle
  -- yapilan bir cagri role'u 'xyz' yapabilir, uyeyi hicbir yetki dalina
  -- girmeyen bir duruma dusurebilirdi. Arayuzun sundugu uc deger disi reddedilir.
  IF p_new_role IS NULL OR p_new_role NOT IN ('admin', 'moderator', 'member') THEN
    RAISE EXCEPTION 'Gecersiz rol: % (admin/moderator/member bekleniyor)', p_new_role
      USING ERRCODE = '22023';
  END IF;

  UPDATE group_members SET role = p_new_role
  WHERE group_id = p_group_id AND user_id = p_user_id;

  GET DIAGNOSTICS v_rows = ROW_COUNT;
  RETURN v_rows > 0;
END;
$function$;

-- -----------------------------------------------------------------------------
-- Yetkiler (repo standardi: PUBLIC/anon kapali, authenticated acik).
-- Yetki sinirini fonksiyon govdesindeki admin kontrolu saglar.
-- -----------------------------------------------------------------------------
DO $grants$
DECLARE
  v_function regprocedure;
BEGIN
  FOREACH v_function IN ARRAY ARRAY[
    to_regprocedure('public.admin_get_all_groups()'),
    to_regprocedure('public.admin_create_group(text,text,boolean,boolean,text,uuid)'),
    to_regprocedure('public.admin_update_group(uuid,text,text,boolean,boolean,text,integer)'),
    to_regprocedure('public.admin_delete_group(uuid)'),
    to_regprocedure('public.admin_get_group_members(uuid)'),
    to_regprocedure('public.admin_remove_group_member(uuid,uuid)'),
    to_regprocedure('public.admin_change_member_role(uuid,uuid,text)')
  ]
  LOOP
    IF v_function IS NOT NULL THEN
      EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon', v_function);
      EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', v_function);
    END IF;
  END LOOP;
END
$grants$;

NOTIFY pgrst, 'reload schema';

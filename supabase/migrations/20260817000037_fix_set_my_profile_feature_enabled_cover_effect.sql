-- =============================================================================
-- set_my_profile_feature_enabled: 'cover_effect' turunu de kabul et
--
-- 20260817000027, profile_feature_catalog'a yeni bir kind ('cover_effect')
-- ekledi ve get_my_profile_feature_assignments (kind <> 'badge' filtresiyle)
-- bu ozellikleri de kullaniciya listeleyip acma/kapama anahtari gosteriyor.
-- Ancak set_my_profile_feature_enabled hala eski kind listesini
-- ('effect', 'avatar_effect', 'icon') kullaniyordu; kullanici satin aldigi
-- bir cover_effect ozelligini ac/kapat yapmaya calistiginda UPDATE hicbir
-- satiri eslemiyor ve "Ozellik bulunamadi, suresi dolmus veya yonetilemez"
-- (P0002) hatasiyla basarisiz oluyordu.
-- =============================================================================

begin;

create or replace function public.set_my_profile_feature_enabled(
  p_feature_id uuid,
  p_enabled boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'set_my_profile_feature_enabled: authentication required'
      using errcode = '42501';
  end if;

  if exists (
    select 1
    from public.profile_feature_catalog c
    where c.id = p_feature_id and c.kind = 'badge'
  ) then
    raise exception 'Rozet ve doğrulama tikleri kullanıcı tarafından değiştirilemez'
      using errcode = '42501';
  end if;

  update public.user_profile_features upf
  set is_enabled = coalesce(p_enabled, false), updated_at = now()
  from public.profile_feature_catalog c
  where upf.feature_id = p_feature_id
    and upf.user_id = v_uid
    and c.id = upf.feature_id
    and c.kind in ('effect', 'avatar_effect', 'cover_effect', 'icon')
    and c.is_active = true
    and upf.starts_at <= now()
    and (upf.expires_at is null or upf.expires_at > now());

  if not found then
    raise exception 'Özellik bulunamadı, süresi dolmuş veya yönetilemez'
      using errcode = 'P0002';
  end if;
end;
$$;

commit;

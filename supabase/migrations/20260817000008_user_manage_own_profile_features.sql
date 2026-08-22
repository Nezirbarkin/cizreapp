-- =============================================================================
-- Kullanıcının kendisine admin tarafından verilmiş profil özelliklerini yönetmesi
-- Rozet/tik (kind='badge') kullanıcı tarafından değiştirilemez.
-- Kullanıcı yeni özellik veremez, süre değiştiremez ve atamayı silemez;
-- yalnız mevcut effect/avatar_effect/icon kaydını açıp kapatabilir.
-- =============================================================================

begin;

create or replace function public.get_my_profile_feature_assignments()
returns table (
  assignment_id uuid,
  feature_id uuid,
  code text,
  kind text,
  name text,
  description text,
  renderer_key text,
  primary_color text,
  secondary_color text,
  config jsonb,
  priority integer,
  is_enabled boolean,
  starts_at timestamptz,
  expires_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    upf.id,
    c.id,
    c.code,
    c.kind,
    c.name,
    c.description,
    c.renderer_key,
    c.primary_color,
    c.secondary_color,
    coalesce(c.config, '{}'::jsonb) || coalesce(upf.config_override, '{}'::jsonb),
    c.priority,
    upf.is_enabled,
    upf.starts_at,
    upf.expires_at
  from public.user_profile_features upf
  join public.profile_feature_catalog c on c.id = upf.feature_id
  where upf.user_id = auth.uid()
    and c.kind <> 'badge'
    and c.is_active = true
    and upf.starts_at <= now()
    and (upf.expires_at is null or upf.expires_at > now())
  order by c.kind, c.priority desc, c.name;
$$;

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
    and c.kind in ('effect', 'avatar_effect', 'icon')
    and c.is_active = true
    and upf.starts_at <= now()
    and (upf.expires_at is null or upf.expires_at > now());

  if not found then
    raise exception 'Özellik bulunamadı, süresi dolmuş veya yönetilemez'
      using errcode = 'P0002';
  end if;
end;
$$;

revoke all on function public.get_my_profile_feature_assignments() from public;
revoke all on function public.set_my_profile_feature_enabled(uuid, boolean) from public;
grant execute on function public.get_my_profile_feature_assignments()
  to authenticated, service_role;
grant execute on function public.set_my_profile_feature_enabled(uuid, boolean)
  to authenticated, service_role;

commit;

-- Akış/yorum listelerinde yazar başına bir get_user_profile_features çağrısı
-- yerine tek istek.
--
-- Neden: Keşfet akışında her gönderi kartı (PrivilegedAvatar +
-- ProfilePrivilegeBadges) yazarının özelliklerini ayrı RPC ile istiyordu; 20
-- gönderilik bir sayfa ~15 eşzamanlı istek demekti. Canlıda özelliği olan
-- kullanıcı sayısı çok az olduğundan bu isteklerin neredeyse tamamı boş
-- dönüyordu. İstemci (ProfileFeatureService.prefetchUserFeatures) bu RPC'yi
-- sayfa başına bir kez çağırır; sonuçta satırı olmayan kullanıcıları da "boş"
-- olarak önbelleğe alır.
--
-- Filtreler ve sıralama get_user_profile_features ile birebir aynıdır
-- (kullanıcı başına priority desc, created_at asc). Herkese açık bilgi olduğu
-- için yetkiler de aynı (anon dahil).

create or replace function public.get_users_profile_features(p_user_ids uuid[])
returns table (
  user_id uuid,
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
  starts_at timestamptz,
  expires_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  -- Kötüye kullanım sınırı: istemci sayfa başına en fazla birkaç düzine kimlik
  -- gönderir.
  if p_user_ids is null or cardinality(p_user_ids) = 0 then
    return;
  end if;
  if cardinality(p_user_ids) > 200 then
    raise exception 'get_users_profile_features: too many ids (max 200)'
      using errcode = '22023';
  end if;

  return query
  select
    upf.user_id,
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
    upf.starts_at,
    upf.expires_at
  from public.user_profile_features upf
  join public.profile_feature_catalog c on c.id = upf.feature_id
  where upf.user_id = any(p_user_ids)
    and upf.is_enabled = true
    and c.is_active = true
    and upf.starts_at <= now()
    and (upf.expires_at is null or upf.expires_at > now())
  order by upf.user_id, c.priority desc, upf.created_at asc;
end;
$$;

revoke all on function public.get_users_profile_features(uuid[]) from public;
grant execute on function public.get_users_profile_features(uuid[])
  to anon, authenticated, service_role;

notify pgrst, 'reload schema';

-- =============================================================================
-- Kullanıcı profil ayrıcalıkları
-- Efektler, hareketli ikonlar ve renkli doğrulama rozetleri için genişletilebilir
-- katalog + kullanıcı ataması + güvenli public/admin RPC yüzeyi.
-- Mevcut profiles güvenlik modeline dokunmaz; admin kontrolünde kanonik
-- private.current_user_is_admin() helper'ını kullanır.
-- =============================================================================

begin;

create table if not exists public.profile_feature_catalog (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  kind text not null check (kind in ('effect', 'icon', 'badge')),
  name text not null,
  description text not null default '',
  renderer_key text not null,
  primary_color text not null default '#2196F3',
  secondary_color text,
  config jsonb not null default '{}'::jsonb,
  priority integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.user_profile_features (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  feature_id uuid not null references public.profile_feature_catalog(id) on delete cascade,
  granted_by uuid references public.profiles(id) on delete set null,
  is_enabled boolean not null default true,
  starts_at timestamptz not null default now(),
  expires_at timestamptz,
  config_override jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint user_profile_features_unique unique (user_id, feature_id),
  constraint user_profile_features_valid_period
    check (expires_at is null or expires_at > starts_at)
);

create index if not exists profile_feature_catalog_kind_active_idx
  on public.profile_feature_catalog(kind, is_active, priority desc);
create index if not exists user_profile_features_public_lookup_idx
  on public.user_profile_features(user_id, is_enabled, expires_at);

alter table public.profile_feature_catalog enable row level security;
alter table public.user_profile_features enable row level security;

-- Katalog, yalnız aktif kayıtlarla public okunabilir. Atama tablosu doğrudan
-- açılmaz; güvenli alanları döndüren RPC üzerinden okunur.
drop policy if exists profile_feature_catalog_public_select
  on public.profile_feature_catalog;
create policy profile_feature_catalog_public_select
  on public.profile_feature_catalog for select
  to anon, authenticated
  using (is_active = true);

revoke all on public.profile_feature_catalog from public, anon, authenticated;
grant select on public.profile_feature_catalog to anon, authenticated;
revoke all on public.user_profile_features from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- Public profil özellikleri: granted_by ve yönetim alanlarını dışarı çıkarmaz.
-- -----------------------------------------------------------------------------
create or replace function public.get_user_profile_features(p_user_id uuid)
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
    upf.starts_at,
    upf.expires_at
  from public.user_profile_features upf
  join public.profile_feature_catalog c on c.id = upf.feature_id
  where upf.user_id = p_user_id
    and upf.is_enabled = true
    and c.is_active = true
    and upf.starts_at <= now()
    and (upf.expires_at is null or upf.expires_at > now())
  order by c.priority desc, upf.created_at asc;
$$;

revoke all on function public.get_user_profile_features(uuid) from public;
grant execute on function public.get_user_profile_features(uuid)
  to anon, authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Admin RPC'leri. Normal istemciye tablo yazma izni verilmez.
-- -----------------------------------------------------------------------------
create or replace function public.admin_profile_feature_users(
  p_search text default null,
  p_limit integer default 40
)
returns table (id uuid, username text, full_name text, avatar_url text)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.current_user_is_admin() then
    raise exception 'admin_profile_feature_users: not admin' using errcode = '42501';
  end if;
  p_limit := greatest(1, least(coalesce(p_limit, 40), 100));
  return query
  select p.id, p.username, p.full_name, p.avatar_url
  from public.profiles p
  where p_search is null or btrim(p_search) = ''
     or p.username ilike '%' || btrim(p_search) || '%'
     or p.full_name ilike '%' || btrim(p_search) || '%'
  order by p.username nulls last, p.id
  limit p_limit;
end;
$$;

create or replace function public.admin_profile_feature_catalog(
  p_kind text default null,
  p_search text default null
)
returns setof public.profile_feature_catalog
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.current_user_is_admin() then
    raise exception 'admin_profile_feature_catalog: not admin' using errcode = '42501';
  end if;
  return query
  select c.*
  from public.profile_feature_catalog c
  where (p_kind is null or p_kind = '' or c.kind = p_kind)
    and (p_search is null or btrim(p_search) = ''
      or c.name ilike '%' || btrim(p_search) || '%'
      or c.code ilike '%' || btrim(p_search) || '%')
  order by c.kind, c.priority desc, c.name;
end;
$$;

create or replace function public.admin_profile_feature_assignments(p_user_id uuid)
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
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.current_user_is_admin() then
    raise exception 'admin_profile_feature_assignments: not admin' using errcode = '42501';
  end if;
  return query
  select upf.id, c.id, c.code, c.kind, c.name, c.description,
    c.renderer_key, c.primary_color, c.secondary_color,
    coalesce(c.config, '{}'::jsonb) || coalesce(upf.config_override, '{}'::jsonb),
    c.priority, upf.is_enabled, upf.starts_at, upf.expires_at
  from public.user_profile_features upf
  join public.profile_feature_catalog c on c.id = upf.feature_id
  where upf.user_id = p_user_id
  order by upf.is_enabled desc, c.kind, c.priority desc, c.name;
end;
$$;

create or replace function public.admin_assign_profile_feature(
  p_user_id uuid,
  p_feature_id uuid,
  p_expires_at timestamptz default null,
  p_config_override jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare v_id uuid;
begin
  if not private.current_user_is_admin() then
    raise exception 'admin_assign_profile_feature: not admin' using errcode = '42501';
  end if;
  if p_expires_at is not null and p_expires_at <= now() then
    raise exception 'Bitiş tarihi gelecekte olmalıdır' using errcode = '22007';
  end if;
  insert into public.user_profile_features
    (user_id, feature_id, granted_by, is_enabled, starts_at, expires_at, config_override, updated_at)
  values
    (p_user_id, p_feature_id, auth.uid(), true, now(), p_expires_at,
     coalesce(p_config_override, '{}'::jsonb), now())
  on conflict (user_id, feature_id) do update set
    granted_by = excluded.granted_by,
    is_enabled = true,
    starts_at = now(),
    expires_at = excluded.expires_at,
    config_override = excluded.config_override,
    updated_at = now()
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.admin_set_profile_feature_enabled(
  p_user_id uuid,
  p_feature_id uuid,
  p_enabled boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.current_user_is_admin() then
    raise exception 'admin_set_profile_feature_enabled: not admin' using errcode = '42501';
  end if;
  update public.user_profile_features
  set is_enabled = coalesce(p_enabled, false), updated_at = now()
  where user_id = p_user_id and feature_id = p_feature_id;
end;
$$;

create or replace function public.admin_revoke_profile_feature(
  p_user_id uuid,
  p_feature_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.current_user_is_admin() then
    raise exception 'admin_revoke_profile_feature: not admin' using errcode = '42501';
  end if;
  delete from public.user_profile_features
  where user_id = p_user_id and feature_id = p_feature_id;
end;
$$;

create or replace function public.admin_set_profile_feature_catalog_active(
  p_feature_id uuid,
  p_active boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.current_user_is_admin() then
    raise exception 'admin_set_profile_feature_catalog_active: not admin' using errcode = '42501';
  end if;
  update public.profile_feature_catalog
  set is_active = coalesce(p_active, false), updated_at = now()
  where id = p_feature_id;
end;
$$;

revoke all on function public.admin_profile_feature_users(text, integer) from public;
revoke all on function public.admin_profile_feature_catalog(text, text) from public;
revoke all on function public.admin_profile_feature_assignments(uuid) from public;
revoke all on function public.admin_assign_profile_feature(uuid, uuid, timestamptz, jsonb) from public;
revoke all on function public.admin_set_profile_feature_enabled(uuid, uuid, boolean) from public;
revoke all on function public.admin_revoke_profile_feature(uuid, uuid) from public;
revoke all on function public.admin_set_profile_feature_catalog_active(uuid, boolean) from public;

grant execute on function public.admin_profile_feature_users(text, integer) to authenticated, service_role;
grant execute on function public.admin_profile_feature_catalog(text, text) to authenticated, service_role;
grant execute on function public.admin_profile_feature_assignments(uuid) to authenticated, service_role;
grant execute on function public.admin_assign_profile_feature(uuid, uuid, timestamptz, jsonb) to authenticated, service_role;
grant execute on function public.admin_set_profile_feature_enabled(uuid, uuid, boolean) to authenticated, service_role;
grant execute on function public.admin_revoke_profile_feature(uuid, uuid) to authenticated, service_role;
grant execute on function public.admin_set_profile_feature_catalog_active(uuid, boolean) to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Başlangıç kataloğu: 120 prosedürel efekt + 120 hareketli ikon + 12 rozet.
-- Tek renderer, config varyasyonlarıyla yüzlerce seçenek üretir; yeni kayıt
-- eklemek için Flutter kodunu değiştirmek gerekmez.
-- -----------------------------------------------------------------------------
with effect_base(renderer_key, title, description, color1, color2, base_priority) as (
  values
    ('lightning', 'Şimşek', 'Profil üzerinde hareketli şimşek parlamaları', '#FFD740', '#FFFFFF', 90),
    ('rain', 'Yağmur', 'Hareketli yağmur damlaları', '#42A5F5', '#B3E5FC', 80),
    ('blink', 'Profil Açılıp Kapanma', 'Profile ritmik görünme ve parlama efekti', '#7E57C2', '#FFFFFF', 70),
    ('rotate', 'Dönen Profil', 'Profil çevresinde dönen enerji parçacıkları', '#AB47BC', '#EC407A', 75),
    ('sparkle', 'Yıldız Tozu', 'Parlayan yıldız parçacıkları', '#FFCA28', '#FFF59D', 85),
    ('snow', 'Kar', 'Yumuşak kar taneleri', '#E1F5FE', '#FFFFFF', 60),
    ('hearts', 'Kalpler', 'Yükselen hareketli kalpler', '#EC407A', '#F8BBD0', 65),
    ('bubbles', 'Baloncuklar', 'Yükselen renkli baloncuklar', '#26C6DA', '#B2EBF2', 55),
    ('fireflies', 'Ateş Böcekleri', 'Gezinen sıcak ışık noktaları', '#CDDC39', '#FFF176', 58),
    ('confetti', 'Konfeti', 'Kutlama konfeti yağmuru', '#FF7043', '#7E57C2', 88),
    ('matrix', 'Dijital Akış', 'Dijital çizgi ve sembol akışı', '#00E676', '#1B5E20', 50),
    ('aurora', 'Aurora', 'Dalgalanan renkli ışık halesi', '#00BFA5', '#7C4DFF', 72)
), variants as (select generate_series(1, 10) as n)
insert into public.profile_feature_catalog
  (code, kind, name, description, renderer_key, primary_color, secondary_color, config, priority)
select
  'effect_' || e.renderer_key || '_' || lpad(v.n::text, 2, '0'),
  'effect', e.title || ' ' || v.n, e.description, e.renderer_key,
  e.color1, e.color2,
  jsonb_build_object(
    'intensity', 1 + ((v.n - 1) % 4),
    'speed', (0.55 + v.n * 0.12)::numeric(4,2),
    'size', (0.70 + ((v.n - 1) % 5) * 0.16)::numeric(4,2),
    'variant', v.n
  ),
  e.base_priority + v.n
from effect_base e cross join variants v
on conflict (code) do nothing;

with icon_base(renderer_key, title, description, glyph, color1) as (
  values
    ('fan', 'Vantilatör', 'Dönen vantilatör simgesi', 'fan', '#29B6F6'),
    ('bolt', 'Şimşek', 'Enerjik şimşek simgesi', 'bolt', '#FFD740'),
    ('crown', 'Taç', 'Ayrıcalıklı taç simgesi', 'crown', '#FFC107'),
    ('diamond', 'Elmas', 'Parlayan elmas simgesi', 'diamond', '#26C6DA'),
    ('rocket', 'Roket', 'Hareketli roket simgesi', 'rocket', '#FF7043'),
    ('star', 'Yıldız', 'Dönen yıldız simgesi', 'star', '#FFCA28'),
    ('heart', 'Kalp', 'Atan kalp simgesi', 'heart', '#EC407A'),
    ('fire', 'Ateş', 'Canlı ateş simgesi', 'fire', '#FF5722'),
    ('shield', 'Kalkan', 'Güven kalkanı simgesi', 'shield', '#5C6BC0'),
    ('music', 'Müzik', 'Dans eden müzik simgesi', 'music', '#AB47BC'),
    ('game', 'Oyuncu', 'Hareketli oyun simgesi', 'game', '#66BB6A'),
    ('camera', 'Kamera', 'İçerik üretici kamerası', 'camera', '#78909C'),
    ('palette', 'Sanatçı', 'Dönen palet simgesi', 'palette', '#FF8A65'),
    ('planet', 'Gezegen', 'Yörüngeli gezegen simgesi', 'planet', '#7E57C2'),
    ('sun', 'Güneş', 'Dönen güneş simgesi', 'sun', '#FFA726'),
    ('moon', 'Ay', 'Salınan ay simgesi', 'moon', '#7986CB'),
    ('flower', 'Çiçek', 'Dönen çiçek simgesi', 'flower', '#F06292'),
    ('coffee', 'Kahve', 'Sıcak kahve simgesi', 'coffee', '#8D6E63'),
    ('verified_user', 'Güvenilir', 'Güvenilir kullanıcı simgesi', 'verified_user', '#42A5F5'),
    ('local_hero', 'Yerel Kahraman', 'Yerel kahraman simgesi', 'local_hero', '#26A69A')
), variants as (select generate_series(1, 6) as n),
palette(colors) as (values (array['#2196F3','#4CAF50','#F44336','#9C27B0','#FF9800','#00BCD4']::text[]))
insert into public.profile_feature_catalog
  (code, kind, name, description, renderer_key, primary_color, secondary_color, config, priority)
select
  'icon_' || i.renderer_key || '_' || lpad(v.n::text, 2, '0'),
  'icon', i.title || ' ' || v.n, i.description, i.renderer_key,
  p.colors[v.n], i.color1,
  jsonb_build_object(
    'glyph', i.glyph,
    'speed', (0.65 + v.n * 0.18)::numeric(4,2),
    'motion', case ((v.n - 1) % 4)
      when 0 then 'rotate' when 1 then 'pulse' when 2 then 'bounce' else 'swing' end,
    'variant', v.n
  ),
  40 + v.n
from icon_base i cross join variants v cross join palette p
on conflict (code) do nothing;

with badges(code, name, description, renderer_key, color1, color2, priority) as (
  values
    ('badge_blue_verified', 'Mavi Tik', 'Kimliği doğrulanmış kullanıcı', 'verified', '#2196F3', '#64B5F6', 200),
    ('badge_green_trusted', 'Yeşil Tik', 'Güvenilir kullanıcı', 'verified', '#43A047', '#81C784', 199),
    ('badge_red_official', 'Kırmızı Tik', 'Resmî veya özel hesap', 'verified', '#E53935', '#EF5350', 198),
    ('badge_purple_creator', 'Mor Tik', 'İçerik üreticisi', 'verified', '#8E24AA', '#BA68C8', 197),
    ('badge_orange_business', 'Turuncu Tik', 'Doğrulanmış işletme', 'verified', '#FB8C00', '#FFB74D', 196),
    ('badge_cyan_supporter', 'Turkuaz Tik', 'Topluluk destekçisi', 'verified', '#00ACC1', '#4DD0E1', 195),
    ('badge_pink_star', 'Pembe Tik', 'Öne çıkan hesap', 'verified', '#D81B60', '#F06292', 194),
    ('badge_gold_vip', 'Altın Tik', 'VIP kullanıcı', 'verified', '#F9A825', '#FFD54F', 210),
    ('badge_black_elite', 'Siyah Tik', 'Elit hesap', 'verified', '#263238', '#607D8B', 209),
    ('badge_white_partner', 'Beyaz Tik', 'Onaylı iş ortağı', 'verified', '#ECEFF1', '#B0BEC5', 193),
    ('badge_indigo_expert', 'Lacivert Tik', 'Alanında uzman kullanıcı', 'verified', '#3949AB', '#7986CB', 192),
    ('badge_lime_new', 'Limon Tik', 'Yeni seçkin kullanıcı', 'verified', '#9E9D24', '#DCE775', 191)
)
insert into public.profile_feature_catalog
  (code, kind, name, description, renderer_key, primary_color, secondary_color, config, priority)
select code, 'badge', name, description, renderer_key, color1, color2,
  jsonb_build_object('shape', 'check', 'animated', true), priority
from badges
on conflict (code) do nothing;

commit;

-- Kontrol sorgusu (migration sonrası):
-- select kind, count(*) from public.profile_feature_catalog group by kind;
-- Beklenen: effect=120, icon=120, badge=12

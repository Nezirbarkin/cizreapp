-- =============================================================================
-- Gönderi istatistikleri (görüntülenme) + düzenleme işareti (2026-10-24)
--
-- 1) Görüntülenme = AKIŞTA GÖRÜLME: kişi başına günde bir (Europe/Istanbul),
--    kendi gönderisi sayılmaz. Olaylar post_impressions'ta (PK üçlü = tekil),
--    sayaç AYRI post_stats tablosunda: posts realtime yayınında ve
--    update_posts_updated_at her UPDATE'te çalıştığı için her gösterimde posts
--    satırı güncellenmez (WAL/realtime yükü, updated_at ezilmesi yok).
--    Yazma yalnız record_post_impressions(uuid[]) DEFINER RPC'si ile (toplu).
-- 2) get_post_insights(uuid): yalnız sahip / admin — gösterim, benzersiz kişi,
--    detay açılışı, beğeni, yorum, paylaşım, kaydetme, etkileşim oranı,
--    takipçi dışı erişim, son 7 gün.
-- 3) posts.edited_at: içerik değişince sunucu damgalar (b_posts_mark_edited);
--    istemci yazamaz (guard_posts_client_write).
-- 4) posts_with_profiles SONUNA views_count + edited_at; public_explore_feed ve
--    public_post_by_id aynı iki sütunla yeniden (canlı tanımlar birebir korundu).
-- 5) Geri doldurma: post_views'teki (gönderi, izleyen, gün) tekilleri.
-- 6) Ölü public.increment_post_view(uuid) kaldırılır (posts.views_count'a yazmaya
--    çalışıyordu; sütun yoktu, Dart'ta çağıran yok).
-- =============================================================================

begin;

set local lock_timeout = '10s';

-- -----------------------------------------------------------------------------
-- 1) Gösterim tabloları
-- -----------------------------------------------------------------------------
create table if not exists public.post_impressions (
  post_id    uuid not null references public.posts (id) on delete cascade,
  viewer_id  uuid not null references auth.users (id) on delete cascade,
  day        date not null,
  created_at timestamptz not null default now(),
  primary key (post_id, viewer_id, day)
);

create index if not exists idx_post_impressions_viewer
  on public.post_impressions (viewer_id);

alter table public.post_impressions enable row level security;
revoke all on public.post_impressions from public, anon, authenticated;

comment on table public.post_impressions is
  'Gönderi gösterimleri: kişi başı günde bir. Yalnız record_post_impressions yazar.';

create table if not exists public.post_stats (
  post_id     uuid primary key references public.posts (id) on delete cascade,
  views_count bigint not null default 0,
  updated_at  timestamptz not null default now()
);

alter table public.post_stats enable row level security;
revoke all on public.post_stats from public, anon, authenticated;
grant select on public.post_stats to anon, authenticated;

drop policy if exists post_stats_select on public.post_stats;
create policy post_stats_select on public.post_stats
  for select to anon, authenticated using (true);

comment on table public.post_stats is
  'Gönderi başına görüntülenme sayacı (posts realtime yükünü ve updated_at''i etkilemesin diye ayrı).';

-- -----------------------------------------------------------------------------
-- 2) Gösterim kaydı (toplu)
-- -----------------------------------------------------------------------------
create or replace function public.record_post_impressions(p_post_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_uid uuid := auth.uid();
  v_day date := (now() at time zone 'Europe/Istanbul')::date;
  v_n   integer := 0;
begin
  if v_uid is null or p_post_ids is null or cardinality(p_post_ids) = 0 then
    return 0;
  end if;

  with ids as (
    select distinct x as post_id
    from unnest(p_post_ids[1:50]) as x
    where x is not null
  ), ok as (
    select p.id
    from ids
    join public.posts p on p.id = ids.post_id
    where p.is_active
      and p.user_id is distinct from v_uid
      and public.can_view_social_author(p.user_id)
  ), ins as (
    insert into public.post_impressions (post_id, viewer_id, day)
    select ok.id, v_uid, v_day from ok
    on conflict do nothing
    returning post_id
  ), up as (
    insert into public.post_stats as s (post_id, views_count, updated_at)
    select ins.post_id, 1, now() from ins
    on conflict (post_id) do update
      set views_count = s.views_count + 1, updated_at = now()
    returning 1
  )
  select count(*) into v_n from up;

  return v_n;
end;
$fn$;

revoke all on function public.record_post_impressions(uuid[]) from public, anon;
grant execute on function public.record_post_impressions(uuid[]) to authenticated;

comment on function public.record_post_impressions(uuid[]) is
  'Akışta görülen gönderiler (en çok 50): kişi başı günde bir sayılır, kendi gönderisi ve göremeyeceği yazar hariç. Yeni sayılan adet döner.';

-- -----------------------------------------------------------------------------
-- 3) Sahibe özel istatistik
-- -----------------------------------------------------------------------------
create or replace function public.get_post_insights(p_post_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_uid       uuid := auth.uid();
  v_today     date := (now() at time zone 'Europe/Istanbul')::date;
  v_post      record;
  v_views     bigint;
  v_unique    bigint;
  v_followers bigint;
  v_detail    bigint;
  v_saves     bigint;
  v_engaged   bigint;
  v_daily     jsonb;
begin
  if v_uid is null then
    raise exception 'Oturum açmanız gerekiyor' using errcode = '42501';
  end if;

  select p.id, p.user_id, p.created_at,
         coalesce(p.likes_count, 0)    as likes,
         coalesce(p.comments_count, 0) as comments,
         coalesce(p.shares_count, 0)   as shares
    into v_post
  from public.posts p
  where p.id = p_post_id;

  if not found then
    raise exception 'Gönderi bulunamadı' using errcode = 'P0002';
  end if;
  if v_post.user_id is distinct from v_uid and not public.social_is_admin() then
    raise exception 'Bu gönderinin istatistiklerini yalnız sahibi görebilir' using errcode = '42501';
  end if;

  select coalesce((select s.views_count from public.post_stats s where s.post_id = p_post_id), 0)
    into v_views;

  select count(distinct i.viewer_id),
         count(distinct i.viewer_id) filter (
           where exists (
             select 1 from public.follows f
             where f.follower_id = i.viewer_id and f.following_id = v_post.user_id))
    into v_unique, v_followers
  from public.post_impressions i
  where i.post_id = p_post_id;

  select count(*) into v_detail from public.post_views v where v.post_id = p_post_id;
  select count(*) into v_saves  from public.post_favorites f where f.post_id = p_post_id;

  select coalesce(jsonb_agg(jsonb_build_object('day', d.day, 'views', coalesce(c.n, 0)) order by d.day), '[]'::jsonb)
    into v_daily
  from (select v_today - g as day from generate_series(0, 6) as g) d
  left join (
    select i.day, count(*) as n
    from public.post_impressions i
    where i.post_id = p_post_id and i.day >= v_today - 6
    group by i.day
  ) c on c.day = d.day;

  v_engaged := v_post.likes + v_post.comments + v_post.shares + v_saves;

  return jsonb_build_object(
    'views',            v_views,
    'unique_viewers',   v_unique,
    'detail_opens',     v_detail,
    'likes',            v_post.likes,
    'comments',         v_post.comments,
    'shares',           v_post.shares,
    'saves',            v_saves,
    'follower_viewers', v_followers,
    'engagement_rate',  case when v_unique > 0
                          then round(least(v_engaged::numeric * 100 / v_unique, 100), 1)
                        end,
    'non_follower_rate', case when v_unique > 0
                          then round((v_unique - v_followers)::numeric * 100 / v_unique, 1)
                        end,
    'daily',            v_daily,
    'created_at',       v_post.created_at
  );
end;
$fn$;

revoke all on function public.get_post_insights(uuid) from public, anon;
grant execute on function public.get_post_insights(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- 4) Düzenleme işareti
-- -----------------------------------------------------------------------------
alter table public.posts add column if not exists edited_at timestamptz;

comment on column public.posts.edited_at is
  'İçeriğin son düzenlendiği an (b_posts_mark_edited); istemci yazamaz.';

CREATE OR REPLACE FUNCTION public.guard_posts_client_write()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
BEGIN
  -- INVOKER: DEFINER sayaç tetikleyicilerinde current_user sahip olur.
  IF current_user NOT IN ('authenticated', 'anon') OR public.social_is_admin() THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    NEW.admin_pinned   := false;
    NEW.likes_count    := 0;
    NEW.comments_count := 0;
    NEW.shares_count   := 0;
    NEW.created_at     := now();
    NEW.edited_at      := NULL;
  ELSE
    NEW.admin_pinned   := OLD.admin_pinned;
    NEW.likes_count    := OLD.likes_count;
    NEW.comments_count := OLD.comments_count;
    NEW.shares_count   := OLD.shares_count;
    NEW.created_at     := OLD.created_at;
    NEW.edited_at      := OLD.edited_at;
  END IF;

  RETURN NEW;
END;
$function$;

-- "a_" önekli koruma tetikleyicisinden SONRA çalışır (ad sırası).
create or replace function public.posts_mark_edited()
returns trigger
language plpgsql
set search_path = ''
as $fn$
begin
  if NEW.content is distinct from OLD.content then
    NEW.edited_at := now();
  end if;
  return NEW;
end;
$fn$;

drop trigger if exists b_posts_mark_edited on public.posts;
create trigger b_posts_mark_edited
  before update of content on public.posts
  for each row execute function public.posts_mark_edited();

-- -----------------------------------------------------------------------------
-- 5) Üye akışı görünümü: sona views_count + edited_at
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.posts_with_profiles
WITH (security_invoker = true) AS
 SELECT p.id,
    p.user_id,
    p.content,
    p.images,
    p.location,
    p.latitude,
    p.longitude,
    p.likes_count,
    p.comments_count,
    p.shares_count,
    p.is_active,
    p.created_at,
    p.updated_at,
    p.image_url,
    p.is_pinned,
    p.admin_pinned,
    p.background,
    p.music,
    p.image_aspect_ratio,
    pr.username,
    pr.full_name,
    pr.avatar_url,
    pr.is_ghost_mode AS author_is_ghost_mode,
    pr.profile_is_public AS author_profile_public,
    pr.status AS author_status,
    pr.is_verified AS author_is_verified,
    NULL::text AS author_role,
    NULL::boolean AS author_is_admin,
    pr.id IS NOT NULL AS author_profile_exists,
    COALESCE(ps.views_count, 0)::integer AS views_count,
    p.edited_at
   FROM public.posts p
     LEFT JOIN public.profiles pr ON pr.id = p.user_id
     LEFT JOIN public.post_stats ps ON ps.post_id = p.id
  WHERE p.is_active = true;

-- -----------------------------------------------------------------------------
-- 6) Misafir akışı ve paylaşılan gönderi: aynı iki sütun (dönüş tipi değişti)
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.public_explore_feed(integer, integer);

CREATE FUNCTION public.public_explore_feed(p_limit integer DEFAULT 20, p_offset integer DEFAULT 0)
 RETURNS TABLE(id uuid, user_id uuid, content text, images text[], image_aspect_ratio real, background text, music jsonb, location text, latitude numeric, longitude numeric, likes_count integer, comments_count integer, shares_count integer, is_active boolean, created_at timestamp with time zone, updated_at timestamp with time zone, image_url text, is_pinned boolean, admin_pinned boolean, username text, full_name text, avatar_url text, author_profile_exists boolean, views_count integer, edited_at timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_limit integer := LEAST(GREATEST(COALESCE(p_limit, 20), 1), 50);
  v_offset integer := GREATEST(COALESCE(p_offset, 0), 0);
  -- Anahtar kapalıysa müzik okunmaz. STABLE olduğu için sorgu başına bir kez
  -- değerlendirilir, satır başına değil.
  v_music boolean := public.music_flag('music_feature_enabled', true)
                 AND public.music_flag('music_attach_enabled', true);
BEGIN
  -- Sunucu tarafı kapı: ayar kapalıysa hiçbir şey dönmez.
  IF NOT COALESCE(
       (SELECT NULLIF(btrim(s.value #>> '{}'), '')::boolean
          FROM public.app_settings s WHERE s.key = 'explore_public_access'),
       false
     ) THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    po.id, po.user_id, po.content, po.images, po.image_aspect_ratio,
    po.background,
    CASE WHEN v_music THEN po.music ELSE NULL::jsonb END,
    po.location,
    po.latitude, po.longitude,
    COALESCE(po.likes_count, 0), COALESCE(po.comments_count, 0),
    COALESCE(po.shares_count, 0),
    COALESCE(po.is_active, true), po.created_at, po.updated_at,
    po.image_url, COALESCE(po.is_pinned, false), COALESCE(po.admin_pinned, false),
    pr.username, pr.full_name, pr.avatar_url,
    (pr.id IS NOT NULL),
    COALESCE(ps.views_count, 0)::integer, po.edited_at
  FROM public.posts po
  LEFT JOIN public.profiles pr ON pr.id = po.user_id
  LEFT JOIN public.post_stats ps ON ps.post_id = po.id
  WHERE po.is_active = true
    -- Gizli hesapların gönderileri misafire kapalıdır (üye tarafındaki
    -- can_view_social_author() kuralının misafir karşılığı).
    AND COALESCE(pr.profile_is_public, true) = true
    AND COALESCE(pr.is_ghost_mode, false) = false
    AND COALESCE(pr.status, 'active'::public.user_status)
        <> 'deleted'::public.user_status
  ORDER BY COALESCE(po.admin_pinned, false) DESC, po.created_at DESC
  LIMIT v_limit OFFSET v_offset;
END;
$function$;

REVOKE ALL ON FUNCTION public.public_explore_feed(integer, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.public_explore_feed(integer, integer)
  TO anon, authenticated, service_role;

DROP FUNCTION IF EXISTS public.public_post_by_id(uuid);

CREATE FUNCTION public.public_post_by_id(p_post_id uuid)
 RETURNS TABLE(id uuid, user_id uuid, content text, images text[], image_aspect_ratio real, background text, music jsonb, location text, latitude numeric, longitude numeric, likes_count integer, comments_count integer, shares_count integer, is_active boolean, created_at timestamp with time zone, updated_at timestamp with time zone, image_url text, is_pinned boolean, admin_pinned boolean, username text, full_name text, avatar_url text, author_profile_exists boolean, views_count integer, edited_at timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_music boolean := public.music_flag('music_feature_enabled', true)
                 AND public.music_flag('music_attach_enabled', true);
BEGIN
  -- Keşfet misafire kapalıysa paylaşılan gönderi de kapalı (aynı kapı).
  IF NOT COALESCE(
       (SELECT NULLIF(btrim(s.value #>> '{}'), '')::boolean
          FROM public.app_settings s WHERE s.key = 'explore_public_access'),
       false
     ) THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    po.id, po.user_id, po.content, po.images, po.image_aspect_ratio,
    po.background,
    CASE WHEN v_music THEN po.music ELSE NULL::jsonb END,
    po.location,
    po.latitude, po.longitude,
    COALESCE(po.likes_count, 0), COALESCE(po.comments_count, 0),
    COALESCE(po.shares_count, 0),
    COALESCE(po.is_active, true), po.created_at, po.updated_at,
    po.image_url, COALESCE(po.is_pinned, false), COALESCE(po.admin_pinned, false),
    pr.username, pr.full_name, pr.avatar_url,
    (pr.id IS NOT NULL),
    COALESCE(ps.views_count, 0)::integer, po.edited_at
  FROM public.posts po
  LEFT JOIN public.profiles pr ON pr.id = po.user_id
  LEFT JOIN public.post_stats ps ON ps.post_id = po.id
  WHERE po.id = p_post_id
    AND po.is_active = true
    AND COALESCE(pr.profile_is_public, true) = true
    AND COALESCE(pr.is_ghost_mode, false) = false
    AND COALESCE(pr.status, 'active'::public.user_status)
        <> 'deleted'::public.user_status;
END;
$function$;

REVOKE ALL ON FUNCTION public.public_post_by_id(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.public_post_by_id(uuid)
  TO anon, authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 7) Geri doldurma (detay açılışları = ilk gösterimler)
-- -----------------------------------------------------------------------------
insert into public.post_impressions (post_id, viewer_id, day, created_at)
select v.post_id, v.viewer_id, v.view_date, coalesce(min(v.viewed_at), now())
from public.post_views v
join public.posts p on p.id = v.post_id
join auth.users u on u.id = v.viewer_id
where v.viewer_id is not null
  and v.view_date is not null
  and v.viewer_id is distinct from p.user_id
group by v.post_id, v.viewer_id, v.view_date
on conflict do nothing;

insert into public.post_stats (post_id, views_count, updated_at)
select i.post_id, count(*), now()
from public.post_impressions i
group by i.post_id
on conflict (post_id) do update set views_count = excluded.views_count, updated_at = now();

-- -----------------------------------------------------------------------------
-- 8) Ölü RPC
-- -----------------------------------------------------------------------------
drop function if exists public.increment_post_view(uuid);

commit;

notify pgrst, 'reload schema';

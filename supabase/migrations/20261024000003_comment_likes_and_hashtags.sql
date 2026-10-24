-- =============================================================================
-- Yorum beğenisi + #etiket (2026-10-24)
--
-- 1) post_comment_likes: kişi başı yorum başına bir beğeni; sayaç
--    post_comments.likes_count DEFINER tetikleyiciyle tutulur, istemci
--    yazamaz (a_post_comments_guard_client_write — yorum sahibi UPDATE
--    yapabildiği için şart). Yorum sahibine 'comment_like' bildirimi
--    (kendine yok, beğeni tercihi kapalıysa yok, aynı kişi 24 saatte bir;
--    entity_id = gönderi → mevcut gönderi yönlendirmesi çalışır).
-- 2) #etiket: public.social_fold_tr (Türkçe katlama: I/İ/ı → i) istemcideki
--    lib/core/utils/hashtags.dart ile AYNI kurallar. posts_by_hashtag ve
--    trending_hashtags INVOKER (posts_with_profiles RLS'i: gizli hesap /
--    engel süzülür) ve jsonb döner — görünümün satır tipine bağımlılık
--    yaratmaz (posts kolonu eklerken görünüm rahatça yeniden yazılır).
-- =============================================================================

begin;

set local lock_timeout = '10s';

-- -----------------------------------------------------------------------------
-- 1) Yorum beğenisi
-- -----------------------------------------------------------------------------
alter table public.post_comments
  add column if not exists likes_count integer not null default 0;

create table if not exists public.post_comment_likes (
  comment_id uuid not null references public.post_comments (id) on delete cascade,
  user_id    uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (comment_id, user_id)
);

create index if not exists idx_post_comment_likes_user
  on public.post_comment_likes (user_id);

alter table public.post_comment_likes enable row level security;
revoke all on public.post_comment_likes from public, anon, authenticated;
grant select, insert, delete on public.post_comment_likes to authenticated;

drop policy if exists post_comment_likes_select on public.post_comment_likes;
create policy post_comment_likes_select on public.post_comment_likes
  for select to authenticated
  using (exists (select 1 from public.post_comments c where c.id = comment_id));

drop policy if exists post_comment_likes_insert on public.post_comment_likes;
create policy post_comment_likes_insert on public.post_comment_likes
  for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and exists (
      select 1 from public.post_comments c
      where c.id = comment_id
        and (c.user_id is null or not public.social_block_exists(c.user_id))
    )
  );

drop policy if exists post_comment_likes_delete on public.post_comment_likes;
create policy post_comment_likes_delete on public.post_comment_likes
  for delete to authenticated
  using (user_id = (select auth.uid()));

-- Sayaç (DEFINER: koruma tetikleyicisine takılmaz).
create or replace function public.post_comment_likes_count()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
begin
  if TG_OP = 'INSERT' then
    update public.post_comments
       set likes_count = likes_count + 1
     where id = NEW.comment_id;
    return NEW;
  end if;
  update public.post_comments
     set likes_count = greatest(likes_count - 1, 0)
   where id = OLD.comment_id;
  return OLD;
end;
$fn$;

drop trigger if exists post_comment_likes_count_trg on public.post_comment_likes;
create trigger post_comment_likes_count_trg
  after insert or delete on public.post_comment_likes
  for each row execute function public.post_comment_likes_count();

-- İstemci sayaç / sahiplik / bağlam sütunlarını yazamaz.
create or replace function public.guard_post_comments_client_write()
returns trigger
language plpgsql
set search_path = ''
as $fn$
begin
  -- INVOKER: DEFINER sayaç tetikleyicilerinde current_user sahip olur.
  if current_user not in ('authenticated', 'anon') or public.social_is_admin() then
    return NEW;
  end if;

  if TG_OP = 'INSERT' then
    NEW.likes_count := 0;
  else
    NEW.likes_count       := OLD.likes_count;
    NEW.post_id           := OLD.post_id;
    NEW.user_id           := OLD.user_id;
    NEW.parent_comment_id := OLD.parent_comment_id;
    NEW.created_at        := OLD.created_at;
  end if;
  return NEW;
end;
$fn$;

drop trigger if exists a_post_comments_guard_client_write on public.post_comments;
create trigger a_post_comments_guard_client_write
  before insert or update on public.post_comments
  for each row execute function public.guard_post_comments_client_write();

-- Yorum sahibine bildirim. Hata beğeniyi engellemez.
create or replace function public.notify_comment_like()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_owner   uuid;
  v_post    uuid;
  v_content text;
  v_name    text;
  v_avatar  text;
begin
  begin
    select c.user_id, c.post_id, c.content
      into v_owner, v_post, v_content
    from public.post_comments c
    where c.id = NEW.comment_id;

    if v_owner is null or v_owner = NEW.user_id or v_post is null then
      return NEW;
    end if;

    if exists (select 1 from public.profiles p where p.id = v_owner and p.is_bot = true) then
      return NEW;
    end if;

    if exists (
      select 1 from public.notification_preferences np
      where np.user_id = v_owner and np.likes_enabled = false
    ) then
      return NEW;
    end if;

    -- Beğen → geri al → beğen döngüsü: 24 saatte bir.
    if exists (
      select 1 from public.notifications n
      where n.user_id = v_owner
        and n.type = 'comment_like'
        and n.actor_id = NEW.user_id
        and n.metadata ->> 'comment_id' = NEW.comment_id::text
        and n.created_at > now() - interval '24 hours'
    ) then
      return NEW;
    end if;

    select coalesce(nullif(p.full_name, ''), p.username), p.avatar_url
      into v_name, v_avatar
    from public.profiles p
    where p.id = NEW.user_id;

    insert into public.notifications (
      user_id, type, title, content, actor_id, actor_name, actor_avatar,
      entity_id, metadata, is_read, created_at
    ) values (
      v_owner, 'comment_like',
      coalesce(v_name, 'Biri') || ' yorumunu beğendi',
      '"' || left(coalesce(v_content, ''), 80) || '"',
      NEW.user_id, v_name, v_avatar,
      v_post::text,
      jsonb_build_object('comment_id', NEW.comment_id, 'post_id', v_post),
      false, now()
    );
  exception when others then
    raise warning 'notify_comment_like(%): % (%)', NEW.comment_id, SQLERRM, SQLSTATE;
  end;
  return NEW;
end;
$fn$;

drop trigger if exists notify_comment_like_trg on public.post_comment_likes;
create trigger notify_comment_like_trg
  after insert on public.post_comment_likes
  for each row execute function public.notify_comment_like();

revoke all on function public.post_comment_likes_count() from public, anon, authenticated;
revoke all on function public.notify_comment_like() from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- 2) #etiket
-- -----------------------------------------------------------------------------
-- Türkçe katlama: I, İ, ı → i; kalan büyük harfler küçülür.
create or replace function public.social_fold_tr(p text)
returns text
language sql
immutable
parallel safe
set search_path = ''
as $fn$
  select lower(translate(coalesce(p, ''), 'IİıÇĞÖŞÜ', 'iiiçğöşü'));
$fn$;

grant execute on function public.social_fold_tr(text) to anon, authenticated, service_role;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_trgm') then
    execute format(
      'create index if not exists idx_posts_content_fold_trgm on public.posts using gin (public.social_fold_tr(content) %I.gin_trgm_ops)',
      (select n.nspname from pg_extension e join pg_namespace n on n.oid = e.extnamespace where e.extname = 'pg_trgm')
    );
  end if;
end;
$$;

-- Etiketli gönderiler (yeniden eskiye). Geçersiz etiket → boş liste.
create or replace function public.posts_by_hashtag(
  p_tag    text,
  p_limit  integer default 20,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $fn$
declare
  v_tag text := public.social_fold_tr(btrim(coalesce(p_tag, ''), '# '));
begin
  if v_tag !~ '^[0-9a-zçğıöşü_]{2,40}$' then
    return '[]'::jsonb;
  end if;

  return coalesce((
    select jsonb_agg(to_jsonb(x) order by x.created_at desc)
    from (
      select p.*
      from public.posts_with_profiles p
      where public.social_fold_tr(p.content)
            ~ ('(^|[^0-9a-zçğıöşü_/])#' || v_tag || '($|[^0-9a-zçğıöşü_])')
      order by p.created_at desc
      limit least(greatest(coalesce(p_limit, 20), 1), 50)
      offset greatest(coalesce(p_offset, 0), 0)
    ) x
  ), '[]'::jsonb);
end;
$fn$;

-- Son günlerin en çok kullanılan etiketleri: [{tag, posts}].
create or replace function public.trending_hashtags(
  p_days  integer default 7,
  p_limit integer default 10
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $fn$
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object('tag', t.tag, 'posts', t.n) order by t.n desc, t.tag)
    from (
      select m[1] as tag, count(distinct p.id) as n
      from public.posts_with_profiles p
      cross join lateral regexp_matches(
        public.social_fold_tr(p.content),
        '(?:^|[^0-9a-zçğıöşü_/])#([0-9a-zçğıöşü_]{2,40})',
        'g'
      ) as m
      where p.created_at > now() - make_interval(days => least(greatest(coalesce(p_days, 7), 1), 90))
      group by m[1]
      order by count(distinct p.id) desc, m[1]
      limit least(greatest(coalesce(p_limit, 10), 1), 30)
    ) t
  ), '[]'::jsonb);
end;
$fn$;

revoke all on function public.posts_by_hashtag(text, integer, integer) from public;
revoke all on function public.trending_hashtags(integer, integer) from public;
revoke all on function public.posts_by_hashtag(text, integer, integer) from anon;
revoke all on function public.trending_hashtags(integer, integer) from anon;
grant execute on function public.posts_by_hashtag(text, integer, integer) to authenticated, service_role;
grant execute on function public.trending_hashtags(integer, integer) to authenticated, service_role;

commit;

notify pgrst, 'reload schema';

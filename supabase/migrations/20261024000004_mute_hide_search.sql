-- =============================================================================
-- Sessize alma + gönderi gizleme + gönderi araması (2026-10-24)
--
-- 1) muted_users: sessize aldığın kişinin gönderileri ve hikâyeleri akışta
--    görünmez; profili, mesajları ve bildirimleri etkilenmez (engellemeden
--    farkı: karşı taraf hiçbir şey fark etmez).
-- 2) hidden_posts: "Gönderiyi gizle" / "İlgilenmiyorum" — yalnız senin akışından.
-- 3) feed_posts_with_profiles: akış SUNUCUDA süzülür (istemcide süzmek
--    sayfalamayı bozardı: dolu sayfa < sayfa boyu = "son"). Üye akışı bu
--    görünümden okur; profil sayfası posts_with_profiles'tan (süzülmez).
--    DİKKAT: p.* oluşturulurken genişler → posts_with_profiles'a kolon
--    eklenen her göçte bu görünüm de yeniden yaratılmalı.
-- 4) search_posts: gönderi metninde arama (Türkçe katlamalı; trigram indeksi
--    idx_posts_content_fold_trgm kullanılır), INVOKER → gizli hesap / engel
--    RLS'te süzülür; jsonb döner.
-- =============================================================================

begin;

set local lock_timeout = '10s';

-- -----------------------------------------------------------------------------
-- 1) Sessize alınanlar
-- -----------------------------------------------------------------------------
create table if not exists public.muted_users (
  muter_id   uuid not null references auth.users (id) on delete cascade,
  muted_id   uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (muter_id, muted_id),
  check (muter_id <> muted_id)
);

alter table public.muted_users enable row level security;
revoke all on public.muted_users from public, anon, authenticated;
grant select, insert, delete on public.muted_users to authenticated;

drop policy if exists muted_users_select_own on public.muted_users;
create policy muted_users_select_own on public.muted_users
  for select to authenticated using (muter_id = (select auth.uid()));

drop policy if exists muted_users_insert_own on public.muted_users;
create policy muted_users_insert_own on public.muted_users
  for insert to authenticated with check (muter_id = (select auth.uid()));

drop policy if exists muted_users_delete_own on public.muted_users;
create policy muted_users_delete_own on public.muted_users
  for delete to authenticated using (muter_id = (select auth.uid()));

-- -----------------------------------------------------------------------------
-- 2) Gizlenen gönderiler
-- -----------------------------------------------------------------------------
create table if not exists public.hidden_posts (
  user_id    uuid not null references auth.users (id) on delete cascade,
  post_id    uuid not null references public.posts (id) on delete cascade,
  reason     text not null default 'hidden' check (reason in ('hidden', 'not_interested')),
  created_at timestamptz not null default now(),
  primary key (user_id, post_id)
);

create index if not exists idx_hidden_posts_post on public.hidden_posts (post_id);

alter table public.hidden_posts enable row level security;
revoke all on public.hidden_posts from public, anon, authenticated;
grant select, insert, delete on public.hidden_posts to authenticated;

drop policy if exists hidden_posts_select_own on public.hidden_posts;
create policy hidden_posts_select_own on public.hidden_posts
  for select to authenticated using (user_id = (select auth.uid()));

drop policy if exists hidden_posts_insert_own on public.hidden_posts;
create policy hidden_posts_insert_own on public.hidden_posts
  for insert to authenticated with check (user_id = (select auth.uid()));

drop policy if exists hidden_posts_delete_own on public.hidden_posts;
create policy hidden_posts_delete_own on public.hidden_posts
  for delete to authenticated using (user_id = (select auth.uid()));

-- -----------------------------------------------------------------------------
-- 3) Süzülmüş akış görünümü
-- -----------------------------------------------------------------------------
drop view if exists public.feed_posts_with_profiles;
create view public.feed_posts_with_profiles
with (security_invoker = true) as
  select p.*
  from public.posts_with_profiles p
  where not exists (
          select 1 from public.muted_users m
          where m.muter_id = (select auth.uid()) and m.muted_id = p.user_id)
    and not exists (
          select 1 from public.hidden_posts h
          where h.user_id = (select auth.uid()) and h.post_id = p.id);

revoke all on public.feed_posts_with_profiles from public, anon, authenticated;
grant select on public.feed_posts_with_profiles to authenticated;

comment on view public.feed_posts_with_profiles is
  'Üye akışı: posts_with_profiles − sessize alınanlar − gizlenen gönderiler. posts_with_profiles kolonları değişince yeniden yaratılmalı.';

-- -----------------------------------------------------------------------------
-- 4) Gönderi araması
-- -----------------------------------------------------------------------------
create or replace function public.search_posts(p_q text, p_limit integer default 20)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $fn$
declare
  v_q text := btrim(coalesce(p_q, ''));
begin
  if char_length(v_q) < 2 then
    return '[]'::jsonb;
  end if;
  v_q := public.social_fold_tr(left(v_q, 100));
  -- LIKE joker karakterleri metin olarak aranır.
  v_q := replace(replace(replace(v_q, '\', '\\'), '%', '\%'), '_', '\_');

  return coalesce((
    select jsonb_agg(to_jsonb(x) order by x.created_at desc)
    from (
      select p.*
      from public.posts_with_profiles p
      where public.social_fold_tr(p.content) like '%' || v_q || '%'
      order by p.created_at desc
      limit least(greatest(coalesce(p_limit, 20), 1), 30)
    ) x
  ), '[]'::jsonb);
end;
$fn$;

revoke all on function public.search_posts(text, integer) from public, anon;
grant execute on function public.search_posts(text, integer) to authenticated, service_role;

commit;

notify pgrst, 'reload schema';

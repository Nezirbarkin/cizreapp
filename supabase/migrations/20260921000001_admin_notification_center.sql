-- =============================================================================
-- 20260921000001_admin_notification_center.sql
-- -----------------------------------------------------------------------------
-- Admin > Bildirimler ekranının yeniden tasarımı için sunucu tarafı.
--
-- ESKİ DURUM
--   * Admin, başkasının `notifications` satırını göremez/değiştiremez/silemez
--     (RLS yalnız sahibine izin verir). Eski ekran bu yüzden yalnız
--     admin_broadcasts'ı listeleyebiliyordu; kişisel gönderimler görünmüyordu,
--     düzenleme ve silme hiç yoktu.
--   * Toplu bildirimin okunma sayısı "1/1" gibi sahte sayılarla gösteriliyordu.
--   * `dedup_notification` + `idx_notifications_user_entity_type` yüzünden aynı
--     kullanıcıya aynı ikonla gönderilen İKİNCİ yönetici bildirimi, birincisini
--     sessizce SİLİYORDU (entity_id = 'admin_icon:<ikon>' hep aynı).
--
-- YENİ DURUM
--   * `admin_notification_campaigns`: her gönderimin tek kaydı (toplu / kişiye
--     özel, gönderildi / zamanlanmış). Alıcı satırları notifications'ta
--     `metadata.campaign_id` ile bağlanır.
--   * Yönetici bildirimleri artık dedup'a girmez (kampanya başına ayrı satır).
--   * Admin RPC'leri: gönder (çoklu alıcı + zamanlama), geçmiş, alıcı listesi,
--     düzenle (istenirse yeniden bildir), sil (toplu), kitle sayısı,
--     zamanlanmışı şimdi gönder. pg_cron her dakika zamanı gelenleri gönderir.
--   * Eski RPC'ler (admin_broadcast_notification, admin_send_personal_notification)
--     imzaları AYNI kalarak yeni kampanya mekanizmasına devredildi; eski admin
--     sürümleri de geçmişte görünür.
--
-- Bu dosya tekrar çalıştırılabilir (idempotent).
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- 1) Kampanya tablosu
-- -----------------------------------------------------------------------------
create table if not exists public.admin_notification_campaigns (
  id              uuid primary key default gen_random_uuid(),
  kind            text not null check (kind in ('broadcast', 'personal')),
  title           text not null,
  content         text not null,
  icon_type       text not null default 'info',
  target_audience text not null check (
    target_audience in ('all_users', 'customers', 'sellers', 'couriers', 'personal')
  ),
  -- Yalnız kişiye özel: seçilen alıcılar (zamanlanmışta gönderim anında kullanılır).
  recipient_ids   uuid[] not null default '{}',
  recipient_count integer not null default 0,
  status          text not null default 'sent' check (status in ('scheduled', 'sent')),
  scheduled_for   timestamptz,
  sent_at         timestamptz,
  created_by      uuid references auth.users(id) on delete set null,
  created_at      timestamptz not null default now(),
  edited_at       timestamptz
);

create index if not exists idx_admin_notif_campaigns_created
  on public.admin_notification_campaigns (created_at desc);
create index if not exists idx_admin_notif_campaigns_due
  on public.admin_notification_campaigns (scheduled_for)
  where status = 'scheduled';

alter table public.admin_notification_campaigns enable row level security;

drop policy if exists "admin_notification_campaigns_select_admin"
  on public.admin_notification_campaigns;
create policy "admin_notification_campaigns_select_admin"
  on public.admin_notification_campaigns
  for select to authenticated
  using ((select public.is_admin()));

-- Yazma yalnız aşağıdaki SECURITY DEFINER RPC'lerle.
revoke all on table public.admin_notification_campaigns from public, anon, authenticated;
grant select on table public.admin_notification_campaigns to authenticated;
grant all on table public.admin_notification_campaigns to service_role;

-- -----------------------------------------------------------------------------
-- 2) Denetim kaydına 'update' ve 'delete' eylemleri
-- -----------------------------------------------------------------------------
do $$
declare
  r record;
begin
  for r in
    select conname
    from pg_constraint
    where conrelid = 'public.admin_notification_audit'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) ilike '%action%'
  loop
    execute format(
      'alter table public.admin_notification_audit drop constraint %I', r.conname
    );
  end loop;
end $$;

alter table public.admin_notification_audit
  add constraint admin_notification_audit_action_check
  check (action in ('personal', 'broadcast', 'update', 'delete'));

-- -----------------------------------------------------------------------------
-- 3) Yönetici bildirimleri dedup'a girmez
--    (entity_id = 'admin_icon:<ikon>' kampanyaya özgü değil; eskiden ikinci
--    bildirim birincisini siliyordu.)
-- -----------------------------------------------------------------------------
drop index if exists public.idx_notifications_user_entity_type;
create unique index idx_notifications_user_entity_type
  on public.notifications (user_id, entity_id, type)
  where entity_id is not null and entity_id not like 'admin\_icon:%';

create or replace function public.dedup_notification()
returns trigger
language plpgsql
set search_path to 'public', 'pg_temp'
as $function$
begin
  -- Yönetici bildirimleri her kampanyada ayrı satırdır; eskisini silme.
  if NEW.entity_id like 'admin\_icon:%' then
    return NEW;
  end if;

  -- Aynı kullanıcı + entity + tip için varolan bildirimi sil. Okunmuş
  -- olsa bile: tekil kısıt (idx_notifications_user_entity_type) yüzünden
  -- eski satır dururken INSERT 23505 veriyor ve eylem geri alınıyordu.
  -- Sil-yenile: tekrar eden eylem bildirimi taze/okunmamış yeniler.
  if NEW.entity_id is not null then
    delete from public.notifications
    where user_id = NEW.user_id
      and entity_id = NEW.entity_id
      and type = NEW.type
      and id != NEW.id;
  end if;

  return NEW;
end;
$function$;

-- -----------------------------------------------------------------------------
-- 4) Yardımcılar (private şema; PostgREST'e açık değil)
-- -----------------------------------------------------------------------------
create or replace function private.admin_notification_guard()
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_admin uuid := auth.uid();
begin
  if v_admin is null or coalesce(auth.role(), '') = 'anon' then
    raise exception 'Oturum açmanız gerekiyor' using errcode = '42501';
  end if;
  if not public.is_admin() then
    raise exception 'Bu işlem için admin yetkisi gereklidir' using errcode = '42501';
  end if;
  return v_admin;
end;
$$;

create or replace function private.admin_notification_icon(p_icon text)
returns text
language sql
immutable
as $$
  select case
    when p_icon in (
      'announcement', 'discount', 'campaign', 'news', 'event',
      'update', 'warning', 'gift', 'info'
    ) then p_icon
    else 'info'
  end
$$;

-- Hedef kitledeki kullanıcılar. Toplu hedeflerde gönderen admin ve botlar hariç.
create or replace function private.admin_notification_recipients(
  p_audience text,
  p_user_ids uuid[],
  p_exclude  uuid
)
returns setof uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select p.id
  from public.profiles p
  where case
    when p_audience = 'personal' then
      p.id = any(coalesce(p_user_ids, '{}'::uuid[]))
    else
      p.id is distinct from p_exclude
      and coalesce(p.is_bot, false) = false
      and (
        p_audience = 'all_users'
        or (p_audience = 'customers' and p.role::text = 'customer')
        or (p_audience = 'sellers'   and p.role::text = 'seller')
        or (p_audience = 'couriers'  and p.role::text in ('courier', 'driver'))
      )
  end
$$;

-- Zamanı gelmiş (ya da hemen gönderilecek) kampanyanın alıcı satırlarını yazar.
-- Idempotent: yalnız 'scheduled' durumundaki kampanya gönderilir.
create or replace function private.admin_dispatch_campaign(p_campaign_id uuid)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  c        public.admin_notification_campaigns%rowtype;
  v_count  integer := 0;
  v_meta   jsonb;
begin
  select * into c
  from public.admin_notification_campaigns
  where id = p_campaign_id
  for update;

  if not found then
    raise exception 'Bildirim kampanyası bulunamadı' using errcode = 'P0002';
  end if;
  if c.status <> 'scheduled' then
    return c.recipient_count;
  end if;

  v_meta := jsonb_build_object(
    'icon_type',   c.icon_type,
    'target',      c.target_audience,
    'campaign_id', c.id
  );

  if c.kind = 'broadcast' then
    v_meta := v_meta || jsonb_build_object('broadcast_id', c.id);
    -- Kullanıcı uygulamasındaki "Duyurular" bölümü bu tablodan okur.
    insert into public.admin_broadcasts (
      id, title, content, icon_type, target_audience, is_active, created_by, created_at
    ) values (
      c.id, c.title, c.content, c.icon_type, c.target_audience, true, c.created_by, now()
    )
    on conflict (id) do nothing;
  end if;

  -- notifications_outbox_trigger bu satırları outbox'a alır → push.
  insert into public.notifications (
    user_id, type, title, content, actor_id, entity_id, metadata, is_read, created_at
  )
  select
    r.uid,
    case when c.kind = 'broadcast' then 'admin_broadcast' else 'admin_notification' end,
    c.title,
    c.content,
    c.created_by,
    'admin_icon:' || c.icon_type,
    v_meta,
    false,
    now()
  from private.admin_notification_recipients(
    c.target_audience, c.recipient_ids, c.created_by
  ) as r(uid);
  get diagnostics v_count = row_count;

  update public.admin_notification_campaigns
     set status = 'sent', sent_at = now(), recipient_count = v_count
   where id = c.id;

  return v_count;
end;
$$;

-- Doğrular, kampanyayı yazar, zamanlanmamışsa hemen gönderir.
create or replace function private.admin_create_campaign(
  p_admin         uuid,
  p_audience      text,
  p_title         text,
  p_content       text,
  p_icon          text,
  p_user_ids      uuid[],
  p_scheduled_for timestamptz
)
returns public.admin_notification_campaigns
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_audience text := coalesce(nullif(btrim(p_audience), ''), 'all_users');
  v_title    text := btrim(coalesce(p_title, ''));
  v_content  text := btrim(coalesce(p_content, ''));
  v_kind     text;
  v_max      integer;
  v_ids      uuid[] := '{}';
  v_found    integer;
  v_when     timestamptz;
  v_row      public.admin_notification_campaigns;
begin
  if v_audience = 'all' then
    v_audience := 'all_users';
  end if;
  if v_audience not in ('all_users', 'customers', 'sellers', 'couriers', 'personal') then
    raise exception 'Geçersiz hedef kitle' using errcode = '22000';
  end if;

  v_kind := case when v_audience = 'personal' then 'personal' else 'broadcast' end;
  v_max  := case when v_kind = 'personal' then 500 else 1000 end;

  if length(v_title) = 0 or length(v_title) > 100 then
    raise exception 'Başlık 1-100 karakter olmalıdır' using errcode = '22000';
  end if;
  if length(v_content) = 0 or length(v_content) > v_max then
    raise exception 'İçerik 1-% karakter olmalıdır', v_max using errcode = '22000';
  end if;

  if v_kind = 'personal' then
    select coalesce(array_agg(distinct u), '{}'::uuid[])
      into v_ids
    from unnest(coalesce(p_user_ids, '{}'::uuid[])) as u;

    if cardinality(v_ids) = 0 then
      raise exception 'En az bir alıcı seçin' using errcode = '22023';
    end if;
    if cardinality(v_ids) > 200 then
      raise exception 'Bir seferde en fazla 200 kişi seçilebilir' using errcode = '22023';
    end if;

    select count(*) into v_found from public.profiles where id = any(v_ids);
    if v_found <> cardinality(v_ids) then
      raise exception 'Alıcı kullanıcı bulunamadı' using errcode = 'P0002';
    end if;
  end if;

  if p_scheduled_for is not null and p_scheduled_for > now() + interval '1 minute' then
    if p_scheduled_for > now() + interval '1 year' then
      raise exception 'Zamanlama en fazla 1 yıl sonrasına yapılabilir' using errcode = '22023';
    end if;
    v_when := p_scheduled_for;
  end if;

  insert into public.admin_notification_campaigns (
    kind, title, content, icon_type, target_audience,
    recipient_ids, status, scheduled_for, created_by
  ) values (
    v_kind, v_title, v_content, private.admin_notification_icon(p_icon), v_audience,
    v_ids, 'scheduled', v_when, p_admin
  )
  returning * into v_row;

  insert into public.admin_notification_audit (
    admin_id, action, target_audience, recipient_id, title, content
  ) values (
    p_admin, case when v_kind = 'personal' then 'personal' else 'broadcast' end,
    v_audience,
    case when cardinality(v_ids) = 1 then v_ids[1] end,
    v_title, v_content
  );

  if v_when is null then
    perform private.admin_dispatch_campaign(v_row.id);
  end if;

  select * into v_row from public.admin_notification_campaigns where id = v_row.id;
  return v_row;
end;
$$;

revoke all on function private.admin_notification_guard() from public, anon, authenticated;
revoke all on function private.admin_notification_icon(text) from public, anon, authenticated;
revoke all on function private.admin_notification_recipients(text, uuid[], uuid)
  from public, anon, authenticated;
revoke all on function private.admin_dispatch_campaign(uuid) from public, anon, authenticated;
revoke all on function private.admin_create_campaign(
  uuid, text, text, text, text, uuid[], timestamptz
) from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- 5) Admin RPC'leri
-- -----------------------------------------------------------------------------

-- 5.1) Gönder (toplu / kişiye özel / çoklu alıcı / zamanlı)
create or replace function public.admin_send_notification(
  p_audience      text,
  p_title         text,
  p_content       text,
  p_icon_type     text default 'info',
  p_user_ids      uuid[] default null,
  p_scheduled_for timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_admin uuid := private.admin_notification_guard();
  v_row   public.admin_notification_campaigns;
begin
  v_row := private.admin_create_campaign(
    v_admin, p_audience, p_title, p_content, p_icon_type, p_user_ids, p_scheduled_for
  );
  return jsonb_build_object(
    'campaign_id',     v_row.id,
    'status',          v_row.status,
    'recipient_count', v_row.recipient_count,
    'scheduled_for',   v_row.scheduled_for
  );
end;
$$;

-- 5.2) Geçmiş: kampanya + okunma sayıları
create or replace function public.admin_notification_history(p_limit integer default 300)
returns table (
  id              uuid,
  kind            text,
  title           text,
  content         text,
  icon_type       text,
  target_audience text,
  status          text,
  scheduled_for   timestamptz,
  sent_at         timestamptz,
  created_at      timestamptz,
  edited_at       timestamptz,
  recipient_count integer,
  read_count      integer,
  live_count      integer,
  created_by      uuid,
  created_by_name text,
  recipient_names text[]
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
#variable_conflict use_column
begin
  perform private.admin_notification_guard();
  p_limit := least(greatest(coalesce(p_limit, 300), 1), 500);

  return query
  select
    c.id, c.kind, c.title, c.content, c.icon_type, c.target_audience, c.status,
    c.scheduled_for, c.sent_at, c.created_at, c.edited_at,
    c.recipient_count,
    coalesce(s.reads, 0),
    coalesce(s.live, 0),
    c.created_by,
    nullif(coalesce(nullif(btrim(ap.full_name), ''), ap.username), ''),
    case
      when c.kind <> 'personal' then null
      when cardinality(c.recipient_ids) > 0 then (
        select array_agg(x.nm)
        from (
          select coalesce(nullif(btrim(pp.full_name), ''), pp.username) as nm
          from public.profiles pp
          where pp.id = any(c.recipient_ids)
          limit 3
        ) x
      )
      else (
        select array_agg(x.nm)
        from (
          select coalesce(nullif(btrim(pp.full_name), ''), pp.username) as nm
          from public.notifications n2
          join public.profiles pp on pp.id = n2.user_id
          where n2.metadata @> jsonb_build_object('campaign_id', c.id)
          limit 3
        ) x
      )
    end
  from (
    select *
    from public.admin_notification_campaigns
    order by coalesce(sent_at, scheduled_for, created_at) desc
    limit p_limit
  ) c
  left join lateral (
    select
      count(*)::integer as live,
      (count(*) filter (where n.is_read))::integer as reads
    from public.notifications n
    where n.metadata @> jsonb_build_object('campaign_id', c.id)
  ) s on true
  left join public.profiles ap on ap.id = c.created_by
  order by coalesce(c.sent_at, c.scheduled_for, c.created_at) desc;
end;
$$;

-- 5.3) Alıcılar ve okundu bilgisi
create or replace function public.admin_notification_recipients(
  p_campaign_id uuid,
  p_filter      text default null,   -- null | 'read' | 'unread'
  p_limit       integer default 100,
  p_offset      integer default 0
)
returns table (
  user_id      uuid,
  username     text,
  full_name    text,
  avatar_url   text,
  role         text,
  is_read      boolean,
  delivered_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
#variable_conflict use_column
declare
  v_status text;
  v_ids    uuid[];
begin
  perform private.admin_notification_guard();
  p_limit  := least(greatest(coalesce(p_limit, 100), 1), 200);
  p_offset := greatest(coalesce(p_offset, 0), 0);

  select c.status, c.recipient_ids into v_status, v_ids
  from public.admin_notification_campaigns c
  where c.id = p_campaign_id;

  if not found then
    raise exception 'Bildirim kampanyası bulunamadı' using errcode = 'P0002';
  end if;

  if v_status = 'scheduled' then
    -- Henüz gönderilmedi: seçili alıcılar, hepsi "okunmadı".
    if p_filter = 'read' then
      return;
    end if;
    return query
    select p.id, p.username, p.full_name, p.avatar_url, p.role::text, false, null::timestamptz
    from public.profiles p
    where p.id = any(v_ids)
    order by lower(coalesce(nullif(btrim(p.full_name), ''), p.username, '')), p.id
    limit p_limit offset p_offset;
    return;
  end if;

  return query
  select
    n.user_id, p.username, p.full_name, p.avatar_url, p.role::text,
    coalesce(n.is_read, false), n.created_at
  from public.notifications n
  left join public.profiles p on p.id = n.user_id
  where n.metadata @> jsonb_build_object('campaign_id', p_campaign_id)
    and (
      p_filter is null
      or (p_filter = 'read'   and coalesce(n.is_read, false))
      or (p_filter = 'unread' and not coalesce(n.is_read, false))
    )
  order by lower(coalesce(nullif(btrim(p.full_name), ''), p.username, '')), n.user_id
  limit p_limit offset p_offset;
end;
$$;

-- 5.4) Düzenle. Gönderilmişse alıcıların bildirim kutusundaki metin de güncellenir
--      (push geri alınamaz). p_renotify: okunmadı yap, en üste al, push'u yeniden gönder.
create or replace function public.admin_update_notification_campaign(
  p_campaign_id   uuid,
  p_title         text,
  p_content       text,
  p_icon_type     text default null,
  p_scheduled_for timestamptz default null,
  p_renotify      boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_admin   uuid := private.admin_notification_guard();
  c         public.admin_notification_campaigns%rowtype;
  v_title   text := btrim(coalesce(p_title, ''));
  v_content text := btrim(coalesce(p_content, ''));
  v_icon    text;
  v_max     integer;
  v_rows    integer := 0;
  v_when    timestamptz;
begin
  select * into c
  from public.admin_notification_campaigns
  where id = p_campaign_id
  for update;

  if not found then
    raise exception 'Bildirim kampanyası bulunamadı' using errcode = 'P0002';
  end if;

  v_max := case when c.kind = 'personal' then 500 else 1000 end;
  if length(v_title) = 0 or length(v_title) > 100 then
    raise exception 'Başlık 1-100 karakter olmalıdır' using errcode = '22000';
  end if;
  if length(v_content) = 0 or length(v_content) > v_max then
    raise exception 'İçerik 1-% karakter olmalıdır', v_max using errcode = '22000';
  end if;

  v_icon := private.admin_notification_icon(coalesce(nullif(p_icon_type, ''), c.icon_type));

  if c.status = 'scheduled' then
    v_when := coalesce(p_scheduled_for, c.scheduled_for);
    if v_when is not null and v_when > now() + interval '1 year' then
      raise exception 'Zamanlama en fazla 1 yıl sonrasına yapılabilir' using errcode = '22023';
    end if;
    update public.admin_notification_campaigns
       set title = v_title, content = v_content, icon_type = v_icon,
           scheduled_for = v_when, edited_at = now()
     where id = c.id;
  else
    update public.admin_notification_campaigns
       set title = v_title, content = v_content, icon_type = v_icon, edited_at = now()
     where id = c.id;

    if c.kind = 'broadcast' then
      update public.admin_broadcasts
         set title = v_title, content = v_content, icon_type = v_icon
       where id = c.id;
    end if;

    update public.notifications n
       set title    = v_title,
           content  = v_content,
           entity_id = 'admin_icon:' || v_icon,
           metadata = coalesce(n.metadata, '{}'::jsonb)
                      || jsonb_build_object('icon_type', v_icon, 'edited', true),
           is_read    = case when p_renotify then false else n.is_read end,
           created_at = case when p_renotify then now() else n.created_at end
     where n.metadata @> jsonb_build_object('campaign_id', c.id);
    get diagnostics v_rows = row_count;

    if p_renotify then
      update public.notification_outbox o
         set status = 'pending', attempts = 0, next_attempt_at = now(),
             locked_at = null, locked_by = null, last_error = null, sent_at = null
       where o.notification_id in (
         select n.id from public.notifications n
         where n.metadata @> jsonb_build_object('campaign_id', c.id)
       );
    end if;
  end if;

  insert into public.admin_notification_audit (
    admin_id, action, target_audience, title, content
  ) values (v_admin, 'update', c.target_audience, v_title, v_content);

  return jsonb_build_object(
    'campaign_id',  c.id,
    'status',       c.status,
    'updated_rows', v_rows,
    'renotified',   coalesce(p_renotify, false) and c.status = 'sent'
  );
end;
$$;

-- 5.5) Sil (bir ya da birden çok kampanya). Alıcıların bildirim kutusundan ve
--      kullanıcı uygulamasındaki "Duyurular"dan da kalkar; bekleyen push iptal olur.
create or replace function public.admin_delete_notification_campaigns(p_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_admin   uuid := private.admin_notification_guard();
  c         public.admin_notification_campaigns%rowtype;
  v_ids     uuid[] := coalesce(p_ids, '{}'::uuid[]);
  v_deleted integer := 0;
  v_id      uuid;
begin
  if cardinality(v_ids) = 0 then
    return 0;
  end if;
  if cardinality(v_ids) > 100 then
    raise exception 'Bir seferde en fazla 100 bildirim silinebilir' using errcode = '22023';
  end if;

  foreach v_id in array v_ids loop
    select * into c
    from public.admin_notification_campaigns
    where id = v_id
    for update;

    if not found then
      continue;
    end if;

    -- notification_outbox satırları ON DELETE CASCADE ile birlikte gider.
    delete from public.notifications n
     where n.metadata @> jsonb_build_object('campaign_id', c.id);
    delete from public.admin_broadcasts where id = c.id;
    delete from public.admin_notification_campaigns where id = c.id;

    insert into public.admin_notification_audit (
      admin_id, action, target_audience, title, content
    ) values (v_admin, 'delete', c.target_audience, c.title, c.content);

    v_deleted := v_deleted + 1;
  end loop;

  return v_deleted;
end;
$$;

-- 5.6) Gönderim öncesi kitle büyüklüğü
create or replace function public.admin_notification_audience_count(
  p_audience text,
  p_user_ids uuid[] default null
)
returns integer
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_admin    uuid := private.admin_notification_guard();
  v_audience text := coalesce(nullif(btrim(p_audience), ''), 'all_users');
begin
  if v_audience = 'all' then
    v_audience := 'all_users';
  end if;
  if v_audience not in ('all_users', 'customers', 'sellers', 'couriers', 'personal') then
    raise exception 'Geçersiz hedef kitle' using errcode = '22000';
  end if;
  return (
    select count(*)::integer
    from private.admin_notification_recipients(v_audience, p_user_ids, v_admin)
  );
end;
$$;

-- 5.7) Zamanlanmış bildirimi şimdi gönder
create or replace function public.admin_send_notification_campaign_now(p_campaign_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_status text;
  v_count  integer;
begin
  perform private.admin_notification_guard();

  select status into v_status
  from public.admin_notification_campaigns
  where id = p_campaign_id;

  if not found then
    raise exception 'Bildirim kampanyası bulunamadı' using errcode = 'P0002';
  end if;
  if v_status <> 'scheduled' then
    raise exception 'Bu bildirim zaten gönderilmiş' using errcode = '22023';
  end if;

  v_count := private.admin_dispatch_campaign(p_campaign_id);
  return jsonb_build_object(
    'campaign_id', p_campaign_id, 'status', 'sent', 'recipient_count', v_count
  );
end;
$$;

-- 5.8) pg_cron: zamanı gelenleri gönder (istemciye kapalı)
create or replace function public.admin_dispatch_due_notifications()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  r       record;
  v_total integer := 0;
begin
  for r in
    select id
    from public.admin_notification_campaigns
    where status = 'scheduled'
      and scheduled_for is not null
      and scheduled_for <= now()
    order by scheduled_for
    limit 20
    for update skip locked
  loop
    begin
      perform private.admin_dispatch_campaign(r.id);
      v_total := v_total + 1;
    exception when others then
      raise warning 'admin_dispatch_due_notifications: % gönderilemedi: %', r.id, sqlerrm;
    end;
  end loop;
  return v_total;
end;
$$;

-- 5.9) Eski RPC'ler: imza AYNI, yeni kampanya mekanizmasına devredildi.
create or replace function public.admin_broadcast_notification(
  p_title           text,
  p_content         text,
  p_icon_type       text default 'info',
  p_target_audience text default 'all_users'
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_admin    uuid := private.admin_notification_guard();
  v_audience text := coalesce(nullif(p_target_audience, ''), 'all_users');
  v_row      public.admin_notification_campaigns;
begin
  if v_audience not in ('customers', 'sellers', 'all_users') then
    raise exception 'Geçersiz hedef kitle' using errcode = '22000';
  end if;
  v_row := private.admin_create_campaign(
    v_admin, v_audience, p_title, p_content, p_icon_type, null, null
  );
  return v_row.id;
end;
$$;

create or replace function public.admin_send_personal_notification(
  p_user_id   uuid,
  p_title     text,
  p_content   text,
  p_icon_type text default 'info'
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_admin uuid := private.admin_notification_guard();
  v_row   public.admin_notification_campaigns;
begin
  if p_user_id is null then
    raise exception 'user_id zorunludur' using errcode = '22023';
  end if;
  v_row := private.admin_create_campaign(
    v_admin, 'personal', p_title, p_content, p_icon_type, array[p_user_id], null
  );
  return v_row.id;
end;
$$;

-- -----------------------------------------------------------------------------
-- 6) Yetkiler
-- -----------------------------------------------------------------------------
revoke all on function public.admin_send_notification(text, text, text, text, uuid[], timestamptz)
  from public, anon;
revoke all on function public.admin_notification_history(integer) from public, anon;
revoke all on function public.admin_notification_recipients(uuid, text, integer, integer)
  from public, anon;
revoke all on function public.admin_update_notification_campaign(
  uuid, text, text, text, timestamptz, boolean
) from public, anon;
revoke all on function public.admin_delete_notification_campaigns(uuid[]) from public, anon;
revoke all on function public.admin_notification_audience_count(text, uuid[]) from public, anon;
revoke all on function public.admin_send_notification_campaign_now(uuid) from public, anon;
revoke all on function public.admin_broadcast_notification(text, text, text, text)
  from public, anon;
revoke all on function public.admin_send_personal_notification(uuid, text, text, text)
  from public, anon;
revoke all on function public.admin_dispatch_due_notifications()
  from public, anon, authenticated;

grant execute on function public.admin_send_notification(text, text, text, text, uuid[], timestamptz)
  to authenticated;
grant execute on function public.admin_notification_history(integer) to authenticated;
grant execute on function public.admin_notification_recipients(uuid, text, integer, integer)
  to authenticated;
grant execute on function public.admin_update_notification_campaign(
  uuid, text, text, text, timestamptz, boolean
) to authenticated;
grant execute on function public.admin_delete_notification_campaigns(uuid[]) to authenticated;
grant execute on function public.admin_notification_audience_count(text, uuid[]) to authenticated;
grant execute on function public.admin_send_notification_campaign_now(uuid) to authenticated;
grant execute on function public.admin_broadcast_notification(text, text, text, text)
  to authenticated;
grant execute on function public.admin_send_personal_notification(uuid, text, text, text)
  to authenticated;
grant execute on function public.admin_dispatch_due_notifications() to service_role;

-- -----------------------------------------------------------------------------
-- 7) Eski verinin kampanyalara taşınması
-- -----------------------------------------------------------------------------

-- 7.1) admin_broadcasts → kampanya (id aynı kalır)
insert into public.admin_notification_campaigns (
  id, kind, title, content, icon_type, target_audience,
  recipient_count, status, sent_at, created_by, created_at
)
select
  b.id,
  'broadcast',
  b.title,
  b.content,
  coalesce(nullif(b.icon_type, ''), 'info'),
  case
    when b.target_audience in ('customers', 'sellers') then b.target_audience
    else 'all_users'
  end,
  (
    select count(*)::integer
    from public.notifications n
    where n.metadata @> jsonb_build_object('broadcast_id', b.id)
  ),
  'sent',
  b.created_at,
  b.created_by,
  b.created_at
from public.admin_broadcasts b
on conflict (id) do nothing;

update public.notifications n
   set metadata = coalesce(n.metadata, '{}'::jsonb)
                  || jsonb_build_object('campaign_id', n.metadata->>'broadcast_id')
 where n.type = 'admin_broadcast'
   and n.metadata->>'broadcast_id' is not null
   and n.metadata->>'campaign_id' is null;

-- 7.2) Eski kişisel/çoklu yönetici bildirimleri: (başlık, içerik, dakika) grubu = bir kampanya
create temporary table _legacy_admin_notif_groups on commit drop as
select
  gen_random_uuid()                                  as campaign_id,
  n.title                                            as title,
  n.content                                          as content,
  date_trunc('minute', n.created_at)                 as minute_key,
  min(n.created_at)                                  as first_at,
  count(*)::integer                                  as n,
  (array_agg(n.entity_id order by n.created_at))[1]  as entity_id,
  (array_agg(n.actor_id order by n.created_at)
     filter (where n.actor_id is not null))[1]       as actor_id
from public.notifications n
where n.type = 'admin_notification'
  and n.entity_id like 'admin\_icon:%'
  and coalesce(n.metadata->>'campaign_id', '') = ''
group by n.title, n.content, date_trunc('minute', n.created_at);

insert into public.admin_notification_campaigns (
  id, kind, title, content, icon_type, target_audience,
  recipient_count, status, sent_at, created_by, created_at
)
select
  g.campaign_id,
  'personal',
  g.title,
  g.content,
  private.admin_notification_icon(substr(g.entity_id, length('admin_icon:') + 1)),
  'personal',
  g.n,
  'sent',
  g.first_at,
  (select u.id from auth.users u where u.id = g.actor_id),
  g.first_at
from _legacy_admin_notif_groups g;

update public.notifications n
   set metadata = coalesce(n.metadata, '{}'::jsonb)
                  || jsonb_build_object('campaign_id', g.campaign_id)
  from _legacy_admin_notif_groups g
 where n.type = 'admin_notification'
   and n.entity_id like 'admin\_icon:%'
   and coalesce(n.metadata->>'campaign_id', '') = ''
   and n.title = g.title
   and n.content = g.content
   and date_trunc('minute', n.created_at) = g.minute_key;

-- -----------------------------------------------------------------------------
-- 8) pg_cron: her dakika zamanı gelen bildirimleri gönder
-- -----------------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule(
      'admin-dispatch-scheduled-notifications',
      '* * * * *',
      'select public.admin_dispatch_due_notifications();'
    );
  end if;
end $$;

commit;

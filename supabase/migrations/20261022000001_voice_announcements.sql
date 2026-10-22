-- =============================================================================
-- Sesli duyurular (2026-10-22)
--
-- Uygulama AÇIKKEN gelen yönetici duyuruları telefonun Türkçe sesiyle, kişiye
-- özel ("Merhaba Ahmet, ...") okunur; her duyuruda "Dinle" düğmesi vardır.
-- Telefon kapalıyken okuma yoktur (iOS izin vermez, Android'de güvenilmez);
-- bildirim normal push olarak gelir.
--
--   * Admin ayarları (app_settings): ana anahtar, varsayılan ses (kadın/erkek),
--     hangi bölümlerin okunacağı, "Merhaba <ad>" karşılaması.
--     Okuyucu: public.voice_announce_settings() (anon dahil; ayar gizli değil).
--   * Kullanıcı tercihi (notification_preferences):
--       voice_announcements_enabled  → otomatik sesli okuma
--       notification_sound_enabled   → push bildirim sesi (false ise sessiz kanal;
--                                       process-notification-outbox okur)
--   * Kampanya başına ayrı "sesli okunacak metin" ve ses seçimi:
--     admin_notification_campaigns / admin_broadcasts .voice_text, .voice_gender;
--     alıcı satırlarında notifications.metadata.voice_text / voice_gender
--     (push verisinde meta_voice_text / meta_voice_gender olarak gelir).
--   * Açılış duyurusu için ayrı sesli metin: app_about_settings.startup_announcement_voice_text
--
-- İmza değişiklikleri (eski admin sürümleri çalışmaya devam eder, yeni
-- parametreler varsayılanlı):
--   private.admin_create_campaign  (+ p_voice_text, p_voice_gender)
--   public.admin_send_notification (+ p_voice_text, p_voice_gender)
--   public.admin_notification_history (+ voice_text, voice_gender sütunları)
-- Yeni: public.admin_set_campaign_voice(...) — gönderilmiş/zamanlanmış
-- kampanyanın sesli metnini düzeltir (admin_update_notification_campaign'in
-- imzası bilerek değişmedi).
-- =============================================================================

begin;

set local lock_timeout = '10s';

-- -----------------------------------------------------------------------------
-- 1) Admin ayarları
-- -----------------------------------------------------------------------------
insert into public.app_settings (key, value, description) values
  ('voice_announce_enabled',  '"true"'::jsonb,
     'Sesli duyurular ana anahtarı (false: hiçbir yerde okunmaz, Dinle düğmeleri gizlenir)'),
  ('voice_announce_gender',   '"female"'::jsonb,
     'Varsayılan okuma sesi: female | male'),
  ('voice_announce_areas',    '"admin_notifications,startup,seller,courier"'::jsonb,
     'Otomatik okunan bölümler (virgülle; hiçbiri için none)'),
  ('voice_announce_greeting', '"true"'::jsonb,
     'Okumaya "Merhaba <ad>," ile başla')
on conflict (key) do nothing;

create or replace function public.voice_announce_settings()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $fn$
  select jsonb_build_object(
    'enabled',  public.music_flag('voice_announce_enabled', true),
    'gender',   case
                  when lower(coalesce(public.music_setting_text('voice_announce_gender'), '')) = 'male'
                    then 'male'
                  else 'female'
                end,
    'areas',    case
                  when a.t is null then 'admin_notifications,startup,seller,courier'
                  when lower(a.t) = 'none' then ''
                  else a.t
                end,
    'greeting', public.music_flag('voice_announce_greeting', true)
  )
  from (select public.music_setting_text('voice_announce_areas') as t) as a;
$fn$;

revoke all on function public.voice_announce_settings() from public;
grant execute on function public.voice_announce_settings() to anon, authenticated, service_role;

comment on function public.voice_announce_settings() is
  'Sesli duyuru ayarları: {enabled, gender(female|male), areas(csv), greeting}. Tırnağa dayanıklı.';

-- -----------------------------------------------------------------------------
-- 2) Kullanıcı tercihleri
-- -----------------------------------------------------------------------------
alter table public.notification_preferences
  add column if not exists voice_announcements_enabled boolean not null default true,
  add column if not exists notification_sound_enabled  boolean not null default true;

comment on column public.notification_preferences.voice_announcements_enabled is
  'Uygulama açıkken yönetici duyurularını sesli oku (istemci kapısı).';
comment on column public.notification_preferences.notification_sound_enabled is
  'false: push bildirimleri sessiz kanaldan (silent_notifications) ve APNs sesi olmadan gider.';

-- -----------------------------------------------------------------------------
-- 3) Kampanya / duyuru / açılış duyurusu sesli alanları
-- -----------------------------------------------------------------------------
alter table public.admin_notification_campaigns
  add column if not exists voice_text   text,
  add column if not exists voice_gender text;

alter table public.admin_broadcasts
  add column if not exists voice_text   text,
  add column if not exists voice_gender text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'admin_notification_campaigns_voice_chk'
  ) then
    alter table public.admin_notification_campaigns
      add constraint admin_notification_campaigns_voice_chk check (
        (voice_gender is null or voice_gender in ('female', 'male'))
        and (voice_text is null or char_length(voice_text) <= 1000)
      );
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'admin_broadcasts_voice_chk'
  ) then
    alter table public.admin_broadcasts
      add constraint admin_broadcasts_voice_chk check (
        (voice_gender is null or voice_gender in ('female', 'male'))
        and (voice_text is null or char_length(voice_text) <= 1000)
      );
  end if;
end;
$$;

alter table public.app_about_settings
  add column if not exists startup_announcement_voice_text text;

-- -----------------------------------------------------------------------------
-- 4) Yardımcılar
-- -----------------------------------------------------------------------------
create or replace function private.admin_voice_text(p_text text)
returns text
language plpgsql
immutable
set search_path = ''
as $fn$
declare
  v text := nullif(btrim(coalesce(p_text, '')), '');
begin
  if v is not null and char_length(v) > 1000 then
    raise exception 'Sesli metin en fazla 1000 karakter olabilir' using errcode = '22000';
  end if;
  return v;
end;
$fn$;

create or replace function private.admin_voice_gender(p_gender text)
returns text
language sql
immutable
set search_path = ''
as $fn$
  select case lower(btrim(coalesce(p_gender, '')))
    when 'female' then 'female'
    when 'male'   then 'male'
    else null
  end;
$fn$;

-- -----------------------------------------------------------------------------
-- 5) Kampanya oluşturma: sesli alanlar (eski 7 parametreli imza kaldırılır;
--    yeni imza varsayılanlı olduğu için 7 argümanla çağıranlar aynen çalışır)
-- -----------------------------------------------------------------------------
drop function if exists private.admin_create_campaign(
  uuid, text, text, text, text, uuid[], timestamptz
);

create or replace function private.admin_create_campaign(
  p_admin         uuid,
  p_audience      text,
  p_title         text,
  p_content       text,
  p_icon          text,
  p_user_ids      uuid[],
  p_scheduled_for timestamptz,
  p_voice_text    text default null,
  p_voice_gender  text default null
)
returns public.admin_notification_campaigns
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_audience text := coalesce(nullif(btrim(p_audience), ''), 'all_users');
  v_title    text := btrim(coalesce(p_title, ''));
  v_content  text := btrim(coalesce(p_content, ''));
  v_voice    text := private.admin_voice_text(p_voice_text);
  v_gender   text := private.admin_voice_gender(p_voice_gender);
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
    recipient_ids, status, scheduled_for, created_by,
    voice_text, voice_gender
  ) values (
    v_kind, v_title, v_content, private.admin_notification_icon(p_icon), v_audience,
    v_ids, 'scheduled', v_when, p_admin,
    v_voice, v_gender
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
$function$;

revoke all on function private.admin_create_campaign(
  uuid, text, text, text, text, uuid[], timestamptz, text, text
) from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- 6) Dağıtım: sesli alanlar metadata'ya ve "Duyurular" satırına
-- -----------------------------------------------------------------------------
create or replace function private.admin_dispatch_campaign(p_campaign_id uuid)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
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
  -- Sesli alanlar yalnız doluysa eklenir (push verisi string-only; null yazılmaz).
  if c.voice_text is not null then
    v_meta := v_meta || jsonb_build_object('voice_text', c.voice_text);
  end if;
  if c.voice_gender is not null then
    v_meta := v_meta || jsonb_build_object('voice_gender', c.voice_gender);
  end if;

  if c.kind = 'broadcast' then
    v_meta := v_meta || jsonb_build_object('broadcast_id', c.id);
    -- Kullanıcı uygulamasındaki "Duyurular" bölümü bu tablodan okur.
    insert into public.admin_broadcasts (
      id, title, content, icon_type, target_audience, is_active, created_by, created_at,
      voice_text, voice_gender
    ) values (
      c.id, c.title, c.content, c.icon_type, c.target_audience, true, c.created_by, now(),
      c.voice_text, c.voice_gender
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
$function$;

-- -----------------------------------------------------------------------------
-- 7) Gönderim RPC'si: sesli alanlar (eski 6 parametreli imza kaldırılır)
-- -----------------------------------------------------------------------------
drop function if exists public.admin_send_notification(
  text, text, text, text, uuid[], timestamptz
);

create or replace function public.admin_send_notification(
  p_audience      text,
  p_title         text,
  p_content       text,
  p_icon_type     text        default 'info',
  p_user_ids      uuid[]      default null,
  p_scheduled_for timestamptz default null,
  p_voice_text    text        default null,
  p_voice_gender  text        default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_admin uuid := private.admin_notification_guard();
  v_row   public.admin_notification_campaigns;
begin
  v_row := private.admin_create_campaign(
    v_admin, p_audience, p_title, p_content, p_icon_type, p_user_ids, p_scheduled_for,
    p_voice_text, p_voice_gender
  );
  return jsonb_build_object(
    'campaign_id',     v_row.id,
    'status',          v_row.status,
    'recipient_count', v_row.recipient_count,
    'scheduled_for',   v_row.scheduled_for
  );
end;
$function$;

revoke all on function public.admin_send_notification(
  text, text, text, text, uuid[], timestamptz, text, text
) from public, anon;
grant execute on function public.admin_send_notification(
  text, text, text, text, uuid[], timestamptz, text, text
) to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 8) Sesli metni sonradan düzelt
-- -----------------------------------------------------------------------------
create or replace function public.admin_set_campaign_voice(
  p_campaign_id  uuid,
  p_voice_text   text,
  p_voice_gender text
)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_admin  uuid := private.admin_notification_guard();
  v_voice  text := private.admin_voice_text(p_voice_text);
  v_gender text := private.admin_voice_gender(p_voice_gender);
  c        public.admin_notification_campaigns%rowtype;
  v_rows   integer := 0;
begin
  select * into c
  from public.admin_notification_campaigns
  where id = p_campaign_id
  for update;

  if not found then
    raise exception 'Bildirim kampanyası bulunamadı' using errcode = 'P0002';
  end if;

  if c.voice_text is not distinct from v_voice
     and c.voice_gender is not distinct from v_gender then
    return 0;
  end if;

  update public.admin_notification_campaigns
     set voice_text = v_voice, voice_gender = v_gender, edited_at = now()
   where id = c.id;

  if c.status <> 'scheduled' then
    if c.kind = 'broadcast' then
      update public.admin_broadcasts
         set voice_text = v_voice, voice_gender = v_gender
       where id = c.id;
    end if;

    update public.notifications n
       set metadata = (coalesce(n.metadata, '{}'::jsonb) - 'voice_text' - 'voice_gender')
                      || jsonb_strip_nulls(jsonb_build_object(
                           'voice_text', v_voice, 'voice_gender', v_gender))
     where n.metadata @> jsonb_build_object('campaign_id', c.id);
    get diagnostics v_rows = row_count;
  end if;

  insert into public.admin_notification_audit (
    admin_id, action, target_audience, title, content
  ) values (v_admin, 'update', c.target_audience, c.title, coalesce(v_voice, c.content));

  return v_rows;
end;
$function$;

revoke all on function public.admin_set_campaign_voice(uuid, text, text) from public, anon;
grant execute on function public.admin_set_campaign_voice(uuid, text, text)
  to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 9) Geçmiş: sesli alanları da döndür (dönüş tipi değiştiği için DROP+CREATE)
-- -----------------------------------------------------------------------------
drop function if exists public.admin_notification_history(integer);

create or replace function public.admin_notification_history(p_limit integer default 300)
returns table(
  id uuid, kind text, title text, content text, icon_type text, target_audience text,
  status text, scheduled_for timestamptz, sent_at timestamptz, created_at timestamptz,
  edited_at timestamptz, recipient_count integer, read_count integer, live_count integer,
  created_by uuid, created_by_name text, recipient_names text[],
  voice_text text, voice_gender text
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $function$
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
    end,
    c.voice_text,
    c.voice_gender
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
$function$;

revoke all on function public.admin_notification_history(integer) from public, anon;
grant execute on function public.admin_notification_history(integer)
  to authenticated, service_role;

commit;

notify pgrst, 'reload schema';

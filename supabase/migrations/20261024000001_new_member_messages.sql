-- =============================================================================
-- Yeni üye karşılama serisi (2026-10-24)
--
-- Yeni kaydolan üyelere zamanlanmış, hazır içerikli ve SESLİ okunabilen
-- bildirimler gider (hoş geldin → profil fotoğrafı → ilk gönderi → dükkânlar
-- → 101 Okey). Admin her adımı açıp kapatır, metnini / sesli metnini / ikonunu /
-- gecikmesini / koşulunu / açacağı ekranı değiştirir, kendine test gönderir.
--
-- Tasarım kararları:
--   * Kayıt akışına tetikleyici EKLENMEZ (handle_new_user hataları yutar; bir
--     hata profil INSERT'ini geri alabilirdi). Her dakika çalışan pg_cron işi
--     private.process_new_member_messages() adayları profiles.created_at'ten
--     bulur.
--   * Tek sefer garantisi new_member_message_deliveries PK'sı (user_id, step_id).
--     Bildirim satırı entity_id='admin_icon:<ikon>' olduğu için dedup'a girmez ve
--     uygulamada mevcut ikon / detay / "Dinle" düğmesini kullanır.
--   * Geriye dönük toplu gönderim YOK: aday penceresi
--     greatest(adım açılışı, ana anahtar açılışı, şimdi − gecikme − 3 gün).
--   * Kısa gecikmeli adımlar (< 60 dk) cihaz token'ı ve kullanıcı adı seçimi için
--     30 dk'ya kadar bekler (token yoksa outbox push'u kaybederdi).
--   * Sessiz saat 22:00–09:00 (Europe/Istanbul); hoş geldin adımı muaf.
--   * Hata kullanıcı başına yakalanır: signup_trigger_errors (source
--     'new_member_messages') + teslim 'failed' (her dakika yeniden denenmez).
--   * add_notification: istemcinin sahte 'new_member' / 'product_review_reply'
--     yazması engellenir (sesli okunan karşılama taklit edilemez).
-- =============================================================================

begin;

set local lock_timeout = '10s';

-- -----------------------------------------------------------------------------
-- 1) Tablolar
-- -----------------------------------------------------------------------------
create table if not exists public.new_member_message_steps (
  id                  uuid primary key default gen_random_uuid(),
  step_key            text not null unique,
  sort_order          integer not null default 0,
  delay_minutes       integer not null check (delay_minutes between 0 and 43200),
  title               text not null check (char_length(btrim(title)) between 1 and 100),
  body                text not null check (char_length(btrim(body)) between 1 and 500),
  voice_text          text check (voice_text is null or char_length(voice_text) <= 1000),
  voice_gender        text check (voice_gender is null or voice_gender in ('female', 'male')),
  icon                text not null default 'gift' check (icon in (
                        'announcement', 'discount', 'campaign', 'news', 'event',
                        'update', 'warning', 'gift', 'info')),
  condition           text not null default 'always' check (condition in (
                        'always', 'no_avatar', 'no_post', 'no_order')),
  action_route        text check (action_route is null or action_route in (
                        'edit_profile', 'create_post', 'market', 'okey')),
  is_active           boolean not null default true,
  respect_quiet_hours boolean not null default true,
  activated_at        timestamptz not null default now(),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

comment on table public.new_member_message_steps is
  'Yeni üye karşılama serisi adımları. Yalnız admin RPC''leriyle okunur/yazılır.';

create table if not exists public.new_member_message_deliveries (
  user_id         uuid not null references auth.users (id) on delete cascade,
  step_id         uuid not null references public.new_member_message_steps (id) on delete cascade,
  status          text not null check (status in ('sent', 'skipped', 'failed')),
  notification_id uuid,
  created_at      timestamptz not null default now(),
  primary key (user_id, step_id)
);

create index if not exists idx_new_member_deliveries_step
  on public.new_member_message_deliveries (step_id, status);

comment on table public.new_member_message_deliveries is
  'Karşılama serisi teslim kaydı; PK (user_id, step_id) tek seferi garanti eder.';

alter table public.new_member_message_steps enable row level security;
alter table public.new_member_message_deliveries enable row level security;
revoke all on public.new_member_message_steps from public, anon, authenticated;
revoke all on public.new_member_message_deliveries from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- 2) Ayarlar (ana anahtar açık; yalnız bu göçten SONRA kaydolanlara gider)
-- -----------------------------------------------------------------------------
insert into public.app_settings (key, value, description) values
  ('new_member_messages_enabled', '"true"'::jsonb,
     'Yeni üye karşılama serisi ana anahtarı'),
  ('new_member_messages_enabled_at', to_jsonb(now()::text),
     'Karşılama serisinin son açıldığı an; bundan önce kaydolanlara gönderilmez')
on conflict (key) do nothing;

-- -----------------------------------------------------------------------------
-- 3) Hazır adımlar
-- -----------------------------------------------------------------------------
insert into public.new_member_message_steps (
  step_key, sort_order, delay_minutes, title, body, voice_text, icon, condition,
  action_route, respect_quiet_hours
) values
  ('welcome', 1, 1,
   'CizreApp''e hoş geldin {ad} 👋',
   'Aramıza katıldığın için çok mutluyuz! Mahallendeki dükkânlardan sipariş verebilir, sosyal akışta paylaşım yapabilir, 101 Okey''de masaya oturabilirsin. İyi eğlenceler!',
   'Merhaba {ad}, CizreApp ailesine hoş geldin! Mahallendeki dükkânlardan sipariş verebilir, sosyal akışta paylaşım yapabilir ve 101 Okey oynayabilirsin. İyi eğlenceler!',
   'gift', 'always', null, false),
  ('complete_profile', 2, 60,
   'Profilini tamamla {ad} 📸',
   'Bir profil fotoğrafı ekle; arkadaşların seni kolayca tanısın, sen de daha çok takipçi kazan.',
   '{ad}, profil fotoğrafını eklemeyi unutma. Arkadaşların seni böylece kolayca tanır.',
   'update', 'no_avatar', 'edit_profile', true),
  ('first_post', 3, 1440,
   'İlk gönderini paylaş ✨',
   'Merhaba {ad}, Cizre''den bir an, bir fotoğraf ya da birkaç kelime paylaş; topluluk seni tanısın.',
   'Merhaba {ad}, ilk gönderini paylaşmaya ne dersin? Bir fotoğraf ya da birkaç kelime yeter.',
   'news', 'no_post', 'create_post', true),
  ('explore_shops', 4, 2880,
   'Mahallendeki dükkânlar seni bekliyor 🛍️',
   'Merhaba {ad}, market, restoran ve daha fazlası kapında. Kampanyaları kaçırma, ilk siparişini şimdi ver.',
   'Merhaba {ad}, mahallendeki dükkânlar seni bekliyor. Kampanyalara göz atıp ilk siparişini verebilirsin.',
   'discount', 'no_order', 'market', true),
  ('okey', 5, 4320,
   '101 Okey masası hazır 🎲',
   'Arkadaşlarınla ya da Cizre''nin dört bir yanından oyuncularla 101 Okey oyna, puan topla, liderlik tablosuna gir.',
   '{ad}, 101 Okey masası seni bekliyor. Puan topla ve liderlik tablosuna adını yazdır.',
   'event', 'always', 'okey', true)
on conflict (step_key) do nothing;

-- -----------------------------------------------------------------------------
-- 4) Yardımcılar
-- -----------------------------------------------------------------------------
-- "Ayşe Nur" → "Ayşe"; ad yoksa kullanıcı adı; geçici misafir_xxx adı kullanılmaz.
create or replace function private.new_member_first_name(p_full_name text, p_username text)
returns text
language sql
immutable
set search_path = ''
as $fn$
  select left(coalesce(
    nullif(split_part(regexp_replace(btrim(coalesce(p_full_name, '')), '\s+', ' ', 'g'), ' ', 1), ''),
    case
      when p_username is null or btrim(p_username) = '' or p_username ilike 'misafir\_%' then null
      else btrim(p_username)
    end,
    ''), 40);
$fn$;

-- {ad} yer tutucusunu doldurur; ad yoksa yer tutucu ve ona yapışık boşluk silinir
-- ("Merhaba {ad}, ..." → "Merhaba, ...").
create or replace function private.new_member_fill(p_text text, p_name text)
returns text
language sql
immutable
set search_path = ''
as $fn$
  select regexp_replace(
    btrim(regexp_replace(regexp_replace(
      case
        when coalesce(btrim(p_name), '') = '' then regexp_replace(coalesce(p_text, ''), '\s*\{ad\}', '', 'g')
        else replace(coalesce(p_text, ''), '{ad}', btrim(p_name))
      end,
      '\s+([,.!?])', '\1', 'g'), '\s{2,}', ' ', 'g')),
    '^[,.!?\s]+', '');
$fn$;

-- Ana anahtarın son açıldığı an; okunamazsa şimdi (kimse geriye dönük almaz).
create or replace function private.new_member_enabled_at()
returns timestamptz
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v text := public.music_setting_text('new_member_messages_enabled_at');
begin
  if v is null then
    return now();
  end if;
  return v::timestamptz;
exception when others then
  return now();
end;
$fn$;

-- Sessiz saat: 22:00–09:00 Türkiye saati.
create or replace function private.new_member_is_quiet(p_at timestamptz)
returns boolean
language sql
immutable
set search_path = ''
as $fn$
  select extract(hour from (p_at at time zone 'Europe/Istanbul')) >= 22
      or extract(hour from (p_at at time zone 'Europe/Istanbul')) < 9;
$fn$;

revoke all on function private.new_member_is_quiet(timestamptz) from public, anon, authenticated;
revoke all on function private.new_member_first_name(text, text) from public, anon, authenticated;
revoke all on function private.new_member_fill(text, text) from public, anon, authenticated;
revoke all on function private.new_member_enabled_at() from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- 5) Zamanlayıcı
-- -----------------------------------------------------------------------------
create or replace function private.process_new_member_messages()
returns integer
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_quiet      boolean := private.new_member_is_quiet(now());
  v_enabled_at timestamptz;
  v_okey_on    boolean;
  v_sent       integer := 0;
  s            record;
  u            record;
  v_ok         boolean;
  v_name       text;
  v_meta       jsonb;
  v_nid        uuid;
begin
  if not pg_try_advisory_xact_lock(hashtext('private.process_new_member_messages')) then
    return 0;
  end if;
  if not public.music_flag('new_member_messages_enabled', false) then
    return 0;
  end if;

  v_enabled_at := private.new_member_enabled_at();
  v_okey_on := public.music_flag('okey_module_enabled', true);

  for s in
    select *
    from public.new_member_message_steps
    where is_active
    order by sort_order, delay_minutes
  loop
    if s.respect_quiet_hours and v_quiet then
      continue;
    end if;

    for u in
      select
        p.id, p.full_name, p.username, p.avatar_url, p.created_at,
        coalesce(p.needs_username, false) as needs_username,
        (p.fcm_token is not null
          or exists (select 1 from public.notification_tokens t where t.user_id = p.id)) as has_token
      from public.profiles p
      join auth.users au on au.id = p.id
      where p.created_at <= now() - make_interval(mins => s.delay_minutes)
        and p.created_at >= greatest(
              s.activated_at,
              v_enabled_at,
              now() - make_interval(mins => s.delay_minutes) - interval '3 days')
        and coalesce(p.is_bot, false) = false
        and coalesce(au.is_anonymous, false) = false
        and au.deleted_at is null
        and coalesce(p.status::text, 'active') = 'active'
        and not exists (
          select 1 from public.new_member_message_deliveries d
          where d.user_id = p.id and d.step_id = s.id)
      order by p.created_at
      limit 200
    loop
      -- Kısa gecikmeli adım: push'un kaybolmaması ve "Merhaba misafir_ab12"
      -- denmemesi için token + kullanıcı adı beklenir (en çok 30 dk).
      if s.delay_minutes < 60
         and (not u.has_token or u.needs_username)
         and u.created_at > now() - make_interval(mins => s.delay_minutes) - interval '30 minutes' then
        continue;
      end if;

      begin
        v_ok := case s.condition
          when 'no_avatar' then nullif(btrim(coalesce(u.avatar_url, '')), '') is null
          when 'no_post'   then not exists (select 1 from public.posts x where x.user_id = u.id)
          when 'no_order'  then not exists (select 1 from public.orders o where o.user_id = u.id)
                            and not exists (select 1 from public.digital_orders o where o.user_id = u.id)
          else true
        end;
        if v_ok and s.action_route = 'okey' and not v_okey_on then
          v_ok := false;
        end if;

        if not v_ok then
          insert into public.new_member_message_deliveries (user_id, step_id, status)
          values (u.id, s.id, 'skipped')
          on conflict do nothing;
          continue;
        end if;

        v_name := private.new_member_first_name(u.full_name, u.username);
        v_meta := jsonb_build_object('icon_type', s.icon, 'new_member_step', s.step_key);
        if s.voice_text is not null then
          v_meta := v_meta || jsonb_build_object('voice_text', s.voice_text);
        end if;
        if s.voice_gender is not null then
          v_meta := v_meta || jsonb_build_object('voice_gender', s.voice_gender);
        end if;
        if s.action_route is not null then
          v_meta := v_meta || jsonb_build_object('route', s.action_route);
        end if;

        -- notifications_outbox_trigger bu satırı outbox'a alır → push.
        insert into public.notifications (
          user_id, type, title, content, entity_id, metadata, is_read, created_at
        ) values (
          u.id, 'new_member',
          left(private.new_member_fill(s.title, v_name), 200),
          left(private.new_member_fill(s.body, v_name), 2000),
          'admin_icon:' || s.icon, v_meta, false, now()
        )
        returning id into v_nid;

        insert into public.new_member_message_deliveries (user_id, step_id, status, notification_id)
        values (u.id, s.id, 'sent', v_nid);
        v_sent := v_sent + 1;
      exception when others then
        insert into public.new_member_message_deliveries (user_id, step_id, status)
        values (u.id, s.id, 'failed')
        on conflict do nothing;
        insert into public.signup_trigger_errors (user_id, source, error_sqlstate, error_message)
        values (u.id, 'new_member_messages', SQLSTATE, left(SQLERRM, 1000));
      end;
    end loop;
  end loop;

  return v_sent;
end;
$fn$;

revoke all on function private.process_new_member_messages() from public, anon, authenticated;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule(
      'new-member-messages',
      '* * * * *',
      'select private.process_new_member_messages()'
    );
  end if;
end;
$$;

-- -----------------------------------------------------------------------------
-- 6) Admin RPC'leri
-- -----------------------------------------------------------------------------
create or replace function public.admin_new_member_steps()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $fn$
begin
  perform private.admin_notification_guard();
  return jsonb_build_object(
    'enabled', public.music_flag('new_member_messages_enabled', false),
    'steps', coalesce((
      select jsonb_agg(
        to_jsonb(s) || jsonb_build_object(
          'sent',         coalesce(st.sent, 0),
          'skipped',      coalesce(st.skipped, 0),
          'failed',       coalesce(st.failed, 0),
          'read',         coalesce(st.read_n, 0),
          'last_sent_at', st.last_sent
        )
        order by s.sort_order, s.delay_minutes
      )
      from public.new_member_message_steps s
      left join lateral (
        select
          count(*) filter (where d.status = 'sent')    as sent,
          count(*) filter (where d.status = 'skipped') as skipped,
          count(*) filter (where d.status = 'failed')  as failed,
          count(*) filter (where n.is_read)            as read_n,
          max(d.created_at) filter (where d.status = 'sent') as last_sent
        from public.new_member_message_deliveries d
        left join public.notifications n on n.id = d.notification_id
        where d.step_id = s.id
      ) st on true
    ), '[]'::jsonb)
  );
end;
$fn$;

create or replace function public.admin_upsert_new_member_step(
  p_id                  uuid,
  p_title               text,
  p_body                text,
  p_voice_text          text,
  p_voice_gender        text,
  p_icon                text,
  p_delay_minutes       integer,
  p_condition           text,
  p_action_route        text,
  p_respect_quiet_hours boolean,
  p_is_active           boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_title  text := btrim(coalesce(p_title, ''));
  v_body   text := btrim(coalesce(p_body, ''));
  v_voice  text;
  v_gender text := private.admin_voice_gender(p_voice_gender);
  v_cond   text := coalesce(nullif(btrim(p_condition), ''), 'always');
  v_route  text := nullif(btrim(coalesce(p_action_route, '')), '');
  v_old    public.new_member_message_steps%rowtype;
  v_row    public.new_member_message_steps%rowtype;
begin
  perform private.admin_notification_guard();
  v_voice := private.admin_voice_text(p_voice_text);

  if char_length(v_title) = 0 or char_length(v_title) > 100 then
    raise exception 'Başlık 1-100 karakter olmalıdır' using errcode = '22000';
  end if;
  if char_length(v_body) = 0 or char_length(v_body) > 500 then
    raise exception 'Metin 1-500 karakter olmalıdır' using errcode = '22000';
  end if;
  if p_delay_minutes is null or p_delay_minutes < 0 or p_delay_minutes > 43200 then
    raise exception 'Gecikme 0 dakika ile 30 gün arasında olmalıdır' using errcode = '22023';
  end if;
  if v_cond not in ('always', 'no_avatar', 'no_post', 'no_order') then
    raise exception 'Geçersiz koşul' using errcode = '22023';
  end if;
  if v_route is not null and v_route not in ('edit_profile', 'create_post', 'market', 'okey') then
    raise exception 'Geçersiz ekran' using errcode = '22023';
  end if;

  if p_id is null then
    insert into public.new_member_message_steps (
      step_key, sort_order, delay_minutes, title, body, voice_text, voice_gender,
      icon, condition, action_route, is_active, respect_quiet_hours, activated_at
    ) values (
      'custom_' || replace(gen_random_uuid()::text, '-', ''),
      coalesce((select max(sort_order) from public.new_member_message_steps), 0) + 1,
      p_delay_minutes, v_title, v_body, v_voice, v_gender,
      private.admin_notification_icon(p_icon), v_cond, v_route,
      coalesce(p_is_active, true), coalesce(p_respect_quiet_hours, true), now()
    )
    returning * into v_row;
  else
    select * into v_old from public.new_member_message_steps where id = p_id for update;
    if not found then
      raise exception 'Adım bulunamadı' using errcode = 'P0002';
    end if;
    update public.new_member_message_steps
       set title               = v_title,
           body                = v_body,
           voice_text          = v_voice,
           voice_gender        = v_gender,
           icon                = private.admin_notification_icon(p_icon),
           delay_minutes       = p_delay_minutes,
           condition           = v_cond,
           action_route        = v_route,
           respect_quiet_hours = coalesce(p_respect_quiet_hours, v_old.respect_quiet_hours),
           is_active           = coalesce(p_is_active, v_old.is_active),
           -- Yeniden açılan adım, kapalıyken kaydolanlara toplu gitmesin.
           activated_at        = case
                                   when coalesce(p_is_active, v_old.is_active) and not v_old.is_active
                                     then now()
                                   else v_old.activated_at
                                 end,
           updated_at          = now()
     where id = p_id
    returning * into v_row;
  end if;

  return to_jsonb(v_row);
end;
$fn$;

create or replace function public.admin_set_new_member_step_active(p_id uuid, p_active boolean)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
begin
  perform private.admin_notification_guard();
  update public.new_member_message_steps
     set is_active    = coalesce(p_active, false),
         activated_at = case when coalesce(p_active, false) and not is_active then now() else activated_at end,
         updated_at   = now()
   where id = p_id;
  if not found then
    raise exception 'Adım bulunamadı' using errcode = 'P0002';
  end if;
end;
$fn$;

create or replace function public.admin_delete_new_member_step(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
begin
  perform private.admin_notification_guard();
  delete from public.new_member_message_steps where id = p_id;
  if not found then
    raise exception 'Adım bulunamadı' using errcode = 'P0002';
  end if;
end;
$fn$;

-- Adımı adminin KENDİSİNE gönderir (teslim kaydı yazılmaz, sayaçlara girmez).
create or replace function public.admin_send_new_member_step_test(p_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_admin uuid := private.admin_notification_guard();
  s       public.new_member_message_steps%rowtype;
  v_name  text;
  v_meta  jsonb;
  v_nid   uuid;
begin
  select * into s from public.new_member_message_steps where id = p_id;
  if not found then
    raise exception 'Adım bulunamadı' using errcode = 'P0002';
  end if;

  select private.new_member_first_name(p.full_name, p.username)
    into v_name
  from public.profiles p
  where p.id = v_admin;

  v_meta := jsonb_build_object('icon_type', s.icon, 'new_member_step', s.step_key, 'test', true);
  if s.voice_text is not null then
    v_meta := v_meta || jsonb_build_object('voice_text', s.voice_text);
  end if;
  if s.voice_gender is not null then
    v_meta := v_meta || jsonb_build_object('voice_gender', s.voice_gender);
  end if;
  if s.action_route is not null then
    v_meta := v_meta || jsonb_build_object('route', s.action_route);
  end if;

  insert into public.notifications (
    user_id, type, title, content, entity_id, metadata, is_read, created_at
  ) values (
    v_admin, 'new_member',
    left(private.new_member_fill(s.title, coalesce(v_name, '')), 200),
    left(private.new_member_fill(s.body, coalesce(v_name, '')), 2000),
    'admin_icon:' || s.icon, v_meta, false, now()
  )
  returning id into v_nid;

  return v_nid;
end;
$fn$;

create or replace function public.admin_set_new_member_messages_enabled(p_enabled boolean)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_was boolean;
begin
  perform private.admin_notification_guard();
  v_was := public.music_flag('new_member_messages_enabled', false);

  insert into public.app_settings (key, value, description, updated_at)
  values ('new_member_messages_enabled',
          to_jsonb(case when coalesce(p_enabled, false) then 'true' else 'false' end),
          'Yeni üye karşılama serisi ana anahtarı', now())
  on conflict (key) do update set value = excluded.value, updated_at = now();

  -- Kapalıyken kaydolanlara açılınca toplu gönderim olmasın.
  if coalesce(p_enabled, false) and not v_was then
    insert into public.app_settings (key, value, description, updated_at)
    values ('new_member_messages_enabled_at', to_jsonb(now()::text),
            'Karşılama serisinin son açıldığı an; bundan önce kaydolanlara gönderilmez', now())
    on conflict (key) do update set value = excluded.value, updated_at = now();
  end if;

  return jsonb_build_object('enabled', coalesce(p_enabled, false));
end;
$fn$;

revoke all on function public.admin_new_member_steps() from public, anon;
revoke all on function public.admin_upsert_new_member_step(
  uuid, text, text, text, text, text, integer, text, text, boolean, boolean
) from public, anon;
revoke all on function public.admin_set_new_member_step_active(uuid, boolean) from public, anon;
revoke all on function public.admin_delete_new_member_step(uuid) from public, anon;
revoke all on function public.admin_send_new_member_step_test(uuid) from public, anon;
revoke all on function public.admin_set_new_member_messages_enabled(boolean) from public, anon;

grant execute on function public.admin_new_member_steps() to authenticated;
grant execute on function public.admin_upsert_new_member_step(
  uuid, text, text, text, text, text, integer, text, text, boolean, boolean
) to authenticated;
grant execute on function public.admin_set_new_member_step_active(uuid, boolean) to authenticated;
grant execute on function public.admin_delete_new_member_step(uuid) to authenticated;
grant execute on function public.admin_send_new_member_step_test(uuid) to authenticated;
grant execute on function public.admin_set_new_member_messages_enabled(boolean) to authenticated;

-- -----------------------------------------------------------------------------
-- 7) add_notification: istemci 'new_member' / 'product_review_reply' yazamaz
--    (canlı gövde aynen; yalnız tür regex'i genişledi)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.add_notification(p_user_id uuid, p_type text, p_title text, p_content text, p_actor_id uuid DEFAULT NULL::uuid, p_actor_name text DEFAULT NULL::text, p_actor_avatar text DEFAULT NULL::text, p_entity_id text DEFAULT NULL::text, p_entity_image text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  c_per_minute CONSTANT integer := 30;
  v_new_id  uuid;
  v_uid     uuid := auth.uid();
  v_count   integer;
BEGIN
  IF v_uid IS NULL THEN
    -- Yalnız sunucu (service_role) kullanıcısız çağırabilir.
    IF COALESCE(NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '') <> 'service_role' THEN
      RAISE EXCEPTION 'add_notification: oturum gerekli' USING ERRCODE = '28000';
    END IF;
  ELSIF NOT public.auth_is_admin() THEN
    -- Sistem / para / moderasyon türleri istemciden yazılamaz.
    IF p_type IS NULL
       OR p_type ~* '^(admin|system|balance|wallet|payment|payout|withdraw|refund|topup|reward|security|account|verification|task_|return_|cancellation|sponsorship|digital_order|courier_document|new_member|product_review_reply)' THEN
      RETURN NULL;
    END IF;

    -- Gönderen taklidi: actor_id verildiyse çağıranın kendisi olmalı.
    IF p_actor_id IS NOT NULL AND p_actor_id <> v_uid THEN
      p_actor_id := v_uid;
      SELECT COALESCE(NULLIF(pr.full_name, ''), pr.username), pr.avatar_url
        INTO p_actor_name, p_actor_avatar
      FROM public.profiles pr
      WHERE pr.id = v_uid;
    END IF;

    -- Hız sınırı (gönderen başına dakikalık pencere).
    INSERT INTO private.notification_send_rate AS r (sender_id, window_start, n)
    VALUES (v_uid, date_trunc('minute', now()), 1)
    ON CONFLICT (sender_id, window_start) DO UPDATE SET n = r.n + 1
    RETURNING r.n INTO v_count;

    IF random() < 0.02 THEN
      DELETE FROM private.notification_send_rate
      WHERE window_start < now() - interval '1 day';
    END IF;

    IF v_count > c_per_minute THEN
      RETURN NULL;
    END IF;
  END IF;

  INSERT INTO public.notifications (
    user_id, type, title, content,
    actor_id, actor_name, actor_avatar,
    entity_id, entity_image,
    is_read, created_at
  )
  VALUES (
    p_user_id, p_type, left(p_title, 200), left(p_content, 2000),
    p_actor_id, p_actor_name, p_actor_avatar,
    p_entity_id, p_entity_image,
    FALSE, NOW()
  )
  RETURNING id INTO v_new_id;

  RETURN v_new_id;
END;
$function$;

commit;

notify pgrst, 'reload schema';

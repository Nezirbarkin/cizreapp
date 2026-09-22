-- =============================================================================
-- ADMIN BILDIRIM MERKEZI — DAVRANIS testleri (pgTAP)
--
-- Kapsam (20260921000001_admin_notification_center.sql):
--   * Yalniz admin: kampanya tablosu, gecmis, gonder, duzenle, sil, kitle sayisi
--   * Toplu gonderim: hedef kitle sayisi dogru, botlar ve gonderen admin haric,
--     admin_broadcasts + alici satirlari yazilir
--   * Ayni ikonla ust uste gonderilen yonetici bildirimi ESKISINI SILMEZ (dedup
--     artik yonetici bildirimlerini atlar), diger tipler icin dedup surer
--   * Kisiye ozel / coklu alici, dogrulama hatalari
--   * Duzenleme: kampanya + broadcast + alici satirlari; "yeniden bildir" outbox'i
--     sifirlar; silme alici satirlarini, broadcast'i ve outbox'i temizler
--   * Zamanlama: gonderilmeden alici satiri yok, "simdi gonder", cron gonderici
--     (istemciye kapali)
--   * Eski RPC imzalari calismaya devam eder ve gecmiste gorunur
--
-- Calistirma:
--   supabase start && supabase test db supabase/tests/database
-- =============================================================================

begin;

create extension if not exists pgtap with schema extensions;

select plan(42);

-- -----------------------------------------------------------------------------
-- YARDIMCILAR
-- -----------------------------------------------------------------------------
create temporary table t_ctx (k text primary key, v text);

create or replace function pg_temp.ctx(p_k text) returns text
language sql stable as $$ select v from t_ctx where k = p_k $$;

-- Verilen kullanici baglaminda (authenticated) tek degerli SQL calistirir.
-- Sonuc metin; hata olursa 'ERR:<sqlstate>'.
create or replace function pg_temp.as_user(p_uid uuid, p_sql text)
returns text language plpgsql as $$
declare
  v text;
begin
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', p_uid::text, 'role', 'authenticated')::text,
    true
  );
  execute 'set local role authenticated';
  begin
    execute p_sql into v;
  exception when others then
    reset role;
    return 'ERR:' || sqlstate;
  end;
  reset role;
  return v;
end $$;

insert into t_ctx
select 'admin', (select id::text from public.profiles where role::text = 'admin' order by created_at limit 1);
insert into t_ctx
select 'cust1', (select id::text from public.profiles
                  where role::text = 'customer' and coalesce(is_bot, false) = false
                  order by created_at limit 1);
insert into t_ctx
select 'cust2', (select id::text from public.profiles
                  where role::text = 'customer' and coalesce(is_bot, false) = false
                  order by created_at offset 1 limit 1);
insert into t_ctx
select 'sellers_expected', (select count(*)::text from public.profiles
                             where role::text = 'seller' and coalesce(is_bot, false) = false
                               and id <> pg_temp.ctx('admin')::uuid);
insert into t_ctx
select 'all_expected', (select count(*)::text from public.profiles
                         where coalesce(is_bot, false) = false
                           and id <> pg_temp.ctx('admin')::uuid);

-- -----------------------------------------------------------------------------
-- A) Yapi ve yetki
-- -----------------------------------------------------------------------------
select ok(
  (select relrowsecurity from pg_class where oid = 'public.admin_notification_campaigns'::regclass),
  'admin_notification_campaigns tablosunda RLS acik'
);

select is(
  pg_temp.as_user(pg_temp.ctx('cust1')::uuid,
    'select count(*)::text from public.admin_notification_campaigns'),
  '0',
  'admin olmayan kullanici kampanya tablosundan satir goremez'
);

select ok(
  pg_temp.as_user(pg_temp.ctx('admin')::uuid,
    'select count(*)::text from public.admin_notification_campaigns')::int
    >= (select count(*) from public.admin_broadcasts),
  'admin kampanyalari gorur; eski broadcast''ler kampanyaya tasinmis'
);

select is(
  pg_temp.as_user(pg_temp.ctx('cust1')::uuid,
    $q$select public.admin_notification_history(10)::text$q$),
  'ERR:42501',
  'admin olmayan gecmisi okuyamaz'
);

select is(
  pg_temp.as_user(pg_temp.ctx('cust1')::uuid,
    $q$select public.admin_send_notification('all_users','x','y')::text$q$),
  'ERR:42501',
  'admin olmayan bildirim gonderemez'
);

select is(
  pg_temp.as_user(pg_temp.ctx('cust1')::uuid,
    $q$select public.admin_delete_notification_campaigns(array[gen_random_uuid()])::text$q$),
  'ERR:42501',
  'admin olmayan silemez'
);

select is(
  pg_temp.as_user(pg_temp.ctx('cust1')::uuid,
    $q$select public.admin_update_notification_campaign(gen_random_uuid(),'x','y')::text$q$),
  'ERR:42501',
  'admin olmayan duzenleyemez'
);

select is(
  pg_temp.as_user(pg_temp.ctx('cust1')::uuid,
    $q$select public.admin_notification_audience_count('all_users')::text$q$),
  'ERR:42501',
  'admin olmayan kitle sayisini goremez'
);

select is(
  pg_temp.as_user(pg_temp.ctx('admin')::uuid,
    $q$select public.admin_dispatch_due_notifications()::text$q$),
  'ERR:42501',
  'cron gondericisi istemciye (admin dahil) kapali'
);

-- -----------------------------------------------------------------------------
-- B) Toplu gonderim
-- -----------------------------------------------------------------------------
select is(
  pg_temp.as_user(pg_temp.ctx('admin')::uuid,
    $q$select public.admin_notification_audience_count('sellers')::text$q$),
  pg_temp.ctx('sellers_expected'),
  'kitle sayisi: saticilar (bot ve gonderen haric)'
);

select is(
  pg_temp.as_user(pg_temp.ctx('admin')::uuid,
    $q$select public.admin_notification_audience_count('all_users')::text$q$),
  pg_temp.ctx('all_expected'),
  'kitle sayisi: herkes (bot ve gonderen haric)'
);

insert into t_ctx
select 'bc', pg_temp.as_user(pg_temp.ctx('admin')::uuid,
  $q$select public.admin_send_notification('sellers','Satici duyurusu','Yeni komisyon','discount')::text$q$);

select is(
  (pg_temp.ctx('bc')::jsonb ->> 'recipient_count'),
  pg_temp.ctx('sellers_expected'),
  'toplu gonderim: recipient_count hedef kitleyle ayni'
);

select is(
  (select count(*)::text from public.notifications
    where metadata @> jsonb_build_object('campaign_id', (pg_temp.ctx('bc')::jsonb ->> 'campaign_id'))
      and type = 'admin_broadcast' and entity_id = 'admin_icon:discount'),
  pg_temp.ctx('sellers_expected'),
  'toplu gonderim: her alici icin admin_broadcast satiri yazildi'
);

select ok(
  exists (select 1 from public.admin_broadcasts
           where id = (pg_temp.ctx('bc')::jsonb ->> 'campaign_id')::uuid
             and target_audience = 'sellers' and is_active),
  'toplu gonderim: admin_broadcasts satiri kampanya kimligiyle yazildi'
);

select ok(
  not exists (
    select 1 from public.notifications n
    join public.profiles p on p.id = n.user_id
    where n.metadata @> jsonb_build_object('campaign_id', (pg_temp.ctx('bc')::jsonb ->> 'campaign_id'))
      and (coalesce(p.is_bot, false) or p.id = pg_temp.ctx('admin')::uuid)
  ),
  'toplu gonderim: bot ve gonderen admin alici degil'
);

-- -----------------------------------------------------------------------------
-- C) Kisiye ozel / coklu alici, dogrulama
-- -----------------------------------------------------------------------------
insert into t_ctx
select 'p1', pg_temp.as_user(pg_temp.ctx('admin')::uuid, format(
  $q$select public.admin_send_notification('personal','Ilk mesaj','Birinci','info',
       array[%L, %L]::uuid[])::text$q$, pg_temp.ctx('cust1'), pg_temp.ctx('cust2')));

insert into t_ctx
select 'p2', pg_temp.as_user(pg_temp.ctx('admin')::uuid, format(
  $q$select public.admin_send_notification('personal','Ikinci mesaj','Ikinci','info',
       array[%L]::uuid[])::text$q$, pg_temp.ctx('cust1')));

select is(
  (pg_temp.ctx('p1')::jsonb ->> 'recipient_count'),
  '2',
  'coklu alici: iki kisiye gitti'
);

select is(
  (select count(*)::text from public.notifications
    where user_id = pg_temp.ctx('cust1')::uuid and type = 'admin_notification'
      and entity_id = 'admin_icon:info'
      and metadata->>'campaign_id' in (pg_temp.ctx('p1')::jsonb ->> 'campaign_id',
                                       pg_temp.ctx('p2')::jsonb ->> 'campaign_id')),
  '2',
  'ayni ikonla ust uste gonderilen yonetici bildirimi eskisini SILMEZ'
);

select is(
  pg_temp.as_user(pg_temp.ctx('admin')::uuid,
    $q$select public.admin_send_notification('personal','  ','icerik')::text$q$),
  'ERR:22000',
  'bos baslik reddedilir'
);

select is(
  pg_temp.as_user(pg_temp.ctx('admin')::uuid,
    $q$select public.admin_send_notification('personal','Baslik','icerik','info','{}'::uuid[])::text$q$),
  'ERR:22023',
  'kisiye ozelde alici secmeden gonderilemez'
);

select is(
  pg_temp.as_user(pg_temp.ctx('admin')::uuid,
    $q$select public.admin_send_notification('personal','Baslik','icerik','info',
         array[gen_random_uuid()])::text$q$),
  'ERR:P0002',
  'var olmayan alici reddedilir'
);

select is(
  pg_temp.as_user(pg_temp.ctx('admin')::uuid,
    $q$select public.admin_send_notification('herkes-degil','Baslik','icerik')::text$q$),
  'ERR:22000',
  'gecersiz hedef kitle reddedilir'
);

-- Dedup diger tipler icin surer.
-- Iki AYRI INSERT: tek deyimde iki satir olursa AFTER-ROW outbox tetikleyicisi, dedup'in sildigi ilk satiri bulamaz.
insert into public.notifications (user_id, type, title, content, entity_id, is_read)
values (pg_temp.ctx('cust2')::uuid, 'post_like', 'a', 'b', 'entity-x', false);
insert into public.notifications (user_id, type, title, content, entity_id, is_read)
values (pg_temp.ctx('cust2')::uuid, 'post_like', 'a2', 'b2', 'entity-x', false);

select is(
  (select count(*)::text from public.notifications
    where user_id = pg_temp.ctx('cust2')::uuid and type = 'post_like' and entity_id = 'entity-x'),
  '1',
  'diger tipler icin dedup surer (ayni entity tek satir)'
);

-- -----------------------------------------------------------------------------
-- D) Gecmis ve alicilar
-- -----------------------------------------------------------------------------
select is(
  pg_temp.as_user(pg_temp.ctx('admin')::uuid, format(
    $q$select (select h.recipient_count::text || '/' || h.read_count::text || '/' || h.live_count::text
               from public.admin_notification_history(500) h where h.id = %L)$q$,
    pg_temp.ctx('p1')::jsonb ->> 'campaign_id')),
  '2/0/2',
  'gecmis: alici / okunan / canli sayilari'
);

update public.notifications set is_read = true
 where user_id = pg_temp.ctx('cust1')::uuid
   and metadata @> jsonb_build_object('campaign_id', (pg_temp.ctx('p1')::jsonb ->> 'campaign_id'));

select is(
  pg_temp.as_user(pg_temp.ctx('admin')::uuid, format(
    $q$select (select h.read_count::text
               from public.admin_notification_history(500) h where h.id = %L)$q$,
    pg_temp.ctx('p1')::jsonb ->> 'campaign_id')),
  '1',
  'gecmis: okunan sayisi gercek is_read durumundan gelir'
);

select is(
  pg_temp.as_user(pg_temp.ctx('admin')::uuid, format(
    $q$select count(*)::text from public.admin_notification_recipients(%L, 'read')$q$,
    pg_temp.ctx('p1')::jsonb ->> 'campaign_id')),
  '1',
  'alicilar: yalniz okuyanlar filtresi'
);

select is(
  pg_temp.as_user(pg_temp.ctx('admin')::uuid, format(
    $q$select count(*)::text from public.admin_notification_recipients(%L, 'unread')$q$,
    pg_temp.ctx('p1')::jsonb ->> 'campaign_id')),
  '1',
  'alicilar: yalniz okumayanlar filtresi'
);

-- -----------------------------------------------------------------------------
-- E) Duzenle ve yeniden bildir
-- -----------------------------------------------------------------------------
-- Outbox satirlarini "gonderildi" say: yeniden bildirim bunlari sifirlamali.
update public.notification_outbox
   set status = 'sent', sent_at = now(), attempts = 1
 where notification_id in (
   select id from public.notifications
    where metadata @> jsonb_build_object('campaign_id', (pg_temp.ctx('bc')::jsonb ->> 'campaign_id'))
 );

select is(
  pg_temp.as_user(pg_temp.ctx('admin')::uuid, format(
    $q$select (public.admin_update_notification_campaign(%L, 'Duzeltildi', 'Yeni metin', 'gift')
               ->> 'updated_rows')$q$,
    pg_temp.ctx('bc')::jsonb ->> 'campaign_id')),
  pg_temp.ctx('sellers_expected'),
  'duzenleme: tum alici satirlari guncellendi'
);

select ok(
  (select bool_and(n.title = 'Duzeltildi' and n.content = 'Yeni metin'
                   and n.entity_id = 'admin_icon:gift')
     from public.notifications n
    where n.metadata @> jsonb_build_object('campaign_id', (pg_temp.ctx('bc')::jsonb ->> 'campaign_id')))
  and exists (select 1 from public.admin_broadcasts b
               where b.id = (pg_temp.ctx('bc')::jsonb ->> 'campaign_id')::uuid
                 and b.title = 'Duzeltildi' and b.icon_type = 'gift')
  and exists (select 1 from public.admin_notification_campaigns c
               where c.id = (pg_temp.ctx('bc')::jsonb ->> 'campaign_id')::uuid
                 and c.title = 'Duzeltildi' and c.edited_at is not null),
  'duzenleme: kampanya, broadcast ve alici satirlari birlikte guncellenir'
);

select is(
  (select count(*)::text from public.notification_outbox o
    where o.status = 'sent'
      and o.notification_id in (
        select id from public.notifications
         where metadata @> jsonb_build_object('campaign_id', (pg_temp.ctx('bc')::jsonb ->> 'campaign_id')))),
  pg_temp.ctx('sellers_expected'),
  'yeniden bildir KAPALIyken outbox dokunulmaz'
);

do $$ begin
  perform pg_temp.as_user(pg_temp.ctx('admin')::uuid, format(
    $q$select (public.admin_update_notification_campaign(%L, 'Duzeltildi', 'Yeni metin', 'gift', null, true)
               ->> 'renotified')$q$,
    pg_temp.ctx('bc')::jsonb ->> 'campaign_id'));
end $$;

select is(
  (select count(*)::text from public.notification_outbox o
    where o.status = 'pending'
      and o.notification_id in (
        select id from public.notifications
         where metadata @> jsonb_build_object('campaign_id', (pg_temp.ctx('bc')::jsonb ->> 'campaign_id'))
           and is_read = false)),
  pg_temp.ctx('sellers_expected'),
  'yeniden bildir: okunmadi + outbox tekrar pending'
);

-- -----------------------------------------------------------------------------
-- F) Sil
-- -----------------------------------------------------------------------------
select is(
  pg_temp.as_user(pg_temp.ctx('admin')::uuid, format(
    $q$select public.admin_delete_notification_campaigns(array[%L]::uuid[])::text$q$,
    pg_temp.ctx('bc')::jsonb ->> 'campaign_id')),
  '1',
  'silme: bir kampanya silindi'
);

select ok(
  not exists (select 1 from public.notifications
               where metadata @> jsonb_build_object('campaign_id', (pg_temp.ctx('bc')::jsonb ->> 'campaign_id')))
  and not exists (select 1 from public.admin_broadcasts
                   where id = (pg_temp.ctx('bc')::jsonb ->> 'campaign_id')::uuid)
  and not exists (select 1 from public.admin_notification_campaigns
                   where id = (pg_temp.ctx('bc')::jsonb ->> 'campaign_id')::uuid),
  'silme: alici satirlari, broadcast ve kampanya kalkti'
);

select ok(
  exists (select 1 from public.admin_notification_audit where action = 'delete' and title = 'Duzeltildi'),
  'silme denetim kaydina yazildi'
);

-- -----------------------------------------------------------------------------
-- G) Zamanlama
-- -----------------------------------------------------------------------------
insert into t_ctx
select 'sch', pg_temp.as_user(pg_temp.ctx('admin')::uuid, format(
  $q$select public.admin_send_notification('personal','Zamanli','Sonra','event',
       array[%L]::uuid[], now() + interval '1 hour')::text$q$, pg_temp.ctx('cust2')));

select is(
  (pg_temp.ctx('sch')::jsonb ->> 'status'),
  'scheduled',
  'zamanli gonderim: durum scheduled'
);

select ok(
  not exists (select 1 from public.notifications
               where metadata @> jsonb_build_object('campaign_id', (pg_temp.ctx('sch')::jsonb ->> 'campaign_id'))),
  'zamanli gonderim: zamani gelmeden alici satiri yok'
);

select is(
  pg_temp.as_user(pg_temp.ctx('admin')::uuid, format(
    $q$select count(*)::text from public.admin_notification_recipients(%L)$q$,
    pg_temp.ctx('sch')::jsonb ->> 'campaign_id')),
  '1',
  'zamanli gonderim: secili alicilar listelenir'
);

do $$ begin
  perform pg_temp.as_user(pg_temp.ctx('admin')::uuid, format(
    $q$select public.admin_update_notification_campaign(%L, 'Zamanli (duzenlendi)', 'Sonra', 'event')::text$q$,
    pg_temp.ctx('sch')::jsonb ->> 'campaign_id'));
end $$;

select ok(
  exists (select 1 from public.admin_notification_campaigns
           where id = (pg_temp.ctx('sch')::jsonb ->> 'campaign_id')::uuid
             and title = 'Zamanli (duzenlendi)' and status = 'scheduled'
             and scheduled_for is not null),
  'zamanli kampanya duzenlenince zamani ve durumu korunur'
);

select is(
  pg_temp.as_user(pg_temp.ctx('admin')::uuid, format(
    $q$select (public.admin_send_notification_campaign_now(%L) ->> 'recipient_count')$q$,
    pg_temp.ctx('sch')::jsonb ->> 'campaign_id')),
  '1',
  'zamanliyi simdi gonder: alici satiri yazildi'
);

-- Cron gondericisi: zamani gelen kampanya gider.
insert into t_ctx
select 'due', pg_temp.as_user(pg_temp.ctx('admin')::uuid, format(
  $q$select public.admin_send_notification('personal','Cron','Zamani geldi','news',
       array[%L]::uuid[], now() + interval '2 hours')::text$q$, pg_temp.ctx('cust1')));

update public.admin_notification_campaigns
   set scheduled_for = now() - interval '1 minute'
 where id = (pg_temp.ctx('due')::jsonb ->> 'campaign_id')::uuid;

-- Ayri deyim: ayni sorgudaki EXISTS, fonksiyonun yazdiklarini goremez (snapshot).
insert into t_ctx select 'dispatched', public.admin_dispatch_due_notifications()::text;

select ok(
  pg_temp.ctx('dispatched')::int >= 1
  and exists (select 1 from public.admin_notification_campaigns
               where id = (pg_temp.ctx('due')::jsonb ->> 'campaign_id')::uuid
                 and status = 'sent' and recipient_count = 1)
  and exists (select 1 from public.notifications
               where metadata @> jsonb_build_object('campaign_id', (pg_temp.ctx('due')::jsonb ->> 'campaign_id'))),
  'cron gondericisi zamani gelen kampanyayi gonderir'
);

-- -----------------------------------------------------------------------------
-- H) Eski RPC imzalari
-- -----------------------------------------------------------------------------
insert into t_ctx
select 'old_personal', pg_temp.as_user(pg_temp.ctx('admin')::uuid, format(
  $q$select public.admin_send_personal_notification(%L, 'Eski RPC', 'Kisisel', 'info')::text$q$,
  pg_temp.ctx('cust1')));

select ok(
  exists (
    select 1 from public.admin_notification_campaigns c
    where c.id::text = pg_temp.ctx('old_personal')
      and c.kind = 'personal' and c.recipient_count = 1
  ),
  'eski admin_send_personal_notification kampanya olusturur ve kampanya kimligini doner'
);

select is(
  pg_temp.as_user(pg_temp.ctx('admin')::uuid,
    $q$select public.admin_broadcast_notification('B','C','info','personal')::text$q$),
  'ERR:22000',
  'eski admin_broadcast_notification "personal" hedefi reddeder'
);

select ok(
  not exists (
    select 1 from public.admin_broadcasts b
    where not exists (select 1 from public.admin_notification_campaigns c where c.id = b.id)
  ),
  'her admin_broadcasts satirinin bir kampanyasi var'
);

select * from finish();

rollback;

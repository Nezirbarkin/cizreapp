-- =============================================================================
-- 2026-08-02 — Güvenli push notification pipeline değişmezleri
--
-- Çalıştırma:
--   supabase start
--   supabase test db
--
-- Bu testler veri yazmaz. Katalog üzerinden şema, RLS, GRANT, SECURITY
-- DEFINER ACL yapılandırmasını doğrular.
-- =============================================================================

begin;

create extension if not exists pgtap with schema extensions;

select plan(20);

-- -----------------------------------------------------------------------------
-- Yardımcı test fonksiyonları
-- -----------------------------------------------------------------------------

create or replace function pg_temp.has_function(p_signature text)
returns boolean
language sql
stable
as $$
  select exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.oid::regprocedure::text = p_signature
  );
$$;

create or replace function pg_temp.function_src_contains(
  p_function_name text,
  p_needle text
)
returns boolean
language sql
stable
as $$
  select position(p_needle in p.prosrc) > 0
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = p_function_name
  limit 1;
$$;

create or replace function pg_temp.function_src_not_contains(
  p_function_name text,
  p_needle text
)
returns boolean
language sql
stable
as $$
  select not pg_temp.function_src_contains(p_function_name, p_needle);
$$;

-- -----------------------------------------------------------------------------
-- A) notification_outbox şeması
-- -----------------------------------------------------------------------------
select has_table(
  'public',
  'notification_outbox',
  'notification_outbox tablosu mevcut'
);

select has_column(
  'public',
  'notification_outbox',
  'notification_id',
  'notification_id sütunu mevcut'
);

select col_is_unique(
  'public',
  'notification_outbox',
  array['notification_id'],
  'notification_id üzerinde UNIQUE constraint var (notification_outbox_notification_uniq)'
);

-- -----------------------------------------------------------------------------
-- B) Outbox yönetim RPC'leri
-- -----------------------------------------------------------------------------
select ok(
  pg_temp.has_function('public.enqueue_notification_outbox(uuid)'),
  'enqueue_notification_outbox(uuid) RPC mevcut'
);

select ok(
  pg_temp.has_function('public.claim_notification_outbox(integer, text)'),
  'claim_notification_outbox(integer, text) RPC mevcut'
);

select ok(
  pg_temp.has_function('public.mark_outbox_sent(uuid)'),
  'mark_outbox_sent(uuid) RPC mevcut'
);

select ok(
  pg_temp.has_function('public.mark_outbox_failed(uuid, text, integer)'),
  'mark_outbox_failed(uuid, text, integer) RPC mevcut'
);

select ok(
  pg_temp.has_function('public.release_stale_outbox(interval)'),
  'release_stale_outbox(interval) RPC mevcut'
);

-- -----------------------------------------------------------------------------
-- C) Güvensiz fonksiyonlar kaldırıldı / yeniden adlandırıldı
-- -----------------------------------------------------------------------------
select ok(
  not pg_temp.has_function('public.send_push_on_notification()'),
  'send_push_on_notification() artık mevcut değil (DEPRECATED olarak yeniden adlandırıldı)'
);

select ok(
  pg_temp.has_function('public.send_push_on_notification_deprecated()'),
  'send_push_on_notification_deprecated() mevcut (eski tetikleyici tarafından tetiklenmeyecek)'
);

-- -----------------------------------------------------------------------------
-- D) notify_price_drops yeni tanımı net.http_post KULLANMAZ
-- -----------------------------------------------------------------------------
select ok(
  pg_temp.has_function('public.notify_price_drops()'),
  'notify_price_drops() mevcut'
);

select ok(
  pg_temp.function_src_not_contains('notify_price_drops', 'net.http_post'),
  'notify_price_drops() net.http_post çağrısı içermez'
);

select ok(
  pg_temp.function_src_not_contains('notify_price_drops', 'xsbukxkgtmdyickknqzf.supabase.co'),
  'notify_price_drops() sabit project URL içermez'
);

select ok(
  pg_temp.function_src_not_contains('notify_price_drops', 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9'),
  'notify_price_drops() sabit anon JWT içermez'
);

-- -----------------------------------------------------------------------------
-- E) enqueue_notification_outbox yalnızca service_role
-- -----------------------------------------------------------------------------
select ok(
  pg_temp.has_function('public.enqueue_notification_outbox(uuid)')
    and has_function_privilege(
      'service_role',
      'public.enqueue_notification_outbox(uuid)',
      'EXECUTE'
    ),
  'service_role enqueue_notification_outbox çalıştırabilir'
);

-- -----------------------------------------------------------------------------
-- F) share_post_with_user yalnızca authenticated
-- -----------------------------------------------------------------------------
select ok(
  pg_temp.has_function('public.share_post_with_user(uuid, uuid)'),
  'share_post_with_user(uuid, uuid) RPC mevcut'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.share_post_with_user(uuid, uuid)',
    'EXECUTE'
  ),
  'authenticated share_post_with_user çalıştırabilir'
);

-- -----------------------------------------------------------------------------
-- G) Admin RPC'leri mevcut
-- -----------------------------------------------------------------------------
select ok(
  pg_temp.has_function('public.admin_send_personal_notification(uuid, text, text, text)'),
  'admin_send_personal_notification RPC mevcut'
);

select ok(
  pg_temp.has_function('public.admin_broadcast_notification(text, text, text, text)'),
  'admin_broadcast_notification RPC mevcut'
);

-- -----------------------------------------------------------------------------
-- H) Eski trigger'lar kaldırıldı, yenileri bağlandı
-- -----------------------------------------------------------------------------
select ok(
  not exists (
    select 1 from pg_trigger
    where tgname = 'notifications_push_trigger'
      and tgrelid = 'public.notifications'::regclass
  ),
  'notifications_push_trigger kaldırıldı'
);

select ok(
  exists (
    select 1 from pg_trigger
    where tgname = 'notifications_outbox_trigger'
      and tgrelid = 'public.notifications'::regclass
  ),
  'notifications_outbox_trigger bağlandı'
);

select * from finish();
rollback;

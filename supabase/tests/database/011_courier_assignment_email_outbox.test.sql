-- Kurye atama e-posta outbox katalog/güvenlik sözleşmesi
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(12);

SELECT has_table(
  'public',
  'courier_assignment_email_outbox',
  'Kurye atama e-posta outbox tablosu mevcut'
);

SELECT has_trigger(
  'public',
  'notifications',
  'notifications_courier_assignment_email_trigger',
  'Notifications e-posta outbox triggerı mevcut'
);

SELECT has_function(
  'public',
  'enqueue_courier_assignment_email_trigger',
  ARRAY[]::text[],
  'E-posta enqueue trigger fonksiyonu mevcut'
);

SELECT has_function(
  'public',
  'claim_courier_assignment_emails',
  ARRAY['integer', 'text'],
  'E-posta claim RPC mevcut'
);

SELECT has_function(
  'public',
  'mark_courier_assignment_email_sent',
  ARRAY['uuid'],
  'E-posta sent RPC mevcut'
);

SELECT has_function(
  'public',
  'mark_courier_assignment_email_failed',
  ARRAY['uuid', 'text', 'integer'],
  'E-posta failed RPC mevcut'
);

SELECT has_function(
  'public',
  'release_stale_courier_assignment_emails',
  ARRAY['interval'],
  'Stale e-posta claim release RPC mevcut'
);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM pg_indexes
    WHERE schemaname = 'public'
      AND tablename = 'courier_assignment_email_outbox'
      AND indexdef ILIKE '%UNIQUE%notification_id%'
  ),
  'notification_id unique ile e-posta idempotency korunuyor'
);

SELECT ok(
  NOT has_table_privilege(
    'authenticated',
    'public.courier_assignment_email_outbox',
    'SELECT'
  ),
  'authenticated outbox okuyamaz'
);

SELECT ok(
  NOT has_table_privilege(
    'authenticated',
    'public.courier_assignment_email_outbox',
    'INSERT'
  ),
  'authenticated outbox yazamaz'
);

SELECT ok(
  NOT has_function_privilege(
    'authenticated',
    'public.claim_courier_assignment_emails(integer,text)',
    'EXECUTE'
  ),
  'authenticated e-posta claim RPC çağıramaz'
);

SELECT ok(
  has_function_privilege(
    'service_role',
    'public.claim_courier_assignment_emails(integer,text)',
    'EXECUTE'
  ),
  'service_role e-posta claim RPC çağırabilir'
);

SELECT * FROM finish();
ROLLBACK;


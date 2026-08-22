-- AdMob reward-point catalog, ACL, isolation and immutability invariants.
begin;
create extension if not exists pgtap with schema extensions;
select plan(48);

select has_table('public', 'user_point_accounts', 'point account exists');
select has_table('public', 'point_ledger_entries', 'point ledger exists');
select has_table('public', 'ad_reward_sessions', 'reward session exists');
select has_table('public', 'ad_reward_ssv_events', 'SSV event exists');
select has_table('public', 'ad_reward_daily_budgets', 'daily budget exists');
select has_table('public', 'digital_order_refunds', 'composition refund exists');
select ok(to_regclass('public.reward_points_public_config') is not null,
  'safe public reward config view exists');
select ok(to_regclass('public.my_point_ledger_entries') is not null,
  'safe own-ledger view exists');
select ok(to_regclass('public.my_ad_reward_sessions') is not null,
  'safe own-session view exists');

select ok((select relrowsecurity from pg_class where oid='public.user_point_accounts'::regclass), 'account RLS enabled');
select ok((select relrowsecurity from pg_class where oid='public.point_ledger_entries'::regclass), 'ledger RLS enabled');
select ok((select relrowsecurity from pg_class where oid='public.ad_reward_ssv_events'::regclass), 'SSV RLS enabled');

select ok(exists(
  select 1 from pg_roles
  where rolname = 'reward_points_owner'
    and not rolcanlogin and not rolinherit and not rolsuper and not rolbypassrls
), 'reward owner is a constrained non-login role');

select ok(not exists(
  select 1
  from (values
    ('public.user_point_accounts'::regclass),
    ('public.point_ledger_entries'::regclass),
    ('public.ad_reward_sessions'::regclass),
    ('public.ad_reward_ssv_events'::regclass),
    ('public.ad_reward_daily_budgets'::regclass),
    ('public.reward_points_config_audit'::regclass),
    ('public.reward_points_migration_audits'::regclass),
    ('public.digital_order_refunds'::regclass)
  ) as expected(relid)
  join pg_class c on c.oid = expected.relid
  where pg_get_userbyid(c.relowner) <> 'reward_points_owner'
), 'reward storage tables are owned by the constrained owner');

select ok(not exists(
  select 1
  from unnest(array[
    'public.reward_points_apply_entry(uuid,text,text,bigint,text,uuid,text,jsonb)'::regprocedure,
    'public.reject_point_ledger_mutation()'::regprocedure,
    'public.create_ad_reward_session(uuid,text,text,text,text)'::regprocedure,
    'public.grant_verified_ad_points(uuid,text,text,text,text,timestamptz,text,text)'::regprocedure,
    'public.create_digital_order_with_points(uuid,uuid,text,integer,text,boolean)'::regprocedure,
    'public.refund_digital_order_payment(uuid,numeric,text,text,boolean)'::regprocedure,
    'public.set_digital_order_reconciliation(uuid,text)'::regprocedure,
    'public.credit_digital_order_seller(uuid,numeric)'::regprocedure,
    'public.admin_update_reward_points_config(integer,integer,bigint,integer,boolean,text,boolean,boolean,boolean,boolean,text,integer,integer,integer,boolean,text,text,text,text)'::regprocedure,
    'public.admin_reward_points_overview()'::regprocedure,
    'public.purge_expired_reward_fraud_hashes(integer)'::regprocedure,
    'public.enforce_product_points_eligibility_admin()'::regprocedure
  ]) as expected(procid)
  join pg_proc p on p.oid = expected.procid
  where pg_get_userbyid(p.proowner) <> 'reward_points_owner'
), 'reward SECURITY DEFINER functions use the constrained owner');

select ok(not exists(
  select 1
  from (values
    ('profiles', 'reward_points_owner_profiles_select', 'r'::"char"),
    ('products', 'reward_points_owner_products_select', 'r'::"char"),
    ('shops', 'reward_points_owner_shops_select', 'r'::"char"),
    ('ad_settings', 'reward_points_owner_ad_settings_select', 'r'::"char"),
    ('ad_settings', 'reward_points_owner_ad_settings_update', 'w'::"char"),
    ('user_balances', 'reward_points_owner_user_balances_select', 'r'::"char"),
    ('user_balances', 'reward_points_owner_user_balances_insert', 'a'::"char"),
    ('user_balances', 'reward_points_owner_user_balances_update', 'w'::"char"),
    ('digital_orders', 'reward_points_owner_digital_orders_select', 'r'::"char"),
    ('digital_orders', 'reward_points_owner_digital_orders_insert', 'a'::"char"),
    ('digital_orders', 'reward_points_owner_digital_orders_update', 'w'::"char"),
    ('balance_transactions', 'reward_points_owner_balance_transactions_insert', 'a'::"char")
  ) as expected(table_name, policy_name, command)
  where not exists(
    select 1
    from pg_policy p
    join pg_class c on c.oid = p.polrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = expected.table_name
      and p.polname = expected.policy_name
      and p.polcmd = expected.command
      and (select oid from pg_roles where rolname = 'reward_points_owner') = any(p.polroles)
  )
), 'reward owner has all required narrow RLS policies');

select ok(
  has_table_privilege('reward_points_owner', 'public.profiles', 'SELECT')
  and has_table_privilege('reward_points_owner', 'public.products', 'SELECT')
  and has_table_privilege('reward_points_owner', 'public.shops', 'SELECT')
  and has_table_privilege('reward_points_owner', 'public.ad_settings', 'SELECT')
  and has_table_privilege('reward_points_owner', 'public.ad_settings', 'UPDATE')
  and has_table_privilege('reward_points_owner', 'public.user_balances', 'SELECT')
  and has_table_privilege('reward_points_owner', 'public.user_balances', 'INSERT')
  and has_table_privilege('reward_points_owner', 'public.user_balances', 'UPDATE')
  and has_table_privilege('reward_points_owner', 'public.digital_orders', 'SELECT')
  and has_table_privilege('reward_points_owner', 'public.digital_orders', 'INSERT')
  and has_table_privilege('reward_points_owner', 'public.digital_orders', 'UPDATE')
  and has_table_privilege('reward_points_owner', 'public.balance_transactions', 'INSERT'),
  'reward owner has required base-table grants'
);

select ok(
  has_type_privilege('reward_points_owner', 'public.balance_transaction_type', 'USAGE')
  and has_type_privilege('reward_points_owner', 'public.balance_transaction_status', 'USAGE')
  and has_type_privilege('reward_points_owner', 'public.digital_order_status', 'USAGE'),
  'reward owner can use required application enum types'
);

select ok(not has_schema_privilege('reward_points_owner', 'public', 'CREATE'),
  'reward owner cannot create arbitrary public-schema objects');

select ok(
  has_schema_privilege('reward_points_owner', 'auth', 'USAGE')
  and has_function_privilege('reward_points_owner', 'auth.uid()', 'EXECUTE'),
  'reward owner can resolve auth.uid for SECURITY DEFINER admin gates'
);

select ok(not has_table_privilege('anon','public.user_point_accounts','SELECT'), 'anon cannot read accounts');
select ok(not has_table_privilege('anon','public.point_ledger_entries','SELECT'), 'anon cannot read ledger');
select ok(not has_table_privilege('authenticated','public.point_ledger_entries','INSERT'), 'authenticated cannot insert ledger');
select ok(not has_table_privilege('authenticated','public.point_ledger_entries','UPDATE'), 'authenticated cannot update ledger');
select ok(not has_table_privilege('service_role','public.point_ledger_entries','UPDATE'), 'service role cannot directly update ledger');
select ok(not has_table_privilege('service_role','public.point_ledger_entries','DELETE'), 'service role cannot directly delete ledger');

select ok(exists(select 1 from pg_trigger where tgrelid='public.point_ledger_entries'::regclass and tgname='point_ledger_reject_update_delete'), 'ledger update/delete trigger exists');
select ok(exists(select 1 from pg_trigger where tgrelid='public.point_ledger_entries'::regclass and tgname='point_ledger_reject_truncate'), 'ledger truncate trigger exists');

select ok(to_regprocedure('public.grant_verified_ad_points(uuid,text,text,text,text,timestamptz,text,text)') is not null,
  'SSV credit RPC requires a custom-data nonce hash');
select ok(to_regprocedure('public.grant_verified_ad_points(uuid,text,text,text,text,timestamptz,text)') is null,
  'nonce-unbound SSV credit signature does not exist');
select ok(not has_function_privilege('anon','public.grant_verified_ad_points(uuid,text,text,text,text,timestamptz,text,text)','EXECUTE')
  and not has_function_privilege('authenticated','public.grant_verified_ad_points(uuid,text,text,text,text,timestamptz,text,text)','EXECUTE'), 'SSV credit is client-closed');
select ok(has_function_privilege('service_role','public.grant_verified_ad_points(uuid,text,text,text,text,timestamptz,text,text)','EXECUTE'), 'SSV credit is service-only');
select ok(not has_function_privilege('service_role','public.grant_ad_reward(uuid,text,text,integer)','EXECUTE'), 'legacy TL grant is closed to service role too');
select ok(not has_function_privilege('authenticated','public.create_digital_order(uuid,uuid,text,integer)','EXECUTE'), 'legacy checkout is closed');
select ok(not has_function_privilege('authenticated','public.refund_digital_order_payment(uuid,numeric,text,text,boolean)','EXECUTE'), 'refund is client-closed');
select ok(
  has_function_privilege('service_role','public.credit_digital_order_seller(uuid,numeric)','EXECUTE')
  and not has_function_privilege('anon','public.credit_digital_order_seller(uuid,numeric)','EXECUTE')
  and not has_function_privilege('authenticated','public.credit_digital_order_seller(uuid,numeric)','EXECUTE'),
  'seller credit is service-only'
);

select ok(exists(
  select 1 from information_schema.columns
  where table_schema='public' and table_name='ad_reward_sessions'
    and column_name='reward_points_snapshot' and data_type='integer'
), 'reward amount is snapshotted on the server session');

select ok(exists(
  select 1 from information_schema.columns
  where table_schema='public' and table_name='digital_orders'
    and column_name='requested_use_points' and data_type='boolean'
), 'point-use preference is part of the order idempotency snapshot');

select ok(not exists(
  select 1 from information_schema.columns
  where table_schema='public' and table_name='my_point_ledger_entries'
    and column_name in ('idempotency_key','metadata','reversal_of_entry_id')
), 'safe ledger view hides internal idempotency and metadata fields');

select ok(not exists(
  select 1 from information_schema.columns
  where table_schema='public' and table_name='reward_points_public_config'
    and column_name in ('admob_app_id_android','admob_app_id_ios')
), 'public reward config excludes native AdMob App IDs');

select ok(not exists(
  select 1
  from (values ('admob_rewarded_unit_id_android'), ('admob_rewarded_unit_id_ios'))
    as expected(column_name)
  where not exists (
    select 1 from information_schema.columns c
    where c.table_schema='public'
      and c.table_name='reward_points_public_config'
      and c.column_name=expected.column_name
  )
), 'public reward config exposes both runtime rewarded unit IDs');

select ok(exists(
  select 1 from pg_trigger
  where tgrelid='public.products'::regclass
    and tgname='products_enforce_points_eligibility_admin'
    and not tgisinternal
), 'product point eligibility is protected by an admin gate trigger');

select ok(exists(
  select 1 from pg_constraint
  where conrelid='public.ad_settings'::regclass
    and conname='ad_settings_reward_points_range_check'
), 'reward config enforces a fixed point award');

select ok(exists(
  select 1 from pg_constraint
  where conrelid='public.ad_settings'::regclass
    and conname='ad_settings_points_per_try_cents_check'
), 'point conversion always resolves to whole kuruş');

select ok(not exists(
  select 1 from information_schema.columns
  where table_schema='public' and table_name in ('ad_reward_sessions','ad_reward_ssv_events')
    and column_name in ('ip_address','device_id','raw_ip','signature','raw_query')
), 'reward fraud tables contain no raw PII/signature columns');

select ok(not exists(
  select 1 from pg_constraint c
  where c.contype='f' and c.conrelid in ('public.user_point_accounts'::regclass,'public.point_ledger_entries'::regclass)
    and c.confrelid in ('public.user_balances'::regclass,'public.balance_transactions'::regclass)
), 'point storage has no FK into cash storage');

select ok(not exists(
  select 1 from public.point_ledger_entries where entry_type = 'ad_reward_credit'
), 'migration performs no historical ad point backfill');

select ok(not exists(
  select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname in ('grant_verified_ad_points','create_ad_reward_session',
    'create_digital_order_with_points','refund_digital_order_payment','credit_digital_order_seller',
    'admin_update_reward_points_config','admin_reward_points_overview')
    and (not p.prosecdef or coalesce(array_to_string(p.proconfig,','),'') not like '%search_path=%')
), 'reward SECURITY DEFINER RPCs pin search_path');

select * from finish();
rollback;

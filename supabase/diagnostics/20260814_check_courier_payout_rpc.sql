select jsonb_pretty(jsonb_build_object(
  'policies', (select jsonb_agg(jsonb_build_object(
      'name', policyname, 'cmd', cmd, 'roles', roles::text, 'qual', qual, 'with_check', with_check
    ) order by policyname)
    from pg_policies where schemaname='public' and tablename='courier_payout_requests'),
  'grants', (select coalesce(jsonb_agg(jsonb_build_object('priv', privilege_type, 'grantee', grantee)), '[]'::jsonb)
    from information_schema.role_table_grants
    where table_schema='public' and table_name='courier_payout_requests' and grantee='authenticated')
)) as durum;

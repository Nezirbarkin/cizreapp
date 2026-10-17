-- ============================================================================
-- 20261017000005_server_created_at_and_tz_backfill — canlı test (geri alır)
-- Göç öncesi: göç gövdesini @@MIGRATION@@ işaretli satırın yerine koyun
-- (geri dönük düzeltme sayıları yalnız ilk uygulamada anlamlıdır).
--   supabase db query --linked --file supabase/tests/manual/server_created_at_test.sql
-- ============================================================================
BEGIN;

CREATE TEMP TABLE _before ON COMMIT DROP AS
SELECT id, created_at, updated_at FROM public.orders;
CREATE TEMP TABLE _before_shops ON COMMIT DROP AS
SELECT id, rating, review_count FROM public.shops;

-- @@MIGRATION@@

CREATE TEMP TABLE _tz_results (n serial, line text) ON COMMIT DROP;

DO $test$
declare
  v_user uuid; v_cnt int; v_ts timestamptz; v_id uuid;
  r text := '';
begin
  select count(*) into v_cnt from public.orders o join _before b using (id)
   where o.created_at = b.created_at - interval '3 hours';
  r := r || format('kaydirilan siparis: %s', v_cnt);

  select count(*) into v_cnt from public.orders o join _before b using (id)
   where o.updated_at is distinct from b.updated_at;
  r := r || chr(10) || case when v_cnt = 0 then 'PASS siparislerin updated_at degismedi'
                            else format('FAIL %s siparisin updated_at degisti', v_cnt) end;

  select count(*) into v_cnt from public.shops s join _before_shops b using (id)
   where s.rating is distinct from b.rating or s.review_count is distinct from b.review_count;
  r := r || chr(10) || case when v_cnt = 0 then 'PASS dukkan puanlari degismedi'
                            else format('FAIL %s dukkanin puani degisti', v_cnt) end;

  -- İstemci eski tarih gönderse de sunucu saati yazılır.
  select id into v_user from public.profiles where role = 'customer' order by created_at limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub', v_user, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  insert into public.notifications (user_id, type, title, content, created_at)
  values (v_user, 'tz_test', 't', 'c', '2000-01-01T00:00:00')
  returning id, created_at into v_id, v_ts;
  execute 'reset role';
  r := r || chr(10) || case when v_ts > now() - interval '1 minute'
                            then 'PASS istemcinin created_at degeri sunucu saatiyle ezildi'
                            else format('FAIL created_at=%s', v_ts) end;

  insert into _tz_results(line) values (r);
end
$test$;

SELECT string_agg(line, E'\n' ORDER BY n) AS result FROM _tz_results;

ROLLBACK;

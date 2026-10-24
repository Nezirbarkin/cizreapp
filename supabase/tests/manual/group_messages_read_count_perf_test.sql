-- ============================================================================
-- 20261023000004_group_messages_read_count_perf — eşdeğerlik testi
-- ----------------------------------------------------------------------------
-- Kendi kendini geri alır. Yeni tek parametreli sürüm, eski tanımın sorgusuyla
-- (satır satır) aynı sonucu vermeli; iki parametreli sürüm büyük limitle
-- tek parametreliyle aynı, küçük limitle son N mesaj (eskiden yeniye).
--   supabase db query --linked --file supabase/tests/manual/group_messages_read_count_perf_test.sql
-- ============================================================================
BEGIN;

-- @@MIGRATION@@

DO $test$
declare
  g record;
  v_old jsonb; v_new jsonb; v_lim jsonb; v_last jsonb;
  v_groups int := 0; v_mismatch int := 0;
  r text := '';
begin
  for g in select id from public.groups loop
    v_groups := v_groups + 1;

    select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at, x.id), '[]') into v_old from (
      SELECT gm.id, gm.group_id, gm.sender_id, gm.content, gm.created_at, gm.updated_at,
             gm.reply_to_id, COALESCE(rrr.read_count, 0)::INTEGER as read_by_count,
             COALESCE(rm.content, '') as reply_to_content,
             COALESCE(p.full_name, '') as reply_to_sender_name
      FROM public.group_messages gm
      LEFT JOIN (SELECT message_id, COUNT(*)::INTEGER as read_count
                 FROM public.group_message_read_receipts GROUP BY message_id) rrr
        ON rrr.message_id = gm.id
      LEFT JOIN public.group_messages rm ON rm.id = gm.reply_to_id
      LEFT JOIN public.profiles p ON p.id = rm.sender_id
      WHERE gm.group_id = g.id) x;

    select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at, x.id), '[]') into v_new
      from public.get_group_messages_with_read_count(g.id) x;
    select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at, x.id), '[]') into v_lim
      from public.get_group_messages_with_read_count(g.id, 500) x;

    if v_old is distinct from v_new or v_new is distinct from v_lim then
      v_mismatch := v_mismatch + 1;
    end if;
  end loop;

  r := r || chr(10) || format('groups=%s mismatches=%s', v_groups, v_mismatch);
  r := r || chr(10) || case when v_mismatch = 0 then 'PASS eşdeğer' else 'FAIL farklı sonuç' end;

  -- Son N: en çok mesajlı grupta limit 1 → en yeni mesaj
  select gm.group_id into g from public.group_messages gm
   group by gm.group_id order by count(*) desc limit 1;
  if found then
    select coalesce(jsonb_agg(x.id), '[]') into v_last
      from public.get_group_messages_with_read_count(g.group_id, 1) x;
    r := r || chr(10) || case when v_last = (
        select jsonb_agg(m.id) from (select id from public.group_messages
          where group_id = g.group_id order by created_at desc limit 1) m)
      then 'PASS limit son mesajı döndürür' else format('FAIL limit %s', v_last) end;
  end if;

  raise exception 'TESTS_DONE %', r;
end;
$test$;

ROLLBACK;

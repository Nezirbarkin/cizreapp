-- =============================================================================
-- get_my_order_unlock_progress: bigint/integer tip uyuşmazlığı düzeltmesi
-- =============================================================================
-- Sorun: count(*) Postgres'te bigint döner ama fonksiyon total_items/
-- unlocked_items kolonlarını integer olarak tanımlamıştı. Sonuç: her çağrıda
-- "structure of query does not match function result type ... Returned type
-- bigint does not match expected type integer in column 7" hatasıyla
-- başarısız oluyordu. Flutter tarafı (ProfileFeatureService.getMyOrderUnlockProgress)
-- bu hatayı sessizce yutup boş liste döndürdüğü için "Profil Özelliklerim"
-- ekranındaki ilerleme kartı hiç görünmüyordu.
-- =============================================================================

begin;

create or replace function public.get_my_order_unlock_progress()
returns table (
  kind text,
  completed_orders integer,
  next_locked_code text,
  next_locked_name text,
  next_locked_unlock_after_orders integer,
  remaining_orders integer,
  total_items integer,
  unlocked_items integer
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_completed_count integer;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  select count(*) into v_completed_count
  from public.orders
  where user_id = v_uid and status = 'delivered';

  return query
  with kinds(k) as (values ('avatar_effect'), ('cover_effect')),
  next_item as (
    select
      ki.k,
      (
        select c.code from public.profile_feature_catalog c
        where c.kind = ki.k and c.is_active = true and c.unlock_after_orders is not null
          and c.unlock_after_orders > v_completed_count
        order by c.unlock_after_orders asc limit 1
      ) as code,
      (
        select c.name from public.profile_feature_catalog c
        where c.kind = ki.k and c.is_active = true and c.unlock_after_orders is not null
          and c.unlock_after_orders > v_completed_count
        order by c.unlock_after_orders asc limit 1
      ) as name,
      (
        select c.unlock_after_orders from public.profile_feature_catalog c
        where c.kind = ki.k and c.is_active = true and c.unlock_after_orders is not null
          and c.unlock_after_orders > v_completed_count
        order by c.unlock_after_orders asc limit 1
      ) as unlock_at,
      (
        select count(*)::integer from public.profile_feature_catalog c
        where c.kind = ki.k and c.is_active = true and c.unlock_after_orders is not null
      ) as total,
      (
        select count(*)::integer from public.profile_feature_catalog c
        where c.kind = ki.k and c.is_active = true and c.unlock_after_orders is not null
          and c.unlock_after_orders <= v_completed_count
      ) as unlocked
    from kinds ki
  )
  select
    ni.k,
    v_completed_count,
    ni.code,
    ni.name,
    ni.unlock_at,
    greatest(coalesce(ni.unlock_at, 0) - v_completed_count, 0),
    ni.total,
    ni.unlocked
  from next_item ni;
end;
$$;

revoke all on function public.get_my_order_unlock_progress() from public;
grant execute on function public.get_my_order_unlock_progress() to authenticated, service_role;

commit;

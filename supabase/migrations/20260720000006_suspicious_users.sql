-- Şüpheli kullanıcı işaretleme altyapısı

alter table public.profiles
  add column if not exists is_suspicious boolean not null default false,
  add column if not exists suspicious_reason text,
  add column if not exists suspicious_flagged_at timestamptz;

create index if not exists idx_profiles_is_suspicious
  on public.profiles (is_suspicious)
  where is_suspicious = true;

create or replace function public.admin_list_suspicious_users()
returns table (
  id uuid,
  full_name text,
  email text,
  suspicious_reason text,
  suspicious_flagged_at timestamptz
)
language sql
security definer
set search_path = public
as $$
  select p.id, p.full_name, p.email, p.suspicious_reason, p.suspicious_flagged_at
  from public.profiles p
  where p.is_suspicious = true
  order by p.suspicious_flagged_at desc;
$$;

create or replace function public.admin_set_user_suspicious(
  target_user_id uuid,
  flagged boolean,
  reason text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin'
  ) then
    raise exception 'Yetkiniz yok';
  end if;

  update public.profiles
  set is_suspicious = flagged,
      suspicious_reason = case when flagged then reason else null end,
      suspicious_flagged_at = case when flagged then now() else null end
  where id = target_user_id;
end;
$$;

grant execute on function public.admin_list_suspicious_users() to authenticated;
grant execute on function public.admin_set_user_suspicious(uuid, boolean, text) to authenticated;

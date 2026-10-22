-- =============================================================================
-- Admin bildirimi yalnız hedef kitleye (2026-10-22)
--
-- Sorun: admin "Satıcılar"a duyuru gönderince push doğru kişilere gidiyordu
-- ama kullanıcı uygulamasındaki "Duyurular" bölümü admin_broadcasts'ı
-- hedef kitleye bakmadan okuyordu ("Anyone can read active broadcasts":
-- is_active = true). Satıcı duyurusu müşterinin ve kuryenin ekranında da
-- görünüyordu.
--
--   1) public.admin_audience_includes_me(audience): oturumdaki kullanıcı bu
--      kitlede mi? all_users / all (eski kayıtlar) herkes; sellers = rolü
--      seller VEYA bir dükkanın sahibi; customers = rolü customer; couriers =
--      courier/driver. Admin hepsini görür (kendi gönderdiklerini denetler).
--   2) admin_broadcasts okuma politikası bu fonksiyonla süzülür — eski uygulama
--      sürümleri de otomatik olarak yalnız kendi kitlesinin duyurusunu görür.
--   3) private.admin_notification_recipients: "Satıcılar" hedefi rolü henüz
--      seller yapılmamış dükkan sahiplerini de kapsar (sayaç da aynı
--      fonksiyonu kullandığı için composer'daki "≈ N kişi" tutarlı kalır).
--   4) set_my_fcm_token: aynı cihaz token'ı başka profilde kaldıysa (hesap
--      değiştirildi, çıkışta temizlenemedi) oradan silinir; eski
--      notification_tokens satırları da. Böylece satıcı hesabından çıkıp
--      müşteri hesabıyla giren telefona satıcı push'u gitmez.
-- =============================================================================

begin;

set local lock_timeout = '10s';

-- -----------------------------------------------------------------------------
-- 1) Kitle kontrolü
-- -----------------------------------------------------------------------------
create or replace function public.admin_audience_includes_me(p_audience text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $fn$
  select case
    when coalesce(nullif(btrim(p_audience), ''), 'all_users') in ('all_users', 'all') then true
    when (select auth.uid()) is null then false
    when public.auth_is_admin() then true
    when p_audience = 'sellers' then
      exists (
        select 1 from public.profiles p
         where p.id = (select auth.uid()) and p.role::text = 'seller'
      )
      or exists (
        select 1 from public.shops s where s.owner_id = (select auth.uid())
      )
    when p_audience = 'customers' then
      exists (
        select 1 from public.profiles p
         where p.id = (select auth.uid()) and p.role::text = 'customer'
      )
    when p_audience = 'couriers' then
      exists (
        select 1 from public.profiles p
         where p.id = (select auth.uid()) and p.role::text in ('courier', 'driver')
      )
    else false
  end;
$fn$;

revoke all on function public.admin_audience_includes_me(text) from public;
grant execute on function public.admin_audience_includes_me(text)
  to anon, authenticated, service_role;

comment on function public.admin_audience_includes_me(text) is
  'Oturumdaki kullanıcı admin bildirim kitlesine (all_users/sellers/customers/couriers) dahil mi.';

-- -----------------------------------------------------------------------------
-- 2) "Duyurular" okuma politikası: yalnız kendi kitlesi
-- -----------------------------------------------------------------------------
drop policy if exists "Anyone can read active broadcasts" on public.admin_broadcasts;
drop policy if exists "Audience can read active broadcasts" on public.admin_broadcasts;

create policy "Audience can read active broadcasts"
  on public.admin_broadcasts
  for select
  to authenticated
  using (is_active = true and public.admin_audience_includes_me(target_audience));

-- -----------------------------------------------------------------------------
-- 3) Alıcılar: "Satıcılar" dükkan sahiplerini de kapsar
-- -----------------------------------------------------------------------------
create or replace function private.admin_notification_recipients(
  p_audience text,
  p_user_ids uuid[],
  p_exclude  uuid
)
returns setof uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $function$
  select p.id
  from public.profiles p
  where case
    when p_audience = 'personal' then
      p.id = any(coalesce(p_user_ids, '{}'::uuid[]))
    else
      p.id is distinct from p_exclude
      and coalesce(p.is_bot, false) = false
      and (
        p_audience = 'all_users'
        or (p_audience = 'customers' and p.role::text = 'customer')
        or (p_audience = 'sellers' and (
              p.role::text = 'seller'
              or exists (select 1 from public.shops s where s.owner_id = p.id)
            ))
        or (p_audience = 'couriers'  and p.role::text in ('courier', 'driver'))
      )
  end
$function$;

-- -----------------------------------------------------------------------------
-- 4) Cihaz token'ı tek profilde
-- -----------------------------------------------------------------------------
create index if not exists idx_profiles_fcm_token
  on public.profiles (fcm_token)
  where fcm_token is not null;

create or replace function public.set_my_fcm_token(p_token text)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'set_my_fcm_token: not authenticated'
      using errcode = '28000';
  end if;

  -- Token NULL/empty ise temizle (logout senaryosu). Aksi halde sınır
  -- kontrolü yap; FCM token'ları pratikte 200-300 karakter civarıdır.
  if p_token is not null then
    if length(p_token) = 0 or btrim(p_token) = '' then
      p_token := null;
    elsif length(p_token) >= 4096 then
      raise exception 'set_my_fcm_token: token too long'
        using errcode = '22023';
    end if;
  end if;

  -- Aynı cihaz başka hesapta kayıtlı kaldıysa (hesap değişti, çıkışta
  -- temizlenemedi) oradan kaldır: o hesabın push'ları bu telefona gelmesin.
  if p_token is not null then
    update public.profiles
       set fcm_token = null
     where fcm_token = p_token
       and id <> v_uid;

    delete from public.notification_tokens
     where token = p_token
       and user_id <> v_uid;
  end if;

  update public.profiles
     set fcm_token = p_token
   where id = v_uid;
end;
$function$;

revoke all on function public.set_my_fcm_token(text) from public;
grant execute on function public.set_my_fcm_token(text) to authenticated, service_role;

commit;

notify pgrst, 'reload schema';

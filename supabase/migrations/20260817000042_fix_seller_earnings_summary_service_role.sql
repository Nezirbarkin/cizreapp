-- =============================================================================
-- get_seller_earnings_summary: service_role baglamini tani
--
-- SORUN: 20260814000002 fonksiyonu su korumayla bitiyor:
--
--     AND ( p_seller_id = (SELECT auth.uid())
--           OR EXISTS (SELECT 1 FROM public.profiles
--                      WHERE id = (SELECT auth.uid()) AND role = 'admin') )
--
--   Ancak tek cagiran get-seller-earnings Edge Function'i ve o,
--   getAdminClient() (service-role anahtari) kullaniyor. Service-role
--   baglaminda auth.uid() NULL doner, dolayisiyla kosulun iki tarafi da
--   FALSE olur ve sorgu HIC SATIR DONDURMEZ.
--
--   Sonuc: satici panelinde ozet toplamlarin hepsi 0 gorunur. Hemen altindaki
--   "son 10 kayit" listesi ise dogrudan tablo okumasi oldugu ve service-role
--   RLS'i bypass ettigi icin dolu gelir — yani kullanici kazanc satirlarini
--   gorur ama toplamlar sifirdir.
--
-- COZUM: JWT rol talebi service_role ise korumayi gec. Edge Function
-- cagirmadan once kullaniciyi zaten dogruluyor ve p_seller_id olarak
-- dogrulanmis user.id'yi geciyor. authenticated yolu icin sahiplik/admin
-- kontrolu aynen korunur.
-- =============================================================================

begin;

create or replace function public.get_seller_earnings_summary(p_seller_id uuid)
returns table(
  total_orders      bigint,
  total_gross       numeric,
  total_commission  numeric,
  total_net         numeric,
  pending_amount    numeric,
  available_amount  numeric,
  withdrawn_amount  numeric
)
language sql
security definer
set search_path = public
as $$
  select
    count(*)::bigint                                                  as total_orders,
    coalesce(sum(gross_amount), 0)                                    as total_gross,
    coalesce(sum(commission_amount), 0)                               as total_commission,
    coalesce(sum(net_amount), 0)                                      as total_net,
    coalesce(sum(net_amount) filter (where status = 'pending'), 0)    as pending_amount,
    coalesce(sum(net_amount) filter (where status = 'available'), 0)  as available_amount,
    coalesce(sum(net_amount) filter (where status = 'withdrawn'), 0)  as withdrawn_amount
  from public.seller_earnings
  where seller_id = p_seller_id
    and (
      -- Sunucu baglami: Edge Function cagiriyi zaten dogruladi.
      coalesce(
        nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role',
        ''
      ) = 'service_role'
      -- Istemci baglami: yalnizca kendi ozeti veya admin.
      or p_seller_id = (select auth.uid())
      or exists (
        select 1 from public.profiles
        where id = (select auth.uid()) and role = 'admin'
      )
    );
$$;

revoke all on function public.get_seller_earnings_summary(uuid) from public, anon;
grant execute on function public.get_seller_earnings_summary(uuid)
  to authenticated, service_role;

comment on function public.get_seller_earnings_summary(uuid) is
  'Satici kazanc ozeti (DB tarafi aggregate). service_role baglaminda auth.uid() NULL oldugu icin JWT rol talebi ayrica kontrol edilir; aksi halde ozet her zaman 0 donuyordu. 2026-08-17.';

commit;

notify pgrst, 'reload schema';

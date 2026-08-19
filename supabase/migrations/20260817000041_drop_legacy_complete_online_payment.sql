-- =============================================================================
-- Eski client-authoritative online odeme finalizer'ini kaldir
--
-- ⚠️  UYGULAMA SIRASI ONEMLI  ⚠️
--
-- Bu migration'i YALNIZCA su iki adim tamamlandiktan SONRA uygulayin:
--   1) 20260817000040 uygulanmis olmali
--      (public.commit_online_order + atomic_finalize_payment_transaction),
--   2) Yeni iyzico-payment-callback deploy edilmis olmali:
--        supabase functions deploy iyzico-payment-callback
--        supabase functions deploy iyzico-payment-init
--
-- NEDEN: Canlida su an callback'in v35 surumu kosuyor ve o surum siparisi
-- public.complete_online_payment ile olusturuyor. Fonksiyon yeni callback
-- deploy edilmeden dusurulurse, aradaki surede alinan odemeler icin SIPARIS
-- OLUSMAZ (para cekilir, siparis yaratilmaz).
--
-- NEDEN KALDIRILIYOR: complete_online_payment siparis kalemlerini ve
-- tutarlari payment_transactions.callback_data->order_data icinden okuyor.
-- Bu veriyi checkout sirasinda ISTEMCI yaziyor; yani fiyat istemci
-- otoriteli. Yerini alan commit_online_order tum tutarlari sunucudaki
-- private.server_checkout_sessions snapshot'indan uretir.
-- =============================================================================

begin;

do $$
begin
  if not exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'commit_online_order'
  ) then
    raise exception
      'Once 20260817000040 uygulanmali: public.commit_online_order bulunamadi.';
  end if;
end $$;

drop function if exists public.complete_online_payment(uuid);

commit;

notify pgrst, 'reload schema';

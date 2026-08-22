-- ============================================
-- ODEME ISTEGI TESLIMAT UCRETI KESINTI DETAYI
-- Tarih: 2026-08-18
-- Aciklama: Kuryesi olmayan magazalar icin, admin'in
-- siparislerden kestigi teslimat ucretinin toplami ve
-- bunu aciklayan bir metin, odeme istegi (payout_requests)
-- kaydinin uzerinde saklanir. Boylece hem satici hem admin
-- "neden bu tutar kesildi" bilgisini istek uzerinde gorur.
--
-- Not: Bu alanlar salt bilgi amaclidir; odenecek tutarin
-- dogrulanmasi (net_receivable) zaten calculate_order_commission /
-- validate_payout_request trigger'larinda subtotal uzerinden
-- yapiliyor, burada degistirilmiyor.
-- ============================================

begin;

alter table public.payout_requests
  add column if not exists delivery_fee_deducted numeric(12, 2) not null default 0,
  add column if not exists deduction_detail text;

comment on column public.payout_requests.delivery_fee_deducted is
  'Kuryesi olmayan magazalarda, bu odeme istegine kadar teslim edilen siparislerden admin tarafindan kesilen toplam teslimat ucreti (bilgi amaclidir).';
comment on column public.payout_requests.deduction_detail is
  'Odeme tutarindan yapilan kesintileri (orn. teslimat ucreti) satici ve admine aciklayan metin.';

commit;

notify pgrst, 'reload schema';

-- =============================================================================
-- Kurye cekirdek tablolarini geriye-donuk (backfill) olustur
-- =============================================================================
-- SORUN: public.courier_assignments, public.courier_earnings ve
-- public.courier_payout_requests tablolari repodaki HICBIR migration
-- tarafindan CREATE TABLE ile olusturulmuyor — yalnizca sonraki
-- migration'larda ALTER TABLE / CREATE POLICY / CREATE INDEX ile
-- degistiriliyorlar. Bu ucu, canli (production) veritabaninda Supabase
-- Studio'dan elle olusturulmus; dolayisiyla `supabase db reset` ile kurulan
-- her yerel/CI/staging ortaminda bu tablolar hic var olmuyor ve onlara
-- dokunan tum sonraki migration'lar "relation does not exist" ile patlar.
-- Bkz. supabase/diagnostics/20260817_courier_payout_chain_state.sql (bu
-- durumu tespit etmek icin yazilmisti) ve
-- supabase/diagnostics/20260816_admin_panel_rpc_drift.sql.
--
-- Bu migration SADECE bu uc tablonun ilk (en erken referans edilen
-- migration'dan ONCEKI) halini geri olusturur — kolonlar CANLI
-- veritabanindan `information_schema.columns` / `pg_constraint` /
-- `pg_indexes` sorgulariyla dogrulandi (2026-08-19). Daha sonra eklenen
-- kolonlar (courier_earnings.package_request_id/amount_snapshot,
-- courier_payout_requests.requested_at/approved_at/approved_by/
-- rejected_at/rejection_reason/payment_reference/idempotency_key) BURADA
-- YAZILMAZ — onlari zaten var olan sonraki migration'lar
-- (20260723000500, 20260802000005, ...) `ADD COLUMN IF NOT EXISTS` ile
-- ekliyor. Tum tanimlar `IF NOT EXISTS` ile idempotent: canli ortamda
-- (tablolar zaten var) bu migration no-op'tur, yalnizca sifirdan kurulan
-- ortamlarda gercek etkisi olur.
--
-- Zaman damgasi bilinçli olarak erken (20260228000000): courier_assignments
-- ilk kez 20260228000002_courier_orders_update.sql icinde bir RLS policy
-- alt-sorgusunda referans ediliyor; courier_earnings ilk kez
-- 20260723000500 icinde ALTER edilecek; courier_payout_requests ilk kez
-- 20260802000005 icinde ALTER edilecek. Bu migration ucunun de onunde
-- calismasi gerekir.
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- 1) courier_assignments — siparis bazli kurye atama tablosu
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.courier_assignments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  courier_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'assigned'
    CHECK (status IN ('assigned', 'picked_up', 'on_the_way', 'delivered', 'cancelled')),
  fee_amount double precision NOT NULL DEFAULT 0,
  assigned_at timestamptz NOT NULL DEFAULT now(),
  picked_up_at timestamptz,
  delivered_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT courier_assignments_order_id_courier_id_key UNIQUE (order_id, courier_id)
);

ALTER TABLE public.courier_assignments ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_courier_assignments_courier
  ON public.courier_assignments (courier_id);
CREATE INDEX IF NOT EXISTS idx_courier_assignments_order
  ON public.courier_assignments (order_id);
CREATE INDEX IF NOT EXISTS idx_courier_assignments_status
  ON public.courier_assignments (status);
CREATE INDEX IF NOT EXISTS idx_courier_assignments_order_status
  ON public.courier_assignments (order_id, status);

-- -----------------------------------------------------------------------------
-- 2) courier_earnings — kurye kazanc kayitlari (siparis + paket teslimati)
-- -----------------------------------------------------------------------------
-- NOT: assignment_id/order_id/package_request_id'nin UCU de nullable'dir
-- cunku bir kazanc kaydi ya bir siparis teslimatindan (assignment_id +
-- order_id) ya da bir kargo paketi teslimatindan (package_request_id,
-- 20260723000500 ile eklenecek) gelir. amount_snapshot da 20260802000005
-- ile eklenecek.
CREATE TABLE IF NOT EXISTS public.courier_earnings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  courier_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  assignment_id uuid REFERENCES public.courier_assignments(id) ON DELETE SET NULL,
  order_id uuid REFERENCES public.orders(id) ON DELETE SET NULL,
  amount double precision NOT NULL DEFAULT 0,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'requested', 'paid')),
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.courier_earnings ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_courier_earnings_courier
  ON public.courier_earnings (courier_id);
CREATE INDEX IF NOT EXISTS idx_courier_earnings_status
  ON public.courier_earnings (status);
CREATE INDEX IF NOT EXISTS idx_courier_earnings_order_id_fk
  ON public.courier_earnings (order_id);
CREATE INDEX IF NOT EXISTS idx_courier_earnings_assignment_id_fk
  ON public.courier_earnings (assignment_id);

-- -----------------------------------------------------------------------------
-- 3) courier_payout_requests — kurye odeme talepleri
-- -----------------------------------------------------------------------------
-- NOT: requested_at/approved_at/approved_by/rejected_at/rejection_reason/
-- payment_reference/idempotency_key kolonlari 20260802000005 ile
-- `ADD COLUMN IF NOT EXISTS` olarak eklenecek — burada yazilmiyor.
CREATE TABLE IF NOT EXISTS public.courier_payout_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  courier_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  amount double precision NOT NULL DEFAULT 0,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'approved', 'paid', 'rejected')),
  paid_at timestamptz,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.courier_payout_requests ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_courier_payout_requests_courier
  ON public.courier_payout_requests (courier_id);
CREATE INDEX IF NOT EXISTS idx_courier_payout_requests_status
  ON public.courier_payout_requests (status);

commit;

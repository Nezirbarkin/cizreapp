-- =============================================================================
-- PERFORMANS DÜZELTMELERİ
--   1) orders / order_items tablolarındaki YETİM SELECT policy'leri drop edilir
--      (comprehensive_rls_optimization'dan kalan, hiç temizlenmeyen
--       per-row EXISTS JOIN içeren 'orders_select' / 'order_items_select').
--      Korunan 'orders_select_policy' / 'order_items_select_policy' tüm
--      erişimleri (müşteri/satıcı/admin/kurye) kapsadığı için erişim kaybı YOK.
--   2) profiles(last_seen) ve profiles(created_at) indeksleri geri yaratılır
--      (idx_profiles_last_seen 20260212000006:128'de drop edilip geri
--       yaratılmamıştı; admin_logs_counts() 7 count(*) seq scan yapıyordu).
--   3) ai_* tabloları policy'lerinde ham auth.uid() -> (SELECT auth.uid())
--      sarması (InitPlan optimizasyonu, 20260727000003 desenine uygun).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1) YETİM RLS POLICY'LERI (per-row EXISTS maliyeti)
-- -----------------------------------------------------------------------------
-- 'orders_select' (20260209000003:210) ile 'orders_select_policy'
-- (en son 20260228000002:42) AYNI ANDA aktif. PostgreSQL tüm permissive SELECT
-- policy'lerini OR'lediği için her orders satırında GEREKSİZ ek EXISTS
-- (order_items JOIN shops) koşulu çalışıyordu. orders_select_policy
-- (user_id | shop owner | admin | courier) üst küme olduğu için drop güvenli.
DROP POLICY IF EXISTS "orders_select" ON public.orders;

-- Aynı durum order_items için: 'order_items_select' (20260209000003:237) yetim;
-- 'order_items_select_policy' (20260210000009:49) müşteri/satıcı/admin'i
-- order_items.order_id -> orders üzerinden karşıladığından üst küme.
DROP POLICY IF EXISTS "order_items_select" ON public.order_items;

-- Güvenlik ağı: hâlâ tek bir SELECT policy kaldığını doğrula (yoksa uyar).
DO $$
DECLARE
  n int;
BEGIN
  SELECT count(*) INTO n FROM pg_policies
   WHERE schemaname='public' AND tablename='orders'
     AND cmd='SELECT';
  IF n = 0 THEN
    RAISE NOTICE 'UYARI: orders üzerinde SELECT policy kalmadı — kontrol edin!';
  END IF;
  SELECT count(*) INTO n FROM pg_policies
   WHERE schemaname='public' AND tablename='order_items'
     AND cmd='SELECT';
  IF n = 0 THEN
    RAISE NOTICE 'UYARI: order_items üzerinde SELECT policy kalmadı — kontrol edin!';
  END IF;
END $$;

-- -----------------------------------------------------------------------------
-- 2) PROFILES INDEKSLERI (admin_logs_counts 7 seq scan -> indeksli erişim)
-- -----------------------------------------------------------------------------
-- last_seen: online/DAU/WAU/MAU/inactive count'ları; created_at: new_today.
CREATE INDEX IF NOT EXISTS idx_profiles_last_seen
    ON public.profiles (last_seen DESC);

CREATE INDEX IF NOT EXISTS idx_profiles_created_at
    ON public.profiles (created_at DESC);

-- -----------------------------------------------------------------------------
-- 3) ai_* POLICY'lerinde auth.uid() -> (SELECT auth.uid()) (InitPlan)
-- -----------------------------------------------------------------------------
-- Semantik koruyucu: PostgreSQL auth.uid()'yi statement başına BİR kez
-- (InitPlan) değerlendirir; per-row çağrı kalkar. 20260727000003 ai_*'yı
-- atlamıştı.
ALTER POLICY "Users can view own ai conversations" ON public.ai_conversations
    FOR SELECT
    USING ((SELECT auth.uid()) = user_id);

ALTER POLICY "Users can insert ai conversations" ON public.ai_conversations
    FOR INSERT
    WITH CHECK ((SELECT auth.uid()) = user_id);

ALTER POLICY "Users can update own ai conversations" ON public.ai_conversations
    FOR UPDATE
    USING ((SELECT auth.uid()) = user_id)
    WITH CHECK ((SELECT auth.uid()) = user_id);

ALTER POLICY "Users can delete own ai conversations" ON public.ai_conversations
    FOR DELETE
    USING ((SELECT auth.uid()) = user_id);

ALTER POLICY "Users can view own ai messages" ON public.ai_messages
    FOR SELECT
    USING (EXISTS (
        SELECT 1 FROM public.ai_conversations
        WHERE id = conversation_id AND user_id = (SELECT auth.uid())
    ));

ALTER POLICY "Users can insert ai messages" ON public.ai_messages
    FOR INSERT
    WITH CHECK (EXISTS (
        SELECT 1 FROM public.ai_conversations
        WHERE id = conversation_id AND user_id = (SELECT auth.uid())
    ));

ALTER POLICY "Admins can manage ai settings" ON public.ai_settings
    FOR ALL
    USING (EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = (SELECT auth.uid()) AND role = 'admin'
    ))
    WITH CHECK (EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = (SELECT auth.uid()) AND role = 'admin'
    ));

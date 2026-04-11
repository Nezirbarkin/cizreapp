-- ============================================================================
-- TG_OP KULLANAN POLICY'LERİ BUL
-- ============================================================================
-- Bu sorgu, RLS policy'lerinde TG_OP kullanan hatalı policy'leri bulur.
-- TG_OP sadece trigger fonksiyonlarında kullanılabilir, RLS policy'lerde DEĞİL!

-- 1. Tüm policy'leri kontrol et
SELECT 
    schemaname,
    tablename,
    policyname,
    permissive,
    roles,
    cmd,
    qual AS using_clause,
    with_check
FROM pg_policies 
WHERE schemaname = 'public'
  AND (
      qual LIKE '%TG_OP%' 
      OR with_check LIKE '%TG_OP%'
  );

-- Eğer yukarıdaki sorgu sonuç döndürürse, bu policy'ler silinmeli:

-- Örnek: Eğer notifications tablosunda TG_OP kullanan bir policy varsa:
-- DROP POLICY IF EXISTS "hatali_policy_adi" ON public.notifications;

-- Sonra doğru policy'leri oluşturun:
/*
-- INSERT: Herkes bildirim ekleyebilir (trigger'lar için)
CREATE POLICY "notifications_insert" ON public.notifications
FOR INSERT TO authenticated WITH CHECK (true);

-- SELECT: Sadece kendi bildirimlerini görebilir
CREATE POLICY "notifications_select" ON public.notifications
FOR SELECT TO authenticated USING (user_id = (select auth.uid()));

-- UPDATE: Sadece kendi bildirimlerini güncelleyebilir
CREATE POLICY "notifications_update" ON public.notifications
FOR UPDATE TO authenticated
USING (user_id = (select auth.uid()))
WITH CHECK (user_id = (select auth.uid()));

-- DELETE: Sadece kendi bildirimlerini silebilir
CREATE POLICY "notifications_delete" ON public.notifications
FOR DELETE TO authenticated USING (user_id = (select auth.uid()));
*/

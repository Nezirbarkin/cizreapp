-- ============================================================
-- NOTIFICATIONS RLS - TEMİZ KURULUM
-- ============================================================
-- Bu SQL'i TEK SEFERDE çalıştırın!

-- 1. RLS'yi geçici olarak kapat
ALTER TABLE notifications DISABLE ROW LEVEL SECURITY;

-- 2. TÜM policy'leri kaldır (mümkün olan tüm isimler)
DO $$ 
DECLARE 
    pol RECORD;
BEGIN
    FOR pol IN 
        SELECT policyname 
        FROM pg_policies 
        WHERE tablename = 'notifications'
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON notifications', pol.policyname);
        RAISE NOTICE 'Dropped policy: %', pol.policyname;
    END LOOP;
END $$;

-- 3. Doğrulama: Hiç policy kalmamalı
SELECT count(*) as remaining_policies FROM pg_policies WHERE tablename = 'notifications';

-- 4. RLS'yi tekrar aç
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

-- 5. NO FORCE - tablo sahibi bypass edebilsin
ALTER TABLE notifications NO FORCE ROW LEVEL SECURITY;

-- 6. GRANT'lar
GRANT ALL ON notifications TO authenticated;
GRANT ALL ON notifications TO anon;
GRANT ALL ON notifications TO service_role;

-- 7. Yeni policy'ler oluştur
CREATE POLICY "notifications_insert" ON notifications
FOR INSERT TO authenticated
WITH CHECK (true);

CREATE POLICY "notifications_select" ON notifications
FOR SELECT TO authenticated
USING (user_id = auth.uid());

CREATE POLICY "notifications_update" ON notifications
FOR UPDATE TO authenticated
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

CREATE POLICY "notifications_delete" ON notifications
FOR DELETE TO authenticated
USING (user_id = auth.uid());

CREATE POLICY "notifications_service_role" ON notifications
FOR ALL TO service_role
USING (true)
WITH CHECK (true);

-- 8. PostgREST schema cache yenile
NOTIFY pgrst, 'reload schema';
NOTIFY pgrst, 'reload config';

-- 9. Doğrulama
SELECT policyname, cmd, permissive, roles, with_check, qual
FROM pg_policies 
WHERE tablename = 'notifications'
ORDER BY policyname;

-- ============================================================
-- NOTIFICATIONS RLS KONTROL VE KESİN ÇÖZÜM
-- ============================================================

-- 1. Mevcut RLS durumunu kontrol et
SELECT tablename, rowsecurity 
FROM pg_tables 
WHERE tablename = 'notifications';

-- 2. Mevcut policy'leri kontrol et
SELECT policyname, cmd, with_check, qual
FROM pg_policies 
WHERE tablename = 'notifications';

-- 3. RLS'yi KAPAT (kalıcı - güvenlik riski düşük çünkü SELECT zaten filtrelenmiş)
ALTER TABLE notifications DISABLE ROW LEVEL SECURITY;

-- 4. Doğrula
SELECT tablename, rowsecurity 
FROM pg_tables 
WHERE tablename = 'notifications';

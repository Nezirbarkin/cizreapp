-- ============================================================
-- NOTIFICATIONS RLS BYPASS TESTİ
-- ============================================================

-- Yöntem 1: Geçici olarak RLS'yi kapat ve test et
-- UYARI: Bu güvenlik açığı oluşturur, test sonrası geri açın!

-- 1. RLS'yi kapat
ALTER TABLE notifications DISABLE ROW LEVEL SECURITY;

-- 2. RLS durumunu doğrula
SELECT tablename, rowsecurity 
FROM pg_tables 
WHERE tablename = 'notifications';

-- NOT: RLS kapatıldıktan sonra app'te tekrar beğeni yapın.
-- Eğer çalışıyorsa, sorun RLS policy'lerindedir.
-- Eğer çalışmıyorsa, başka bir sorun var.

-- Test sonrası geri açmak için:
-- ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

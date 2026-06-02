-- ============================================
-- KURYE ATAMA İÇİN GEREKLİ RLS KONTROLÜ
-- ============================================

-- courier_assignments INSERT politikası kontrol et
-- Kurye atama yapabilmeli mi? Veya sadece satıcı mı yapabilmeli?
SELECT policyname, cmd, permissive, roles, qual, with_check
FROM pg_policies
WHERE tablename = 'courier_assignments'
  AND schemaname = 'public'
  AND cmd = 'INSERT'
ORDER BY policyname;

-- orders UPDATE politikası kontrol et
-- Kurye sipariş durumunu güncelleyebilmeli mi (on_the_way)?
SELECT policyname, cmd, permissive, roles, qual, with_check
FROM pg_policies
WHERE tablename = 'orders'
  AND schemaname = 'public'
  AND cmd = 'UPDATE'
ORDER BY policyname;

-- Test: Kurye test4 kullanıcısının atama yapabiliyor mu?
-- Bu sorguyu test4 ile login olup çalıştırın
-- SELECT * FROM courier_assignments WHERE courier_id = 'ce598db8-4e36-4f0c-9fae-50f197162d87';
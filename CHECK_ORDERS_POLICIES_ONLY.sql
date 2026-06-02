-- Orders tablosundaki TÜM politikaları kontrol et
SELECT policyname, cmd, permissive, roles, qual, with_check
FROM pg_policies
WHERE tablename = 'orders'
  AND schemaname = 'public'
ORDER BY policyname, cmd;
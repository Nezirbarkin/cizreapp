-- Politika sonuçlarını görmek için
SELECT 
    policyname,
    cmd,
    permissive,
    with_check,
    qual
FROM pg_policies 
WHERE tablename = 'notifications'
ORDER BY cmd, policyname;

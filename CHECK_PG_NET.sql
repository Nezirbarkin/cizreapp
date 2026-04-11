-- =====================================================
-- PG_NET HTTP_POST DOĞRU KULLANIM
-- =====================================================
--
-- pg_net asenkron çalışır: net.http_post() sadece request_id (bigint) döndürür
-- Response'u sonra net._http_response tablosundan alabilirsiniz
-- Ama trigger'da beklemeye gerek yok, fire-and-forget yeterli
--
-- =====================================================

-- Önce pg_net extension'ı kontrol
SELECT * FROM pg_extension WHERE extname = 'pg_net';

-- net.http_post'un return type'ını kontrol
SELECT 
    p.proname,
    pg_get_function_result(p.oid) as return_type,
    pg_get_function_arguments(p.oid) as arguments
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'net'
AND p.proname = 'http_post'
ORDER BY p.proname;

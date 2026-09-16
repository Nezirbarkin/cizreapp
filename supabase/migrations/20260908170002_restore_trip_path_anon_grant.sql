-- =============================================================================
-- Şehiriçi: get_sehirici_trip_path üzerindeki kayıp anon GRANT'ını geri yükle
-- =============================================================================
-- KÖK NEDEN (2026-09-08, canlıda has_function_privilege ile doğrulandı):
--
--   20260729000003_get_sehirici_trip_path.sql fonksiyonu
--     GRANT EXECUTE ... TO authenticated, anon;
--   ile tanımlamıştı. Canlıda anon yetkisi düşmüş:
--     has_function_privilege('anon','get_sehirici_trip_path(uuid)','EXECUTE') = false
--
--   Bu, repoda tekrar eden RPC-yetki drift sınıfı (bkz. 20260817000021'in
--   get_sehirici_lines_with_stops / _active_trips / _trips_for_stop /
--   compute_sehirici_next_stop için yaptığı aynı düzeltme — o dördü
--   düzeltilmiş ama trip_path listede unutulmuş).
--
--   ETKİ: misafir kullanıcı canlı haritada otobüsün geçtiği yolu (polyline)
--   göremiyor; konsola "permission denied for function
--   get_sehirici_trip_path (42501)" düşüyor.
--
-- KAPSAM: sadece bu tek RPC'nin anon EXECUTE yetkisi.
--
-- NOT: public.get_nearby_couriers BİLEREK kapsam dışı. Orası drift değil,
-- tasarım: 20260809000005_courier_heading.sql açıkça
--   REVOKE ALL ... FROM PUBLIC; GRANT ... TO authenticated, service_role;
-- diyor. Kurye konumları misafire açılmamalı; istemcinin misafirken bu RPC'yi
-- çağırması ayrı (zararsız, yutulan) bir istemci davranışı.
-- =============================================================================

BEGIN;

GRANT EXECUTE ON FUNCTION public.get_sehirici_trip_path(UUID) TO anon;

NOTIFY pgrst, 'reload schema';

COMMIT;

-- DOĞRULAMA:
--   SELECT has_function_privilege('anon','public.get_sehirici_trip_path(uuid)','EXECUTE');
--   -- Beklenen: true

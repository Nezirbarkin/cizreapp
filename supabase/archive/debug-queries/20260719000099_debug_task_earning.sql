-- =============================================================================
-- 20260719000099_debug_task_earning.sql
-- "Aktif görevler çıkmıyor" sorununun KÖK NEDENİNİ teşhis et.
--
-- Bu script OKUMA yapar — hiçbir veri değiştirmez. Supabase Dashboard >
-- SQL Editor'da çalıştırın ve TÜM çıktıyı kopyalayıp bana gönderin.
-- =============================================================================

\echo '========== 1) MIGRATION DURUMU =========='

SELECT 'tasks tablosu var mı?' AS check,
       EXISTS(SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='tasks') AS result;

SELECT 'tasks.image_url kolonu var mı?' AS check,
       EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='tasks' AND column_name='image_url') AS result;

SELECT 'get_active_tasks RPC var mı?' AS check,
       EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON p.pronamespace=n.oid
              WHERE n.nspname='public' AND p.proname='get_active_tasks') AS result;

\echo '========== 2) RPC SIGNATURE (kolon isimleri) =========='

SELECT pg_get_function_result(p.oid) AS rpc_return_type
FROM pg_proc p JOIN pg_namespace n ON p.pronamespace=n.oid
WHERE n.nspname='public' AND p.proname='get_active_tasks';

\echo '========== 3) GÖREV VERİSİ =========='

SELECT
  COUNT(*)                                      AS toplam_gorev,
  COUNT(*) FILTER (WHERE status='active')       AS active_gorev,
  COUNT(*) FILTER (WHERE status='draft')        AS draft_gorev,
  COUNT(*) FILTER (WHERE status='paused')       AS paused_gorev,
  COUNT(*) FILTER (WHERE status='completed')    AS completed_gorev
FROM public.tasks;

\echo '========== 4) AKTİF GÖREVLERİN DURUMU (RLS effectsiz) =========='

-- SECURITY DEFINER RPC'nin gördüğü ile aynı mantık:
SELECT
  id,
  title,
  status,
  starts_at,
  expires_at,
  current_participants,
  max_participants,
  image_url,
  CASE
    WHEN status <> 'active' THEN '⚠ status aktif değil: '||status
    WHEN starts_at > NOW()   THEN '⚠ starts_at gelecekte: '||starts_at
    WHEN expires_at IS NOT NULL AND expires_at <= NOW() THEN '⚠ expires_at geçmiş: '||expires_at
    ELSE '✓ görünür olmalı'
  END AS neden
FROM public.tasks
ORDER BY created_at DESC
LIMIT 20;

\echo '========== 5) KATEGORİLER =========='

SELECT id, name, icon, is_active FROM public.task_categories ORDER BY sort_order;

\echo '========== 6) RPC ÇALIŞTIRMA TESTİ (auth context olmadan) =========='

-- auth.uid() NULL olduğu için user_already_claimed=false olur ama görev listesi döner:
SELECT
  task_id,
  title,
  status,
  remaining_slots,
  image_url,
  user_already_claimed
FROM public.get_active_tasks(NULL, 50, 0)
LIMIT 20;

\echo '========== 7) BUCKET DURUMU =========='

SELECT id, name, public, file_size_limit FROM storage.buckets WHERE id IN ('task_images','task_screenshots');

\echo '========== 8) RLS POLICY ÖZETİ (tasks) =========='

SELECT policyname, cmd, roles, qual
FROM pg_policies
WHERE schemaname='public' AND tablename='tasks';

\echo '========== BİTTİ =========='
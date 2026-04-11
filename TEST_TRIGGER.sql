-- ============================================================================
-- TRIGGER TEST - DÜZELTİLMİŞ (Doğru notification type ile)
-- ============================================================================

-- 1. Hangi notification type'ları geçerli kontrol et
SELECT column_name, data_type, check_clause
FROM information_schema.check_constraints cc
JOIN information_schema.constraint_column_usage ccu USING (constraint_name)
WHERE ccu.table_name = 'notifications' AND ccu.column_name = 'type';


-- 2. Manuel test bildirimi gönder (DÜZELTILMIŞ)
INSERT INTO notifications (
  user_id,
  type,
  title,
  content,
  actor_id
) VALUES (
  '78665f8b-6a07-40f3-b13d-d4b5a29296c6',
  'like',  -- DÜZELTİLDİ: post_like değil, sadece like
  '🔔 MANUEL TEST',
  'Bu bildirim trigger''ı test ediyor',
  '78665f8b-6a07-40f3-b13d-d4b5a29296c6'
);

-- Bu komutu çalıştırınca:
-- 1. Notification oluşacak
-- 2. Trigger tetiklenecek
-- 3. Edge Function çağrılacak
-- 4. Supabase → Edge Functions → send-push-notification → Logs
-- 5. Yeni log görünecek!

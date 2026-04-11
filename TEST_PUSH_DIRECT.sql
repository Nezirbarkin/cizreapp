-- ============================================================================
-- PUSH EDİT FUNCTION TESTİ
-- ============================================================================
-- Önce FIX_NEW_ORDER_NOTIFICATION.sql çalıştırın
-- Sonra bu testi çalıştırın
-- ============================================================================

-- TEST: Edge Function'ı doğrudan çağır ve sonucu gör
-- Bir kullanıcının FCM token'ına test push gönder
SELECT extensions.http_post(
  url := 'https://xsbukxkgtmdyickknqzf.supabase.co/functions/v1/send-push-notification',
  headers := jsonb_build_object(
    'Content-Type', 'application/json',
    'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhzYnVreGtndG1keWlja2tucXpmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njg5MzI3MzgsImV4cCI6MjA4NDUwODczOH0.UqycLmPhsjpVQbD0706gp-FVPQ3aCyCs-m9S5rcO2pc'
  ),
  body := jsonb_build_object(
    'user_id', '78665f8b-6a07-40f3-b13d-d4b5a29296c6',
    'title', 'Test Push Bildirimi',
    'body', 'Bu bir test push bildirimidir',
    'data', jsonb_build_object(
      'type', 'test',
      'notification_id', 'test-001'
    )
  ),
  timeout_milliseconds := 10000
);

-- ============================================================================
-- PUSH BİLDİRİM ZİNCİRİNİ ADIM ADIM TEST ET
-- ============================================================================
-- Her adımı ayrı ayrı çalıştırın ve sonucu paylaşın
-- ============================================================================

-- ============================================================================
-- ADIM 1: Edge Function'ı doğrudan çağır (test kullanıcısına)
-- http_post doğru imza ile + response'u collect et
-- ============================================================================
SELECT '=== ADIM 1: EDGE FUNCTION DIREKT TEST ===' AS adim;

-- Request gönder (request_id al)
SELECT extensions.http_post(
  'https://xsbukxkgtmdyickknqzf.supabase.co/functions/v1/send-push-notification',
  jsonb_build_object(
    'user_id', '78665f8b-6a07-40f3-b13d-d4b5a29296c6',
    'title', 'Test Push',
    'body', 'Bu bir test bildirimidir',
    'data', jsonb_build_object('type', 'test')
  ),
  '{}'::jsonb,
  jsonb_build_object(
    'Content-Type', 'application/json',
    'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhzYnVreGtndG1keWlja2tucXpmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njg5MzI3MzgsImV4cCI6MjA4NDUwODczOH0.UqycLmPhsjpVQbD0706gp-FVPQ3aCyCs-m9S5rcO2pc'
  ),
  10000
) AS request_id;

-- ============================================================================
-- ADIM 2: Son http request'in sonucunu al
-- (Yukarıdaki request_id'yi buraya yazın, örn: 123)
-- ============================================================================
-- SELECT * FROM extensions.http_collect_response(REQUEST_ID_BURAYA, false);

-- ============================================================================
-- ADIM 3: Supabase Edge Function loglarını kontrol et
-- Dashboard > Edge Functions > send-push-notification > Logs
-- ============================================================================

-- ============================================================================
-- ADIM 4: Test bildirim oluştur ve push trigger'ın çalıştığını kontrol et
-- ============================================================================
SELECT '=== ADIM 4: TEST BILDIRIMI OLUSTUR ===' AS adim;

INSERT INTO notifications (user_id, type, title, content, is_read, created_at)
VALUES (
  '78665f8b-6a07-40f3-b13d-d4b5a29296c6',
  'test',
  'Test Push Bildirimi',
  'Bu bildirim push olarak gelmeli',
  false,
  NOW()
) RETURNING id, title;

-- ============================================================================
-- ADIM 5: Supabase loglarında push sonucunu kontrol et
-- Dashboard > Logs > Postgres Logs > ara: "Push notification"
-- ============================================================================

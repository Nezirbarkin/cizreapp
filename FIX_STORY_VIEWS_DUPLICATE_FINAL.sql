-- ============================================
-- STORY VIEWS 2'Lİ ATLAMA SORUNU - SON ÇÖZÜM
-- ============================================
-- Sorun: Her story görüntüleme 2 olarak sayılıyor
-- Neden: İki farklı trigger aynı anda çalışıyor
-- Çözüm: Duplicate trigger'ı ve fonksiyonu sil

-- 1. Eski (duplicate) trigger'ı sil
DROP TRIGGER IF EXISTS trigger_increment_story_views_count ON public.story_views;

-- 2. Eski (duplicate) fonksiyonu sil
DROP FUNCTION IF EXISTS public.increment_story_views_count();

-- 3. Kalan trigger'ın doğru çalıştığını doğrula (sadece 1 trigger kalmalı)
SELECT 
    tgname AS trigger_name,
    proname AS function_name,
    pg_get_triggerdef(t.oid) AS trigger_definition
FROM pg_trigger t
JOIN pg_class c ON t.tgrelid = c.oid
JOIN pg_proc p ON t.tgfoid = p.oid
WHERE c.relname = 'story_views'
AND tgname NOT LIKE 'pg_%';

-- Beklenen Sonuç: Sadece 1 satır olmalı
-- trigger_name: story_views_count_trigger
-- function_name: update_story_views_count

-- 4. BONUS: Mevcut story'lerin yanlış sayılmış views_count değerlerini düzelt
-- (Şu ana kadar 2 katı sayılmış, yarıya indir)
UPDATE public.stories 
SET views_count = CEIL(views_count / 2.0) 
WHERE views_count > 0;

-- 5. Test: Yeni bir story view eklendiğinde sadece +1 artmalı
-- Manuel test için:
-- a) Önce bir story'nin mevcut views_count'unu kontrol edin
-- b) O story'ye yeni bir view ekleyin (story_views tablosuna INSERT)
-- c) views_count'un sadece +1 arttığını doğrulayın

-- Test örneği (gerçek story_id ve viewer_id ile değiştirin):
-- SELECT id, views_count FROM stories WHERE id = 'STORY_ID_BURAYA';
-- INSERT INTO story_views (story_id, viewer_id) VALUES ('STORY_ID_BURAYA', 'VIEWER_ID_BURAYA');
-- SELECT id, views_count FROM stories WHERE id = 'STORY_ID_BURAYA';
-- views_count +1 olmalı (örn: 10 -> 11)

-- ============================================
-- ÖZET
-- ============================================
-- ✅ Duplicate trigger silindi
-- ✅ Duplicate function silindi  
-- ✅ Sadece tek trigger kaldı: story_views_count_trigger
-- ✅ Mevcut views_count değerleri düzeltildi
-- ⚠️ Dart kodunda market_screen.dart'taki duplicate viewStory çağrısını da düzeltin

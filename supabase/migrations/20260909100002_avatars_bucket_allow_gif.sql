-- ============================================================================
-- 20260909100002_avatars_bucket_allow_gif.sql
-- ----------------------------------------------------------------------------
-- AMAÇ: Hareketli (animasyonlu GIF) hazır avatarlar.
--
-- Hazır avatar seçildiğinde asset baytları `avatars` bucket'ına yüklenip normal
-- bir avatar_url gibi saklanıyor (ProfileService.uploadProfilePhotoBytes).
-- Bucket'ın allowed_mime_types listesinde image/gif YOKTU: hareketli avatar
-- seçen kullanıcı kaydederken storage 400 alıyordu.
--
-- Boyut limiti (5 MB) yeterli: paketle gelen hareketli avatarların hepsi
-- 200 KB'ın altında. Limit bilinçli olarak değiştirilmedi.
-- ============================================================================

UPDATE storage.buckets
SET allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif']
WHERE id = 'avatars';

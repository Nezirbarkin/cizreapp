-- Tüm kullanıcıları çevrimdışı yap
-- Bu scripti bir kez çalıştırın, sonra uygulama açıldığında doğru is_online durumları güncellenecek

UPDATE profiles
SET is_online = false
WHERE is_online = true;

-- Kontrol
SELECT COUNT(*) as online_user_count FROM profiles WHERE is_online = true;

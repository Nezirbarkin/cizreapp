-- FCM Token sayısını kontrol et
SELECT COUNT(*) as fcm_token_sayisi 
FROM profiles 
WHERE fcm_token IS NOT NULL AND fcm_token != '';

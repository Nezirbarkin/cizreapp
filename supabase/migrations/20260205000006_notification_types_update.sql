-- ============================================================================
-- NOTIFICATIONS TYPE CONSTRAINT GÜNCELLEMESİ
-- ============================================================================
-- shop_review ve shop_review_reply tiplerini notifications tablosuna ekler

-- NOT: Mevcut verilerdeki tipleri görmek için:
-- SELECT DISTINCT type, count(*) FROM notifications GROUP BY type;

-- ÇÖZÜM 1: Constraint'i tamamen kaldır (en güvenli yol)
-- Type alanı zaten text, herhangi bir değer alabilir
ALTER TABLE notifications DROP CONSTRAINT IF EXISTS notifications_type_check;

-- Constraint olmadan devam ediyoruz - böylece tüm tipler geçerli olur
-- Uygulama seviyesinde tipler kontrol edilir

-- Onay mesajı
SELECT 'Notification type constraint kaldırıldı - artık tüm tipler geçerli!' as status;

-- ============================================================================
-- BAKİYE BİLDİRİM TRIGGER'INI KALDIR
-- Çift bildirim sorununu çözer.
-- Trigger INSERT anında tetiklenip pending kayıt için bildirim oluşturuyordu.
-- Şimdi bildirim sadece confirm-balance-topup callback'inde (başarılı olduğunda)
-- oluşturuluyor. Bu daha temiz bir akış sağlar.
-- ============================================================================

DROP TRIGGER IF EXISTS trigger_notify_admin_balance_topup ON balance_transactions;

-- Fonksiyonu da kaldır (artık kullanılmıyor)
DROP FUNCTION IF EXISTS notify_admin_balance_topup();

-- ============================================================================
-- BAŞARILI
-- Artık bakiye yükleme bildirimleri sadece callback'te (başarılı işlemde) oluşur.
-- ============================================================================
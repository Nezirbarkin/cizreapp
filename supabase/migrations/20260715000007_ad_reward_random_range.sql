-- ============================================
-- REKLAM ÖDÜLÜNÜ SABİT TUTARDAN RASTGELE ARALIĞA ÇEVİR
-- Tarih: 2026-07-15
-- Açıklama: Kullanıcı her izlemede sabit tutar yerine min-max arası
-- rastgele (ağırlıklı, düşük tutara yakın) bir ödül kazanır — daha çok
-- izlenmeyi teşvik eder ("50 kuruştan 10 TL'ye çıkma şansı" gibi).
-- ============================================

ALTER TABLE ad_settings
    ADD COLUMN IF NOT EXISTS reward_min_try DECIMAL(10, 2) NOT NULL DEFAULT 0.50 CHECK (reward_min_try >= 0),
    ADD COLUMN IF NOT EXISTS reward_max_try DECIMAL(10, 2) NOT NULL DEFAULT 10.00 CHECK (reward_max_try >= 0);

-- Mevcut sabit tutarı min tarafına taşı (geriye dönük uyumluluk)
UPDATE ad_settings SET reward_min_try = reward_amount_try WHERE reward_min_try = 0.50;

ALTER TABLE ad_settings
    ADD CONSTRAINT ad_settings_reward_range_check CHECK (reward_max_try >= reward_min_try);

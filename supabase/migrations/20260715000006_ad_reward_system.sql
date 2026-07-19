-- ============================================
-- REKLAM İZLEYEREK BAKİYE KAZANMA SİSTEMİ
-- Tarih: 2026-07-15
-- Açıklama: AdMob ödüllü (rewarded) reklam izleyen kullanıcıya
-- admin tarafından belirlenen tutarda bakiye yükler.
-- Bakiye mutasyonu SADECE service_role (Edge Function) üzerinden yapılır.
-- ============================================

-- 1) balance_transactions enum'una 'ad_reward' tipi ekle
ALTER TYPE balance_transaction_type ADD VALUE IF NOT EXISTS 'ad_reward';

-- 2) AD_SETTINGS: Tekil (id=1) admin config satırı
CREATE TABLE IF NOT EXISTS ad_settings (
    id INT PRIMARY KEY DEFAULT 1,
    is_enabled BOOLEAN NOT NULL DEFAULT false,
    test_mode BOOLEAN NOT NULL DEFAULT true,

    -- AdMob App ID'leri (bilgi amaçlı; gerçek değer native manifest/plist'e girilmelidir)
    admob_app_id_android TEXT,
    admob_app_id_ios TEXT,

    -- Ödüllü reklam birim ID'leri (uygulama runtime'da bunları çeker)
    admob_rewarded_unit_id_android TEXT,
    admob_rewarded_unit_id_ios TEXT,

    -- Ödül ve limit ayarları
    reward_amount_try DECIMAL(10, 2) NOT NULL DEFAULT 0.50 CHECK (reward_amount_try >= 0),
    max_views_per_day INT NOT NULL DEFAULT 10 CHECK (max_views_per_day >= 0),
    max_views_per_hour INT NOT NULL DEFAULT 3 CHECK (max_views_per_hour >= 0),
    min_watch_seconds INT NOT NULL DEFAULT 15 CHECK (min_watch_seconds >= 0),
    cooldown_seconds INT NOT NULL DEFAULT 60 CHECK (cooldown_seconds >= 0),
    max_daily_payout_try DECIMAL(10, 2) NOT NULL DEFAULT 5000 CHECK (max_daily_payout_try >= 0),

    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT ad_settings_singleton CHECK (id = 1)
);

INSERT INTO ad_settings (id) VALUES (1) ON CONFLICT (id) DO NOTHING;

ALTER TABLE ad_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "ad_settings_select_authenticated" ON ad_settings;
CREATE POLICY "ad_settings_select_authenticated" ON ad_settings
    FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "ad_settings_admin_all" ON ad_settings;
CREATE POLICY "ad_settings_admin_all" ON ad_settings
    FOR ALL TO authenticated
    USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin'))
    WITH CHECK (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin'));

-- 3) AD_REWARD_VIEWS: Her ödüllü reklam izleme denemesinin kaydı (anti-fraud)
CREATE TABLE IF NOT EXISTS ad_reward_views (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    reward_amount DECIMAL(10, 2) NOT NULL DEFAULT 0,
    status VARCHAR(20) NOT NULL DEFAULT 'success', -- success | blocked
    block_reason TEXT,
    device_id TEXT,
    ip_address TEXT,
    balance_transaction_id UUID REFERENCES balance_transactions(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ad_reward_views_user_id ON ad_reward_views(user_id);
CREATE INDEX IF NOT EXISTS idx_ad_reward_views_created_at ON ad_reward_views(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_ad_reward_views_user_created ON ad_reward_views(user_id, created_at DESC);

ALTER TABLE ad_reward_views ENABLE ROW LEVEL SECURITY;

-- Kullanıcı kendi geçmişini görebilir, yazma sadece service_role (Edge Function) içindir
DROP POLICY IF EXISTS "ad_reward_views_select_own" ON ad_reward_views;
CREATE POLICY "ad_reward_views_select_own" ON ad_reward_views
    FOR SELECT TO authenticated USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "ad_reward_views_admin_select" ON ad_reward_views;
CREATE POLICY "ad_reward_views_admin_select" ON ad_reward_views
    FOR SELECT TO authenticated
    USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin'));

DROP POLICY IF EXISTS "ad_reward_views_service_role_all" ON ad_reward_views;
CREATE POLICY "ad_reward_views_service_role_all" ON ad_reward_views
    FOR ALL TO service_role USING (true) WITH CHECK (true);

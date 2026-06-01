-- ============================================
-- BAŞARIMLAR VE OFFLINE MODE VERİTABANI ŞEMASI
-- ============================================

-- 1. Başarımlar tablosu
CREATE TABLE IF NOT EXISTS achievements (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    type VARCHAR(50) NOT NULL UNIQUE,
    title VARCHAR(100) NOT NULL,
    description TEXT NOT NULL,
    icon_name VARCHAR(50) NOT NULL,
    required_count INTEGER NOT NULL DEFAULT 1,
    xp_reward INTEGER NOT NULL DEFAULT 10,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Kullanıcı başarımları (XP, seviye, streak)
CREATE TABLE IF NOT EXISTS user_achievements (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    total_xp INTEGER DEFAULT 0,
    level INTEGER DEFAULT 1,
    streak_days INTEGER DEFAULT 0,
    last_login_date TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. Kullanıcı açılmış başarımlar
CREATE TABLE IF NOT EXISTS user_unlocked_achievements (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    achievement_id UUID NOT NULL REFERENCES achievements(id) ON DELETE CASCADE,
    unlocked_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, achievement_id)
);

-- 4. Adreslere koordinat ekle
ALTER TABLE addresses 
ADD COLUMN IF NOT EXISTS latitude DOUBLE PRECISION,
ADD COLUMN IF NOT EXISTS longitude DOUBLE PRECISION,
ADD COLUMN IF NOT EXISTS place_id VARCHAR(255);

-- 5. İndeksler
CREATE INDEX IF NOT EXISTS idx_user_achievements_user_id ON user_achievements(user_id);
CREATE INDEX IF NOT EXISTS idx_user_unlocked_achievements_user_id ON user_unlocked_achievements(user_id);
CREATE INDEX IF NOT EXISTS idx_addresses_lat_lng ON addresses(latitude, longitude);

-- ============================================
-- BAŞLANGIÇ VERİLERİ
-- ============================================

-- Varsayılan başarımları ekle
INSERT INTO achievements (type, title, description, icon_name, required_count, xp_reward)
VALUES 
    ('firstOrder', 'İlk Sipariş', 'İlk siparişinizi tamamlayın', 'shopping_bag', 1, 10),
    ('loyalCustomer', 'Sadık Müşteri', '10 sipariş tamamlayın', 'star', 10, 100),
    ('superCustomer', 'Süper Müşteri', '50 sipariş tamamlayın', 'workspace_premium', 50, 500),
    ('reviewer', 'İlk Değerlendirme', 'İlk ürün değerlendirmenizi yapın', 'star', 1, 5),
    ('topReviewer', 'Üstün Değerlendiren', '10 ürün değerlendirin', 'military_tech', 10, 50),
    ('socializer', 'Sosyal İnsan', 'İlk gönderinizi paylaşın', 'celebration', 1, 15),
    ('popular', 'Popüler', '100 takipçi kazanın', 'local_fire_department', 100, 200),
    ('weeklyStreak', 'Haftalık Streak', '7 gün üst üste giriş yapın', 'bolt', 7, 50),
    ('monthlyStreak', 'Aylık Streak', '30 gün üst üste giriş yapın', 'diamond', 30, 200),
    ('bigSpender', 'Büyük Harcayıcı', '1000₺ harcama yapın', 'restaurant', 1000, 100),
    ('explorer', 'Kaşif', '10 farklı mağazadan alışveriş yapın', 'explore', 10, 75),
    ('earlyBird', 'Erken Kuş', 'İlk 1000 kayıt olan arasına girin', 'schedule', 1, 250)
ON CONFLICT (type) DO NOTHING;

-- ============================================
-- FONKSİYONLAR
-- ============================================

-- XP ekleme fonksiyonu
CREATE OR REPLACE FUNCTION add_user_xp(p_user_id UUID, p_xp INTEGER)
RETURNS VOID AS $$
BEGIN
    INSERT INTO user_achievements (user_id, total_xp, level, updated_at)
    VALUES (p_user_id, p_xp, 1, NOW())
    ON CONFLICT (user_id) DO UPDATE SET
        total_xp = user_achievements.total_xp + p_xp,
        level = GREATEST(
            user_achievements.level,
            CASE 
                WHEN user_achievements.total_xp + p_xp >= 5000 THEN 10
                WHEN user_achievements.total_xp + p_xp >= 2000 THEN 7
                WHEN user_achievements.total_xp + p_xp >= 1000 THEN 5
                WHEN user_achievements.total_xp + p_xp >= 500 THEN 3
                WHEN user_achievements.total_xp + p_xp >= 100 THEN 2
                ELSE 1
            END
        ),
        updated_at = NOW();
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- RLS POLICIES
-- ============================================

-- User achievements RLS
ALTER TABLE user_achievements ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view own achievements" ON user_achievements
    FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can update own achievements" ON user_achievements
    FOR UPDATE USING (auth.uid() = user_id);

-- User unlocked achievements RLS
ALTER TABLE user_unlocked_achievements ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view own unlocked achievements" ON user_unlocked_achievements
    FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert own unlocked achievements" ON user_unlocked_achievements
    FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Achievements RLS (herkes görebilir)
ALTER TABLE achievements ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone can view achievements" ON achievements
    FOR SELECT USING (true);

-- Addresses RLS (koordinatlar dahil)
ALTER TABLE addresses ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view own addresses" ON addresses
    FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can update own addresses" ON addresses
    FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Users can insert own addresses" ON addresses
    FOR INSERT WITH CHECK (auth.uid() = user_id);

-- ============================================
-- TRIGGERLER
-- ============================================

-- Updated_at trigger
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_achievements_updated_at
    BEFORE UPDATE ON achievements
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_user_achievements_updated_at
    BEFORE UPDATE ON user_achievements
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================
-- NOTLAR
-- ============================================
-- 
-- 1. Başarımlar sayfası: /lib/features/profile/screens/achievements_screen.dart
-- 2. Offline servis: /lib/core/services/offline_service.dart
-- 3. Adres seçici: /lib/features/market/screens/address_picker_screen.dart
-- 4. Başarım servisi: /lib/core/services/achievement_service.dart
--
-- Kullanıcı giriş yaptığında:
--   await AchievementService().checkAndUnlockAchievements(userId);
--   await OfflineService().initialize();
--
-- Sipariş tamamlandığında:
--   await AchievementService().onOrderCompleted(userId);
--
-- Değerlendirme yapıldığında:
--   await AchievementService().onReviewAdded(userId);

-- ============================================
-- YOKLAMA/ÇİZRELİLER SİSTEMİ
-- ============================================
-- Kullanıcıların günlük yoklama yapması ve streak kazanması

-- ============================================
-- 1. YOKLAMA TABLOSU
-- ============================================
CREATE TABLE IF NOT EXISTS daily_checkins (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    checkin_date DATE NOT NULL DEFAULT CURRENT_DATE,
    streak_count INTEGER DEFAULT 1,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    metadata JSONB DEFAULT '{}'::jsonb,
    UNIQUE(user_id, checkin_date)
);

-- Index'ler
CREATE INDEX IF NOT EXISTS idx_checkins_user_id ON daily_checkins(user_id);
CREATE INDEX IF NOT EXISTS idx_checkins_date ON daily_checkins(checkin_date);
CREATE INDEX IF NOT EXISTS idx_checkins_streak ON daily_checkins(streak_count DESC);

-- RLS Politikaları
ALTER TABLE daily_checkins ENABLE ROW LEVEL SECURITY;

CREATE POLICY "checkins_select_own" ON daily_checkins
    FOR SELECT TO authenticated
    USING (user_id = (SELECT auth.uid()));

CREATE POLICY "checkins_insert_own" ON daily_checkins
    FOR INSERT TO authenticated
    WITH CHECK (user_id = (SELECT auth.uid()));

CREATE POLICY "checkins_update_own" ON daily_checkins
    FOR UPDATE TO authenticated
    USING (user_id = (SELECT auth.uid()));

CREATE POLICY "checkins_all_admin" ON daily_checkins
    FOR ALL TO authenticated
    USING ((SELECT auth.jwt() ->> 'role') = 'admin');

-- ============================================
-- 2. YOKLAMA ÖDÜLLERİ TABLOSU
-- ============================================
CREATE TABLE IF NOT EXISTS checkin_rewards (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    streak_days INTEGER NOT NULL,
    reward_type TEXT NOT NULL, -- 'badge', 'points', 'special'
    reward_name TEXT NOT NULL,
    reward_description TEXT,
    reward_data JSONB DEFAULT '{}'::jsonb,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(streak_days)
);

-- RLS Politikaları
ALTER TABLE checkin_rewards ENABLE ROW LEVEL SECURITY;

CREATE POLICY "rewards_select_all" ON checkin_rewards
    FOR SELECT TO authenticated
    USING (is_active = TRUE);

CREATE POLICY "rewards_all_admin" ON checkin_rewards
    FOR ALL TO authenticated
    USING ((SELECT auth.jwt() ->> 'role') = 'admin');

-- ============================================
-- 3. YOKLAMA LİDERLİK TABLOSU (Materialized View)
-- ============================================
CREATE MATERIALIZED VIEW IF NOT EXISTS checkin_leaderboard AS
SELECT 
    dc.user_id,
    p.username,
    p.full_name,
    p.avatar_url,
    MAX(dc.streak_count) as current_streak,
    COUNT(dc.id) as total_checkins,
    MAX(dc.checkin_date) as last_checkin
FROM daily_checkins dc
JOIN profiles p ON p.id = dc.user_id
GROUP BY dc.user_id, p.username, p.full_name, p.avatar_url
ORDER BY MAX(dc.streak_count) DESC, COUNT(dc.id) DESC;

-- Refresh için index
CREATE UNIQUE INDEX IF NOT EXISTS idx_leaderboard_user_id ON checkin_leaderboard(user_id);

-- ============================================
-- 4. YOKLAMA FONKSİYONLARI
-- ============================================
-- Günlük yoklama yap
CREATE OR REPLACE FUNCTION checkin_daily(p_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
    v_today DATE := CURRENT_DATE;
    v_yesterday DATE := CURRENT_DATE - INTERVAL '1 day';
    v_last_checkin DATE;
    v_current_streak INTEGER := 1;
    v_total_checkins INTEGER;
    v_reward JSONB;
BEGIN
    -- Son yoklama tarihini kontrol et
    SELECT checkin_date INTO v_last_checkin
    FROM daily_checkins
    WHERE user_id = p_user_id
    ORDER BY checkin_date DESC
    LIMIT 1;
    
    -- Bugün zaten yoklama yapmış mı?
    IF v_last_checkin = v_today THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'message', 'Bugün zaten yoklama yaptınız',
            'streak', (SELECT streak_count FROM daily_checkins WHERE user_id = p_user_id AND checkin_date = v_today)
        );
    END IF;
    
    -- Streak hesapla
    IF v_last_checkin = v_yesterday THEN
        -- Dün de yoklama yapmış, streak devam ediyor
        v_current_streak := (SELECT streak_count FROM daily_checkins WHERE user_id = p_user_id AND checkin_date = v_yesterday) + 1;
    ELSE
        -- Streak bozuldu, yeniden başla
        v_current_streak := 1;
    END IF;
    
    -- Yoklama kaydı oluştur
    INSERT INTO daily_checkins (user_id, checkin_date, streak_count)
    VALUES (p_user_id, v_today, v_current_streak)
    ON CONFLICT (user_id, checkin_date) DO UPDATE SET
        streak_count = v_current_streak,
        updated_at = NOW();
    
    -- Toplam yoklama sayısı
    SELECT COUNT(*) INTO v_total_checkins
    FROM daily_checkins
    WHERE user_id = p_user_id;
    
    -- Ödül kontrolü
    SELECT jsonb_build_object(
        'type', reward_type,
        'name', reward_name,
        'description', reward_description
    ) INTO v_reward
    FROM checkin_rewards
    WHERE streak_days = v_current_streak AND is_active = TRUE;
    
    -- Liderlik tablosunu güncelle
    REFRESH MATERIALIZED VIEW CONCURRENTLY checkin_leaderboard;
    
    RETURN jsonb_build_object(
        'success', TRUE,
        'message', 'Yoklama yapıldı!',
        'streak', v_current_streak,
        'total_checkins', v_total_checkins,
        'reward', v_reward
    );
END;
$$;

-- Kullanıcı istatistiklerini getir
CREATE OR REPLACE FUNCTION get_checkin_stats(p_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
    v_current_streak INTEGER := 0;
    v_max_streak INTEGER := 0;
    v_total_checkins INTEGER := 0;
    v_last_checkin DATE;
    v_today_checkin BOOLEAN;
    v_rank INTEGER;
BEGIN
    -- İstatistikleri al
    SELECT 
        COALESCE(MAX(streak_count), 0),
        COUNT(*),
        MAX(checkin_date)
    INTO v_max_streak, v_total_checkins, v_last_checkin
    FROM daily_checkins
    WHERE user_id = p_user_id;
    
    -- Bugünkü streak
    SELECT streak_count INTO v_current_streak
    FROM daily_checkins
    WHERE user_id = p_user_id
    ORDER BY checkin_date DESC
    LIMIT 1;
    
    -- Bugün yoklama yapıldı mı?
    SELECT EXISTS(
        SELECT 1 FROM daily_checkins
        WHERE user_id = p_user_id AND checkin_date = CURRENT_DATE
    ) INTO v_today_checkin;
    
    -- Sıralama
    SELECT COUNT(*) + 1 INTO v_rank
    FROM checkin_leaderboard
    WHERE current_streak > v_current_streak;
    
    RETURN jsonb_build_object(
        'current_streak', v_current_streak,
        'max_streak', v_max_streak,
        'total_checkins', v_total_checkins,
        'last_checkin', v_last_checkin,
        'today_checkin', v_today_checkin,
        'rank', v_rank
    );
END;
$$;

-- Liderlik tablosunu getir (sayfalama ile)
CREATE OR REPLACE FUNCTION get_leaderboard(p_limit INTEGER DEFAULT 50, p_offset INTEGER DEFAULT 0)
RETURNS TABLE (
    user_id UUID,
    username TEXT,
    full_name TEXT,
    avatar_url TEXT,
    current_streak INTEGER,
    total_checkins BIGINT,
    last_checkin DATE
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        cl.user_id,
        cl.username::TEXT,
        cl.full_name::TEXT,
        cl.avatar_url::TEXT,
        cl.current_streak,
        cl.total_checkins,
        cl.last_checkin
    FROM checkin_leaderboard cl
    ORDER BY cl.current_streak DESC, cl.total_checkins DESC
    LIMIT p_limit
    OFFSET p_offset;
END;
$$;

-- ============================================
-- 5. VARSAYILAN ÖDÜLLER
-- ============================================
INSERT INTO checkin_rewards (streak_days, reward_type, reward_name, reward_description, reward_data) VALUES
    (3, 'points', '3 Gün Serisi', '3 gün arka arkaya yoklama', '{"points": 10}'),
    (7, 'badge', 'Haftalık Kahraman', '7 gün arka arkaya yoklama', '{"badge_id": "weekly_hero"}'),
    (14, 'points', '2 Hafta Serisi', '14 gün arka arkaya yoklama', '{"points": 50}'),
    (30, 'badge', 'Aylık Şampiyon', '30 gün arka arkaya yoklama', '{"badge_id": "monthly_champion"}'),
    (60, 'badge', 'Efsanevi Çizreli', '60 gün arka arkaya yoklama', '{"badge_id": "legendary", "points": 100}'),
    (100, 'badge', 'Yüzyıl Savaşçısı', '100 gün arka arkaya yoklama', '{"badge_id": "century_warrior", "points": 500}')
ON CONFLICT (streak_days) DO NOTHING;

-- ============================================
-- 6. TRIGGER'LAR
-- ============================================
-- updated_at otomatik güncelleme
CREATE OR REPLACE FUNCTION update_checkin_timestamp()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

CREATE TRIGGER trigger_update_checkin_timestamp
    BEFORE UPDATE ON daily_checkins
    FOR EACH ROW
    EXECUTE FUNCTION update_checkin_timestamp();

-- ============================================
-- 7. INDEX'LER (Performans için)
-- ============================================
CREATE INDEX IF NOT EXISTS idx_checkins_user_date ON daily_checkins(user_id, checkin_date DESC);

-- ============================================
-- TAMAMLANDI
-- ============================================
-- Bu tablolar ve fonksiyonlar Yoklama/Çizreliler sistemi için kullanılacak:
-- - daily_checkins: Günlük yoklama kayıtları
-- - checkin_rewards: Streak ödülleri
-- - checkin_leaderboard: Liderlik tablosu
-- - checkin_daily(): Yoklama yap
-- - get_checkin_stats(): Kullanıcı istatistikleri
-- - get_leaderboard(): Liderlik tablosu
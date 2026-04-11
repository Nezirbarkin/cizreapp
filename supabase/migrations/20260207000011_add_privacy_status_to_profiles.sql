-- ============================================================================
-- GİZLİLİK VE DURUM ÖZELLİKLERİ - profiles tablosu
-- ============================================================================

-- Mevcut sütunları kontrol et ve gerekirse ekle
ALTER TABLE profiles 
ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'online' CHECK (status IN ('online', 'busy', 'away', 'offline'));

ALTER TABLE profiles 
ADD COLUMN IF NOT EXISTS show_last_seen BOOLEAN DEFAULT true;

ALTER TABLE profiles 
ADD COLUMN IF NOT EXISTS allow_messages_from_non_followers BOOLEAN DEFAULT true;

ALTER TABLE profiles 
ADD COLUMN IF NOT EXISTS profile_is_public BOOLEAN DEFAULT true;

ALTER TABLE profiles 
ADD COLUMN IF NOT EXISTS last_seen TIMESTAMP WITH TIME ZONE DEFAULT NOW();

-- Index oluştur
CREATE INDEX IF NOT EXISTS idx_profiles_status ON profiles(status);
CREATE INDEX IF NOT EXISTS idx_profiles_last_seen ON profiles(last_seen DESC);

-- RLS politikası - Kullanıcı kendi gizlilik ayarlarını güncelleyebilir
DROP POLICY IF EXISTS "profiles_update_privacy_own" ON profiles;
CREATE POLICY "profiles_update_privacy_own"
    ON profiles
    FOR UPDATE
    TO authenticated
    USING (id = auth.uid())
    WITH CHECK (id = auth.uid());

-- Fonksiyon: Kullanıcının son görülme zamanını güncelle
CREATE OR REPLACE FUNCTION update_last_seen()
RETURNS TRIGGER AS $$
BEGIN
    NEW.last_seen = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger: Profil her güncellendiğinde son görülme zamanını güncelle
DROP TRIGGER IF EXISTS update_profiles_last_seen ON profiles;
CREATE TRIGGER update_profiles_last_seen
    BEFORE UPDATE ON profiles
    FOR EACH ROW
    EXECUTE FUNCTION update_last_seen();

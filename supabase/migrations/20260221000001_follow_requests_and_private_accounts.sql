-- Follow Requests Table - Gizli hesaplar için takip isteği sistemi
-- profile_is_public = false olan hesaplar için takip isteği gerekir

-- follow_requests tablosunu oluştur
CREATE TABLE IF NOT EXISTS public.follow_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    follower_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    following_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'rejected')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    -- Aynı kişi aynı kişiye sadece bir istek gönderebilir
    UNIQUE(follower_id, following_id)
);

-- Indexler
CREATE INDEX IF NOT EXISTS idx_follow_requests_follower ON follow_requests(follower_id);
CREATE INDEX IF NOT EXISTS idx_follow_requests_following ON follow_requests(following_id);
CREATE INDEX IF NOT EXISTS idx_follow_requests_status ON follow_requests(status);
CREATE INDEX IF NOT EXISTS idx_follow_requests_created_at ON follow_requests(created_at DESC);

-- Kendini takip etmeyi engelle
ALTER TABLE follow_requests ADD CONSTRAINT check_not_self 
CHECK (follower_id != following_id);

-- updated_at trigger
CREATE OR REPLACE FUNCTION update_follow_requests_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_follow_requests_updated_at
BEFORE UPDATE ON follow_requests
FOR EACH ROW
EXECUTE FUNCTION update_follow_requests_updated_at();

-- Follow Request Notification Trigger
CREATE OR REPLACE FUNCTION notify_follow_request_trigger()
RETURNS TRIGGER AS $$
DECLARE
    follower_profile JSONB;
    following_profile JSONB;
BEGIN
    -- Sadece yeni istekler için bildirim gönder (pending status)
    IF TG_OP = 'INSERT' AND NEW.status = 'pending' THEN
        -- Follower profili
        SELECT row_to_json(p) INTO follower_profile
        FROM profiles p
        WHERE p.id = NEW.follower_id;
        
        INSERT INTO notifications (user_id, type, title, content, actor_id, actor_name, actor_avatar, entity_id)
        VALUES (
            NEW.following_id,
            'follow_request',
            'Takip isteği',
            'seni takip etmek istiyor',
            NEW.follower_id,
            COALESCE(follower_profile->>'username', 'Bir kullanıcı'),
            follower_profile->>'avatar_url',
            NEW.id::text
        );
    END IF;
    
    -- İstek kabul edildiğinde bildirim gönder
    IF TG_OP = 'UPDATE' AND OLD.status = 'pending' AND NEW.status = 'accepted' THEN
        INSERT INTO notifications (user_id, type, title, content, actor_id, actor_name, actor_avatar, entity_id)
        VALUES (
            NEW.follower_id,
            'follow_request_accepted',
            'Takip isteği kabul edildi',
            'seni takip etmeye başladı',
            NEW.following_id,
            COALESCE((SELECT username FROM profiles WHERE id = NEW.following_id), 'Bir kullanıcı'),
            (SELECT avatar_url FROM profiles WHERE id = NEW.following_id),
            NEW.id::text
        );
        
        -- Otomatik olarak follows tablosuna ekle
        INSERT INTO follows (follower_id, following_id, created_at)
        VALUES (NEW.follower_id, NEW.following_id, NEW.created_at)
        ON CONFLICT (follower_id, following_id) DO NOTHING;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER notify_follow_request
AFTER INSERT OR UPDATE ON follow_requests
FOR EACH ROW
EXECUTE FUNCTION notify_follow_request_trigger();

-- RLS Policies
ALTER TABLE follow_requests ENABLE ROW LEVEL SECURITY;

-- Herkes istekleri görebilir
CREATE POLICY "Anyone can view follow requests"
ON follow_requests FOR SELECT
USING (true);

-- Sadece ilgili kullanıcılar insert yapabilir
CREATE POLICY "Users can create follow requests"
ON follow_requests FOR INSERT
WITH CHECK (auth.uid() = follower_id);

-- Sadece following_id (hedef kullanıcı) update yapabilir (onaylayabilir)
CREATE POLICY "Target user can update follow request status"
ON follow_requests FOR UPDATE
USING (auth.uid() = following_id)
WITH CHECK (auth.uid() = following_id);

-- Sadece ilgili kullanıcılar delete yapabilir
CREATE POLICY "Users can delete their own requests"
ON follow_requests FOR DELETE
USING (auth.uid() = follower_id OR auth.uid() = following_id);

-- Comments
COMMENT ON TABLE follow_requests IS 'Gizli hesaplar için takip istekleri';
COMMENT ON COLUMN follow_requests.status IS 'pending: bekliyor, accepted: kabul edildi, rejected: reddedildi';

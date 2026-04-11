-- support_tickets tablosuna category kolonu ekle
-- Eğer tablo varsa ve category kolonu yoksa ekle

-- Önce kolonun var olup olmadığını kontrol et
DO $$
BEGIN
    -- category kolonu yoksa ekle
    IF NOT EXISTS (
        SELECT 1 
        FROM information_schema.columns 
        WHERE table_schema = 'public' 
        AND table_name = 'support_tickets' 
        AND column_name = 'category'
    ) THEN
        ALTER TABLE support_tickets 
        ADD COLUMN category TEXT NOT NULL DEFAULT 'general' 
        CHECK (category IN ('general', 'account', 'payment', 'order', 'technical', 'other'));
        
        RAISE NOTICE 'category kolonu eklendi';
    ELSE
        RAISE NOTICE 'category kolonu zaten mevcut';
    END IF;
END
$$;

-- Eğer support_tickets tablosu hiç yoksa oluştur
CREATE TABLE IF NOT EXISTS support_tickets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    subject TEXT NOT NULL,
    category TEXT NOT NULL DEFAULT 'general' CHECK (category IN ('general', 'account', 'payment', 'order', 'technical', 'other')),
    message TEXT NOT NULL,
    status TEXT DEFAULT 'open' CHECK (status IN ('open', 'in_progress', 'resolved', 'closed')),
    admin_response TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- İndeksler (IF NOT EXISTS ile)
CREATE INDEX IF NOT EXISTS idx_support_tickets_user ON support_tickets(user_id);
CREATE INDEX IF NOT EXISTS idx_support_tickets_status ON support_tickets(status);
CREATE INDEX IF NOT EXISTS idx_support_tickets_category ON support_tickets(category);
CREATE INDEX IF NOT EXISTS idx_support_tickets_created ON support_tickets(created_at DESC);

-- RLS etkinleştir
ALTER TABLE support_tickets ENABLE ROW LEVEL SECURITY;

-- RLS Politikaları (varsa atla)
DO $$
BEGIN
    -- Kullanıcılar kendi taleplerini görebilir
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE policyname = 'Kullanıcılar kendi taleplerini görebilir' AND tablename = 'support_tickets'
    ) THEN
        CREATE POLICY "Kullanıcılar kendi taleplerini görebilir"
            ON support_tickets FOR SELECT
            TO authenticated
            USING (auth.uid() = user_id);
    END IF;
    
    -- Kullanıcılar talep oluşturabilir
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE policyname = 'Kullanıcılar talep oluşturabilir' AND tablename = 'support_tickets'
    ) THEN
        CREATE POLICY "Kullanıcılar talep oluşturabilir"
            ON support_tickets FOR INSERT
            TO authenticated
            WITH CHECK (auth.uid() = user_id);
    END IF;
    
    -- Admin'ler tüm talepleri görebilir
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE policyname = 'Admin tüm talepleri görebilir' AND tablename = 'support_tickets'
    ) THEN
        CREATE POLICY "Admin tüm talepleri görebilir"
            ON support_tickets FOR SELECT
            TO authenticated
            USING (
                EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND is_admin = true)
            );
    END IF;
    
    -- Admin'ler talepleri güncelleyebilir
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE policyname = 'Admin talepleri güncelleyebilir' AND tablename = 'support_tickets'
    ) THEN
        CREATE POLICY "Admin talepleri güncelleyebilir"
            ON support_tickets FOR UPDATE
            TO authenticated
            USING (
                EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND is_admin = true)
            )
            WITH CHECK (
                EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND is_admin = true)
            );
    END IF;
END
$$;

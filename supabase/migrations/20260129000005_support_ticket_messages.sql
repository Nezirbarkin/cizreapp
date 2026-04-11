-- Destek talebi mesajlaşma sistemi
-- 1. Ticket mesajları tablosu
CREATE TABLE IF NOT EXISTS support_ticket_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ticket_id UUID NOT NULL REFERENCES support_tickets(id) ON DELETE CASCADE,
    sender_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    sender_type VARCHAR NOT NULL DEFAULT 'user', -- 'user' veya 'admin'
    message TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Eski is_admin kolonu varsa sender_type'ye dönüştür
DO $$
BEGIN
    -- is_admin kolonu varsa sender_type'ye dönüştür ve is_admin'i kaldır
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'support_ticket_messages'
        AND column_name = 'is_admin'
    ) THEN
        -- sender_type yoksa önce ekle
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.columns
            WHERE table_name = 'support_ticket_messages'
            AND column_name = 'sender_type'
        ) THEN
            ALTER TABLE support_ticket_messages ADD COLUMN sender_type VARCHAR NOT NULL DEFAULT 'user';
        END IF;
        
        -- Mevcut verileri dönüştür
        UPDATE support_ticket_messages SET sender_type = CASE WHEN is_admin = true THEN 'admin' ELSE 'user' END;
        
        -- is_admin kolonunu kaldır
        ALTER TABLE support_ticket_messages DROP COLUMN IF EXISTS is_admin;
    END IF;
END $$;

-- İndeksler
CREATE INDEX IF NOT EXISTS idx_ticket_messages_ticket ON support_ticket_messages(ticket_id);
CREATE INDEX IF NOT EXISTS idx_ticket_messages_sender ON support_ticket_messages(sender_id);
CREATE INDEX IF NOT EXISTS idx_ticket_messages_created ON support_ticket_messages(created_at);

-- RLS etkinleştir
ALTER TABLE support_ticket_messages ENABLE ROW LEVEL SECURITY;

-- RLS Politikaları
DO $$
BEGIN
    -- Kullanıcılar kendi taleplerinin mesajlarını görebilir
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE policyname = 'Kullanıcı kendi talep mesajlarını görebilir' AND tablename = 'support_ticket_messages'
    ) THEN
        CREATE POLICY "Kullanıcı kendi talep mesajlarını görebilir"
            ON support_ticket_messages FOR SELECT
            TO authenticated
            USING (
                EXISTS (
                    SELECT 1 FROM support_tickets 
                    WHERE support_tickets.id = support_ticket_messages.ticket_id 
                    AND support_tickets.user_id = auth.uid()
                )
            );
    END IF;
    
    -- Kullanıcılar kendi taleplerine mesaj yazabilir
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE policyname = 'Kullanıcı kendi talebine mesaj yazabilir' AND tablename = 'support_ticket_messages'
    ) THEN
        CREATE POLICY "Kullanıcı kendi talebine mesaj yazabilir"
            ON support_ticket_messages FOR INSERT
            TO authenticated
            WITH CHECK (
                auth.uid() = sender_id
                AND EXISTS (
                    SELECT 1 FROM support_tickets 
                    WHERE support_tickets.id = support_ticket_messages.ticket_id 
                    AND support_tickets.user_id = auth.uid()
                )
            );
    END IF;
    
    -- Admin'ler tüm mesajları görebilir
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE policyname = 'Admin tüm talep mesajlarını görebilir' AND tablename = 'support_ticket_messages'
    ) THEN
        CREATE POLICY "Admin tüm talep mesajlarını görebilir"
            ON support_ticket_messages FOR SELECT
            TO authenticated
            USING (
                EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND is_admin = true)
            );
    END IF;
    
    -- Admin'ler mesaj yazabilir
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE policyname = 'Admin taleplere mesaj yazabilir' AND tablename = 'support_ticket_messages'
    ) THEN
        CREATE POLICY "Admin taleplere mesaj yazabilir"
            ON support_ticket_messages FOR INSERT
            TO authenticated
            WITH CHECK (
                EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND is_admin = true)
            );
    END IF;
END
$$;

-- Realtime etkinleştir (tablo zaten ekliyse hata vermez)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime'
        AND tablename = 'support_ticket_messages'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE support_ticket_messages;
    END IF;
END $$;

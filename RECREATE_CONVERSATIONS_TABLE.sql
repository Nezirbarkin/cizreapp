-- =====================================================
-- CONVERSATIONS TABLOSUNU YENİDEN OLUŞTUR
-- =====================================================
-- Bu dosya conversations tablosunu sıfırdan oluşturur
-- Eğer tablo varsa önce siler, sonra yeniden oluşturur
-- =====================================================

-- Tablo varsa önce sil
DROP TABLE IF EXISTS public.conversations CASCADE;

-- Conversations tablosunu oluştur
CREATE TABLE public.conversations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    other_user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    last_message TEXT,
    last_message_time TIMESTAMP WITH TIME ZONE,
    unread_count INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    -- Constraint: Kullanıcı kendisiyle konuşma başlatamaz
    CONSTRAINT conversations_users_check CHECK (user_id != other_user_id)
);

-- Index'leri oluştur
CREATE INDEX idx_conversations_user_id ON public.conversations(user_id);
CREATE INDEX idx_conversations_other_user_id ON public.conversations(other_user_id);
CREATE INDEX idx_conversations_last_message_time ON public.conversations(last_message_time DESC);

-- RLS'yi kapat (test için)
ALTER TABLE public.conversations DISABLE ROW LEVEL SECURITY;

-- =====================================================
-- MESSAGES TABLOSUNU DA YENİDEN OLUŞTUR
-- =====================================================

-- Messages tablosu varsa önce sil
DROP TABLE IF EXISTS public.messages CASCADE;

-- Messages tablosunu oluştur
CREATE TABLE public.messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    sender_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    is_read BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Index'leri oluştur
CREATE INDEX idx_messages_conversation_id ON public.messages(conversation_id);
CREATE INDEX idx_messages_sender_id ON public.messages(sender_id);
CREATE INDEX idx_messages_created_at ON public.messages(created_at DESC);

-- RLS'yi kapat (test için)
ALTER TABLE public.messages DISABLE ROW LEVEL SECURITY;

-- =====================================================
-- KONTROL
-- =====================================================

-- Tablonun oluşturulduğunu doğrula
SELECT
    table_name,
    CASE
        WHEN table_name IN ('conversations', 'messages') THEN '✅ OLUŞTURULDU'
        ELSE '❌ OLUŞTURULAMADI'
    END as durum
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN ('conversations', 'messages');

-- Conversations sütunlarını gör
SELECT
    'conversations' as tablo,
    column_name,
    data_type,
    is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'conversations'
ORDER BY ordinal_position;

-- Messages sütunlarını gör
SELECT
    'messages' as tablo,
    column_name,
    data_type,
    is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'messages'
ORDER BY ordinal_position;

-- =====================================================
-- TAMAMLANDI!
-- =====================================================
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '═══════════════════════════════════════════════';
    RAISE NOTICE '✅ CONVERSATIONS TABLOSU OLUŞTURULDU!';
    RAISE NOTICE '═══════════════════════════════════════════════';
    RAISE NOTICE 'Artık mesaj gönderme çalışacak!';
    RAISE NOTICE '═══════════════════════════════════════════════';
    RAISE NOTICE '';
END $$;

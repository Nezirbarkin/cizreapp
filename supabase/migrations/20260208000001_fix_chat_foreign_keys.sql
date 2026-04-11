-- ============================================================================
-- CHAT SİSTEMİ FOREIGN KEY DÜZELTMESİ
-- ============================================================================
-- Sorun: conversations tablosundaki user_id ve other_user_id foreign key'leri
-- auth.users tablosuna referans veriyordu. Ancak Flutter kodunda profiles tablosundan
-- join yapılmaya çalışılıyordu. Bu uyumsuzluk konuşma açılamama hatasına neden oluyordu.
--
-- Çözüm: Foreign key'leri profiles tablosuna referans verecek şekilde güncelle.

-- Önce mevcut foreign key'leri kaldır
ALTER TABLE conversations DROP CONSTRAINT IF EXISTS conversations_user_id_fk;
ALTER TABLE conversations DROP CONSTRAINT IF EXISTS conversations_other_user_id_fk;

-- Yeni foreign key'leri profiles tablosuna ekle
ALTER TABLE conversations
    ADD CONSTRAINT conversations_user_id_fk
        FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE,
    ADD CONSTRAINT conversations_other_user_id_fk
        FOREIGN KEY (other_user_id) REFERENCES profiles(id) ON DELETE CASCADE;

-- Aynı düzeltmeyi messages tablosu için de yap
ALTER TABLE messages DROP CONSTRAINT IF EXISTS messages_sender_id_fkey;
ALTER TABLE messages
    ADD CONSTRAINT messages_sender_id_fk
        FOREIGN KEY (sender_id) REFERENCES profiles(id) ON DELETE CASCADE;

-- RLS politikalarını güncelle (auth.uid() kontrolü profiles tablosunda da çalışmalı)
-- Mevcut politikaları sil ve yeniden oluştur
DROP POLICY IF EXISTS "conversations_select_own" ON conversations;
CREATE POLICY "conversations_select_own"
    ON conversations
    FOR SELECT
    TO authenticated
    USING (user_id = auth.uid() OR other_user_id = auth.uid());

DROP POLICY IF EXISTS "conversations_insert_own" ON conversations;
CREATE POLICY "conversations_insert_own"
    ON conversations
    FOR INSERT
    TO authenticated
    WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "conversations_update_own" ON conversations;
CREATE POLICY "conversations_update_own"
    ON conversations
    FOR UPDATE
    TO authenticated
    USING (user_id = auth.uid() OR other_user_id = auth.uid());

-- Messages politikalarını güncelle
DROP POLICY IF EXISTS "messages_select_own" ON messages;
CREATE POLICY "messages_select_own"
    ON messages
    FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM conversations
            WHERE conversations.id = messages.conversation_id
            AND (conversations.user_id = auth.uid() OR conversations.other_user_id = auth.uid())
        )
    );

DROP POLICY IF EXISTS "messages_insert_own" ON messages;
CREATE POLICY "messages_insert_own"
    ON messages
    FOR INSERT
    TO authenticated
    WITH CHECK (
        sender_id = auth.uid()
        AND EXISTS (
            SELECT 1 FROM conversations
            WHERE conversations.id = messages.conversation_id
            AND (conversations.user_id = auth.uid() OR conversations.other_user_id = auth.uid())
        )
    );

DROP POLICY IF EXISTS "messages_update_own" ON messages;
CREATE POLICY "messages_update_own"
    ON messages
    FOR UPDATE
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM conversations
            WHERE conversations.id = messages.conversation_id
            AND (conversations.user_id = auth.uid() OR conversations.other_user_id = auth.uid())
        )
    );

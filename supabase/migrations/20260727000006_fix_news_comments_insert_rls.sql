-- =============================================================================
-- news_comments INSERT policy'sini sağlamlaştırma
-- =============================================================================
-- Sorun: "Authenticated users can insert comments" INSERT policy'si
-- auth.role() = 'authenticated' kullanıyordu. auth.role() helper'ı Supabase
-- initplan optimizasyonu sırasında tutarsız davranıp 42501 (RLS) hatası veriyor.
-- Çözüm: TO authenticated + user_id = auth.uid() ile hem authenticated kontrolü
-- yapılır hem de kullanıcının kendi adına yorum eklemesi zorunlu olur.
-- =============================================================================

ALTER TABLE news_comments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated users can insert comments" ON news_comments;
CREATE POLICY "Authenticated users can insert comments" ON news_comments
    FOR INSERT TO authenticated WITH CHECK (
        user_id = auth.uid()
    );

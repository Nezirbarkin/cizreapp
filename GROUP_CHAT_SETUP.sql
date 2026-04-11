-- ============================================
-- GRUP SOHBET SİSTEMİ - SUPABASE SQL
-- ============================================
-- Özellikler:
-- 1. Grup oluşturma (açık/gizli)
-- 2. Üyelik istekleri (gizli gruplar için)
-- 3. Grup arama
-- 4. Grup mesajlaşma
-- 5. Üye yönetimi
-- ============================================

-- 1. GROUPS (Gruplar) Tablosu
CREATE TABLE IF NOT EXISTS public.groups (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    description TEXT,
    avatar_url TEXT,
    cover_url TEXT,
    is_private BOOLEAN DEFAULT false, -- true ise gizli, false ise herkese açık
    created_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    member_count INTEGER DEFAULT 1,
    last_message TEXT,
    last_message_time TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    
    -- İndeksler
    CONSTRAINT groups_name_check CHECK (char_length(name) >= 3 AND char_length(name) <= 100)
);

-- İndeksler
CREATE INDEX IF NOT EXISTS idx_groups_created_by ON public.groups(created_by);
CREATE INDEX IF NOT EXISTS idx_groups_is_private ON public.groups(is_private);
CREATE INDEX IF NOT EXISTS idx_groups_created_at ON public.groups(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_groups_name_search ON public.groups USING gin(to_tsvector('turkish', name));

-- 2. GROUP_MEMBERS (Grup Üyeleri) Tablosu
CREATE TABLE IF NOT EXISTS public.group_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    group_id UUID NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    role TEXT DEFAULT 'member', -- 'admin', 'moderator', 'member'
    joined_at TIMESTAMPTZ DEFAULT now(),
    unread_count INTEGER DEFAULT 0, -- Her üyenin kendi okunmamış mesaj sayısı
    
    -- Bir kullanıcı bir gruba sadece bir kez üye olabilir
    UNIQUE(group_id, user_id)
);

-- İndeksler
CREATE INDEX IF NOT EXISTS idx_group_members_group_id ON public.group_members(group_id);
CREATE INDEX IF NOT EXISTS idx_group_members_user_id ON public.group_members(user_id);
CREATE INDEX IF NOT EXISTS idx_group_members_role ON public.group_members(role);

-- 3. GROUP_JOIN_REQUESTS (Grup Katılma İstekleri) Tablosu - Sadece gizli gruplar için
CREATE TABLE IF NOT EXISTS public.group_join_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    group_id UUID NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    status TEXT DEFAULT 'pending', -- 'pending', 'approved', 'rejected'
    message TEXT, -- Kullanıcının katılma isteği mesajı
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    
    -- Bir kullanıcı bir gruba aynı anda sadece bir istek gönderebilir
    UNIQUE(group_id, user_id)
);

-- İndeksler
CREATE INDEX IF NOT EXISTS idx_group_join_requests_group_id ON public.group_join_requests(group_id);
CREATE INDEX IF NOT EXISTS idx_group_join_requests_user_id ON public.group_join_requests(user_id);
CREATE INDEX IF NOT EXISTS idx_group_join_requests_status ON public.group_join_requests(status);

-- 4. GROUP_MESSAGES (Grup Mesajları) Tablosu
CREATE TABLE IF NOT EXISTS public.group_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    group_id UUID NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
    sender_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    
    CONSTRAINT group_messages_content_check CHECK (char_length(content) > 0 AND char_length(content) <= 5000)
);

-- İndeksler
CREATE INDEX IF NOT EXISTS idx_group_messages_group_id ON public.group_messages(group_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_group_messages_sender_id ON public.group_messages(sender_id);

-- 5. GROUP_MESSAGE_READS (Grup Mesajlarının Okunma Durumu) Tablosu
-- Her üye için her mesajın okunma durumunu takip eder
CREATE TABLE IF NOT EXISTS public.group_message_reads (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    message_id UUID NOT NULL REFERENCES public.group_messages(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    read_at TIMESTAMPTZ DEFAULT now(),
    
    UNIQUE(message_id, user_id)
);

-- İndeksler
CREATE INDEX IF NOT EXISTS idx_group_message_reads_message_id ON public.group_message_reads(message_id);
CREATE INDEX IF NOT EXISTS idx_group_message_reads_user_id ON public.group_message_reads(user_id);

-- ============================================
-- RLS POLİTİKALARI
-- ============================================

-- Groups tablosu RLS
ALTER TABLE public.groups ENABLE ROW LEVEL SECURITY;

-- Herkes açık grupları görebilir
CREATE POLICY "Anyone can view public groups"
    ON public.groups FOR SELECT
    USING (is_private = false OR id IN (
        SELECT group_id FROM public.group_members WHERE user_id = auth.uid()
    ));

-- Sadece giriş yapmış kullanıcılar grup oluşturabilir
CREATE POLICY "Authenticated users can create groups"
    ON public.groups FOR INSERT
    WITH CHECK (auth.uid() = created_by);

-- Sadece grup admini grubu güncelleyebilir
CREATE POLICY "Group admins can update groups"
    ON public.groups FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM public.group_members
            WHERE group_id = id
            AND user_id = auth.uid()
            AND role = 'admin'
        )
    );

-- Sadece grup admini grubu silebilir
CREATE POLICY "Group admins can delete groups"
    ON public.groups FOR DELETE
    USING (
        EXISTS (
            SELECT 1 FROM public.group_members
            WHERE group_id = id
            AND user_id = auth.uid()
            AND role = 'admin'
        )
    );

-- Group Members tablosu RLS
ALTER TABLE public.group_members ENABLE ROW LEVEL SECURITY;

-- Üyeler kendi grup üyeliklerini görebilir
CREATE POLICY "Users can view group members"
    ON public.group_members FOR SELECT
    USING (
        user_id = auth.uid() OR
        group_id IN (SELECT group_id FROM public.group_members WHERE user_id = auth.uid())
    );

-- Sistem üyelik ekleyebilir (trigger ile)
CREATE POLICY "System can insert group members"
    ON public.group_members FOR INSERT
    WITH CHECK (true);

-- Adminler ve kendi üyeliklerini silebilir
CREATE POLICY "Admins and self can delete members"
    ON public.group_members FOR DELETE
    USING (
        user_id = auth.uid() OR
        EXISTS (
            SELECT 1 FROM public.group_members gm
            WHERE gm.group_id = group_members.group_id
            AND gm.user_id = auth.uid()
            AND gm.role = 'admin'
        )
    );

-- Adminler üyeleri güncelleyebilir
CREATE POLICY "Admins can update members"
    ON public.group_members FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM public.group_members gm
            WHERE gm.group_id = group_members.group_id
            AND gm.user_id = auth.uid()
            AND gm.role = 'admin'
        )
    );

-- Group Join Requests tablosu RLS
ALTER TABLE public.group_join_requests ENABLE ROW LEVEL SECURITY;

-- Kullanıcılar kendi isteklerini görebilir, adminler tüm istekleri görebilir
CREATE POLICY "Users can view their requests and admins can view all"
    ON public.group_join_requests FOR SELECT
    USING (
        user_id = auth.uid() OR
        EXISTS (
            SELECT 1 FROM public.group_members
            WHERE group_id = group_join_requests.group_id
            AND user_id = auth.uid()
            AND role IN ('admin', 'moderator')
        )
    );

-- Kullanıcılar istek gönderebilir
CREATE POLICY "Users can create join requests"
    ON public.group_join_requests FOR INSERT
    WITH CHECK (user_id = auth.uid());

-- Adminler istekleri güncelleyebilir
CREATE POLICY "Admins can update join requests"
    ON public.group_join_requests FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM public.group_members
            WHERE group_id = group_join_requests.group_id
            AND user_id = auth.uid()
            AND role IN ('admin', 'moderator')
        )
    );

-- Kullanıcılar kendi isteklerini silebilir
CREATE POLICY "Users can delete their own requests"
    ON public.group_join_requests FOR DELETE
    USING (user_id = auth.uid());

-- Group Messages tablosu RLS
ALTER TABLE public.group_messages ENABLE ROW LEVEL SECURITY;

-- Grup üyeleri mesajları görebilir
CREATE POLICY "Group members can view messages"
    ON public.group_messages FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.group_members
            WHERE group_id = group_messages.group_id
            AND user_id = auth.uid()
        )
    );

-- Grup üyeleri mesaj gönderebilir
CREATE POLICY "Group members can send messages"
    ON public.group_messages FOR INSERT
    WITH CHECK (
        sender_id = auth.uid() AND
        EXISTS (
            SELECT 1 FROM public.group_members
            WHERE group_id = group_messages.group_id
            AND user_id = auth.uid()
        )
    );

-- Kendi mesajını silebilir veya admin silebilir
CREATE POLICY "Users can delete own messages or admins can delete"
    ON public.group_messages FOR DELETE
    USING (
        sender_id = auth.uid() OR
        EXISTS (
            SELECT 1 FROM public.group_members
            WHERE group_id = group_messages.group_id
            AND user_id = auth.uid()
            AND role = 'admin'
        )
    );

-- Group Message Reads tablosu RLS
ALTER TABLE public.group_message_reads ENABLE ROW LEVEL SECURITY;

-- Herkes kendi okuma kayıtlarını görebilir
CREATE POLICY "Users can view their own reads"
    ON public.group_message_reads FOR SELECT
    USING (user_id = auth.uid());

-- Herkes kendi okuma kaydını ekleyebilir
CREATE POLICY "Users can insert their own reads"
    ON public.group_message_reads FOR INSERT
    WITH CHECK (user_id = auth.uid());

-- ============================================
-- TRİGGERLAR VE FONKSİYONLAR
-- ============================================

-- 1. Grup oluşturulduğunda kurucuyu admin olarak ekle
CREATE OR REPLACE FUNCTION public.add_group_creator_as_admin()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.group_members (group_id, user_id, role)
    VALUES (NEW.id, NEW.created_by, 'admin');
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_group_created ON public.groups;
CREATE TRIGGER on_group_created
    AFTER INSERT ON public.groups
    FOR EACH ROW
    EXECUTE FUNCTION public.add_group_creator_as_admin();

-- 2. Üye eklendiğinde/çıkarıldığında member_count güncelle
CREATE OR REPLACE FUNCTION public.update_group_member_count()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE public.groups
        SET member_count = member_count + 1
        WHERE id = NEW.group_id;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE public.groups
        SET member_count = member_count - 1
        WHERE id = OLD.group_id;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_group_member_change ON public.group_members;
CREATE TRIGGER on_group_member_change
    AFTER INSERT OR DELETE ON public.group_members
    FOR EACH ROW
    EXECUTE FUNCTION public.update_group_member_count();

-- 3. Grup mesajı gönderildiğinde grupun last_message ve last_message_time güncelle
CREATE OR REPLACE FUNCTION public.update_group_last_message()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE public.groups
    SET 
        last_message = NEW.content,
        last_message_time = NEW.created_at,
        updated_at = NEW.created_at
    WHERE id = NEW.group_id;
    
    -- Gönderen hariç tüm üyelerin unread_count'unu artır
    UPDATE public.group_members
    SET unread_count = unread_count + 1
    WHERE group_id = NEW.group_id
    AND user_id != NEW.sender_id;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_group_message_sent ON public.group_messages;
CREATE TRIGGER on_group_message_sent
    AFTER INSERT ON public.group_messages
    FOR EACH ROW
    EXECUTE FUNCTION public.update_group_last_message();

-- 4. Katılma isteği onaylandığında üye ekle
CREATE OR REPLACE FUNCTION public.approve_group_join_request(
    request_id UUID
)
RETURNS BOOLEAN AS $$
DECLARE
    v_group_id UUID;
    v_user_id UUID;
    v_status TEXT;
BEGIN
    -- İstek bilgilerini al
    SELECT group_id, user_id, status
    INTO v_group_id, v_user_id, v_status
    FROM public.group_join_requests
    WHERE id = request_id;
    
    -- İstek bulunamadıysa veya zaten işlenmişse
    IF v_group_id IS NULL OR v_status != 'pending' THEN
        RETURN false;
    END IF;
    
    -- Üye ekle
    INSERT INTO public.group_members (group_id, user_id, role)
    VALUES (v_group_id, v_user_id, 'member')
    ON CONFLICT (group_id, user_id) DO NOTHING;
    
    -- İstek durumunu güncelle
    UPDATE public.group_join_requests
    SET status = 'approved', updated_at = now()
    WHERE id = request_id;
    
    RETURN true;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 5. Katılma isteğini reddet
CREATE OR REPLACE FUNCTION public.reject_group_join_request(
    request_id UUID
)
RETURNS BOOLEAN AS $$
BEGIN
    UPDATE public.group_join_requests
    SET status = 'rejected', updated_at = now()
    WHERE id = request_id AND status = 'pending';
    
    RETURN FOUND;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 6. Kullanıcının grup mesajlarını okundu olarak işaretle
CREATE OR REPLACE FUNCTION public.mark_group_messages_as_read(
    p_group_id UUID
)
RETURNS VOID AS $$
DECLARE
    v_user_id UUID := auth.uid();
BEGIN
    -- Kullanıcının okunmamış mesajlarını bul ve okuma kaydı ekle
    INSERT INTO public.group_message_reads (message_id, user_id)
    SELECT gm.id, v_user_id
    FROM public.group_messages gm
    WHERE gm.group_id = p_group_id
    AND gm.sender_id != v_user_id
    AND NOT EXISTS (
        SELECT 1 FROM public.group_message_reads gmr
        WHERE gmr.message_id = gm.id
        AND gmr.user_id = v_user_id
    )
    ON CONFLICT (message_id, user_id) DO NOTHING;
    
    -- Kullanıcının unread_count'unu sıfırla
    UPDATE public.group_members
    SET unread_count = 0
    WHERE group_id = p_group_id
    AND user_id = v_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 7. Grup arama fonksiyonu
CREATE OR REPLACE FUNCTION public.search_groups(
    search_term TEXT,
    include_private BOOLEAN DEFAULT false
)
RETURNS TABLE (
    id UUID,
    name TEXT,
    description TEXT,
    avatar_url TEXT,
    is_private BOOLEAN,
    member_count INTEGER,
    created_at TIMESTAMPTZ,
    is_member BOOLEAN
) AS $$
DECLARE
    v_user_id UUID := auth.uid();
BEGIN
    RETURN QUERY
    SELECT 
        g.id,
        g.name,
        g.description,
        g.avatar_url,
        g.is_private,
        g.member_count,
        g.created_at,
        EXISTS(
            SELECT 1 FROM public.group_members gm
            WHERE gm.group_id = g.id
            AND gm.user_id = v_user_id
        ) as is_member
    FROM public.groups g
    WHERE 
        (g.is_private = false OR (include_private AND EXISTS(
            SELECT 1 FROM public.group_members gm
            WHERE gm.group_id = g.id
            AND gm.user_id = v_user_id
        )))
        AND (
            g.name ILIKE '%' || search_term || '%'
            OR g.description ILIKE '%' || search_term || '%'
        )
    ORDER BY 
        -- Üyesi olduğu gruplar önce
        EXISTS(
            SELECT 1 FROM public.group_members gm
            WHERE gm.group_id = g.id
            AND gm.user_id = v_user_id
        ) DESC,
        -- Sonra üye sayısına göre
        g.member_count DESC,
        -- Sonra oluşturulma tarihine göre
        g.created_at DESC
    LIMIT 50;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 8. Kullanıcının gruplarını getir
CREATE OR REPLACE FUNCTION public.get_user_groups()
RETURNS TABLE (
    id UUID,
    name TEXT,
    description TEXT,
    avatar_url TEXT,
    cover_url TEXT,
    is_private BOOLEAN,
    member_count INTEGER,
    last_message TEXT,
    last_message_time TIMESTAMPTZ,
    unread_count INTEGER,
    user_role TEXT,
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ
) AS $$
DECLARE
    v_user_id UUID := auth.uid();
BEGIN
    RETURN QUERY
    SELECT 
        g.id,
        g.name,
        g.description,
        g.avatar_url,
        g.cover_url,
        g.is_private,
        g.member_count,
        g.last_message,
        g.last_message_time,
        gm.unread_count,
        gm.role as user_role,
        g.created_at,
        g.updated_at
    FROM public.groups g
    INNER JOIN public.group_members gm ON g.id = gm.group_id
    WHERE gm.user_id = v_user_id
    ORDER BY g.updated_at DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================
-- REALTIME AYARLARI
-- ============================================

-- Realtime için tabloları yayınla
ALTER PUBLICATION supabase_realtime ADD TABLE public.groups;
ALTER PUBLICATION supabase_realtime ADD TABLE public.group_members;
ALTER PUBLICATION supabase_realtime ADD TABLE public.group_messages;
ALTER PUBLICATION supabase_realtime ADD TABLE public.group_join_requests;

-- ============================================
-- BAŞLANGIÇ VERİLERİ (OPSIYONEL)
-- ============================================

-- Test için örnek açık grup (isteğe bağlı)
-- INSERT INTO public.groups (name, description, is_private, created_by)
-- VALUES ('Genel Sohbet', 'Herkesin katılabileceği genel sohbet grubu', false, auth.uid());

COMMENT ON TABLE public.groups IS 'Grup sohbet grupları';
COMMENT ON TABLE public.group_members IS 'Grup üyelikleri ve rolleri';
COMMENT ON TABLE public.group_join_requests IS 'Gizli gruplara katılma istekleri';
COMMENT ON TABLE public.group_messages IS 'Grup mesajları';
COMMENT ON TABLE public.group_message_reads IS 'Grup mesajlarının okunma durumu';

-- ============================================
-- SUPABASE LINTER UYARILARINI DÜZELTME
-- ============================================
-- 1. Function Search Path: search_path = '' ekle
-- 2. RLS Policy Always True: group_members INSERT politikasını düzelt
-- 3. Auth RLS InitPlan: auth.uid() -> (select auth.uid()) değiştir
-- ============================================

-- ============================================
-- 1. FUNCTION SEARCH PATH DÜZELTMELERİ
-- ============================================

-- add_group_creator_as_admin
CREATE OR REPLACE FUNCTION public.add_group_creator_as_admin()
RETURNS TRIGGER 
LANGUAGE plpgsql 
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    INSERT INTO public.group_members (group_id, user_id, role)
    VALUES (NEW.id, NEW.created_by, 'admin');
    RETURN NEW;
END;
$$;

-- update_group_member_count
CREATE OR REPLACE FUNCTION public.update_group_member_count()
RETURNS TRIGGER 
LANGUAGE plpgsql 
SECURITY DEFINER
SET search_path = ''
AS $$
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
$$;

-- update_group_last_message
CREATE OR REPLACE FUNCTION public.update_group_last_message()
RETURNS TRIGGER 
LANGUAGE plpgsql 
SECURITY DEFINER
SET search_path = ''
AS $$
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
$$;

-- approve_group_join_request
CREATE OR REPLACE FUNCTION public.approve_group_join_request(
    request_id UUID
)
RETURNS BOOLEAN 
LANGUAGE plpgsql 
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_group_id UUID;
    v_user_id UUID;
    v_status TEXT;
BEGIN
    SELECT group_id, user_id, status
    INTO v_group_id, v_user_id, v_status
    FROM public.group_join_requests
    WHERE id = request_id;
    
    IF v_group_id IS NULL OR v_status != 'pending' THEN
        RETURN false;
    END IF;
    
    INSERT INTO public.group_members (group_id, user_id, role)
    VALUES (v_group_id, v_user_id, 'member')
    ON CONFLICT (group_id, user_id) DO NOTHING;
    
    UPDATE public.group_join_requests
    SET status = 'approved', updated_at = now()
    WHERE id = request_id;
    
    RETURN true;
END;
$$;

-- reject_group_join_request
CREATE OR REPLACE FUNCTION public.reject_group_join_request(
    request_id UUID
)
RETURNS BOOLEAN 
LANGUAGE plpgsql 
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    UPDATE public.group_join_requests
    SET status = 'rejected', updated_at = now()
    WHERE id = request_id AND status = 'pending';
    
    RETURN FOUND;
END;
$$;

-- mark_group_messages_as_read
CREATE OR REPLACE FUNCTION public.mark_group_messages_as_read(
    p_group_id UUID
)
RETURNS VOID 
LANGUAGE plpgsql 
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_user_id UUID := auth.uid();
BEGIN
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
    
    UPDATE public.group_members
    SET unread_count = 0
    WHERE group_id = p_group_id
    AND user_id = v_user_id;
END;
$$;

-- search_groups
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
) 
LANGUAGE plpgsql 
SECURITY DEFINER
SET search_path = ''
AS $$
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
        EXISTS(
            SELECT 1 FROM public.group_members gm
            WHERE gm.group_id = g.id
            AND gm.user_id = v_user_id
        ) DESC,
        g.member_count DESC,
        g.created_at DESC
    LIMIT 50;
END;
$$;

-- get_user_groups
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
) 
LANGUAGE plpgsql 
SECURITY DEFINER
SET search_path = ''
AS $$
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
$$;

-- ============================================
-- 2. RLS POLİTİKALARINI DÜZELTME (auth.uid() -> (select auth.uid()))
-- ============================================

-- groups tablosu - eski politikaları sil ve yeniden oluştur
DROP POLICY IF EXISTS "Anyone can view public groups" ON public.groups;
DROP POLICY IF EXISTS "Authenticated users can create groups" ON public.groups;
DROP POLICY IF EXISTS "Group admins can update groups" ON public.groups;
DROP POLICY IF EXISTS "Group admins can delete groups" ON public.groups;

CREATE POLICY "Anyone can view public groups"
    ON public.groups FOR SELECT
    USING (is_private = false OR id IN (
        SELECT group_id FROM public.group_members WHERE user_id = (select auth.uid())
    ));

CREATE POLICY "Authenticated users can create groups"
    ON public.groups FOR INSERT
    WITH CHECK ((select auth.uid()) = created_by);

CREATE POLICY "Group admins can update groups"
    ON public.groups FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM public.group_members
            WHERE group_id = id
            AND user_id = (select auth.uid())
            AND role = 'admin'
        )
    );

CREATE POLICY "Group admins can delete groups"
    ON public.groups FOR DELETE
    USING (
        EXISTS (
            SELECT 1 FROM public.group_members
            WHERE group_id = id
            AND user_id = (select auth.uid())
            AND role = 'admin'
        )
    );

-- group_members tablosu - eski politikaları sil ve yeniden oluştur
DROP POLICY IF EXISTS "Users can view group members" ON public.group_members;
DROP POLICY IF EXISTS "System can insert group members" ON public.group_members;
DROP POLICY IF EXISTS "Admins and self can delete members" ON public.group_members;
DROP POLICY IF EXISTS "Admins can update members" ON public.group_members;

CREATE POLICY "Users can view group members"
    ON public.group_members FOR SELECT
    USING (
        user_id = (select auth.uid()) OR
        group_id IN (SELECT group_id FROM public.group_members WHERE user_id = (select auth.uid()))
    );

-- INSERT politikası: trigger ve kullanıcı kendisi ekleyebilir
CREATE POLICY "Users can insert group members"
    ON public.group_members FOR INSERT
    WITH CHECK (
        -- Kullanıcı kendi üyeliğini ekleyebilir (gruba katılma)
        user_id = (select auth.uid())
        -- VEYA trigger üzerinden oluşturulan kayıtlar (admin eklediğinde)
        OR EXISTS (
            SELECT 1 FROM public.group_members gm
            WHERE gm.group_id = group_members.group_id
            AND gm.user_id = (select auth.uid())
            AND gm.role IN ('admin', 'moderator')
        )
    );

CREATE POLICY "Admins and self can delete members"
    ON public.group_members FOR DELETE
    USING (
        user_id = (select auth.uid()) OR
        EXISTS (
            SELECT 1 FROM public.group_members gm
            WHERE gm.group_id = group_members.group_id
            AND gm.user_id = (select auth.uid())
            AND gm.role = 'admin'
        )
    );

CREATE POLICY "Admins can update members"
    ON public.group_members FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM public.group_members gm
            WHERE gm.group_id = group_members.group_id
            AND gm.user_id = (select auth.uid())
            AND gm.role = 'admin'
        )
    );

-- group_join_requests tablosu
DROP POLICY IF EXISTS "Users can view their requests and admins can view all" ON public.group_join_requests;
DROP POLICY IF EXISTS "Users can create join requests" ON public.group_join_requests;
DROP POLICY IF EXISTS "Admins can update join requests" ON public.group_join_requests;
DROP POLICY IF EXISTS "Users can delete their own requests" ON public.group_join_requests;

CREATE POLICY "Users can view their requests and admins can view all"
    ON public.group_join_requests FOR SELECT
    USING (
        user_id = (select auth.uid()) OR
        EXISTS (
            SELECT 1 FROM public.group_members
            WHERE group_id = group_join_requests.group_id
            AND user_id = (select auth.uid())
            AND role IN ('admin', 'moderator')
        )
    );

CREATE POLICY "Users can create join requests"
    ON public.group_join_requests FOR INSERT
    WITH CHECK (user_id = (select auth.uid()));

CREATE POLICY "Admins can update join requests"
    ON public.group_join_requests FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM public.group_members
            WHERE group_id = group_join_requests.group_id
            AND user_id = (select auth.uid())
            AND role IN ('admin', 'moderator')
        )
    );

CREATE POLICY "Users can delete their own requests"
    ON public.group_join_requests FOR DELETE
    USING (user_id = (select auth.uid()));

-- group_messages tablosu
DROP POLICY IF EXISTS "Group members can view messages" ON public.group_messages;
DROP POLICY IF EXISTS "Group members can send messages" ON public.group_messages;
DROP POLICY IF EXISTS "Users can delete own messages or admins can delete" ON public.group_messages;

CREATE POLICY "Group members can view messages"
    ON public.group_messages FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.group_members
            WHERE group_id = group_messages.group_id
            AND user_id = (select auth.uid())
        )
    );

CREATE POLICY "Group members can send messages"
    ON public.group_messages FOR INSERT
    WITH CHECK (
        sender_id = (select auth.uid()) AND
        EXISTS (
            SELECT 1 FROM public.group_members
            WHERE group_id = group_messages.group_id
            AND user_id = (select auth.uid())
        )
    );

CREATE POLICY "Users can delete own messages or admins can delete"
    ON public.group_messages FOR DELETE
    USING (
        sender_id = (select auth.uid()) OR
        EXISTS (
            SELECT 1 FROM public.group_members
            WHERE group_id = group_messages.group_id
            AND user_id = (select auth.uid())
            AND role = 'admin'
        )
    );

-- group_message_reads tablosu
DROP POLICY IF EXISTS "Users can view their own reads" ON public.group_message_reads;
DROP POLICY IF EXISTS "Users can insert their own reads" ON public.group_message_reads;

CREATE POLICY "Users can view their own reads"
    ON public.group_message_reads FOR SELECT
    USING (user_id = (select auth.uid()));

CREATE POLICY "Users can insert their own reads"
    ON public.group_message_reads FOR INSERT
    WITH CHECK (user_id = (select auth.uid()));

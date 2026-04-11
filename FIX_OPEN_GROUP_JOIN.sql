-- =====================================================
-- AÇIK GRUBA KATILIM + BİLDİRİM + RLS LİNT UYARISLARI DÜZELT
-- =====================================================

-- =====================================================
-- 1. join_open_group RPC fonksiyonu
-- =====================================================
CREATE OR REPLACE FUNCTION public.join_open_group(
    p_group_id UUID
)
RETURNS BOOLEAN 
LANGUAGE plpgsql 
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_is_private BOOLEAN;
    v_already_member BOOLEAN;
BEGIN
    IF v_user_id IS NULL THEN
        RETURN false;
    END IF;

    SELECT COALESCE(is_private, false) INTO v_is_private
    FROM public.groups WHERE id = p_group_id;

    IF v_is_private IS NULL THEN
        RETURN false;
    END IF;

    IF v_is_private = true THEN
        RETURN false;
    END IF;

    SELECT EXISTS (
        SELECT 1 FROM public.group_members
        WHERE group_id = p_group_id AND user_id = v_user_id
    ) INTO v_already_member;

    IF v_already_member THEN
        RETURN true;
    END IF;

    INSERT INTO public.group_members (group_id, user_id, role)
    VALUES (p_group_id, v_user_id, 'member')
    ON CONFLICT (group_id, user_id) DO NOTHING;

    UPDATE public.groups
    SET member_count = (
        SELECT count(*) FROM public.group_members WHERE group_id = p_group_id
    )
    WHERE id = p_group_id;

    RETURN true;
END;
$$;

-- =====================================================
-- 2. group_members INSERT - Tek birleştirilmiş RLS politikası
-- =====================================================
DROP POLICY IF EXISTS "Users can join open groups" ON public.group_members;
DROP POLICY IF EXISTS "Group creators can add themselves" ON public.group_members;
DROP POLICY IF EXISTS "Group admins can add members" ON public.group_members;
DROP POLICY IF EXISTS "Users can insert group members" ON public.group_members;
DROP POLICY IF EXISTS "Unified group members insert" ON public.group_members;

CREATE POLICY "Unified group members insert" ON public.group_members
    FOR INSERT WITH CHECK (
        (select auth.uid()) = user_id
        AND (
            EXISTS (
                SELECT 1 FROM public.groups g
                WHERE g.id = group_members.group_id
                AND COALESCE(g.is_private, false) = false
            )
            OR EXISTS (
                SELECT 1 FROM public.groups g
                WHERE g.id = group_members.group_id
                AND g.created_by = (select auth.uid())
            )
            OR EXISTS (
                SELECT 1 FROM public.group_members gm
                WHERE gm.group_id = group_members.group_id
                AND gm.user_id = (select auth.uid())
                AND gm.role IN ('admin', 'owner', 'moderator')
            )
        )
    );

-- =====================================================
-- 3. notifications INSERT - Authenticated kullanıcılar başkalarına bildirim gönderebilir
-- =====================================================
DROP POLICY IF EXISTS "Authenticated users can create notifications" ON public.notifications;
DROP POLICY IF EXISTS "Anyone can create notifications" ON public.notifications;
DROP POLICY IF EXISTS "Users can create notifications" ON public.notifications;
DROP POLICY IF EXISTS "Users can insert notifications" ON public.notifications;

CREATE POLICY "Authenticated users can create notifications" ON public.notifications
    FOR INSERT WITH CHECK (
        (select auth.uid()) IS NOT NULL
    );

-- =====================================================
-- 4. Schema cache yenile
-- =====================================================
NOTIFY pgrst, 'reload schema';

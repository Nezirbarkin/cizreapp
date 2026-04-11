-- =============================================
-- ADMIN GRUP YÖNETİMİ İÇİN RPC FONKSİYONLARI
-- RLS politikalarını bypass eden SECURITY DEFINER fonksiyonlar
-- search_path sabitlenmiş
-- NOT: profiles.role = 'admin' ile admin kontrolü yapılır
-- =============================================

-- 1. Admin grup silme
CREATE OR REPLACE FUNCTION admin_delete_group(p_group_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_is_admin BOOLEAN;
BEGIN
    SELECT (role = 'admin') INTO v_is_admin FROM profiles WHERE id = auth.uid();
    IF NOT COALESCE(v_is_admin, false) THEN
        RAISE EXCEPTION 'Yetkisiz: Admin değilsiniz';
    END IF;

    DELETE FROM group_join_requests WHERE group_id = p_group_id;
    DELETE FROM group_messages WHERE group_id = p_group_id;
    DELETE FROM group_members WHERE group_id = p_group_id;
    DELETE FROM groups WHERE id = p_group_id;

    RETURN true;
END;
$$;

-- 2. Admin grup güncelleme
CREATE OR REPLACE FUNCTION admin_update_group(
    p_group_id UUID,
    p_name TEXT DEFAULT NULL,
    p_description TEXT DEFAULT NULL,
    p_is_private BOOLEAN DEFAULT NULL,
    p_is_discoverable BOOLEAN DEFAULT NULL,
    p_avatar_url TEXT DEFAULT NULL,
    p_member_count INTEGER DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_is_admin BOOLEAN;
BEGIN
    SELECT (role = 'admin') INTO v_is_admin FROM profiles WHERE id = auth.uid();
    IF NOT COALESCE(v_is_admin, false) THEN
        RAISE EXCEPTION 'Yetkisiz: Admin değilsiniz';
    END IF;

    UPDATE groups SET
        name = COALESCE(p_name, name),
        description = COALESCE(p_description, description),
        is_private = COALESCE(p_is_private, is_private),
        is_discoverable = COALESCE(p_is_discoverable, is_discoverable),
        avatar_url = COALESCE(p_avatar_url, avatar_url),
        member_count = COALESCE(p_member_count, member_count),
        updated_at = NOW()
    WHERE id = p_group_id;

    RETURN true;
END;
$$;

-- 3. Admin grup oluşturma
CREATE OR REPLACE FUNCTION admin_create_group(
    p_name TEXT,
    p_description TEXT DEFAULT NULL,
    p_is_private BOOLEAN DEFAULT false,
    p_is_discoverable BOOLEAN DEFAULT true,
    p_avatar_url TEXT DEFAULT NULL,
    p_created_by UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_is_admin BOOLEAN;
    v_group_id UUID;
BEGIN
    SELECT (role = 'admin') INTO v_is_admin FROM profiles WHERE id = auth.uid();
    IF NOT COALESCE(v_is_admin, false) THEN
        RAISE EXCEPTION 'Yetkisiz: Admin değilsiniz';
    END IF;

    INSERT INTO groups (name, description, is_private, is_discoverable, avatar_url, created_by, member_count)
    VALUES (p_name, p_description, p_is_private, p_is_discoverable, p_avatar_url, COALESCE(p_created_by, auth.uid()), 0)
    RETURNING id INTO v_group_id;

    RETURN v_group_id;
END;
$$;

-- 4. Admin üye çıkarma
CREATE OR REPLACE FUNCTION admin_remove_group_member(
    p_group_id UUID,
    p_user_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_is_admin BOOLEAN;
    v_count INTEGER;
BEGIN
    SELECT (role = 'admin') INTO v_is_admin FROM profiles WHERE id = auth.uid();
    IF NOT COALESCE(v_is_admin, false) THEN
        RAISE EXCEPTION 'Yetkisiz: Admin değilsiniz';
    END IF;

    DELETE FROM group_members WHERE group_id = p_group_id AND user_id = p_user_id;

    SELECT COUNT(*) INTO v_count FROM group_members WHERE group_id = p_group_id;
    UPDATE groups SET member_count = v_count, updated_at = NOW() WHERE id = p_group_id;

    RETURN true;
END;
$$;

-- 5. Admin üye rolü değiştirme
CREATE OR REPLACE FUNCTION admin_change_member_role(
    p_group_id UUID,
    p_user_id UUID,
    p_new_role TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_is_admin BOOLEAN;
BEGIN
    SELECT (role = 'admin') INTO v_is_admin FROM profiles WHERE id = auth.uid();
    IF NOT COALESCE(v_is_admin, false) THEN
        RAISE EXCEPTION 'Yetkisiz: Admin değilsiniz';
    END IF;

    UPDATE group_members SET role = p_new_role WHERE group_id = p_group_id AND user_id = p_user_id;

    RETURN true;
END;
$$;

-- 6. Admin katılma isteğini onaylama
CREATE OR REPLACE FUNCTION admin_approve_join_request(
    p_request_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_is_admin BOOLEAN;
    v_group_id UUID;
    v_user_id UUID;
    v_count INTEGER;
BEGIN
    SELECT (role = 'admin') INTO v_is_admin FROM profiles WHERE id = auth.uid();
    IF NOT COALESCE(v_is_admin, false) THEN
        RAISE EXCEPTION 'Yetkisiz: Admin değilsiniz';
    END IF;

    SELECT group_id, user_id INTO v_group_id, v_user_id
    FROM group_join_requests WHERE id = p_request_id AND status = 'pending';

    IF v_group_id IS NULL THEN RETURN false; END IF;

    INSERT INTO group_members (group_id, user_id, role)
    VALUES (v_group_id, v_user_id, 'member')
    ON CONFLICT (group_id, user_id) DO NOTHING;

    UPDATE group_join_requests SET status = 'approved', reviewed_at = NOW() WHERE id = p_request_id;

    SELECT COUNT(*) INTO v_count FROM group_members WHERE group_id = v_group_id;
    UPDATE groups SET member_count = v_count, updated_at = NOW() WHERE id = v_group_id;

    RETURN true;
END;
$$;

-- 7. Admin katılma isteğini reddetme
CREATE OR REPLACE FUNCTION admin_reject_join_request(
    p_request_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_is_admin BOOLEAN;
BEGIN
    SELECT (role = 'admin') INTO v_is_admin FROM profiles WHERE id = auth.uid();
    IF NOT COALESCE(v_is_admin, false) THEN
        RAISE EXCEPTION 'Yetkisiz: Admin değilsiniz';
    END IF;

    UPDATE group_join_requests SET status = 'rejected', reviewed_at = NOW() WHERE id = p_request_id;

    RETURN true;
END;
$$;

-- 8. Admin tüm grupları getirme
CREATE OR REPLACE FUNCTION admin_get_all_groups()
RETURNS SETOF groups
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_is_admin BOOLEAN;
BEGIN
    SELECT (role = 'admin') INTO v_is_admin FROM profiles WHERE id = auth.uid();
    IF NOT COALESCE(v_is_admin, false) THEN
        RAISE EXCEPTION 'Yetkisiz: Admin değilsiniz';
    END IF;

    RETURN QUERY SELECT * FROM groups ORDER BY created_at DESC;
END;
$$;

-- 9. Admin tüm join request'leri getirme
CREATE OR REPLACE FUNCTION admin_get_all_join_requests()
RETURNS TABLE(
    id UUID,
    group_id UUID,
    user_id UUID,
    message TEXT,
    status TEXT,
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ,
    reviewed_at TIMESTAMPTZ,
    group_name TEXT,
    group_avatar_url TEXT,
    group_is_private BOOLEAN,
    user_full_name TEXT,
    user_avatar_url TEXT,
    user_username TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_is_admin BOOLEAN;
BEGIN
    SELECT (role = 'admin') INTO v_is_admin FROM profiles WHERE id = auth.uid();
    IF NOT COALESCE(v_is_admin, false) THEN
        RAISE EXCEPTION 'Yetkisiz: Admin değilsiniz';
    END IF;

    RETURN QUERY
    SELECT 
        jr.id,
        jr.group_id,
        jr.user_id,
        jr.message,
        jr.status,
        jr.created_at,
        jr.updated_at,
        jr.reviewed_at,
        g.name AS group_name,
        g.avatar_url AS group_avatar_url,
        g.is_private AS group_is_private,
        p.full_name AS user_full_name,
        p.avatar_url AS user_avatar_url,
        p.username AS user_username
    FROM group_join_requests jr
    LEFT JOIN groups g ON g.id = jr.group_id
    LEFT JOIN profiles p ON p.id = jr.user_id
    WHERE jr.status = 'pending'
    ORDER BY jr.created_at DESC;
END;
$$;

-- 10. Admin grup üyelerini getirme
CREATE OR REPLACE FUNCTION admin_get_group_members(p_group_id UUID)
RETURNS TABLE(
    id UUID,
    group_id UUID,
    user_id UUID,
    role TEXT,
    joined_at TIMESTAMPTZ,
    user_full_name TEXT,
    user_avatar_url TEXT,
    user_username TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_is_admin BOOLEAN;
BEGIN
    SELECT (p.role = 'admin') INTO v_is_admin FROM profiles p WHERE p.id = auth.uid();
    IF NOT COALESCE(v_is_admin, false) THEN
        RAISE EXCEPTION 'Yetkisiz: Admin değilsiniz';
    END IF;

    RETURN QUERY
    SELECT 
        gm.id,
        gm.group_id,
        gm.user_id,
        gm.role,
        gm.joined_at,
        p.full_name AS user_full_name,
        p.avatar_url AS user_avatar_url,
        p.username AS user_username
    FROM group_members gm
    LEFT JOIN profiles p ON p.id = gm.user_id
    WHERE gm.group_id = p_group_id
    ORDER BY 
        CASE gm.role 
            WHEN 'admin' THEN 1 
            WHEN 'moderator' THEN 2 
            ELSE 3 
        END,
        gm.joined_at;
END;
$$;

-- Schema cache yenile
NOTIFY pgrst, 'reload schema';

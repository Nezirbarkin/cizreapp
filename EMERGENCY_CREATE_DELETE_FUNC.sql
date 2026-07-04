--acil fonksiyon olustur - delete_conversation_for_user
DROP FUNCTION IF EXISTS public.delete_conversation_for_user(UUID);

CREATE OR REPLACE FUNCTION public.delete_conversation_for_user(p_conversation_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID;
    v_other_user_id UUID;
    v_caller UUID := auth.uid();
BEGIN
    SELECT user_id, other_user_id
    INTO v_user_id, v_other_user_id
    FROM conversations
    WHERE id = p_conversation_id;

    IF v_user_id IS NULL THEN
        RETURN false;
    END IF;

    IF v_caller IS NULL OR
       (v_caller != v_user_id AND v_caller != v_other_user_id) THEN
        RETURN false;
    END IF;

    UPDATE conversations
    SET deleted_for_user_id = v_caller
    WHERE id = p_conversation_id;

    RETURN true;
END;
$$;

GRANT EXECUTE ON FUNCTION public.delete_conversation_for_user(UUID) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.delete_conversation_for_user(UUID) FROM anon;
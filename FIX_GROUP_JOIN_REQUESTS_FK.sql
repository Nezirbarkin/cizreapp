-- group_join_requests tablosuna FK ilişkisi ekle
-- Eğer FK zaten varsa hata vermez (IF NOT EXISTS benzeri kontrol)

DO $$
BEGIN
    -- user_id için FK ekle (eğer yoksa)
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints
        WHERE constraint_name = 'group_join_requests_user_id_fkey'
          AND table_name = 'group_join_requests'
    ) THEN
        ALTER TABLE group_join_requests
        ADD CONSTRAINT group_join_requests_user_id_fkey
        FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE;
        
        RAISE NOTICE 'FK group_join_requests_user_id_fkey eklendi';
    ELSE
        RAISE NOTICE 'FK group_join_requests_user_id_fkey zaten mevcut';
    END IF;
END $$;

-- Schema cache'i yenile (PostgREST için)
NOTIFY pgrst, 'reload schema';

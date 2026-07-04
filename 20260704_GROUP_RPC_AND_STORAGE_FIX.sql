-- =====================================================================
-- GRUP RPC OVERLOAD + GRUP FOTOĞRAFI STORAGE RLS DÜZELTMESİ
-- =====================================================================
-- Hata 1: PGRST203 "Could not choose the best candidate function" —
--   mark_group_messages_read_receipts fonksiyonunun iki farklı imzası
--   (1 parametreli ve 2 parametreli) aynı anda veritabanında duruyor.
--   PostgREST, Dart'tan tek parametre (p_group_id) ile çağrıldığında
--   hangisini çalıştıracağını seçemiyor. Çözüm: 1 parametreli eski
--   sürümü sil, group_id kolonunu da dolduran 2 parametreli (varsayılan
--   NULL) sürümü tek versiyon olarak bırak.
--
-- Hata 2: StorageException 403 "new row violates row-level security
--   policy" — grup fotoğrafı 'public' bucket'ının 'group_images'
--   klasörüne yüklenirken RLS engelliyor. Bucket'ın var olduğunu
--   garanti ediyoruz (önceki script'te DO/EXCEPTION bloğu olası bir
--   hatayı sessizce yutmuş olabilir) ve INSERT/UPDATE/DELETE
--   politikalarını "TO authenticated" ile açıkça yeniden oluşturuyoruz.
-- =====================================================================

-- ── 1. mark_group_messages_read_receipts: tek imzaya indir ──
DROP FUNCTION IF EXISTS public.mark_group_messages_read_receipts(UUID);
DROP FUNCTION IF EXISTS public.mark_group_messages_read_receipts(UUID, UUID);

CREATE OR REPLACE FUNCTION public.mark_group_messages_read_receipts(
    p_group_id UUID,
    p_last_message_id UUID DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID := auth.uid();
BEGIN
    IF v_user_id IS NULL THEN
        RETURN;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.group_members
        WHERE group_id = p_group_id AND user_id = v_user_id
    ) THEN
        RETURN;
    END IF;

    INSERT INTO public.group_message_read_receipts (message_id, group_id, user_id)
    SELECT gm.id, gm.group_id, v_user_id
    FROM public.group_messages gm
    WHERE gm.group_id = p_group_id
      AND gm.sender_id != v_user_id
      AND NOT EXISTS (
          SELECT 1 FROM public.group_message_read_receipts gmr
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

GRANT EXECUTE ON FUNCTION public.mark_group_messages_read_receipts(UUID, UUID) TO authenticated;
REVOKE ALL ON FUNCTION public.mark_group_messages_read_receipts(UUID, UUID) FROM PUBLIC, anon;

-- ── 2. 'public' storage bucket'ının var olduğunu garanti et ──
INSERT INTO storage.buckets (id, name, public)
VALUES ('public', 'public', true)
ON CONFLICT (id) DO UPDATE SET public = true;

-- ── 3. group_images klasörü için politikaları yeniden oluştur ──
DROP POLICY IF EXISTS "Group images are publicly accessible" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated users can upload group images" ON storage.objects;
DROP POLICY IF EXISTS "Group admins can update group images" ON storage.objects;
DROP POLICY IF EXISTS "Group admins can delete group images" ON storage.objects;

CREATE POLICY "Group images are publicly accessible"
    ON storage.objects FOR SELECT
    TO public
    USING (bucket_id = 'public' AND (storage.foldername(name))[1] = 'group_images');

CREATE POLICY "Authenticated users can upload group images"
    ON storage.objects FOR INSERT
    TO authenticated
    WITH CHECK (
        bucket_id = 'public'
        AND (storage.foldername(name))[1] = 'group_images'
    );

CREATE POLICY "Group admins can update group images"
    ON storage.objects FOR UPDATE
    TO authenticated
    USING (
        bucket_id = 'public'
        AND (storage.foldername(name))[1] = 'group_images'
    )
    WITH CHECK (
        bucket_id = 'public'
        AND (storage.foldername(name))[1] = 'group_images'
    );

CREATE POLICY "Group admins can delete group images"
    ON storage.objects FOR DELETE
    TO authenticated
    USING (
        bucket_id = 'public'
        AND (storage.foldername(name))[1] = 'group_images'
    );

-- ── 4. Şema cache yenile ──
NOTIFY pgrst, 'reload schema';

-- ── 5. Doğrulama: bucket ve politikaların gerçekten oluştuğunu kontrol et ──
-- SELECT id, public FROM storage.buckets WHERE id = 'public';
-- SELECT policyname, cmd FROM pg_policies WHERE tablename = 'objects' AND policyname ILIKE '%group images%';
-- SELECT proname, pronargs FROM pg_proc WHERE proname = 'mark_group_messages_read_receipts';

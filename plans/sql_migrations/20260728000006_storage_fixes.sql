-- =====================================================
-- DOSYA: supabase/migrations/20260728000006_storage_fixes.sql
-- AMAÇ: Storage bucket RLS tutarlılık + path helpers + S3 config
-- TARİH: 2026-07-28
-- UYGULAMA: Supabase Dashboard > SQL Editor
-- =====================================================

-- 1. Dosya var mı kontrolü için helper
CREATE OR REPLACE FUNCTION check_storage_object(
  p_bucket TEXT,
  p_path TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, storage
AS $$
DECLARE
  v_exists BOOLEAN;
BEGIN
  -- service_role ile storage.objects sorgula
  SELECT EXISTS (
    SELECT 1 FROM storage.objects
    WHERE bucket_id = p_bucket
      AND name = p_path
  ) INTO v_exists;

  RETURN v_exists;
END;
$$;

REVOKE ALL ON FUNCTION check_storage_object(TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION check_storage_object(TEXT, TEXT) TO authenticated, service_role;

-- 2. S3 ayarları için api_settings kolonları (yoksa ekle)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'api_settings' AND column_name = 's3_enabled'
  ) THEN
    ALTER TABLE api_settings ADD COLUMN s3_enabled BOOLEAN DEFAULT FALSE;
    ALTER TABLE api_settings ADD COLUMN s3_access_key TEXT;
    ALTER TABLE api_settings ADD COLUMN s3_secret_key TEXT;
    ALTER TABLE api_settings ADD COLUMN s3_bucket TEXT;
    ALTER TABLE api_settings ADD COLUMN s3_endpoint TEXT;
    ALTER TABLE api_settings ADD COLUMN s3_region TEXT DEFAULT 'us-east-1';
    ALTER TABLE api_settings ADD COLUMN s3_public_url TEXT;
  END IF;
END $$;

-- 3. api_settings RLS - sadece admin görebilir/düzenleyebilir
DROP POLICY IF EXISTS "Admins manage api settings" ON api_settings;
CREATE POLICY "Admins manage api settings" ON api_settings
  FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid() AND role = 'admin'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- 4. Storage bucket RLS (örnek - 'images' bucket)
-- Mevcut policy'leri koru, yoksa ekle
INSERT INTO storage.buckets (id, name, public)
VALUES ('products', 'products', TRUE)
ON CONFLICT (id) DO NOTHING;

INSERT INTO storage.buckets (id, name, public)
VALUES ('avatars', 'avatars', TRUE)
ON CONFLICT (id) DO NOTHING;

INSERT INTO storage.buckets (id, name, public)
VALUES ('posts', 'posts', TRUE)
ON CONFLICT (id) DO NOTHING;

INSERT INTO storage.buckets (id, name, public)
VALUES ('stories', 'stories', TRUE)
ON CONFLICT (id) DO NOTHING;

INSERT INTO storage.buckets (id, name, public)
VALUES ('chat_attachments', 'chat_attachments', FALSE)
ON CONFLICT (id) DO NOTHING;

-- 5. Test query
-- SELECT check_storage_object('products', 'test/image.jpg');

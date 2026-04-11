-- ============================================================
-- S3 Storage Ayarları Migration
-- idrive e2 veya herhangi bir S3 uyumlu depolama servisi
-- ============================================================

-- Önce api_settings tablosunu oluştur (yoksa)
CREATE TABLE IF NOT EXISTS api_settings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  require_https BOOLEAN DEFAULT true,
  cors_enabled BOOLEAN DEFAULT true,
  requests_per_minute INTEGER DEFAULT 60,
  requests_per_hour INTEGER DEFAULT 10000,
  requests_per_month INTEGER DEFAULT 500000,
  total_requests INTEGER DEFAULT 0,
  successful_requests INTEGER DEFAULT 0,
  failed_requests INTEGER DEFAULT 0,
  allowed_ips TEXT DEFAULT 'Sınırsız',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- S3 kolonlarını ekle (yoksa)
DO $$ 
BEGIN
  -- S3 etkin mi
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'api_settings' AND column_name = 's3_enabled') THEN
    ALTER TABLE api_settings ADD COLUMN s3_enabled BOOLEAN DEFAULT false;
  END IF;

  -- S3 Access Key
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'api_settings' AND column_name = 's3_access_key') THEN
    ALTER TABLE api_settings ADD COLUMN s3_access_key TEXT DEFAULT '';
  END IF;

  -- S3 Secret Key
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'api_settings' AND column_name = 's3_secret_key') THEN
    ALTER TABLE api_settings ADD COLUMN s3_secret_key TEXT DEFAULT '';
  END IF;

  -- S3 Bucket Name
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'api_settings' AND column_name = 's3_bucket') THEN
    ALTER TABLE api_settings ADD COLUMN s3_bucket TEXT DEFAULT '';
  END IF;

  -- S3 Endpoint URL
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'api_settings' AND column_name = 's3_endpoint') THEN
    ALTER TABLE api_settings ADD COLUMN s3_endpoint TEXT DEFAULT '';
  END IF;

  -- S3 Region
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'api_settings' AND column_name = 's3_region') THEN
    ALTER TABLE api_settings ADD COLUMN s3_region TEXT DEFAULT 'us-east-1';
  END IF;

  -- S3 Public URL prefix (CDN veya doğrudan erişim için)
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'api_settings' AND column_name = 's3_public_url') THEN
    ALTER TABLE api_settings ADD COLUMN s3_public_url TEXT DEFAULT '';
  END IF;
END $$;

-- Varsayılan kayıt ekle (yoksa)
INSERT INTO api_settings (id, s3_enabled)
SELECT gen_random_uuid(), false
WHERE NOT EXISTS (SELECT 1 FROM api_settings LIMIT 1);

-- RLS politikaları
ALTER TABLE api_settings ENABLE ROW LEVEL SECURITY;

-- Sadece adminler okuyabilir ve yazabilir
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'admin_read_api_settings' AND tablename = 'api_settings') THEN
    CREATE POLICY admin_read_api_settings ON api_settings
      FOR SELECT
      USING (
        EXISTS (
          SELECT 1 FROM profiles
          WHERE profiles.id = (SELECT auth.uid())
          AND profiles.role = 'admin'
        )
      );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'admin_update_api_settings' AND tablename = 'api_settings') THEN
    CREATE POLICY admin_update_api_settings ON api_settings
      FOR UPDATE
      USING (
        EXISTS (
          SELECT 1 FROM profiles
          WHERE profiles.id = (SELECT auth.uid())
          AND profiles.role = 'admin'
        )
      );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'admin_insert_api_settings' AND tablename = 'api_settings') THEN
    CREATE POLICY admin_insert_api_settings ON api_settings
      FOR INSERT
      WITH CHECK (
        EXISTS (
          SELECT 1 FROM profiles
          WHERE profiles.id = (SELECT auth.uid())
          AND profiles.role = 'admin'
        )
      );
  END IF;
END $$;

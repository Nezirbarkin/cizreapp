-- ============================================================================
-- ADMIN BROADCASTS - Herkese Açık Duyurular Tablosu (GÜVENLİ VERSİYON)
-- Supabase SQL Editor'da çalıştırın
-- ============================================================================

-- 1. admin_broadcasts tablosu oluştur
CREATE TABLE IF NOT EXISTS public.admin_broadcasts (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  title TEXT NOT NULL,
  content TEXT NOT NULL,
  icon_type TEXT NOT NULL DEFAULT 'announcement',
  target_audience TEXT DEFAULT 'all',
  is_active BOOLEAN DEFAULT TRUE,
  created_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  expires_at TIMESTAMPTZ
);

-- 2. Index'ler
CREATE INDEX IF NOT EXISTS admin_broadcasts_active_idx 
ON public.admin_broadcasts(is_active, created_at DESC) 
WHERE is_active = TRUE;

-- 3. RLS aktifleştir
ALTER TABLE public.admin_broadcasts ENABLE ROW LEVEL SECURITY;

-- 4. Herkes okuyabilir (SELECT with USING true - bu güvenli, public read access)
DO $$ BEGIN
  CREATE POLICY "Anyone can read active broadcasts"
  ON public.admin_broadcasts
  FOR SELECT
  USING (is_active = TRUE);
EXCEPTION WHEN duplicate_object THEN
  RAISE NOTICE 'Policy zaten mevcut';
END $$;

-- 5. Sadece admin rolüne sahip kullanıcılar yazabilir
DO $$ BEGIN
  CREATE POLICY "Admins can insert broadcasts"
  ON public.admin_broadcasts
  FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid()
      AND role = 'admin'
    )
  );
EXCEPTION WHEN duplicate_object THEN
  RAISE NOTICE 'Policy zaten mevcut';
END $$;

-- 6. Sadece admin rolüne sahip kullanıcılar güncelleyebilir
DO $$ BEGIN
  CREATE POLICY "Admins can update broadcasts"
  ON public.admin_broadcasts
  FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid()
      AND role = 'admin'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid()
      AND role = 'admin'
    )
  );
EXCEPTION WHEN duplicate_object THEN
  RAISE NOTICE 'Policy zaten mevcut';
END $$;

-- 7. Sadece admin rolüne sahip kullanıcılar silebilir
DO $$ BEGIN
  CREATE POLICY "Admins can delete broadcasts"
  ON public.admin_broadcasts
  FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid()
      AND role = 'admin'
    )
  );
EXCEPTION WHEN duplicate_object THEN
  RAISE NOTICE 'Policy zaten mevcut';
END $$;

-- Yorumlar
COMMENT ON TABLE public.admin_broadcasts IS 'Admin tarafından gönderilen herkese açık duyurular';
COMMENT ON COLUMN public.admin_broadcasts.icon_type IS 'İkon tipi: announcement, discount, campaign, news, event, update, warning, gift, info';

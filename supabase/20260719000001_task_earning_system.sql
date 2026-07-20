-- =============================================================================
-- 20260719000001_task_earning_system.sql
-- Görev Yaparak Kazan (Task Earning) Sistemi
--
-- YENİ TABLOLAR:
--   1. task_categories      — Görev kategorileri (Instagram, YouTube, vb.)
--   2. tasks                — Görev tanımları (admin tarafından oluşturulur)
--   3. task_submissions     — Kullanıcı başvuruları (ekran görüntüsü + durum)
--
-- GÜVENLİK ÖĞRENMELERİ (PROJE_HAVIZA referans):
--   - Bakiye mutasyonu YALNIZ service_role policy + atomik RPC (§4.1.7)
--   - is_admin() GRANT REVOKE ayrıca verilmeli (§4.1.1)
--   - RLS recursion'dan kaçınmak için basit kolon karşılaştırma (§4.1.4)
--   - Race condition için FOR UPDATE lock + partial unique index
--   - Idempotency: submission.status='approved' guard + balance transaction type unique
-- =============================================================================

SET search_path = public, pg_temp;

-- ===========================================================================
-- 1. ENUM: task_status (görev durumu)
-- ===========================================================================
DO $$ BEGIN
  CREATE TYPE task_status AS ENUM (
    'draft',      -- Taslak (henüz yayında değil)
    'active',     -- Aktif (kullanıcılar katılabilir)
    'paused',     -- Duraklatıldı (admin tarafından geçici kapatıldı)
    'completed',  -- Tamamlandı (katılımcı limiti doldu)
    'archived'    -- Arşivlendi (admin tarafından kaldırıldı)
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE task_submission_status AS ENUM (
    'pending',    -- Beklemede (admin onayı bekleniyor)
    'approved',   -- Onaylandı (bakiye eklendi)
    'rejected'    -- Reddedildi
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

-- balance_transaction_type enum'una 'task_reward' değeri ekle
DO $$ BEGIN
  -- Mevcut değerleri kontrol et, yoksa ekle
  IF NOT EXISTS (
    SELECT 1 FROM pg_enum
    WHERE enumlabel = 'task_reward'
      AND enumtypid = (SELECT oid FROM pg_type WHERE typname = 'balance_transaction_type')
  ) THEN
    ALTER TYPE balance_transaction_type ADD VALUE 'task_reward';
  END IF;
EXCEPTION
  WHEN OTHERS THEN NULL;
END $$;

-- ===========================================================================
-- 2. TABLO: task_categories (Görev Kategorileri)
-- ===========================================================================
CREATE TABLE IF NOT EXISTS public.task_categories (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name          TEXT NOT NULL UNIQUE,
  icon          TEXT,                          -- emoji veya icon adı
  sort_order    INTEGER NOT NULL DEFAULT 0,
  is_active     BOOLEAN NOT NULL DEFAULT TRUE,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Başlangıç kategorileri (idempotent)
INSERT INTO public.task_categories (name, icon, sort_order) VALUES
  ('Instagram',  '📷', 1),
  ('YouTube',    '🎥', 2),
  ('TikTok',     '🎵', 3),
  ('Twitter/X',  '🐦', 4),
  ('Facebook',   '📘', 5),
  ('Uygulama',   '📱', 6),
  ('Anket',      '📋', 7),
  ('Diğer',      '🎯', 99)
ON CONFLICT (name) DO NOTHING;

-- ===========================================================================
-- 3. TABLO: tasks (Görevler)
-- ===========================================================================
CREATE TABLE IF NOT EXISTS public.tasks (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  category_id           UUID REFERENCES public.task_categories(id) ON DELETE SET NULL,
  title                 TEXT NOT NULL,
  description           TEXT NOT NULL,
  warning_text          TEXT,                   -- "Sadece Türkiye'den katılım" vb.
  task_link             TEXT,                   -- Takip et, beğen, indir vb. linki
  reward_amount         NUMERIC(12,2) NOT NULL CHECK (reward_amount > 0),
  max_participants      INTEGER NOT NULL CHECK (max_participants > 0),
  current_participants  INTEGER NOT NULL DEFAULT 0,
  starts_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at            TIMESTAMPTZ,           -- NULL = süresiz
  status                task_status NOT NULL DEFAULT 'draft',
  created_by            UUID NOT NULL REFERENCES auth.users(id),
  created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- expires_at kontrolü (NULL veya starts_at'tan sonra olmalı)
  CONSTRAINT tasks_expires_after_starts CHECK (expires_at IS NULL OR expires_at > starts_at)
);

CREATE INDEX IF NOT EXISTS idx_tasks_status         ON public.tasks(status);
CREATE INDEX IF NOT EXISTS idx_tasks_category_id    ON public.tasks(category_id);
CREATE INDEX IF NOT EXISTS idx_tasks_starts_at      ON public.tasks(starts_at DESC);
CREATE INDEX IF NOT EXISTS idx_tasks_active_pending ON public.tasks(status, starts_at DESC) WHERE status = 'active';

-- ===========================================================================
-- 4. TABLO: task_submissions (Görev Başvuruları)
-- ===========================================================================
CREATE TABLE IF NOT EXISTS public.task_submissions (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id             UUID NOT NULL REFERENCES public.tasks(id) ON DELETE CASCADE,
  user_id             UUID NOT NULL REFERENCES auth.users(id),
  screenshot_url      TEXT NOT NULL,           -- Ekran görüntüsü (storage)
  user_note           TEXT,                    -- Kullanıcının eklediği opsiyonel not
  status              task_submission_status NOT NULL DEFAULT 'pending',
  reward_amount      NUMERIC(12,2),            -- Onayda yazılır
  balance_txn_id      UUID REFERENCES public.balance_transactions(id),
  reviewed_by         UUID REFERENCES auth.users(id),
  reviewed_at         TIMESTAMPTZ,
  rejection_reason    TEXT,                    -- Admin reddetme gerekçesi
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_task_submissions_task_id    ON public.task_submissions(task_id);
CREATE INDEX IF NOT EXISTS idx_task_submissions_user_id    ON public.task_submissions(user_id);
CREATE INDEX IF NOT EXISTS idx_task_submissions_status     ON public.task_submissions(status);
CREATE INDEX IF NOT EXISTS idx_task_submissions_pending    ON public.task_submissions(status, created_at DESC) WHERE status = 'pending';

-- Aynı kullanıcı, aynı görev için yalnız 1 'pending' veya 'approved' başvuru olabilir
-- (rejected ise tekrar başvurabilir). Race condition önleme (PROJE_HAVIZA §4.1.7 deseni).
CREATE UNIQUE INDEX IF NOT EXISTS uq_task_submissions_active_per_user
  ON public.task_submissions(task_id, user_id)
  WHERE status IN ('pending', 'approved');

-- ===========================================================================
-- 5. TRIGGER: updated_at otomatik güncelleme
-- ===========================================================================
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_tasks_updated_at ON public.tasks;
CREATE TRIGGER trg_tasks_updated_at
  BEFORE UPDATE ON public.tasks
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_task_submissions_updated_at ON public.task_submissions;
CREATE TRIGGER trg_task_submissions_updated_at
  BEFORE UPDATE ON public.task_submissions
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ===========================================================================
-- 6. STORAGE: task_screenshots bucket
-- ===========================================================================
-- Görev ekran görüntüleri public bucket (admin görmesi için).
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'task_screenshots',
  'task_screenshots',
  true,
  5242880, -- 5 MB
  ARRAY['image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO UPDATE SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

-- Eski politikaları temizle (idempotent)
DO $$ BEGIN
  DROP POLICY IF EXISTS "task_screenshots_select_all"     ON storage.objects;
  DROP POLICY IF EXISTS "task_screenshots_insert_owner"    ON storage.objects;
  DROP POLICY IF EXISTS "task_screenshots_update_owner"    ON storage.objects;
  DROP POLICY IF EXISTS "task_screenshots_delete_owner"    ON storage.objects;
  DROP POLICY IF EXISTS "task_screenshots_admin_all"       ON storage.objects;
EXCEPTION
  WHEN undefined_object THEN NULL;
END $$;

-- SELECT: public (herkes görebilir; URL admin panelde açılıyor)
CREATE POLICY "task_screenshots_select_all"
  ON storage.objects FOR SELECT
  TO public
  USING (bucket_id = 'task_screenshots');

-- INSERT: kullanıcı yalnızca kendi klasörüne yazabilir (user_id ile başlayan path)
CREATE POLICY "task_screenshots_insert_owner"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'task_screenshots'
    AND (storage.foldername(name))[1] = (SELECT auth.uid()::text)
  );

-- UPDATE: dosya sahibi (user_id klasörden okunur)
CREATE POLICY "task_screenshots_update_owner"
  ON storage.objects FOR UPDATE
  TO authenticated
  USING (
    bucket_id = 'task_screenshots'
    AND (storage.foldername(name))[1] = (SELECT auth.uid()::text)
  );

-- DELETE: dosya sahibi veya admin
CREATE POLICY "task_screenshots_delete_owner"
  ON storage.objects FOR DELETE
  TO authenticated
  USING (
    bucket_id = 'task_screenshots'
    AND (
      (storage.foldername(name))[1] = (SELECT auth.uid()::text)
      OR EXISTS(SELECT 1 FROM public.profiles WHERE id = (SELECT auth.uid()) AND role = 'admin')
    )
  );

-- ===========================================================================
-- 7. RELOAD SCHEMA (PGRST yeni kolonları tanıması için zorunlu)
-- ===========================================================================
NOTIFY pgrst, 'reload schema';

-- Başarı log
DO $$ BEGIN
  RAISE NOTICE '✅ 20260719000001_task_earning_system.sql — şema, enum, storage ve trigger oluşturuldu';
END $$;

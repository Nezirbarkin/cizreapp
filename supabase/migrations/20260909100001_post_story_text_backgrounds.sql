-- ============================================================================
-- 20260909100001_post_story_text_backgrounds.sql
-- ----------------------------------------------------------------------------
-- AMAÇ: Gönderi ve hikayelerde "arka planlı metin" desteği.
--
--   * posts.background      → metin gönderisinin arka plan kimliği (ör. 'sunset')
--   * stories.background    → metin hikayesinin arka plan kimliği
--   * stories.text_content  → metin hikayesinin yazısı
--   * stories.image_url artık NULL olabilir (metin hikayesinde görsel yok)
--   * stories.media_type'a 'text' değeri eklendi
--
-- TASARIM NOTU: Arka plan RENGİ değil KİMLİĞİ saklanır. Renk paleti istemcide
-- (lib/core/widgets/text_background.dart) tanımlı; böylece palet güncellenince
-- eski gönderiler de yeni renklerle çizilir ve DB'de renk kopyası tutulmaz.
-- Bilinmeyen bir kimlik gelirse istemci sade (arka plansız) çizime düşer.
--
-- VIEW UYARISI: posts_with_profiles `p.*` ile tanımlı olsa da PostgreSQL yıldızı
-- view OLUŞTURULURKEN genişletir. Yeni kolonun view'da görünmesi için view'ın
-- yeniden yaratılması ZORUNLU (aksi halde Dart tarafı background'ı hep null
-- görür). Tanım 20260812000001 ile birebir aynı bırakıldı.
-- ============================================================================

-- ---------------------------------------------------------------- posts
ALTER TABLE public.posts
  ADD COLUMN IF NOT EXISTS background TEXT;

COMMENT ON COLUMN public.posts.background IS
  'Metin gönderisinin arka plan kimliği (lib/core/widgets/text_background.dart). '
  'NULL = sade metin gönderisi. Görselli gönderilerde kullanılmaz.';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.posts'::regclass AND conname = 'posts_background_slug_check'
  ) THEN
    ALTER TABLE public.posts
      ADD CONSTRAINT posts_background_slug_check
      CHECK (background IS NULL OR background ~ '^[a-z0-9_]{1,32}$');
  END IF;
END $$;

-- -------------------------------------------------------------- stories
ALTER TABLE public.stories
  ADD COLUMN IF NOT EXISTS background TEXT,
  ADD COLUMN IF NOT EXISTS text_content TEXT;

COMMENT ON COLUMN public.stories.background IS
  'Metin hikayesinin arka plan kimliği (lib/core/widgets/text_background.dart).';
COMMENT ON COLUMN public.stories.text_content IS
  'Metin hikayesinin yazısı. media_type = ''text'' olduğunda dolu olmalı.';

ALTER TABLE public.stories
  ALTER COLUMN image_url DROP NOT NULL;

-- media_type'a 'text' eklendi (mevcut satırlar image/video, dokunulmuyor).
ALTER TABLE public.stories
  DROP CONSTRAINT IF EXISTS stories_media_type_check;
ALTER TABLE public.stories
  ADD CONSTRAINT stories_media_type_check
  CHECK ((media_type)::text = ANY (ARRAY['image', 'video', 'text']));

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.stories'::regclass AND conname = 'stories_media_payload_check'
  ) THEN
    -- Görsel/video hikayede image_url zorunlu; metin hikayede yazı zorunlu.
    ALTER TABLE public.stories
      ADD CONSTRAINT stories_media_payload_check
      CHECK (
        CASE
          WHEN (media_type)::text = 'text'
            THEN text_content IS NOT NULL AND length(btrim(text_content)) > 0
          ELSE image_url IS NOT NULL
        END
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.stories'::regclass AND conname = 'stories_background_slug_check'
  ) THEN
    ALTER TABLE public.stories
      ADD CONSTRAINT stories_background_slug_check
      CHECK (background IS NULL OR background ~ '^[a-z0-9_]{1,32}$');
  END IF;
END $$;

-- ------------------------------------------------- posts_with_profiles view
-- `p.*` yeniden genişlesin diye view baştan yaratılıyor. Tanım 20260812000001
-- ile aynı: profiles'tan yalnızca GRANT'lı 15 güvenli sütun okunur, role ve
-- is_admin kasıtlı NULL (aksi halde security_invoker 42501 fırlatır).
DROP VIEW IF EXISTS public.posts_with_profiles;

CREATE VIEW public.posts_with_profiles
WITH (security_invoker = true) AS
SELECT
  p.*,
  pr.username,
  pr.full_name,
  pr.avatar_url,
  pr.is_ghost_mode     AS author_is_ghost_mode,
  pr.profile_is_public AS author_profile_public,
  pr.status            AS author_status,
  NULL::BOOLEAN AS author_is_verified,
  NULL::TEXT    AS author_role,
  NULL::BOOLEAN AS author_is_admin,
  (pr.id IS NOT NULL) AS author_profile_exists
FROM posts p
LEFT JOIN profiles pr ON pr.id = p.user_id
WHERE p.is_active = true;

GRANT SELECT ON public.posts_with_profiles TO authenticated, anon;

COMMENT ON VIEW public.posts_with_profiles IS
  'Posts + profiles LEFT JOIN. security_invoker=true. 2026-09-09: posts.background '
  'kolonu eklendiği için view yeniden yaratıldı (p.* oluşturma anında genişler).';

NOTIFY pgrst, 'reload schema';

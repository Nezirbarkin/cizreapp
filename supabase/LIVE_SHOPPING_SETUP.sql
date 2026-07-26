-- ============================================================================
-- LIVE SHOPPING SETUP (Canlı Yayın Alışverişi - Agora)
-- ============================================================================
-- CizreApp - Satıcı canlı yayın açar, izleyiciler katılır, ürün pinler.
-- Realtime: yorum broadcast + presence (izleyici sayısı) + postgres_changes (pin)
-- ============================================================================

-- ============================================================================
-- 1) LIVE SESSIONS TABLOSU
-- ============================================================================
CREATE TABLE IF NOT EXISTS live_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  host_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  shop_id UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  description TEXT,
  cover_image_url TEXT,
  -- Agora channel adı (genellikle session id'nin basitleştirilmiş hali)
  channel_name TEXT NOT NULL UNIQUE,
  -- status: scheduled | live | ended
  status TEXT NOT NULL DEFAULT 'scheduled'
    CHECK (status IN ('scheduled','live','ended')),
  started_at TIMESTAMPTZ,
  ended_at TIMESTAMPTZ,
  peak_viewer_count INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_live_sessions_status ON live_sessions(status, started_at);
CREATE INDEX IF NOT EXISTS idx_live_sessions_shop ON live_sessions(shop_id);
CREATE INDEX IF NOT EXISTS idx_live_sessions_host ON live_sessions(host_user_id);

CREATE OR REPLACE FUNCTION trg_live_sessions_set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql
SET search_path = public, pg_temp;

DROP TRIGGER IF EXISTS live_sessions_set_updated_at ON live_sessions;
CREATE TRIGGER live_sessions_set_updated_at
  BEFORE UPDATE ON live_sessions
  FOR EACH ROW EXECUTE FUNCTION trg_live_sessions_set_updated_at();

-- ============================================================================
-- 2) LIVE PINNED PRODUCTS (Satıcının yayında öne çıkardığı ürün)
-- ============================================================================
CREATE TABLE IF NOT EXISTS live_pinned_products (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID NOT NULL REFERENCES live_sessions(id) ON DELETE CASCADE,
  product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  pinned_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  pinned_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  -- Aynı anda sadece bir pin aktif olsun: partial unique
  is_current BOOLEAN NOT NULL DEFAULT true
);

-- Bir session'da aynı anda tek aktif pin
CREATE UNIQUE INDEX IF NOT EXISTS idx_live_pin_current_unique
  ON live_pinned_products(session_id)
  WHERE is_current = true;

CREATE INDEX IF NOT EXISTS idx_live_pin_session ON live_pinned_products(session_id);

-- ============================================================================
-- 3) LIVE MESSAGES (Yorum geçmişi - broadcast anlık, bu tablo kalıcı)
-- ============================================================================
CREATE TABLE IF NOT EXISTS live_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID NOT NULL REFERENCES live_sessions(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  message TEXT NOT NULL,
  is_host BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_live_messages_session_time
  ON live_messages(session_id, created_at DESC);

-- ============================================================================
-- 4) RLS: LIVE SESSIONS
-- ============================================================================
ALTER TABLE live_sessions ENABLE ROW LEVEL SECURITY;

-- Herkes okuyabilir (keşfet için)
DROP POLICY IF EXISTS "live_sessions_select_all" ON live_sessions;
CREATE POLICY "live_sessions_select_all" ON live_sessions
  FOR SELECT USING (true);

-- Satıcı kendi mağazası için yayın oluşturur
DROP POLICY IF EXISTS "live_sessions_insert_host" ON live_sessions;
CREATE POLICY "live_sessions_insert_host" ON live_sessions
  FOR INSERT
  WITH CHECK (
    auth.uid() = host_user_id
    AND EXISTS (
      SELECT 1 FROM shops s
      WHERE s.id = shop_id AND s.owner_id = auth.uid()
    )
  );

-- Sadece host güncelleyebilir (status değişimi, peak viewer vs.)
DROP POLICY IF EXISTS "live_sessions_update_host" ON live_sessions;
CREATE POLICY "live_sessions_update_host" ON live_sessions
  FOR UPDATE
  USING (auth.uid() = host_user_id);

-- ============================================================================
-- 5) RLS: LIVE PINNED PRODUCTS
-- ============================================================================
ALTER TABLE live_pinned_products ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "live_pin_select_all" ON live_pinned_products;
CREATE POLICY "live_pin_select_all" ON live_pinned_products
  FOR SELECT USING (true);

-- Sadece session'un host'u pinleyebilir
DROP POLICY IF EXISTS "live_pin_insert_host" ON live_pinned_products;
CREATE POLICY "live_pin_insert_host" ON live_pinned_products
  FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM live_sessions ls
      WHERE ls.id = session_id
        AND ls.host_user_id = auth.uid()
    )
  );

-- Host kendi pinlerini güncelleyebilir/silebilir
DROP POLICY IF EXISTS "live_pin_update_host" ON live_pinned_products;
CREATE POLICY "live_pin_update_host" ON live_pinned_products
  FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM live_sessions ls
      WHERE ls.id = live_pinned_products.session_id
        AND ls.host_user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "live_pin_delete_host" ON live_pinned_products;
CREATE POLICY "live_pin_delete_host" ON live_pinned_products
  FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM live_sessions ls
      WHERE ls.id = live_pinned_products.session_id
        AND ls.host_user_id = auth.uid()
    )
  );

-- ============================================================================
-- 6) RLS: LIVE MESSAGES
-- ============================================================================
ALTER TABLE live_messages ENABLE ROW LEVEL SECURITY;

-- Session katılımcıları okuyabilir (basitleştirilmiş: herkes okur)
DROP POLICY IF EXISTS "live_messages_select_all" ON live_messages;
CREATE POLICY "live_messages_select_all" ON live_messages
  FOR SELECT USING (true);

-- Giriş yapmış kullanıcı yazabilir
DROP POLICY IF EXISTS "live_messages_insert_auth" ON live_messages;
CREATE POLICY "live_messages_insert_auth" ON live_messages
  FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- Sadece host kendi mesajlarını silebilir (moderasyon)
DROP POLICY IF EXISTS "live_messages_delete_host" ON live_messages;
CREATE POLICY "live_messages_delete_host" ON live_messages
  FOR DELETE
  USING (
    is_host = true
    AND EXISTS (
      SELECT 1 FROM live_sessions ls
      WHERE ls.id = live_messages.session_id
        AND ls.host_user_id = auth.uid()
    )
  );

-- ============================================================================
-- 7) HELPER: Yayını başlat (status -> live, started_at set)
-- ============================================================================
CREATE OR REPLACE FUNCTION start_live_session(p_session_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_session live_sessions%ROWTYPE;
BEGIN
  SELECT * INTO v_session FROM live_sessions WHERE id = p_session_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Yayın bulunamadı');
  END IF;
  IF v_session.host_user_id != auth.uid() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Yetkisiz');
  END IF;
  UPDATE live_sessions
    SET status = 'live', started_at = NOW()
    WHERE id = p_session_id;
  RETURN jsonb_build_object('success', true, 'channel_name', v_session.channel_name);
END;
$$;

-- Yayını bitir
CREATE OR REPLACE FUNCTION end_live_session(p_session_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  UPDATE live_sessions
    SET status = 'ended', ended_at = NOW()
    WHERE id = p_session_id AND host_user_id = auth.uid();
  RETURN jsonb_build_object('success', true);
END;
$$;

-- ============================================================================
-- 8) REALTIME: pin değişimi + mesajlar için publication
-- ============================================================================
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables
                 WHERE pubname = 'supabase_realtime' AND tablename = 'live_sessions') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE live_sessions;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables
                 WHERE pubname = 'supabase_realtime' AND tablename = 'live_pinned_products') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE live_pinned_products;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables
                 WHERE pubname = 'supabase_realtime' AND tablename = 'live_messages') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE live_messages;
  END IF;
END $$;

-- ============================================================================
-- 9) PRIVILEGES: Anon revoke, authenticated explicit grant
-- ============================================================================
-- Linter: anon bu SECURITY DEFINER RPC'leri REST ile çağırabiliyor.
-- Sadece authenticated (giriş yapmış) yayın sahibi çağırabilsin.
REVOKE EXECUTE ON FUNCTION public.start_live_session(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.end_live_session(uuid) FROM anon;

GRANT EXECUTE ON FUNCTION public.start_live_session(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.end_live_session(uuid) TO authenticated;

-- ============================================================================
-- TAMAMLANDI
-- ============================================================================
-- Not: Agora App ID ve (varsa) token auth istemci tarafında tutulur.
-- Token generation için bir Supabase Edge Function önerilir (AppCertificate ile).
-- Bu script idempotent'tir.
-- ============================================================================
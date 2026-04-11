-- Hesap silme için RPC fonksiyonları

-- 1. Onay kodu oluştur ve email gönder
CREATE OR REPLACE FUNCTION request_account_deletion()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_user_id uuid;
  v_email text;
  v_confirmation_code text;
  v_expires_at timestamptz;
BEGIN
  -- Kullanıcıyı al
  v_user_id := auth.uid();
  
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;
  
  -- Email'i al
  SELECT email INTO v_email
  FROM auth.users
  WHERE id = v_user_id;
  
  -- 6 haneli onay kodu oluştur
  v_confirmation_code := LPAD(FLOOR(RANDOM() * 1000000)::text, 6, '0');
  v_expires_at := NOW() + INTERVAL '15 minutes';
  
  -- Onay kodunu kaydet
  INSERT INTO account_deletion_codes (user_id, code, expires_at)
  VALUES (v_user_id, v_confirmation_code, v_expires_at)
  ON CONFLICT (user_id)
  DO UPDATE SET
    code = v_confirmation_code,
    expires_at = v_expires_at,
    created_at = NOW();
  
  -- Onay kodunu ve email'i döndür (Flutter tarafında email gönderilecek)
  RETURN jsonb_build_object(
    'success', true,
    'message', 'Onay kodu oluşturuldu',
    'email', v_email,
    'confirmationCode', v_confirmation_code
  );
END;
$$;

-- 2. Onay kodu ile hesabı sil
CREATE OR REPLACE FUNCTION delete_account_with_code(p_confirmation_code text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_user_id uuid;
  v_stored_code text;
  v_expires_at timestamptz;
BEGIN
  -- Kullanıcıyı al
  v_user_id := auth.uid();
  
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;
  
  -- Onay kodunu kontrol et
  SELECT code, expires_at INTO v_stored_code, v_expires_at
  FROM account_deletion_codes
  WHERE user_id = v_user_id;
  
  IF v_stored_code IS NULL THEN
    RAISE EXCEPTION 'Onay kodu bulunamadı';
  END IF;
  
  IF NOW() > v_expires_at THEN
    RAISE EXCEPTION 'Onay kodu süresi dolmuş';
  END IF;
  
  IF v_stored_code != p_confirmation_code THEN
    RAISE EXCEPTION 'Geçersiz onay kodu';
  END IF;
  
  -- Onay kodunu sil
  DELETE FROM account_deletion_codes WHERE user_id = v_user_id;
  
  -- Kullanıcının tüm verilerini sil
  -- 1. Posts
  DELETE FROM posts WHERE user_id = v_user_id;
  
  -- 2. Comments
  DELETE FROM comments WHERE user_id = v_user_id;
  
  -- 3. Stories
  DELETE FROM stories WHERE user_id = v_user_id;
  
  -- 4. Products
  DELETE FROM products WHERE user_id = v_user_id;
  
  -- 5. Profile
  DELETE FROM profiles WHERE id = v_user_id;
  
  -- 6. Auth user (CASCADE ile diğer auth tabloları da silinecek)
  DELETE FROM auth.users WHERE id = v_user_id;
  
  RETURN jsonb_build_object(
    'success', true,
    'message', 'Hesabınız başarıyla silindi'
  );
END;
$$;

-- Onay kodları tablosu
CREATE TABLE IF NOT EXISTS account_deletion_codes (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  code text NOT NULL,
  expires_at timestamptz NOT NULL,
  created_at timestamptz DEFAULT NOW()
);

-- RLS politikaları
ALTER TABLE account_deletion_codes ENABLE ROW LEVEL SECURITY;

-- Policy zaten varsa CREATE IF NOT EXISTS çalışmaz, DROP & CREATE kullanıyoruz
DROP POLICY IF EXISTS "Users can view own deletion codes" ON account_deletion_codes;

CREATE POLICY "Users can view own deletion codes"
  ON account_deletion_codes
  FOR SELECT
  USING (auth.uid() = user_id);

COMMENT ON FUNCTION request_account_deletion IS 'Hesap silme için onay kodu oluşturur ve email gönderir';
COMMENT ON FUNCTION delete_account_with_code IS 'Onay kodu ile kullanıcı hesabını ve tüm verilerini siler';

-- E-posta Ayarları Tablosu
-- Admin panelinden yapılandırılabilir e-posta ayarları

-- Tablo oluştur
CREATE TABLE IF NOT EXISTS email_settings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  -- E-posta sağlayıcı tipi: 'resend', 'smtp', 'sendgrid', 'mailgun'
  provider TEXT NOT NULL DEFAULT 'resend',
  
  -- Resend ayarları
  resend_api_key TEXT,
  
  -- SMTP ayarları (kendi sunucu)
  smtp_host TEXT,
  smtp_port INTEGER DEFAULT 587,
  smtp_username TEXT,
  smtp_password TEXT,
  smtp_encryption TEXT DEFAULT 'tls', -- 'none', 'ssl', 'tls'
  
  -- SendGrid ayarları
  sendgrid_api_key TEXT,
  
  -- Mailgun ayarları
  mailgun_api_key TEXT,
  mailgun_domain TEXT,
  
  -- Genel ayarlar
  from_email TEXT NOT NULL DEFAULT 'noreply@cizreapp.com',
  from_name TEXT NOT NULL DEFAULT 'CizreApp',
  reply_to_email TEXT,
  
  -- Bildirim tercihleri
  notify_admin_new_order BOOLEAN DEFAULT true,
  notify_seller_new_order BOOLEAN DEFAULT true,
  notify_customer_order_status BOOLEAN DEFAULT true,
  
  -- Admin e-posta adresi (sistem bildirimleri için)
  admin_email TEXT,
  
  -- Aktiflik durumu
  is_active BOOLEAN DEFAULT true,
  
  -- Zaman damgaları
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Varsayılan kayıt ekle
INSERT INTO email_settings (
  provider,
  from_email,
  from_name,
  notify_admin_new_order,
  notify_seller_new_order,
  notify_customer_order_status,
  is_active
) VALUES (
  'resend',
  'noreply@cizreapp.com',
  'CizreApp',
  true,
  true,
  true,
  true
) ON CONFLICT DO NOTHING;

-- RLS Politikaları
ALTER TABLE email_settings ENABLE ROW LEVEL SECURITY;

-- Sadece admin okuyabilir
CREATE POLICY "Admins can view email settings" ON email_settings
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM profiles 
      WHERE profiles.id = auth.uid() 
      AND profiles.role = 'admin'
    )
  );

-- Sadece admin güncelleyebilir
CREATE POLICY "Admins can update email settings" ON email_settings
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM profiles 
      WHERE profiles.id = auth.uid() 
      AND profiles.role = 'admin'
    )
  );

-- Sadece admin insert yapabilir (ilk kayıt için)
CREATE POLICY "Admins can insert email settings" ON email_settings
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM profiles 
      WHERE profiles.id = auth.uid() 
      AND profiles.role = 'admin'
    )
  );

-- Updated_at trigger
CREATE OR REPLACE FUNCTION update_email_settings_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS email_settings_updated_at ON email_settings;
CREATE TRIGGER email_settings_updated_at
  BEFORE UPDATE ON email_settings
  FOR EACH ROW
  EXECUTE FUNCTION update_email_settings_updated_at();

-- E-posta ayarlarını getiren fonksiyon (Edge Function için)
CREATE OR REPLACE FUNCTION get_email_settings()
RETURNS JSON AS $$
DECLARE
  result JSON;
BEGIN
  SELECT row_to_json(es) INTO result
  FROM email_settings es
  WHERE es.is_active = true
  LIMIT 1;
  
  RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON TABLE email_settings IS 'Admin tarafından yapılandırılabilen e-posta ayarları';

-- AI Settings için RLS'yi kaldır (geçici çözüm)
-- Bu, admin panelden API anahtarı kaydetmeyi sağlar

-- RLS'yi devre dışı bırak
ALTER TABLE public.ai_settings DISABLE ROW LEVEL SECURITY;

-- Tüm politikaları sil
DROP POLICY IF EXISTS "Admins can manage ai settings" ON public.ai_settings;
DROP POLICY IF EXISTS "Admins can insert ai settings" ON public.ai_settings;
DROP POLICY IF EXISTS "Anyone can read ai settings" ON public.ai_settings;

-- Tekrar etkinleştir ama daha basit politika ile
ALTER TABLE public.ai_settings ENABLE ROW LEVEL SECURITY;

-- Herkes okuyabilir, sadece authenticated kullanıcılar güncelleyebilir
CREATE POLICY "ai_settings_read" ON public.ai_settings FOR SELECT USING (true);
CREATE POLICY "ai_settings_write" ON public.ai_settings FOR ALL USING (auth.role() = 'authenticated');

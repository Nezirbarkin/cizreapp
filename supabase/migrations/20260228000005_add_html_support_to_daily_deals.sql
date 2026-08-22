-- =====================================================
-- Günün Fırsatları tablosuna HTML desteği ekle
-- =====================================================

-- deal_type kolonu: 'image' (varsayılan) veya 'html'
ALTER TABLE public.daily_deals 
ADD COLUMN IF NOT EXISTS deal_type TEXT NOT NULL DEFAULT 'image';

-- html_content kolonu: HTML/iframe içeriği
ALTER TABLE public.daily_deals 
ADD COLUMN IF NOT EXISTS html_content TEXT;

-- Yorum: deal_type = 'html' olduğunda, html_content alanındaki HTML içeriği
-- uygulamada WebView ile gösterilir. Örnek kullanım:
-- INSERT INTO daily_deals (title, deal_type, html_content, image_url, link_type, is_active)
-- VALUES ('Nöbetçi Eczaneler', 'html', '<iframe src="https://www.eczaneler.gen.tr/iframe.php?lokasyon=1223" ...></iframe>', '', 'url', true);

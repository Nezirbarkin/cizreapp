-- Satıcının dijital ürünlerinde sabit olarak gösterilecek uyarı metni.
-- Ürün bazında değil, mağaza bazında tutulur; satıcı bir kez yazar,
-- tüm dijital ürünlerinde aynı uyarı görünür.
ALTER TABLE public.shops
    ADD COLUMN IF NOT EXISTS digital_warning_note TEXT;

NOTIFY pgrst, 'reload schema';

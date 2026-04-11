-- ⚠️ BU DOSYA SADECE REFERANS / ÖRNEK DOSYADIR
-- DOĞRUDAN ÇALIŞTIRMA
--
-- Satıcı Kuryesi Durumu Değişimi - Örnek Senaryo
--
-- SENARYO:
-- Satıcı başta kuryesi var (has_own_courier = TRUE)
--   → Kapıda ödeme alıyor → Komisyon borcu birikmiş
--   → Ödeme isteği oluşturmuş ama çıkaramadı (borç > 0)
-- 
-- Daha sonra admin kuryesine geçmek istiyor (has_own_courier = FALSE)
--   → Yeni siparişler = kuryesi olmayan mantığıyla
--   → Eski borç + Yeni alacak = Net tutar hesaplanacak

-- ⚠️ PLACEHOLDER DOLDUR: 'SATICI_ID_BURAYA' yerine gerçek UUID yaz!
-- Örnek: UPDATE shops SET has_own_courier = FALSE WHERE id = '70ab05f6-6aeb-4d32-810e-f3955c300f12';

-- -- 1. Satıcı kuryesi durumunu değiştir
-- UPDATE shops
-- SET
--   has_own_courier = FALSE,
--   updated_at = NOW()
-- WHERE id = 'SATICI_ID_BURAYA';

-- -- 2. Bu satıcının ödeme durumunu kontrol et
-- SELECT
--   id,
--   name,
--   has_own_courier,
--   commission_debt as eski_kuryeli_komisyon_borcu,
--   admin_credit as yeni_kuryesiz_alacagi,
--   (admin_credit - commission_debt) as net_odeme_tutari
-- FROM shops
-- WHERE id = 'SATICI_ID_BURAYA';

-- -- 3. Bu satıcının son siparişlerini kontrol et
-- SELECT
--   id,
--   created_at,
--   payment_method,
--   seller_has_own_courier,
--   subtotal,
--   delivery_fee,
--   total,
--   admin_commission,
--   seller_debt_amount,
--   seller_credit_amount,
--   commission_status
-- FROM orders
-- WHERE shop_id = 'SATICI_ID_BURAYA'
-- ORDER BY created_at DESC
-- LIMIT 20;

-- ═════════════════════════════════════════════════════════════════
-- AÇIKLAMA:
-- ═════════════════════════════════════════════════════════════════

/*
SİSTEM OTOMATİK OLARAK ŞUNLARI YAPAR:

1. Eski Siparişler (has_own_courier = TRUE iken)
   - Zaten commission_debt'e eklenmişler
   - Değişmez (orders tablosundaki seller_has_own_courier kaydedilmiş)

2. Yeni Siparişler (has_own_courier = FALSE sonrası)
   - trigger calculate_order_commission çalışacak
   - has_own_courier = FALSE olduğu için
   - seller_credit_amount = subtotal - admin_commission
   - admin_credit'e eklenecek

3. Ödeme İsteği Hesaplaması:
   IF NOT has_own_courier THEN
     net_receivable := admin_credit
   ELSE
     net_receivable := admin_credit - commission_debt

   ESKI DURUM (kuryesi var):
   - admin_credit = 0 (sadece kapıda ödeme alıyor)
   - commission_debt = 500₺ (birikmiş borç)
   - net = -500₺ (borç var, ödeme isteği oluşturamaz)

   YENİ DURUM (kuryesi yok):
   - admin_credit = 800₺ (yeni siparişler)
   - commission_debt = 500₺ (eski borç)
   - net = 300₺ (ödeme isteği oluşturabilir)

4. Açık Ödeme İsteği Varsa:
   - Eski isteği kapatması gerekebilir
   - Yeni isteği açması gerekebilir

ÖRNEK:

Satıcı Kuryesi VAR durumda:
  - 5 sipariş (kapıda ödeme)
  - Toplam: 500₺
  - Komisyon: 20% × 500₺ = 100₺
  - Borç: 100₺
  - admin_credit = 0
  - Ödeme isteği: YAPAMAZ

Satıcı Kuryesi YOK'a Geçtikten Sonra:
  - 2 yeni sipariş (admin kuryesi)
  - Toplam: 400₺
  - Komisyon: 20% × 400₺ = 80₺
  - Satıcı alacağı: 400₺ - 80₺ = 320₺
  - admin_credit = 320₺
  - commission_debt = 100₺ (kalıyor)
  - Net: 320₺ - 100₺ = 220₺
  - Ödeme isteği: 220₺ ile oluşturabilir
*/

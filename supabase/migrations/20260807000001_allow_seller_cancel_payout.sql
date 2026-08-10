-- ============================================================================
-- Satıcının kendi pending ödeme isteğini iptal edebilmesi
-- ============================================================================
-- Arka plan (tespit edilen hata):
--   * payout_requests.status CHECK constraint'i yalnızca
--     ('pending','approved','paid','rejected') değerlerine izin veriyordu —
--     'cancelled' yoktu, dolayısıyla iptal hiçbir zaman DB seviyesinde
--     geçerli değildi (bkz. 20260130000001_payout_requests.sql).
--   * payout_requests için UPDATE RLS politikası yalnızca adminlere açıktı.
--     Satıcı tarafındaki PayoutService.cancelPayoutRequest() bir UPDATE
--     yapıyordu ama RLS bunu sessizce 0 satıra düşürüyordu; UI ise dönen
--     bool'u yok sayıp "iptal edildi" bildirimi gösteriyordu → sahte başarı.
--
-- Bu migration iki şey yapar:
--   1) status constraint'ine 'cancelled' ekler (geriye dönük uyumlu).
--   2) Satıcının yalnızca KENDİ ve yalnızca 'pending' olan isteğini
--      'cancelled'a çekebileceği kısıtlı bir UPDATE politikası ekler.
--
-- Güvenlik kapsamı:
--   USING  → satır güncellenebilir mi: seller_id = auth.uid() AND status='pending'
--   WITH CHECK → sonuç satırı geçerli mi: seller_id = auth.uid() AND status='cancelled'
--   Yani satıcı yalnızca pending→cancelled geçişini yapabilir; amount, iban gibi
--   başka alanları değiştiremez ve approved/paid/rejected üretemez. Mevcut admin
--   UPDATE politikası (permissive, OR'lenir) olduğu gibi korunur.
-- ============================================================================

-- 1) status constraint'ine 'cancelled' ekle
ALTER TABLE public.payout_requests
  DROP CONSTRAINT IF EXISTS payout_requests_status_check;

ALTER TABLE public.payout_requests
  ADD CONSTRAINT payout_requests_status_check
  CHECK (status IN ('pending', 'approved', 'paid', 'rejected', 'cancelled'));

-- 2) Satıcıya özel, sıkı kapsamlı iptal UPDATE politikası
DROP POLICY IF EXISTS "payout_requests_seller_cancel_own_pending"
  ON public.payout_requests;

CREATE POLICY "payout_requests_seller_cancel_own_pending"
  ON public.payout_requests FOR UPDATE
  TO authenticated
  USING (seller_id = auth.uid() AND status = 'pending')
  WITH CHECK (seller_id = auth.uid() AND status = 'cancelled');

-- ============================================================================

-- Kontrol notu: 'cancelled' isteği clear_shop_balance trigger'ını tetiklemez
-- (trigger yalnızca 'approved' ve 'paid' için çalışır) — bakiyeler dokunulmaz,
-- bu doğru: iptal edilen istek için para hareketi olmamıştır.
-- Ayrıca validate_payout_request, bekleyen istekleri SUM(total_amount)
-- WHERE status='pending' ile toplar; iptal edilen istek 'pending' olmaktan
-- çıktığı için satıcının kullanılabilir bakiyesi serbest kalır.

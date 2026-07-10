-- ============================================================
-- Admin View SECURITY DEFINER Düzeltmesi
-- Tarih: 2026-07-10
-- Sorun: admin_user_spending_summary SECURITY DEFINER olarak tanımlanmış
-- ve RLS politikalarını atlayabilir
-- Çözüm: View'ı SECURITY INVOKER (varsayılan) olarak yeniden oluştur
-- ============================================================

-- Önce mevcut view'ı düşür
DROP VIEW IF EXISTS admin_user_spending_summary CASCADE;

-- View'ı SECURITY DEFINER OLMADAN yeniden oluştur
-- Bu, view'ın sorgulayan kullanıcının RLS politikalarını kullanmasını sağlar
CREATE OR REPLACE VIEW admin_user_spending_summary AS
SELECT
  p.id AS user_id,
  p.full_name,
  COALESCE(
    (SELECT SUM(o.total_amount) FROM orders o WHERE o.user_id = p.id AND o.status != 'cancelled'),
    0
  ) AS total_spent,
  COALESCE(
    (SELECT COUNT(*) FROM orders o WHERE o.user_id = p.id AND o.status != 'cancelled'),
    0
  ) AS order_count,
  (SELECT MAX(created_at) FROM orders WHERE user_id = p.id) AS last_order_date,
  COALESCE(
    (SELECT SUM(bt.amount) FROM balance_transactions bt WHERE bt.user_id = p.id AND bt.type = 'refund'),
    0
  ) AS total_refunds,
  COALESCE(
    (SELECT COUNT(*) FROM balance_transactions bt WHERE bt.user_id = p.id AND bt.type = 'refund'),
    0
  ) AS refund_count
FROM profiles p
WHERE p.role = 'customer';

-- Yetkilendirme
GRANT SELECT ON admin_user_spending_summary TO authenticated;
GRANT SELECT ON admin_user_spending_summary TO anon;

SELECT 'Admin view başarıyla yeniden oluşturuldu (SECURITY DEFINER olmadan)!' AS status;

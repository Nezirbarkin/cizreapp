-- Yeni commission trigger function'larına search_path ekle
-- Supabase linter uyarılarını çözmek için

ALTER FUNCTION calculate_order_commission() SET search_path = 'public';
ALTER FUNCTION update_shop_balance() SET search_path = 'public';
ALTER FUNCTION validate_payout_request() SET search_path = 'public';
ALTER FUNCTION clear_shop_balance() SET search_path = 'public';

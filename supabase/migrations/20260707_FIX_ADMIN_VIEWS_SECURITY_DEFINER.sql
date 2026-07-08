-- ============================================
-- GÜVENLİK: Admin view'larındaki SECURITY DEFINER sorunu düzeltmesi
-- Tarih: 2026-07-07
-- Supabase linter: security_definer_view
--
-- Views varsayılan olarak sahibinin (postgres) yetkileriyle çalışıyor
-- ve alttaki tablolardaki RLS politikalarını atlıyordu. security_invoker
-- ayarı ile view artık sorguyu yapan kullanıcının RLS haklarıyla çalışır.
-- user_balances ve balance_transactions tablolarında zaten "admin görebilir /
-- kullanıcı sadece kendisininkini görebilir" politikaları mevcut.
-- ============================================

ALTER VIEW admin_users_with_balance SET (security_invoker = true);
ALTER VIEW admin_user_spending_summary SET (security_invoker = true);
ALTER VIEW admin_balance_transactions_full SET (security_invoker = true);

-- Dolandiricilik sinyali RPC'leri yalnizca oturum acmis kullanicilar
-- tarafindan cagrilabilir. Fonksiyonlar kendi iclerinde admin rolunu dogrular.
--
-- Onceki migration bu izinleri tanimlasa da canli veritabaninda EXECUTE
-- yetkileri eksik kalabildigi icin izinleri idempotent olarak yeniden kurar.

revoke all on function public.admin_scan_fraud_signals() from public, anon;
revoke all on function public.admin_list_fraud_signals(text, text, integer, integer) from public, anon;
revoke all on function public.admin_review_fraud_signal(uuid, text, text) from public, anon;

grant execute on function public.admin_scan_fraud_signals() to authenticated;
grant execute on function public.admin_list_fraud_signals(text, text, integer, integer) to authenticated;
grant execute on function public.admin_review_fraud_signal(uuid, text, text) to authenticated;


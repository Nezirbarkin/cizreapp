-- =====================================================================
-- GRUP SİSTEMİ LİNTER UYARILARI DÜZELTMESİ
-- =====================================================================
-- Supabase linter, grup sistemi için eklediğimiz bazı yardımcı/trigger
-- fonksiyonlarının anon/authenticated rolleri tarafından REST API
-- (/rest/v1/rpc/...) üzerinden çağrılabildiğini işaretledi. Bu
-- fonksiyonlar sadece RLS politikaları ve trigger içinde kullanılmak
-- üzere tasarlandı, dışarıdan çağrılmalarına gerek yok. EXECUTE
-- yetkisini geri alıyoruz; davranış değişmiyor, sadece gereksiz dış
-- erişim yüzeyi kapatılıyor.
-- =====================================================================

-- is_group_admin / is_group_member: sadece RLS politikaları içinde
-- kullanılıyor, dışarıdan RPC olarak çağrılmasına gerek yok.
REVOKE EXECUTE ON FUNCTION public.is_group_admin(UUID, UUID) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.is_group_member(UUID, UUID) FROM PUBLIC, anon, authenticated;

-- Trigger fonksiyonu - kimsenin RPC ile çağırmasına gerek yok.
REVOKE EXECUTE ON FUNCTION public.prevent_group_member_role_self_escalation() FROM PUBLIC, anon, authenticated;

-- admin_add_group_member: sadece giriş yapmış kullanıcılar çağırabilmeli
-- (içeride zaten is_group_admin kontrolü var, ama anon'a hiç açık olmamalı).
REVOKE EXECUTE ON FUNCTION public.admin_add_group_member(UUID, UUID, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_add_group_member(UUID, UUID, UUID) TO authenticated;

NOTIFY pgrst, 'reload schema';

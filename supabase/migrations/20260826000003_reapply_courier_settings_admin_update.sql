-- courier_settings_admin_update policy dosyası (20260723000200) migration
-- geçmişi senkron olmadığı için canlıda hiç uygulanmamıştı; tablo sadece
-- public SELECT policy'sine sahipti ve admin UPDATE'leri RLS'e çarpıp
-- sessizce 0 satır dönüyordu (UI: "Kayıt güncellenemedi" hatası).
drop policy if exists "courier_settings_admin_update" on courier_service_settings;
create policy "courier_settings_admin_update" on courier_service_settings
  for update to authenticated
  using (public.is_admin())
  with check (public.is_admin());

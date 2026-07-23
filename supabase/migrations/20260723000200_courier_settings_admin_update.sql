-- courier_service_settings: sadece SELECT policy vardı, admin güncellemesi RLS'e çarpıp
-- sessizce 0 satır dönüyordu (hata fırlamıyor). Admin için UPDATE izni ekle.
create policy "courier_settings_admin_update" on courier_service_settings
  for update to authenticated
  using (public.is_admin())
  with check (public.is_admin());

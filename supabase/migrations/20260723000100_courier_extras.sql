-- Açık adres detayı ve kurye reddi sonrası yeniden atama için kolonlar
alter table courier_requests
  add column if not exists delivery_address_detail text,
  add column if not exists rejected_by uuid[] not null default '{}'::uuid[];

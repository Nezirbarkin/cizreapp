-- Mesafe bazlı paket fiyatlandırma (açılış ücreti + km ücreti) ve komisyon ayarları
alter table courier_service_settings
  add column if not exists commission_percent numeric not null default 20,
  add column if not exists base_fee numeric not null default 15,
  add column if not exists per_km_fee numeric not null default 3;

alter table courier_requests
  add column if not exists sender_name text,
  add column if not exists sender_phone text,
  add column if not exists pickup_address text,
  add column if not exists pickup_lat double precision,
  add column if not exists pickup_lng double precision,
  add column if not exists delivery_lat double precision,
  add column if not exists delivery_lng double precision,
  add column if not exists distance_km numeric,
  add column if not exists total_fee numeric,
  add column if not exists courier_fee numeric,
  add column if not exists admin_commission numeric,
  add column if not exists delivered_at timestamptz;

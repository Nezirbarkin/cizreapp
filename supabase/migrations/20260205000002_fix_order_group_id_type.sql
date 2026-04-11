-- Hotfix: order_group_id alanını UUID'den TEXT'e değiştir
-- Bu migration 20260205000001_multi_shop_order_system.sql sonrasında çalıştırılmalı

-- order_group_id alanının tipini TEXT'e değiştir (UUID yerine)
ALTER TABLE orders ALTER COLUMN order_group_id TYPE TEXT USING order_group_id::TEXT;

-- Yorum ekle
COMMENT ON COLUMN orders.order_group_id IS 'Grup sipariş ID - aynı anda verilen çoklu dükkan siparişlerini gruplar (TEXT format)';

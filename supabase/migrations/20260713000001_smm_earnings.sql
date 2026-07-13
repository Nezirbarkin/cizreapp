-- Dijital sipariş satıcı kazancı takibi
-- Fiziksel siparişlerdeki seller_earnings/payout akışı orders tablosuna bağımlı olduğundan
-- (order_id FK -> orders(id)) dijital siparişler için kullanılamıyor. Bunun yerine mevcut
-- add_to_balance('commission') RPC'si ile satıcının bakiyesine doğrudan kazanç eklenir -
-- balance_transactions üzerinden (reference_type='digital_order') satıcı kazanç geçmişinde görünür.

ALTER TABLE digital_orders
  ADD COLUMN IF NOT EXISTS seller_credited BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS commission_amount NUMERIC(12,2),
  ADD COLUMN IF NOT EXISTS net_seller_amount NUMERIC(12,2);

-- Profil/kapak dekorasyonu satın alma işlemleri için yeni bakiye işlem tipi.
-- ALTER TYPE ... ADD VALUE aynı transaction içinde kullanılamadığı için
-- (bkz. 20260723000101_courier_balance_type.sql, 20260817000024_ilan_publish_fee_balance_type.sql
-- ile aynı desen) bu değer ayrı, tek başına bir migration'da eklenir; kullanan
-- RPC sonraki migration'dadır (20260817000027).
alter type balance_transaction_type add value if not exists 'profile_feature_purchase';

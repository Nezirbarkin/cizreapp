-- İlan yayınlama ücreti tahsilatı/iadesi için işlem tipleri.
-- ALTER TYPE ... ADD VALUE aynı transaction içinde kullanılamadığı için
-- (bkz. 20260723000101_courier_balance_type.sql ile aynı desen) bu değerler
-- ayrı, tek başına bir migration'da eklenir; kullanan trigger sonraki
-- migration'dadır (20260817000024).
alter type balance_transaction_type add value if not exists 'ilan_publish_fee';
alter type balance_transaction_type add value if not exists 'ilan_publish_refund';

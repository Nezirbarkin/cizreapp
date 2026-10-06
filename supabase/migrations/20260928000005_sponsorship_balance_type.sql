-- Satıcı öne çıkarma (sponsorlu vitrin, Görev 3.2) ödemeleri için yeni bakiye
-- işlem tipi. ALTER TYPE ... ADD VALUE aynı transaction içinde kullanılamadığı
-- için (bkz. 20260817000026_profile_feature_purchase_balance_type.sql ile aynı
-- desen) bu değer ayrı, tek başına bir migration'da eklenir; kullanan RPC
-- sonraki migration'dadır (20260928000006).
alter type balance_transaction_type add value if not exists 'sponsorship_purchase';

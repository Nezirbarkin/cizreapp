-- Paket teslimat ücretinin bakiyeden kesilmesi için işlem tipi
alter type balance_transaction_type add value if not exists 'courier_payment';

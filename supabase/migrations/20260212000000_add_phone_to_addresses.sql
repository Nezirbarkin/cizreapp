-- Addresses tablosuna phone sütunu ekle
-- Böylece her adres için özel telefon numarası kaydedilebilir

ALTER TABLE addresses 
ADD COLUMN IF NOT EXISTS phone TEXT;

-- Mevcut adreslerin varsa telefonlarını null olarak bırak
-- Kullanıcı adres eklerken telefon numarası da girebilecek

-- Comment ekle
COMMENT ON COLUMN addresses.phone IS 'Telefon numarası - teslimat sırasında aranmak için';

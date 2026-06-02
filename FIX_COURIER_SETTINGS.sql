-- Kurye ucretini duzelt: eski kaydi sil, sadece 49 olan kalsin
DELETE FROM courier_settings WHERE fee_per_delivery = 15;

-- Kontrol
SELECT * FROM courier_settings;
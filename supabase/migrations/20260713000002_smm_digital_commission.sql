-- Dijital ürün komisyon oranını fiziksel siparişlerin commission_rate'inden ayırır.
-- NULL ise varsayılan %10 uygulanır (Edge Function tarafında fallback).
ALTER TABLE shops ADD COLUMN IF NOT EXISTS digital_commission_rate NUMERIC(5,2);

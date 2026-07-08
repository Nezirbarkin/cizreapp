-- ============================================================================
-- 20260708_FIX_SELLER_EARNINGS_TRIGGER.sql
-- ----------------------------------------------------------------------------
-- Sorun: Sipariş delivered yapıldığında create_seller_earnings_on_delivery
-- trigger'ı seller_earnings satırı eklerken gross_amount null kalıyor.
-- Hata: "null value in column 'gross_amount' of relation 'seller_earnings'
-- violates not-null constraint" (23502).
--
-- İki katmanlı neden:
-- 1) orders tablosunda Dart kodu 'total' kolonu kullanıyor (legacy). Eski
--    trigger ise v_order.total_amount çağırıyor → null.
-- 2) Eski trigger'lar (FIX_COMMISSION_TRIGGER.sql dahil) v_order.total_amount
--    hard-code etmiş; bu nedenle gerçek sipariş tutarı gross_amount'a hiç
--    yazılamıyor.
--
-- Çözüm: Trigger'ı sıfırdan yaz, orders tablosundaki GERÇEK kolon adını
-- (total) kullan, gross/commission/net hesaplamalarını eksiksiz yap.
-- Aynı zamanda 20260630 FIX ile gelen total_amount kolonu doluysa onu da
-- tercih et (geriye dönük uyumluluk).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.create_seller_earnings_on_delivery()
RETURNS TRIGGER AS $$
DECLARE
    v_order RECORD;
    v_shop RECORD;
    v_gross DECIMAL(12, 2);
    v_commission_percent DECIMAL(5, 2);
    v_commission DECIMAL(12, 2);
    v_net DECIMAL(12, 2);
    v_seller_id UUID;
BEGIN
    -- Sadece delivered'a geçişte çalış (pending -> delivered, vb.)
    IF NEW.status = 'delivered' AND (OLD.status IS DISTINCT FROM 'delivered') THEN
        -- Siparişin tam snapshot'unu al
        SELECT * INTO v_order FROM public.orders WHERE id = NEW.id;

        -- Brüt tutar: önce legacy 'total' (Dart'ın yazdığı), sonra 'total_amount'
        -- (geriye dönük uyumluluk için eklenen). İkisi de null ise 0.
        v_gross := COALESCE(
            NULLIF(v_order.total, 0),
            v_order.total_amount,
            0
        );

        IF v_gross IS NULL OR v_gross <= 0 THEN
            RAISE NOTICE 'Sipariş % için geçerli tutar bulunamadı (total=%, total_amount=%), seller_earnings atlanıyor',
                v_order.id, v_order.total, v_order.total_amount;
            RETURN NEW;
        END IF;

        IF v_order.shop_id IS NULL THEN
            RAISE NOTICE 'Sipariş % için shop_id NULL, seller_earnings atlanıyor', v_order.id;
            RETURN NEW;
        END IF;

        -- Dükkan sahibini ve komisyon oranını al
        SELECT * INTO v_shop FROM public.shops WHERE id = v_order.shop_id;

        v_seller_id := v_shop.owner_id;
        v_commission_percent := COALESCE(v_shop.commission_rate, 10.00);

        v_commission := ROUND(v_gross * v_commission_percent / 100, 2);
        v_net := v_gross - v_commission;

        INSERT INTO public.seller_earnings (
            seller_id,
            order_id,
            order_number,
            shop_id,
            gross_amount,
            commission_amount,
            commission_percent,
            net_amount,
            status,
            available_at
        ) VALUES (
            v_seller_id,
            v_order.id,
            v_order.order_number,
            v_order.shop_id,
            v_gross,
            v_commission,
            v_commission_percent,
            v_net,
            'available',
            NOW() + INTERVAL '24 hours'
        )
        ON CONFLICT (order_id) DO NOTHING;

        RAISE NOTICE 'seller_earnings oluşturuldu: order=%, gross=%, commission=%, net=%',
            v_order.order_number, v_gross, v_commission, v_net;
    END IF;

    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    -- Trigger hatası sipariş güncellemesini engellemesin
    RAISE NOTICE 'create_seller_earnings hatası (görmezden gelindi): %', SQLERRM;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

-- Trigger'ı garanti olarak yeniden oluştur
DROP TRIGGER IF EXISTS trigger_create_seller_earnings ON public.orders;
CREATE TRIGGER trigger_create_seller_earnings
    AFTER UPDATE OF status ON public.orders
    FOR EACH ROW
    EXECUTE FUNCTION public.create_seller_earnings_on_delivery();

-- Güvenlik linter uyarısı için search_path'i fonksiyon üzerinde netleştirildi
-- (yukarıda SET search_path = public, pg_temp).

COMMENT ON FUNCTION public.create_seller_earnings_on_delivery IS
'Sipariş delivered durumuna geçtiğinde seller_earnings satırı oluşturur. orders.total (Dart) veya orders.total_amount (geriye dönük) brüt tutarı verir. gross/commission/net hesaplamaları eksiksiz yapılır. 2026-07-08 düzeltmesi: önceki sürümde v_order.total_amount null olduğu için gross_amount not-null constraint ihlali oluşuyordu.';
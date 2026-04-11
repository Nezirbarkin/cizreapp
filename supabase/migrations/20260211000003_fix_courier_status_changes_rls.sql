-- Fix courier_status_changes RLS for admin INSERT
-- Problem: Admin shops tablosunu güncellediğinde trigger INSERT yapmaya çalışıyor
-- ama INSERT policy yok, sadece SELECT policy var

-- DROP mevcut policy'leri
DROP POLICY IF EXISTS "courier_status_changes_select" ON public.courier_status_changes;

-- Admin için tam yetki (SELECT + INSERT)
CREATE POLICY "courier_status_changes_admin_all"
ON public.courier_status_changes FOR ALL
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.profiles
    WHERE profiles.id = (SELECT auth.uid())
    AND profiles.is_admin = true
  )
);

-- Satıcı için sadece kendi dükkanını okuma
CREATE POLICY "courier_status_changes_seller_select"
ON public.courier_status_changes FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.shops s
    WHERE s.id = courier_status_changes.shop_id
    AND s.owner_id = (SELECT auth.uid())
  )
);

-- Alternatif: Trigger'ı SECURITY DEFINER yaparak RLS'i bypass et
CREATE OR REPLACE FUNCTION public.on_courier_status_change()
RETURNS TRIGGER 
SECURITY DEFINER  -- RLS bypass
SET search_path = public
LANGUAGE plpgsql
AS $$
BEGIN
  -- Kurye durumu değişmişse log kaydet
  IF OLD.has_own_courier IS DISTINCT FROM NEW.has_own_courier THEN
    -- Değişiklik logunu kaydet
    INSERT INTO public.courier_status_changes (
      shop_id,
      previous_status,
      new_status,
      admin_credit_at_change,
      commission_debt_at_change,
      cash_revenue_at_change,
      online_revenue_at_change,
      notes
    ) VALUES (
      NEW.id,
      OLD.has_own_courier,
      NEW.has_own_courier,
      OLD.admin_credit,
      OLD.commission_debt,
      OLD.cash_payment_revenue,
      OLD.online_payment_revenue,
      CASE
        WHEN NEW.has_own_courier THEN 'Kuryesiz → Kuryeli geçiş yapıldı'
        ELSE 'Kuryeli → Kuryesiz geçiş yapıldı'
      END
    );
    
    -- KURYELI → KURYESIZ geçişi
    IF OLD.has_own_courier = TRUE AND NEW.has_own_courier = FALSE THEN
      -- Borç alacaktan düşülür (eğer yeterliyse)
      IF OLD.commission_debt > 0 AND OLD.admin_credit > 0 THEN
        -- Alacak borcun karşılayabilir
        IF OLD.admin_credit >= OLD.commission_debt THEN
          NEW.admin_credit := OLD.admin_credit - OLD.commission_debt;
          NEW.commission_debt := 0;
        ELSE
          -- Alacak yetmez, kalan borç kalır
          NEW.commission_debt := OLD.commission_debt - OLD.admin_credit;
          NEW.admin_credit := 0;
        END IF;
      END IF;
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.on_courier_status_change() IS 'Kurye durumu değiştiğinde otomatik log kaydeder ve borç/alacak hesabı yapar. SECURITY DEFINER ile RLS bypass edilir.';

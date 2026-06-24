-- ============================================
-- FIX: Admin Sipariş Silme Sorunu (Düzeltilmiş)
-- ============================================

-- Sorun: Admin sipariş sildiğinde "başarıyla silindi" diyor ama silinmiyor
-- Neden: RLS Policy veya Foreign Key constraint

-- 1. Admin rolünün siparişleri silebilmesi için gerekli yetki
DROP POLICY IF EXISTS "Admin can delete orders" ON orders;
CREATE POLICY "Admin can delete orders"
ON orders FOR DELETE
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM profiles 
        WHERE id = auth.uid() 
        AND role = 'admin'
    )
);

-- Service role için de policy ekle
DROP POLICY IF EXISTS "Service role can delete orders" ON orders;
CREATE POLICY "Service role can delete orders"
ON orders FOR DELETE
TO service_role
USING (true);

-- 2. Foreign key cascade delete kontrolü - order_items
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.table_constraints 
        WHERE constraint_name = 'order_items_order_id_fkey'
        AND table_name = 'order_items'
    ) THEN
        ALTER TABLE order_items DROP CONSTRAINT order_items_order_id_fkey;
    END IF;
    
    ALTER TABLE order_items 
    ADD CONSTRAINT order_items_order_id_fkey 
    FOREIGN KEY (order_id) 
    REFERENCES orders(id) 
    ON DELETE CASCADE;
END $$;

-- 3. courier_assignments için cascade delete
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.table_constraints 
        WHERE constraint_name = 'courier_assignments_order_id_fkey'
        AND table_name = 'courier_assignments'
    ) THEN
        ALTER TABLE courier_assignments DROP CONSTRAINT courier_assignments_order_id_fkey;
    END IF;
    
    ALTER TABLE courier_assignments 
    ADD CONSTRAINT courier_assignments_order_id_fkey 
    FOREIGN KEY (order_id) 
    REFERENCES orders(id) 
    ON DELETE CASCADE;
END $$;

-- 4. Sipariş silme fonksiyonu
CREATE OR REPLACE FUNCTION admin_delete_order(p_order_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
    v_is_admin BOOLEAN;
BEGIN
    SELECT EXISTS (
        SELECT 1 FROM profiles 
        WHERE id = auth.uid() 
        AND role = 'admin'
    ) INTO v_is_admin;
    
    IF NOT v_is_admin THEN
        RAISE EXCEPTION 'Bu işlem için admin yetkisi gerekli';
    END IF;
    
    -- Önce ilişkili kayıtları sil
    DELETE FROM order_items WHERE order_id = p_order_id;
    DELETE FROM courier_assignments WHERE order_id = p_order_id;
    
    -- Ana siparişi sil
    DELETE FROM orders WHERE id = p_order_id;
    
    RETURN TRUE;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Silme hatası: %', SQLERRM;
    RETURN FALSE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 5. RLS'yi etkinleştir
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;

COMMENT ON FUNCTION admin_delete_order IS 'Admin yetkisiyle sipariş ve ilişkili tüm verileri siler';

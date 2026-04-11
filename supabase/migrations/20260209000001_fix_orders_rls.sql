-- Fix orders RLS INSERT policy
-- Mevcut policy'leri sil
DROP POLICY IF EXISTS "orders_insert_policy" ON public.orders;
DROP POLICY IF EXISTS "orders_update_policy" ON public.orders;
DROP POLICY IF EXISTS "orders_select_policy" ON public.orders;
DROP POLICY IF EXISTS "orders_delete_policy" ON public.orders;

-- Yeni INSERT policy - Kullanıcı kendi siparişini oluşturabilir
CREATE POLICY "orders_insert_policy" 
ON public.orders 
FOR INSERT 
TO authenticated
WITH CHECK (
  auth.uid() = user_id
);

-- SELECT policy - Kullanıcı kendi siparişlerini görebilir, admin ve satıcı tümünü görebilir
CREATE POLICY "orders_select_policy" 
ON public.orders 
FOR SELECT 
TO authenticated
USING (
  auth.uid() = user_id 
  OR EXISTS (
    SELECT 1 FROM profiles 
    WHERE profiles.id = auth.uid() 
    AND profiles.role IN ('admin', 'seller')
  )
);

-- UPDATE policy - Sadece admin güncelleyebilir
CREATE POLICY "orders_update_policy" 
ON public.orders 
FOR UPDATE 
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM profiles 
    WHERE profiles.id = auth.uid() 
    AND profiles.role = 'admin'
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM profiles 
    WHERE profiles.id = auth.uid() 
    AND profiles.role = 'admin'
  )
);

-- DELETE policy - Sadece admin silebilir
CREATE POLICY "orders_delete_policy" 
ON public.orders 
FOR DELETE 
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM profiles 
    WHERE profiles.id = auth.uid() 
    AND profiles.role = 'admin'
  )
);

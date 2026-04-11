-- RLS Performans Optimizasyonu Migration
-- auth.uid() -> (select auth.uid()) dönüşümü ve çoklu policy birleştirme

-- ================================================================
-- POSTS TABLOSU
-- ================================================================

-- Mevcut sorunlu policy'leri kaldır
DROP POLICY IF EXISTS "Posts are viewable by everyone" ON posts;
DROP POLICY IF EXISTS "Users can delete own posts" ON posts;
DROP POLICY IF EXISTS "Users can update own posts" ON posts;
DROP POLICY IF EXISTS "posts_select_admin_policy" ON posts;
DROP POLICY IF EXISTS "posts_update_admin_policy" ON posts;
DROP POLICY IF EXISTS "posts_delete_admin_policy" ON posts;

-- Birleştirilmiş SELECT policy (herkes + admin)
CREATE POLICY "posts_select_unified"
ON posts FOR SELECT
TO public
USING (true);

-- Birleştirilmiş UPDATE policy (sahibi VEYA admin)
CREATE POLICY "posts_update_unified"
ON posts FOR UPDATE
TO authenticated
USING (
  user_id = (select auth.uid())
  OR EXISTS (
    SELECT 1 FROM profiles 
    WHERE id = (select auth.uid()) AND is_admin = true
  )
);

-- Birleştirilmiş DELETE policy (sahibi VEYA admin)
CREATE POLICY "posts_delete_unified"
ON posts FOR DELETE
TO authenticated
USING (
  user_id = (select auth.uid())
  OR EXISTS (
    SELECT 1 FROM profiles 
    WHERE id = (select auth.uid()) AND is_admin = true
  )
);

-- INSERT policy (sadece authenticated kullanıcılar)
DROP POLICY IF EXISTS "Users can insert posts" ON posts;
CREATE POLICY "posts_insert_unified"
ON posts FOR INSERT
TO authenticated
WITH CHECK (user_id = (select auth.uid()));

-- ================================================================
-- SUPPORT_TICKETS TABLOSU
-- ================================================================

-- Mevcut sorunlu policy'leri kaldır
DROP POLICY IF EXISTS "Admin tüm talepleri görebilir" ON support_tickets;
DROP POLICY IF EXISTS "Kullanıcılar kendi taleplerini görebilir" ON support_tickets;
DROP POLICY IF EXISTS "Admin talepleri güncelleyebilir" ON support_tickets;
DROP POLICY IF EXISTS "support_tickets_select_unified" ON support_tickets;
DROP POLICY IF EXISTS "support_tickets_update_unified" ON support_tickets;

-- Birleştirilmiş SELECT policy (sahibi VEYA admin)
CREATE POLICY "support_tickets_select_optimized"
ON support_tickets FOR SELECT
TO authenticated
USING (
  user_id = (select auth.uid())
  OR EXISTS (
    SELECT 1 FROM profiles 
    WHERE id = (select auth.uid()) AND is_admin = true
  )
);

-- Birleştirilmiş UPDATE policy (admin VEYA sahibi status değişikliği hariç)
CREATE POLICY "support_tickets_update_optimized"
ON support_tickets FOR UPDATE
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM profiles 
    WHERE id = (select auth.uid()) AND is_admin = true
  )
  OR user_id = (select auth.uid())
);

-- INSERT policy
DROP POLICY IF EXISTS "Kullanıcılar talep oluşturabilir" ON support_tickets;
CREATE POLICY "support_tickets_insert_optimized"
ON support_tickets FOR INSERT
TO authenticated
WITH CHECK (user_id = (select auth.uid()));

-- ================================================================
-- SUPPORT_TICKET_MESSAGES TABLOSU
-- ================================================================

-- Mevcut sorunlu policy'leri kaldır
DROP POLICY IF EXISTS "Admin tüm talep mesajlarını görebilir" ON support_ticket_messages;
DROP POLICY IF EXISTS "Kullanıcı kendi talep mesajlarını görebilir" ON support_ticket_messages;
DROP POLICY IF EXISTS "Admin taleplere mesaj yazabilir" ON support_ticket_messages;
DROP POLICY IF EXISTS "Kullanıcı kendi talebine mesaj yazabilir" ON support_ticket_messages;

-- Birleştirilmiş SELECT policy (sahibi VEYA admin)
CREATE POLICY "support_ticket_messages_select_optimized"
ON support_ticket_messages FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM support_tickets st 
    WHERE st.id = ticket_id 
    AND (st.user_id = (select auth.uid()) OR EXISTS (
      SELECT 1 FROM profiles 
      WHERE id = (select auth.uid()) AND is_admin = true
    ))
  )
);

-- Birleştirilmiş INSERT policy (sahibi VEYA admin)
CREATE POLICY "support_ticket_messages_insert_optimized"
ON support_ticket_messages FOR INSERT
TO authenticated
WITH CHECK (
  sender_id = (select auth.uid())
  AND EXISTS (
    SELECT 1 FROM support_tickets st 
    WHERE st.id = ticket_id 
    AND (st.user_id = (select auth.uid()) OR EXISTS (
      SELECT 1 FROM profiles 
      WHERE id = (select auth.uid()) AND is_admin = true
    ))
  )
);

-- ================================================================
-- PAYOUT_REQUESTS TABLOSU
-- ================================================================

-- Mevcut sorunlu policy'leri kaldır
DROP POLICY IF EXISTS "Adminler tüm ödeme isteklerini görebilir" ON payout_requests;
DROP POLICY IF EXISTS "Satıcılar kendi ödeme isteklerini görebilir" ON payout_requests;
DROP POLICY IF EXISTS "Adminler ödeme isteklerini güncelleyebilir" ON payout_requests;
DROP POLICY IF EXISTS "Satıcılar ödeme isteği oluşturabilir" ON payout_requests;

-- Birleştirilmiş SELECT policy (sahibi VEYA admin)
CREATE POLICY "payout_requests_select_optimized"
ON payout_requests FOR SELECT
TO authenticated
USING (
  seller_id = (select auth.uid())
  OR EXISTS (
    SELECT 1 FROM profiles 
    WHERE id = (select auth.uid()) AND is_admin = true
  )
);

-- INSERT policy (satıcılar)
CREATE POLICY "payout_requests_insert_optimized"
ON payout_requests FOR INSERT
TO authenticated
WITH CHECK (seller_id = (select auth.uid()));

-- UPDATE policy (adminler)
CREATE POLICY "payout_requests_update_optimized"
ON payout_requests FOR UPDATE
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM profiles 
    WHERE id = (select auth.uid()) AND is_admin = true
  )
);

-- ================================================================
-- SHOP_IMAGES BUCKET POLICY GÜNCELLEME
-- ================================================================

-- Mevcut policy'leri kaldır
DROP POLICY IF EXISTS "shop_images_public_access" ON storage.objects;
DROP POLICY IF EXISTS "shop_images_seller_insert" ON storage.objects;
DROP POLICY IF EXISTS "shop_images_seller_update" ON storage.objects;
DROP POLICY IF EXISTS "shop_images_seller_delete" ON storage.objects;
DROP POLICY IF EXISTS "shop_images_admin_all" ON storage.objects;

-- Public SELECT (okuma)
CREATE POLICY "shop_images_public_access"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'shop-images');

-- Satıcı INSERT (yükleme) - optimized
CREATE POLICY "shop_images_seller_insert"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'shop-images' 
  AND (storage.foldername(name))[1] IN (
    SELECT id::text FROM public.shops WHERE owner_id = (select auth.uid())
  )
);

-- Satıcı UPDATE - optimized
CREATE POLICY "shop_images_seller_update"
ON storage.objects FOR UPDATE
TO authenticated
USING (
  bucket_id = 'shop-images'
  AND (storage.foldername(name))[1] IN (
    SELECT id::text FROM public.shops WHERE owner_id = (select auth.uid())
  )
);

-- Satıcı DELETE - optimized
CREATE POLICY "shop_images_seller_delete"
ON storage.objects FOR DELETE
TO authenticated
USING (
  bucket_id = 'shop-images'
  AND (storage.foldername(name))[1] IN (
    SELECT id::text FROM public.shops WHERE owner_id = (select auth.uid())
  )
);

-- Admin ALL (tüm işlemler) - optimized
CREATE POLICY "shop_images_admin_all"
ON storage.objects FOR ALL
TO authenticated
USING (
  bucket_id = 'shop-images'
  AND EXISTS (
    SELECT 1 FROM public.profiles WHERE id = (select auth.uid()) AND is_admin = true
  )
);

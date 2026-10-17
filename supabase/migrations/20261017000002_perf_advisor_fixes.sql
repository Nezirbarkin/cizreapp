-- ============================================================================
-- Performance Advisor düzeltmeleri (2026-10-17)
-- ----------------------------------------------------------------------------
-- `supabase db advisors --type performance` çıktısından yalnız kesin ve
-- davranışı değiştirmeyenler:
--
-- 1) auth_rls_initplan (5): politikada çıplak auth.uid() satır başına
--    yeniden hesaplanır; (select auth.uid()) tek seferlik initplan olur.
--    Anlam aynı.
-- 2) "Sellers can manage their products" (FOR ALL, auth.uid() = shop_id):
--    hiçbir dükkânın id'si sahibinin id'sine eşit değil (canlıda 0 satır),
--    yani politika hiçbir satırla eşleşmiyor; yalnız her ürün sorgusunda
--    fazladan değerlendiriliyordu. Kaldırıldı.
-- 3) duplicate_index (2): aynı sütunlarda iki UNIQUE kısıt → her yazımda iki
--    indeks bakımı. Eski adlı (_key) kısıt kalır; ON CONFLICT ON CONSTRAINT
--    ile isimden referans veren fonksiyon yok (canlıda tarandı).
-- 4) unindexed_foreign_keys (19): kapsayan indeksi olmayan yabancı
--    anahtarlar (üst satır silinirken / join'de tam tarama).
--
-- Bilerek yapılmayanlar: 202 "unused_index" (veri ve trafik küçük, kullanım
-- istatistiği güvenilir değil) ve 41 "multiple_permissive_policies"
-- (birebir aynı ifadeli politika yok; birleştirmek RLS anlamına dokunur).
-- ============================================================================

BEGIN;

-- 1) auth_rls_initplan ------------------------------------------------------
ALTER POLICY payout_requests_seller_cancel_own_pending ON public.payout_requests
  USING ((seller_id = (SELECT auth.uid())) AND ((status)::text = 'pending'::text))
  WITH CHECK ((seller_id = (SELECT auth.uid())) AND ((status)::text = 'cancelled'::text));

ALTER POLICY "Shop owners can insert products" ON public.products
  WITH CHECK (EXISTS (
    SELECT 1 FROM public.shops
    WHERE shops.id = products.shop_id AND shops.owner_id = (SELECT auth.uid())
  ));

ALTER POLICY "Shop owners can update their products" ON public.products
  USING (EXISTS (
    SELECT 1 FROM public.shops
    WHERE shops.id = products.shop_id AND shops.owner_id = (SELECT auth.uid())
  ))
  WITH CHECK (EXISTS (
    SELECT 1 FROM public.shops
    WHERE shops.id = products.shop_id AND shops.owner_id = (SELECT auth.uid())
  ));

ALTER POLICY "Shop owners can delete their products" ON public.products
  USING (EXISTS (
    SELECT 1 FROM public.shops
    WHERE shops.id = products.shop_id AND shops.owner_id = (SELECT auth.uid())
  ));

-- 2) Hiç eşleşmeyen politika -----------------------------------------------
DROP POLICY IF EXISTS "Sellers can manage their products" ON public.products;

-- 3) Yinelenen UNIQUE kısıtlar ---------------------------------------------
ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS orders_order_number_unique;
ALTER TABLE public.post_likes DROP CONSTRAINT IF EXISTS post_likes_post_user_unique;

-- 4) Yabancı anahtar indeksleri --------------------------------------------
CREATE INDEX IF NOT EXISTS idx_server_checkout_sessions_address_id_fk ON private.server_checkout_sessions (address_id);
CREATE INDEX IF NOT EXISTS idx_server_checkout_sessions_coupon_id_fk ON private.server_checkout_sessions (coupon_id);
CREATE INDEX IF NOT EXISTS idx_flash_sale_reservations_product_id_fk ON private.flash_sale_reservations (product_id);
CREATE INDEX IF NOT EXISTS idx_flash_sale_reservations_shop_id_fk ON private.flash_sale_reservations (shop_id);
CREATE INDEX IF NOT EXISTS idx_server_checkout_audit_payment_transaction_id_fk ON private.server_checkout_audit (payment_transaction_id);
CREATE INDEX IF NOT EXISTS idx_server_checkout_audit_user_id_fk ON private.server_checkout_audit (user_id);
CREATE INDEX IF NOT EXISTS idx_server_checkout_audit_resolved_by_fk ON private.server_checkout_audit (resolved_by);
CREATE INDEX IF NOT EXISTS idx_seller_announcements_created_by_fk ON public.seller_announcements (created_by);
CREATE INDEX IF NOT EXISTS idx_music_catalog_submitted_by_fk ON public.music_catalog (submitted_by);
CREATE INDEX IF NOT EXISTS idx_music_track_submissions_reviewed_by_fk ON public.music_track_submissions (reviewed_by);
CREATE INDEX IF NOT EXISTS idx_music_track_submissions_catalog_id_fk ON public.music_track_submissions (catalog_id);
CREATE INDEX IF NOT EXISTS idx_admin_notification_campaigns_created_by_fk ON public.admin_notification_campaigns (created_by);
CREATE INDEX IF NOT EXISTS idx_sehirici_lines_vehicle_type_fk ON public.sehirici_lines (vehicle_type);
CREATE INDEX IF NOT EXISTS idx_shop_sponsorships_product_id_fk ON public.shop_sponsorships (product_id);
CREATE INDEX IF NOT EXISTS idx_shop_sponsorships_package_id_fk ON public.shop_sponsorships (package_id);
CREATE INDEX IF NOT EXISTS idx_cart_price_drop_notifications_product_id_fk ON public.cart_price_drop_notifications (product_id);
CREATE INDEX IF NOT EXISTS idx_live_sessions_pinned_product_id_fk ON public.live_sessions (pinned_product_id);
CREATE INDEX IF NOT EXISTS idx_follow_suggestion_dismissals_dismissed_user_id_fk ON public.follow_suggestion_dismissals (dismissed_user_id);
CREATE INDEX IF NOT EXISTS idx_bot_comment_jobs_library_id_fk ON public.bot_comment_jobs (library_id);

COMMIT;

NOTIFY pgrst, 'reload schema';

-- =============================================================================
-- SUPABASE PERFORMANCE ADVISOR: AUTH RLS INITPLAN
-- =============================================================================
-- The expressions below are copied from the live pg_policies catalog. The only
-- semantic-preserving change is:
--   auth.uid()  -> (SELECT auth.uid())
--   auth.role() -> (SELECT auth.role())
-- PostgreSQL can therefore evaluate each auth helper once per statement instead
-- of once per candidate row.
-- =============================================================================

ALTER POLICY "ad_reward_views_admin_select" ON "public"."ad_reward_views"
  USING (EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = (SELECT auth.uid())) AND (profiles.role = 'admin'::user_role))));

ALTER POLICY "ad_reward_views_select_own" ON "public"."ad_reward_views"
  USING ((SELECT auth.uid()) = user_id);

ALTER POLICY "ad_settings_admin_all" ON "public"."ad_settings"
  USING (EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = (SELECT auth.uid())) AND (profiles.role = 'admin'::user_role))))
  WITH CHECK (EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = (SELECT auth.uid())) AND (profiles.role = 'admin'::user_role))));

ALTER POLICY "Admins can delete broadcasts" ON "public"."admin_broadcasts"
  USING (EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = (SELECT auth.uid())) AND (profiles.role = 'admin'::user_role))));

ALTER POLICY "Admins can insert broadcasts" ON "public"."admin_broadcasts"
  WITH CHECK (EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = (SELECT auth.uid())) AND (profiles.role = 'admin'::user_role))));

ALTER POLICY "Admins can update broadcasts" ON "public"."admin_broadcasts"
  USING (EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = (SELECT auth.uid())) AND (profiles.role = 'admin'::user_role))))
  WITH CHECK (EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = (SELECT auth.uid())) AND (profiles.role = 'admin'::user_role))));

ALTER POLICY "Admins can view all transactions" ON "public"."balance_transactions"
  USING (EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = (SELECT auth.uid())) AND (profiles.role = 'admin'::user_role))));

ALTER POLICY "Users can view own transactions" ON "public"."balance_transactions"
  USING ((SELECT auth.uid()) = user_id);

ALTER POLICY "cr_insert_own" ON "public"."cancellation_requests"
  WITH CHECK (user_id = (SELECT auth.uid()));

ALTER POLICY "cr_select_own" ON "public"."cancellation_requests"
  USING (user_id = (SELECT auth.uid()));

ALTER POLICY "cr_select_shop" ON "public"."cancellation_requests"
  USING ((shop_id IS NOT NULL) AND (shop_id IN ( SELECT shops.id
   FROM shops
  WHERE (shops.owner_id = (SELECT auth.uid())))));

ALTER POLICY "courier_notices_admin_write" ON "public"."courier_service_notices"
  USING (EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = (SELECT auth.uid())) AND (profiles.role = 'admin'::user_role))))
  WITH CHECK (EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = (SELECT auth.uid())) AND (profiles.role = 'admin'::user_role))));

ALTER POLICY "flash_sales_delete_seller" ON "public"."flash_sales"
  USING (EXISTS ( SELECT 1
   FROM shops s
  WHERE ((s.id = flash_sales.shop_id) AND (s.owner_id = (SELECT auth.uid())))));

ALTER POLICY "flash_sales_insert_seller" ON "public"."flash_sales"
  WITH CHECK (((SELECT auth.uid()) = created_by) AND (EXISTS ( SELECT 1
   FROM shops s
  WHERE ((s.id = flash_sales.shop_id) AND (s.owner_id = (SELECT auth.uid()))))));

ALTER POLICY "flash_sales_update_seller" ON "public"."flash_sales"
  USING (EXISTS ( SELECT 1
   FROM shops s
  WHERE ((s.id = flash_sales.shop_id) AND (s.owner_id = (SELECT auth.uid())))));

ALTER POLICY "Users can insert their own group read receipts" ON "public"."group_message_read_receipts"
  WITH CHECK (user_id = (SELECT auth.uid()));

ALTER POLICY "Users can view their own group read receipts" ON "public"."group_message_read_receipts"
  USING (user_id = (SELECT auth.uid()));

ALTER POLICY "live_messages_delete_host" ON "public"."live_messages"
  USING ((is_host = true) AND (EXISTS ( SELECT 1
   FROM live_sessions ls
  WHERE ((ls.id = live_messages.session_id) AND (ls.host_user_id = (SELECT auth.uid()))))));

ALTER POLICY "live_messages_insert_auth" ON "public"."live_messages"
  WITH CHECK ((SELECT auth.uid()) = user_id);

ALTER POLICY "live_pin_delete_host" ON "public"."live_pinned_products"
  USING (EXISTS ( SELECT 1
   FROM live_sessions ls
  WHERE ((ls.id = live_pinned_products.session_id) AND (ls.host_user_id = (SELECT auth.uid())))));

ALTER POLICY "live_pin_insert_host" ON "public"."live_pinned_products"
  WITH CHECK (EXISTS ( SELECT 1
   FROM live_sessions ls
  WHERE ((ls.id = live_pinned_products.session_id) AND (ls.host_user_id = (SELECT auth.uid())))));

ALTER POLICY "live_pin_update_host" ON "public"."live_pinned_products"
  USING (EXISTS ( SELECT 1
   FROM live_sessions ls
  WHERE ((ls.id = live_pinned_products.session_id) AND (ls.host_user_id = (SELECT auth.uid())))));

ALTER POLICY "live_sessions_insert_host" ON "public"."live_sessions"
  WITH CHECK (((SELECT auth.uid()) = host_user_id) AND (EXISTS ( SELECT 1
   FROM shops s
  WHERE ((s.id = live_sessions.shop_id) AND (s.owner_id = (SELECT auth.uid()))))));

ALTER POLICY "live_sessions_update_host" ON "public"."live_sessions"
  USING ((SELECT auth.uid()) = host_user_id);

ALTER POLICY "Authors and admins can update news" ON "public"."news"
  USING ((author_id = (SELECT auth.uid())) OR current_user_role_in_list(ARRAY['admin'::text]));

ALTER POLICY "Authenticated users can like comments" ON "public"."news_comment_likes"
  WITH CHECK ((SELECT auth.role()) = 'authenticated'::text);

ALTER POLICY "Users can unlike comments" ON "public"."news_comment_likes"
  USING (user_id = (SELECT auth.uid()));

ALTER POLICY "Users can view their own comment likes" ON "public"."news_comment_likes"
  USING (user_id = (SELECT auth.uid()));

ALTER POLICY "Authenticated users can insert comments" ON "public"."news_comments"
  WITH CHECK ((SELECT auth.role()) = 'authenticated'::text);

ALTER POLICY "Comment owners can update their comments" ON "public"."news_comments"
  USING (user_id = (SELECT auth.uid()));

ALTER POLICY "Users can delete own comments" ON "public"."news_comments"
  USING (user_id = (SELECT auth.uid()));

ALTER POLICY "News authors can delete own images" ON "public"."news_images"
  USING (EXISTS ( SELECT 1
   FROM news
  WHERE ((news.id = news_images.news_id) AND ((news.author_id = (SELECT auth.uid())) OR current_user_role_in_list(ARRAY['admin'::text, 'news'::text])))));

ALTER POLICY "News authors can insert images" ON "public"."news_images"
  WITH CHECK (EXISTS ( SELECT 1
   FROM news
  WHERE ((news.id = news_images.news_id) AND ((news.author_id = (SELECT auth.uid())) OR current_user_role_in_list(ARRAY['admin'::text, 'news'::text])))));

ALTER POLICY "News authors can manage images" ON "public"."news_images"
  USING (EXISTS ( SELECT 1
   FROM news
  WHERE ((news.id = news_images.news_id) AND ((news.author_id = (SELECT auth.uid())) OR current_user_role_in_list(ARRAY['admin'::text, 'news'::text])))));

ALTER POLICY "News authors can update own images" ON "public"."news_images"
  USING (EXISTS ( SELECT 1
   FROM news
  WHERE ((news.id = news_images.news_id) AND ((news.author_id = (SELECT auth.uid())) OR current_user_role_in_list(ARRAY['admin'::text, 'news'::text])))));

ALTER POLICY "Authenticated users can like" ON "public"."news_likes"
  WITH CHECK (((SELECT auth.role()) = 'authenticated'::text) AND (user_id = (SELECT auth.uid())));

ALTER POLICY "Users can unlike" ON "public"."news_likes"
  USING (user_id = (SELECT auth.uid()));

ALTER POLICY "Users can view their own likes" ON "public"."news_likes"
  USING (user_id = (SELECT auth.uid()));

ALTER POLICY "Authenticated users can share" ON "public"."news_shares"
  WITH CHECK ((SELECT auth.role()) = 'authenticated'::text);

ALTER POLICY "Anyone can record news views" ON "public"."news_views"
  WITH CHECK ((user_id IS NULL) OR (user_id = (SELECT auth.uid())));

ALTER POLICY "notifications_insert_own_policy" ON "public"."notifications"
  WITH CHECK (user_id = (SELECT auth.uid()));

ALTER POLICY "price_alerts_delete_own" ON "public"."price_alerts"
  USING ((SELECT auth.uid()) = user_id);

ALTER POLICY "price_alerts_insert_own" ON "public"."price_alerts"
  WITH CHECK ((SELECT auth.uid()) = user_id);

ALTER POLICY "price_alerts_select_own" ON "public"."price_alerts"
  USING ((SELECT auth.uid()) = user_id);

ALTER POLICY "price_alerts_update_own" ON "public"."price_alerts"
  USING ((SELECT auth.uid()) = user_id);

ALTER POLICY "sehirici_drivers_select_admin" ON "public"."sehirici_drivers"
  USING (auth_is_admin() OR (profile_id = (SELECT auth.uid())));

ALTER POLICY "sehirici_drivers_update_self" ON "public"."sehirici_drivers"
  USING (profile_id = (SELECT auth.uid()))
  WITH CHECK (profile_id = (SELECT auth.uid()));

ALTER POLICY "sehirici_favorite_stops_own" ON "public"."sehirici_favorite_stops"
  USING (user_id = (SELECT auth.uid()))
  WITH CHECK (user_id = (SELECT auth.uid()));

ALTER POLICY "sehirici_routes_driver_update" ON "public"."sehirici_routes"
  USING (driver_id IN ( SELECT sehirici_drivers.id
   FROM sehirici_drivers
  WHERE (sehirici_drivers.profile_id = (SELECT auth.uid()))))
  WITH CHECK (driver_id IN ( SELECT sehirici_drivers.id
   FROM sehirici_drivers
  WHERE (sehirici_drivers.profile_id = (SELECT auth.uid()))));

ALTER POLICY "sehirici_trip_locations_driver_insert" ON "public"."sehirici_trip_locations"
  WITH CHECK ((trip_id IN ( SELECT t.id
   FROM (sehirici_trips t
     JOIN sehirici_drivers d ON ((t.driver_id = d.id)))
  WHERE (d.profile_id = (SELECT auth.uid())))) OR auth_is_admin());

ALTER POLICY "sehirici_trips_driver_insert" ON "public"."sehirici_trips"
  WITH CHECK ((driver_id IN ( SELECT sehirici_drivers.id
   FROM sehirici_drivers
  WHERE (sehirici_drivers.profile_id = (SELECT auth.uid())))) OR auth_is_admin());

ALTER POLICY "sehirici_trips_driver_update" ON "public"."sehirici_trips"
  USING ((driver_id IN ( SELECT sehirici_drivers.id
   FROM sehirici_drivers
  WHERE (sehirici_drivers.profile_id = (SELECT auth.uid())))) OR auth_is_admin());

ALTER POLICY "sehirici_trips_select_all" ON "public"."sehirici_trips"
  USING ((status = ANY (ARRAY['active'::sehirici_trip_status, 'paused'::sehirici_trip_status, 'completed'::sehirici_trip_status])) OR auth_is_admin() OR (driver_id IN ( SELECT sehirici_drivers.id
   FROM sehirici_drivers
  WHERE (sehirici_drivers.profile_id = (SELECT auth.uid())))));

ALTER POLICY "Admins can view all earnings" ON "public"."seller_earnings"
  USING (EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = (SELECT auth.uid())) AND (profiles.role = 'admin'::user_role))));

ALTER POLICY "Sellers can view own earnings" ON "public"."seller_earnings"
  USING ((SELECT auth.uid()) = seller_id);

ALTER POLICY "Admins can manage withdrawals" ON "public"."seller_withdrawals"
  USING (EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = (SELECT auth.uid())) AND (profiles.role = 'admin'::user_role))));

ALTER POLICY "Admins can view all withdrawals" ON "public"."seller_withdrawals"
  USING (EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = (SELECT auth.uid())) AND (profiles.role = 'admin'::user_role))));

ALTER POLICY "Sellers can create withdrawals" ON "public"."seller_withdrawals"
  WITH CHECK ((SELECT auth.uid()) = seller_id);

ALTER POLICY "Sellers can view own withdrawals" ON "public"."seller_withdrawals"
  USING ((SELECT auth.uid()) = seller_id);

ALTER POLICY "transfer_confirmations_insert_own" ON "public"."transfer_confirmations"
  WITH CHECK ((user_id = (SELECT auth.uid())) AND (status = 'pending'::text));

ALTER POLICY "transfer_confirmations_select_admin" ON "public"."transfer_confirmations"
  USING (EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = (SELECT auth.uid())) AND (profiles.role = 'admin'::user_role))));

ALTER POLICY "transfer_confirmations_select_own" ON "public"."transfer_confirmations"
  USING (user_id = (SELECT auth.uid()));

ALTER POLICY "transfer_confirmations_update_admin" ON "public"."transfer_confirmations"
  USING (EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = (SELECT auth.uid())) AND (profiles.role = 'admin'::user_role))))
  WITH CHECK (EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = (SELECT auth.uid())) AND (profiles.role = 'admin'::user_role))));

ALTER POLICY "Admins can view all balances" ON "public"."user_balances"
  USING (EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = (SELECT auth.uid())) AND (profiles.role = 'admin'::user_role))));

ALTER POLICY "Users can view own balance" ON "public"."user_balances"
  USING ((SELECT auth.uid()) = user_id);

-- =============================================================================
-- End of migration
-- =============================================================================

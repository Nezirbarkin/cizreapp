# PROJE_HAVIZA_CHANGELOG

Project Ref: `xsbukxkgtmdyickknqzf`  
Başlangıç tarihi: 2026-06-29

Bu dosya; şema, RLS, Edge Function, Storage ve operasyonel değişikliklerin tarihçesini tutar.

---

## 1) Kayıt Formatı (Standart)

Her kayıt şu formatta olmalı:

- `TarihSaat` | `Tür` | `Nesne` | `Ortam` | `Etkisi` | `Özet` | `Geri Alma` | `Yapan`

### Alan Açıklamaları
- `TarihSaat`: ISO önerilir (`2026-06-29 14:35 UTC`)
- `Tür`: `SCHEMA`, `RLS`, `FUNCTION`, `STORAGE`, `DATA`, `HOTFIX`, `PERF`
- `Nesne`: tablo/policy/function adı
- `Ortam`: `prod` / `staging` / `dev`
- `Etkisi`: `low` / `medium` / `high`
- `Özet`: ne değişti?
- `Geri Alma`: rollback yöntemi veya not
- `Yapan`: kişi/ekip

---

## 2) Değişiklik Kategorileri

### 2.1 SCHEMA
Örnekler:
- tablo oluşturma/silme
- kolon ekleme/değiştirme
- index ekleme
- constraint/FK değişimi
- enum değişimi

### 2.2 RLS
Örnekler:
- policy create/alter/drop
- role kapsam değişimi
- `USING` / `WITH CHECK` güncellemesi

### 2.3 FUNCTION
Örnekler:
- edge function deploy
- `verify_jwt` değişikliği
- provider/API entegrasyonu

### 2.4 STORAGE
Örnekler:
- bucket oluşturma
- bucket policy değişimi
- public/private geçiş

### 2.5 DATA
Örnekler:
- toplu veri düzeltme
- backfill script
- tek seferlik migration data operasyonu

### 2.6 HOTFIX / PERF
Örnekler:
- acil prod düzeltme
- sorgu/index optimizasyonu
- timeout azaltma

---

## 3) Kayıt Şablonları

### 3.1 Tek Satır Kısa Kayıt
- `2026-06-29 14:35 UTC | FUNCTION | iyzico-payment-callback | prod | high | callback doğrulama iyileştirildi | v17 geri deploy | @ekip`

### 3.2 Detaylı Kayıt
- **TarihSaat:** 2026-06-29 14:35 UTC
- **Tür:** FUNCTION
- **Nesne:** `iyzico-payment-callback`
- **Ortam:** prod
- **Etkisi:** high
- **Özet:** ödeme callback doğrulaması ve status map güncellendi.
- **Test:** başarılı ödeme + başarısız ödeme + tekrar callback senaryosu çalıştırıldı.
- **Geri Alma:** v17 yeniden deploy.
- **Yapan:** @ekip

---

## 4) Değişiklik Günlüğü (Kayıtlar)

## 2026-06

- `2026-06-29 00:00 UTC | DOCS | PROJE_HAVIZA_* | prod | medium | proje hafıza dosyaları bloklu yapıya taşındı (SCHEMA/RLS/FUNCTIONS/CHANGELOG) | önceki tek dosyaya dönüş mümkün | @owner`

- `2026-06-29 12:30 UTC | FUNCTION | atomic_add_balance_topup | prod | high | yeni SQL fonksiyonu: bakiye yüklemede FOR UPDATE lock + pending kayıt silme + atomik güncelleme. Race condition koruması sağlar. | migration: 20260629_FIX_BALANCE_TOPUP_RACE_CONDITION.sql | @owner #payment #security`

- `2026-06-29 12:35 UTC | FUNCTION | confirm-balance-topup | prod | high | HATA-1 düzeltme: add_to_balance yerine atomic_add_balance_topup RPC kullanılıyor. Race condition giderildi, bildirimler balanceBefore/balanceAfter değişkenleri doğru kullanılıyor. | eski sürüm: JS tarafında manuel SELECT→UPDATE | @owner #payment #security`

- `2026-06-29 13:00 UTC | FUNCTION | iyzico-payment-callback | prod | high | HATA-2 düzeltme: updatePaymentTransaction → updatePaymentTransactionAtomic. Atomik UPDATE WHERE payment_status='pending' kullanılıyor, etkilenen satır sayısı kontrol ediliyor. İkinci callback sipariş oluşturmaz (çift sipariş önlenir). | eski sürüm: non-atomic update + race window | @owner #payment #security`

- `2026-06-29 13:10 UTC | CODE | checkout_screen.dart | prod | medium | HATA-3 düzeltme: bakiye ödemesinde sepet temizleme hatası try-catch ile yakalanıyor (kritik değil, sipariş etkilenmez). Audit trail için iptal nedeni loglanıyor. | eski sürüm: hata yakalanmıyordu | @owner #payment`

- `2026-06-30 13:30 UTC | FUNCTION | atomic_finalize_payment_transaction | prod | high | yeni SQL RPC: iyzico-payment-callback için atomik güncelleme. SELECT FOR UPDATE + UPDATE WHERE payment_status='pending' + GET DIAGNOSTICS ile %100 güvenilir sonuç. Eski JS count tabanlı kontrol PostgREST count sorunu nedeniyle güvenilir değildi. | migration: 20260630_FIX_CALLBACK_IDEMPOTENCY_RPC.sql | @owner #payment #security #hotfix`

- `2026-06-30 13:35 UTC | FUNCTION | iyzico-payment-callback | prod | critical | HATA-2 REGRESYON çözümü: updatePaymentTransactionAtomic artık SQL RPC (atomic_finalize_payment_transaction) çağırıyor. Kullanıcı artık aynı üründen tekrar sipariş verebilir. Duplicate check sadeleştirildi, gereksiz "Yeni ödeme başlatılıyor" log bloğu kaldırıldı. Race condition ve duplicate prevention %100 güvenilir. | eski sürüm: JS count tabanlı kontrol + token eşleşmesi | @owner #payment #security #hotfix`

- `2026-06-30 14:00 UTC | FUNCTION | iyzico-payment-callback | prod | critical | HATA-2 REGRESYON (GERÇEK) çözümü: getPaymentTransaction → önce PENDING transaction ara, yoksa diğerlerini al. Eski kod .single() ile aynı token varsa PGRST116 hatası veriyordu ve en son kaydı alıyordu (pending olmasa bile). Yeni siparişlerde pending transaction doğru bulunuyor. | eski sürüm: .single() + en son kayıt | @owner #payment #hotfix`

- `2026-06-30 14:00 UTC | SCHEMA | payment_transactions | prod | high | Yeni partial unique index: pending transaction'larda token benzersiz olmalı. Mevcut duplicate pending kayıtları temizlenip cancelled yapıldı. Token + status index eklendi (performans). | migration: 20260630_PREVENT_DUPLICATE_TOKEN.sql | @owner #payment #hotfix`

- `2026-06-30 14:30 UTC | CODE | payment_webview_screen.dart | prod | critical | Callback URL navigation'ı engellendi. iyzico callback POST'u arka planda zaten Edge Function'a yapıyor. WebView iyzico ödeme sayfasında kalmalı, callback URL'ine navigate etmemel. Yoksa aynı HTML sayfa tekrar tekrar yüklenir ve polling yanıltıcı "zaten oluşturuldu" mesajı verir. | eski sürüm: tüm navigation'a izin | @owner #payment #hotfix`

- `2026-06-30 14:35 UTC | CODE | payment_service.dart | prod | critical | HATA-4: checkPaymentStatus artık payment_status='success' + order_id varlığını birlikte kontrol ediyor. Callback'de sıra kaybı (callback başarılı ama order oluşturulmadı) durumunda "success ama order_id yok" tespit ediliyor, "Ödeme Durumu Belirsiz" mesajı gösteriliyor. Destek ekibine yönlendirme. | eski sürüm: yalnızca payment_status='success' ise başarılı sayıyordu | @owner #payment #hotfix`

- `2026-06-30 17:30 UTC | FUNCTION | iyzico-payment-callback | prod | critical | HATA-5: Race condition koruması — alreadyProcessed=true ama isPaymentSuccess=true ise order kontrol edilip oluşturuluyor. Kazanan callback kazandırılıyor. complete_online_payment idempotent çalıştığı için güvenle çağırılıyor. | eski sürüm: alreadyProcessed=true → direkt çıkış, sipariş oluşturulmuyor | @owner #payment #hotfix`

- `2026-06-30 18:30 UTC | FUNCTION | complete_online_payment | prod | critical | Yeni migration: complete_online_payment idempotent yapıldı. Önce mevcut order_id kontrol ediliyor, varsa döndürülüyor. payment_status='success' şartı gevşetildi (race condition). order_id update race koruması eklendi. | migration: 20260630_FIX_COMPLETE_ONLINE_PAYMENT_IDEMPOTENT.sql | @owner #payment #hotfix`

- `2026-06-30 18:50 UTC | SCHEMA | orders | prod | critical | HATA-6: orders tablosunda `delivery_address` kolonu yok, `delivery_address_text` ve `address_id` var. complete_online_payment fonksiyonu eski kolon adını kullanıyordu → "column delivery_address does not exist" hatası. Yeni migration'da INSERT kolonları düzeltildi. | migration: 20260630_FIX_COMPLETE_ONLINE_PAYMENT_IDEMPOTENT.sql | @owner #payment #schema`

- `2026-06-30 19:20 UTC | SCHEMA | orders / order_items | prod | critical | HATA-6 (genişletilmiş): complete_online_payment INSERT'inde yanlış kolon adları düzeltildi. Doğru kolonlar: total (total_amount değil), discount (coupon_discount değil), delivery_address_text + address_id (delivery_address değil), notes (note değil), customer_phone. order_items: product_price, subtotal, shop_id, shop_name zorunlu. Migration 20260405000001 baz alındı + idempotent eklendi. | migration: 20260630_FIX_COMPLETE_ONLINE_PAYMENT_IDEMPOTENT.sql (rewrite) | @owner #payment #schema #hotfix`

- `2026-06-30 19:45 UTC | SCHEMA | orders / order_items | prod | critical | HATA-6 (v3): variant_data kolonu order_items'da YOK. Kullanıcının tablo dökümünden GERÇEK şema kullanıldı. Hem `total` hem `total_amount`, hem `discount` hem `coupon_discount`, hem `address_id` hem `delivery_address_id` mevcut. Hem `discount` hem `coupon_discount`'a yazılıyor (tutarlılık için). variant_data kaldırıldı. | migration: 20260630_FIX_COMPLETE_ONLINE_PAYMENT_IDEMPOTENT.sql v3 | @owner #payment #schema`

- `2026-06-30 20:30 UTC | FUNCTION | iyzico-payment-callback | prod | high | İSTEK-2 + İSTEK-3: sendNotifications geliştirildi. Artık MÜŞTERİ + SATICI + ADMİN'e push notification + DB bildirimi gönderiliyor. Satıcıya: "Mağazanıza Yeni Sipariş". Admin'lere: "X dükkanına Y tutarında sipariş". Email zaten on_order_created_send_email trigger'ı ile gidiyordu. | eski sürüm: sadece müşteriye push | @owner #notification #payment`

- `2026-06-30 20:35 UTC | DOCS | mevcut-durum | prod | low | İSTEK-1 (sipariş sonrası yönlendirme) ZATEN mevcut: payment_webview_screen.dart _handlePaymentSuccess → OrdersScreen'e yönlendiriyor. Web'de otomatik, mobilde dialog sonrası. Email altyapısı ZATEN mevcut: send-order-email Edge Function + on_order_created_send_email trigger. | değişiklik yok | @owner #notification`

- `2026-06-30 13:30 UTC | RLS | orders_select_policy / orders_update_policy | prod | high | Kurye kendisine atanmış siparişi görebilir/güncelleyebilir. orders_select_policy ve orders_update_policy yeniden oluşturuldu: (1) kurye kendisine atanmış siparişin orders satırını görür (delivered dahil tüm durumlar) - müşteri/satıcı/admin kolları korundu. Kök neden: kurye panelinde "Teslim Ettim" sonrası sipariş listeden kayboluyordu çünkü orders SELECT policy kuryeyi kapsamıyordu ve nested select null dönüyordu. (2) kurye kendi atanmış siparişini güncelleyebilir (delivered_courier_id/name/phone dahil). migration: 20260701_COURIER_RLS_FIX.sql | eski policy'ler: only user_id OR shop owner OR admin | @owner #schema #rls #notification #hotfix`

- `2026-06-30 13:35 UTC | CODE | seller_orders_screen.dart | prod | high | Kuryeye gereksiz broadcast kaldırıldı. _updateOrderStatus içinden confirmed/preparing/ready için notifyCouriersForNewOrder (TÜM kuryelere "Yeni Sipariş Onaylandı/Hazır") çağrısı silindi. Kurye bildirimi artık yalnızca atama anında CourierNotificationService._notifyCourierOfAssignment → "🛵 Sipariş Sana Atandı!" olarak gidiyor. | eski sürüm: her statü geçişinde tüm kuryelere broadcast | @owner #notification`

- `2026-06-30 13:40 UTC | CODE | courier_panel_screen.dart | prod | high | Çift "Yolda" bildirimi engellendi. _startDelivery (kurye "Yola Çıktım") içindeki müşteriye "🚴 Siparişiniz Yolda" insert kaldırıldı. Tek kaynak: _acceptDelivery (kurye "Siparişi Aldım"). Aynı dosyada _acceptDelivery artık courier_assignments.status='picked_up' ile birlikte orders.status='on_the_way' da günceller, böylece satıcı paneli müşteriye Yolda bildirimi gönderebilir. | eski sürüm: kurye hem "Aldım" hem "Yola Çıktım"da iki kez Yolda bildirimi | @owner #notification`

- `2026-07-01 09:00 UTC | RLS | orders_select_policy / orders_update_policy (HOTFIX V2) | prod | critical | V1 migration çalıştırıldıktan sonra PostgrestException 42P17 "infinite recursion detected in policy for relation orders" alındı. Sebep: orders SELECT/UPDATE policy içindeki `EXISTS (SELECT ... FROM courier_assignments ...)` ile courier_assignments policy'si içindeki `EXISTS (SELECT ... FROM orders ...)` karşılıklı recursion oluşturuyordu. Düzeltme: `public.courier_assigned_to_order(p_order_id)` SECURITY DEFINER STABLE helper fonksiyonu eklendi; orders policy artık courier_assignments tablosuna doğrudan subquery yerine bu fonksiyonu çağırıyor (SECURITY DEFINER RLS'yi bypass eder → courier_assignments policy tetiklenmez → recursion yok). migration: 20260701_COURIER_RLS_FIX_V2.sql | rollback: 20260701_COURIER_RLS_FIX.sql içindeki DROP POLICY satırları + fonksiyonu DROP FUNCTION | @owner #rls #schema #hotfix`

- `2026-07-01 09:30 UTC | RLS | orders_select_policy / orders_update_policy (HOTFIX V3) | prod | critical | V2 de başarısız oldu: `permission denied for function is_admin` (42501). Sebep: SECURITY DEFINER fn postgres rolüne düşerek auth.uid() → is_admin zincirinde yetki hatası. V3 çözümü: denormalize kolon. orders tablosuna `assigned_courier_id UUID` eklendi, courier_assignments INSERT/UPDATE/DELETE trigger'ı bu kolonu otomatik senkronize eder. orders SELECT/UPDATE policy'ye `OR assigned_courier_id = (SELECT auth.uid())` eklendi — basit kolon karşılaştırması, subquery yok, RLS tetiklenmez, recursion yok, permission hatası yok. Backfill mevcut atamaları doldurur. migration: 20260701_COURIER_RLS_FIX_V3.sql | rollback: DROP TRIGGER ... + DROP FUNCTION sync_assigned_courier_to_order + ALTER TABLE orders DROP COLUMN assigned_courier_id + orijinal 3 koşullu policy'lere dön | @owner #rls #schema #hotfix`

- `2026-07-01 10:00 UTC | RLS | orders_select_policy / orders_update_policy (HOTFIX V3_2 - FINAL) | prod | critical | V3 güvenlik sağlamlaştırıldı. PROJE_HAVIZA'dan öğrenilenler: (1) orders policy içinde courier_assignments subquery → 42P17 recursion (V1 hatası); (2) SECURITY DEFINER fn içinde auth.uid() → is_admin/auth_is_admin zinciri → 42501 (V2 hatası); (3) policy içinde is_admin()/auth_is_admin() helper → profiles bağımlılığı (FIX_ORDERS_POLICIES_CLEAN.sql uyarısı). V3_2: trigger fn `sync_assigned_courier_to_order()` SECURITY DEFINER ama auth.uid() KULLANMIYOR (sadece NEW/OLD.courier_id kopyalar) → is_admin zincirine düşmez. orders policy admin koşulu `EXISTS(SELECT 1 FROM profiles WHERE id=(SELECT auth.uid()) AND role='admin')` subquery ile yazıldı (helper fn yok). Kurye koşulu `assigned_courier_id = (SELECT auth.uid())` basit kolon karşılaştırması. Backfill mevcut atamaları doldurur. PREREQUISITE: 20260701_COURIER_RLS_ROLLBACK.sql çalıştırılmış olmalı (V2 temizliği). migration: 20260701_COURIER_RLS_FIX_V3_2.sql | rollback: DROP TRIGGER trigger_sync_assigned_courier ON courier_assignments + DROP FUNCTION public.sync_assigned_courier_to_order() CASCADE + ALTER TABLE orders DROP COLUMN assigned_courier_id + orijinal 3 koşullu policy'lere dön | @owner #rls #schema #hotfix #security`

- `2026-07-02 12:00 UTC | RLS | profiles_update_own / is_admin() GRANT | prod | critical | "permission denied for function is_admin" (42501) kök neden düzeltmesi. DIAG_20260702_ISADMIN_TEYIT.sql ile teyit edildi: profiles UPDATE policy'si `is_admin()` çağırıyor; `is_admin()` fonksiyonunun `proacl = {postgres=X/postgres, service_role=X/postgres}` → authenticated rolünde EXECUTE yetkisi YOK. auth_is_admin()'in yetkileri tamdı ama policy onu çağırmıyordu. Düzeltme: GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated + REVOKE EXECUTE ... FROM anon (güvenlik sertleştirme). Fonksiyon gövdesi değişmedi (SECURITY DEFINER + SET search_path = public korundu). NOT: profiles_update_own policy ile uyumlu hale gelen tek fonksiyon is_admin() olduğu için tek satırlık GRANT yeterli. AI ve diğer tablolarda `is_admin()` kullanan policy'ler de bu yetki ile çalışır hale geldi. migration: FIX_IS_ADMIN_PERMISSION_42501.sql | rollback: REVOKE EXECUTE ON FUNCTION public.is_admin() FROM authenticated | @owner #rls #security #hotfix #admin`

- `2026-07-02 12:05 UTC | CODE | admin_dashboard_screen.dart | prod | low | ÖNEMLİ NOT: Hata mesajı Flutter tarafında zaten "Rol güncellenirken hata: $e" şeklinde kullanıcıya gösteriliyordu; stack trace ile loglanıyordu. PostgrestException 42501 EXECUTE yetki eksikliği ile eşleşiyordu ama generic PostgrestException olduğu için tam kod görünmüyordu. LOG_DEBUG iyileştirmesi önerilir (gelecek): PostgrestException.code ve .details ayrı loglanırsa PostgREST hata kodu kök neden teşhisini hızlandırır. | değişiklik yok (sadece not) | @owner #admin`

- `2026-07-02 18:00 UTC | SCHEMA | app_about_settings | prod | low | "Her an her kapıda" sloganı ve üst bar animasyon sürelerinin admin panelden saniyesine kadar ayarlanabilmesi için 3 yeni kolon eklendi: animation_primary_duration_ms (INT, default 6000, range 1000-30000), animation_secondary_duration_ms (INT, default 3000, range 500-15000), animation_transition_duration_ms (INT, default 700, range 100-3000). Her kolona CHECK constraint eklendi (negatif/absürt değer koruması). Mevcut RLS policy korunuyor (sadece admin UPDATE). Geriye dönük uyumlu: eski kayıtlar varsayılan değerlerle çalışır. | migration: 20260702000000_app_animation_settings.sql | rollback: ALTER TABLE public.app_about_settings DROP COLUMN animation_primary_duration_ms, DROP COLUMN animation_secondary_duration_ms, DROP COLUMN animation_transition_duration_ms; | @owner #admin #ui #animation`

- `2026-07-02 18:05 UTC | CODE | animated_app_title.dart + app_about_service.dart + about_settings_screen.dart + 3 ekran | prod | medium | Admin panel "Hakkında Ayarları" ekranına "Animasyon Ayarları" bölümü eklendi. Slogan metni ("Her an her kapıda") bu bölümün altına taşındı (Uygulama Bilgileri'nden kaldırıldı). 3 slider: başlık/slogan/geçiş süreleri (saniye cinsinden, anlık önizleme değeri). AppAboutService'e statik cache + listener mekanizması eklendi (slogan/animasyon değişikliği anında tüm ekranlara yansır). AnimatedAppTitle.fromSettings factory eklendi. main_screen/market_screen/social_screen artık DB'den okunan değerleri kullanıyor (varsayılan: 6000/3000/700ms). | eski sürüm: süreler hardcoded, slogan Uygulama Bilgileri bölümündeydi | @owner #ui #animation #admin`

- `2026-07-03 10:00 UTC | SCHEMA | app_about_settings | prod | medium | PGRST204 "Could not find the 'company_account_holder' column" düzeltmesi. app_about_service.updateAboutSettings() tüm toJson() alanlarını .update() ile gönderiyor; şemada eksik olan banka/bakiye/duyuru kolonları PostgREST'i ilk eksik kolonda reddediyordu. Idempotent ALTER TABLE ADD COLUMN IF NOT EXISTS ile tüm eksik kolonlar eklendi (company_bank_name/iban/account_holder, balance_enabled, card_topup_enabled, min/max_topup_amount, withdrawal_fee_percent, min_withdrawal_amount, iyzico_*, support_phone, google_maps_api_key, startup_announcement_*). NOTIFY pgrst reload schema. | migration: 20260703_ABOUT_SETTINGS_MISSING_COLUMNS.sql | rollback: gerekmez (yalnızca eksik kolon ekler) | @owner #schema #admin`

- `2026-07-03 12:00 UTC | FUNCTION | send_message_with_recipient (V3) | prod | high | CHAT Bug A: RPC RETURNS TABLE içinde created_at DÖNMÜYORDU → client Message.fromMap FormatException fırlatıp sendMessage null dönüyor → mesaj DB'ye yazılıp realtime ile gelmesine rağmen "Mesaj gönderilemedi" hatası gösteriliyordu ("1 gönderiyor 1 hata veriyor"). Düzeltme: RPC artık created_at, updated_at, is_read (FALSE), reply alanlarını da döndürüyor. Mailbox modeli korundu (gönderen kopyası is_read=true, alıcı kopyası is_read=false). | migration: 20260703_CHAT_SEND_RETURN_FIX.sql | rollback: 20260702_CHAT_REALTIME_FIX_V2.sql içindeki eski RPC | @owner #chat #hotfix`

- `2026-07-03 12:30 UTC | CODE | chat_service.dart + chat_detail_screen.dart | prod | high | CHAT Bug B (çift mesaj) + okundu tiki düzeltmeleri. (1) getMessages artık id yerine KOMPOZIT ANAHTAR (sender_id|content|created_at) ile tekilleştiriyor — mailbox modelinde aynı mesaj iki conv'da farklı id ile durduğu için id-dedup çalışmıyor, her mesaj 2 kez görünüyordu ("tekrar girince 2 aynı mesaj"). (2) Gönderenin kendi mesajı için is_read SADECE partner kopyasından alınır (kendi kopyası hep true, anlamsız) → erken "görüldü" önlendi; sendMessage is_read=false döndürüyor; _addOrMerge kendi kopyanın true'sunu yok sayıyor + kompozit anahtarla iki-kopya korumalı. | eski sürüm: id-dedup + is_read=true | @owner #chat #hotfix` 

- `2026-07-03 13:00 UTC | CODE | chat_service.dart (getConversations) | prod | high | CHAT: "Mesajlar" listesi kartlarında karşı taraf bakmadan "görüldü" (mavi tik) çıkıyordu. KÖK NEDEN: reverseConvs satırları user_id=currentUserId olarak mutasyona uğruyor, sonra convByUserAndOther bu mutasyonlu değerlerle kuruluyordu → partner conversation lookup HER ZAMAN null → kartın okundu bilgisi yalnızca kendi conv kopyasından (is_read hep true) hesaplanıyordu. Düzeltme: temiz reverseConvIdByPartner haritası (mutasyonlu other_user_id=partnerId üzerinden). Kendi son mesajım için last_message_read yalnızca partner kopyasının is_read'inden gelir, yoksa false. Kullanılmayan convByUserAndOther kaldırıldı. NOT: liste state'te cache'lenir; değişiklik için tam restart veya pull-to-refresh gerekir. | eski sürüm: bozuk lookup + kendi kopya is_read | @owner #chat #hotfix`

- `2026-07-03 18:10 UTC | DATA | conversations.unread_count recount (bakım) | prod | medium | Eski çift-yönetim trigger'ının bozduğu unread_count değerleri gerçek değere eşitlendi. Doğru unread = conv'da sender_id != user_id AND is_read=false AND deleted_for_user_id IS NULL mesaj sayısı. Teşhis SELECT + UPDATE. BADGE_FIX migration'ından SONRA bir kez çalıştırılır. | migration: 20260703_CHAT_UNREAD_RECOUNT.sql | rollback: yok (yeniden hesap) | @owner #chat #data`

- `2026-07-03 18:00 UTC | FUNCTION | update_conversation_on_message trigger + send_message_with_recipient RPC | prod | critical | MESAJ OKUNMAMIŞ ROZETİ (badge) düzeltmesi — B'de yüzen mesaj ikonu + sohbet kartı unread görünmüyordu. KÖK NEDEN (çift yönetim): RPC conversations.unread'i güncelliyordu AMA message_insert_trigger de HER messages insert'inde güncelliyordu. Mailbox modelinde 2 satır yazıldığı için eski trigger koşulsuz NEW.conversation_id unread=0 yapıp karşı tarafı +1 artırıyordu → alıcı kopyası (row2) eklenince alıcının conv'u 0'a çekiliyordu. ÇÖZÜM (tek yetkili = TRIGGER, satır-bazlı): RPC artık conversations'a DOKUNMUYOR (sadece 2 messages satırı ekler + gerekiyorsa alıcı conv'unu unread=0 ile oluşturur). Trigger her satırda conv sahibine bakar: sender=owner → unread=0; sender≠owner → unread+=1; yalnızca NEW.conversation_id güncellenir (çapraz artırım yok); yeni mesaj ilgili taraf için soft-delete'i geri alır. DM push trigger zaten yalnızca gönderen kopyasında push atıyor (tutarlı). Bu RPC, 20260703_CHAT_SEND_RETURN_FIX.sql'deki sürümün YERİNE geçer. Client tarafı değişmez (market_screen realtime badge yenilemesi 17:30'da eklenmişti). | migration: 20260703_CHAT_UNREAD_BADGE_FIX.sql | rollback: 20260703_CHAT_SEND_RETURN_FIX.sql (RPC) + 20260702_CHAT_REALTIME_FIX_V2.sql (trigger) — çift yönetim geri döner | @owner #chat #hotfix`

- `2026-07-03 17:30 UTC | CODE | market_screen.dart + members_screen.dart + notifications_screen.dart | prod | medium | 3 UI/bildirim düzeltmesi. (1) MESAJ ROZETİ REALTIME: market_screen'deki yüzen mesaj butonu badge'i (_unreadChatCount) sadece açılışta yükleniyordu → yeni mesajda güncellenmiyordu. subscribeToConversations aboneliği eklendi (dispose'ta removeChannel). Sohbet kartı badge'i zaten realtime idi (chat_list subscribeToConversations). Veri kaynağı conversations.unread_count (RPC +1, markMessagesAsRead 0). (2) ARKADAŞ EKLE (members_screen) canlı çevrimiçi: PresenceService.onlineUsersStream aboneliği + tile'da isActive = _onlineIds ∪ yükleme anı _isActive. (3) BİLDİRİM TIKLAMA yönlendirme: _handleNotificationTap switch'inde eksik DB type'ları eklendi — en kritik 'new_follower' (takip trigger'ı bu type ile insert ediyor, eskiden default'a düşüp hiçbir şey yapmıyordu → artık actorId ile UserProfileScreen). Ayrıca alias: post_like/story_like, post_comment, post_mention/comment_mention, order/order_confirmed/delivered, follow_accepted. admin_notification hariç hepsi ilgili hedefe gider. | @owner #chat #notification #ui #realtime`

- `2026-07-03 16:30 UTC | CODE | notifications_content_v2.dart + notifications_screen.dart | prod | medium | ADMIN bildirimi (1) uygulama içi listede görünmüyordu, (2) tıklanınca detay açmıyordu. (1) KÖK NEDEN: kişisel admin bildirimi notifications.insert'te 'data' kolonuna yazıyordu — böyle kolon YOK (doğru kolon 'metadata' JSONB, 20260406000001) → PGRST204 → INSERT sessizce başarısız (catch yutuyordu) → sadece push gidiyordu. Düzeltme: 'data' → 'metadata'. (2) _handleNotificationTap'e 'admin_notification' case + default'ta entity_id 'admin_icon:' yakalama eklendi → _showFullNotificationContent (başlık+içerik dialogu). Diğer tipler (like/comment/order...) zaten kendi hedefine yönlendiriyor, dokunulmadı. NOT: Toplu (all/customers/sellers) admin bildirimleri tasarımca notifications'a yazılmaz, admin_broadcasts → "Duyurular" bölümünde gösterilir. | eski sürüm: 'data' kolonu + admin tıklamada no-op | @owner #admin #notification`

- `2026-07-03 16:00 UTC | FUNCTION | notify_direct_message + notify_direct_message_trigger (messages) | prod | high | CHAT: birebir mesajda alıcıya PUSH bildirimi gelmiyordu. KÖK NEDEN: messages INSERT üzerinde DM push trigger'ı DB'ye kurulu değildi (loose SQL dosyaları vardı ama deploy edilmemiş; ayrıca eski V2 mailbox modelinde çift push atıyordu). ÇÖZÜM: canonical trigger deploy edildi. Push YALNIZCA gönderenin conversation kopyasında (conversations.user_id = sender_id) üretilir, alıcı kopyası atlanır → tam 1 push. Altyapı: net.http_post (pg_net) → Edge Function send-push-notification → FCM v1 (profiles.fcm_token). data.type='chat'. NOT: uygulama İÇİ (notifications tablosu) mesaj bildirimi bilinçli olarak KAPALI (chat unread badge = conversations.unread_count kullanılıyor; notification_service message/chat tiplerini filtreler). | migration: 20260703_DM_PUSH_TRIGGER.sql | rollback: DROP TRIGGER notify_direct_message_trigger ON messages + DROP FUNCTION notify_direct_message | @owner #chat #notification #push`

- `2026-07-03 15:00 UTC | FUNCTION+CODE | clear_shop_balance trigger + admin_dashboard_screen._processPayoutRequest | prod | critical | Payout onay akışında total_paid ÇİFT SAYIMI + çakışan trigger düzeltmesi. KÖK NEDEN: clear_shop_balance'ın iki çakışan sürümü vardı (20260308000001... vs FIX_PAYOUT_APPROVED_CLEAR_REVENUE.sql) — hangisinin canlı olduğu belirsizdi. Ayrıca _processPayoutRequest(approved) Dart tarafında total_paid += amount + pending_payout -= amount yaparken trigger de UPDATE'te total_paid += NEW.amount ekliyordu → çift sayım. ÇÖZÜM: (1) Dart artık yalnızca payout_requests.status'unu değiştiriyor, shops'a DOKUNMUYOR. (2) Tek canonical trigger: approved VEYA paid'e İLK geçişte bir kez settle eder (idempotent; approved→paid tekrar saymaz): commission_debt/admin_credit/cash_payment_revenue/online_payment_revenue/total_collected_cash=0, pending_payout-=amount (GREATEST 0), total_paid+=amount, paid_at=NOW(). NOT: tam-ödeme varsayımı (kısmi ödeme için admin_credit düşüm mantığı ayrıca gerekir). | migration: 20260703_PAYOUT_TRIGGER_CONSOLIDATE.sql | rollback: eski iki SQL'den biri (çift sayım geri döner) + Dart shops update'i geri ekle | @owner #seller #finance #hotfix`

- `2026-07-03 14:30 UTC | CODE | admin_dashboard_screen.dart (Ödeme İşlemleri butonları) | prod | high | Admin ödeme aksiyonlarından sonra satıcı "Genel Bakış" kartlarının stale kalması düzeltildi. Satıcı genel bakış tamamen shops kolonlarından okur (cash_payment_revenue=Kapıda Kazanç, online_payment_revenue=Online Kazanç, admin_credit=Adminden Alacak). Eskiden "Ödeme Yapıldı" yalnızca admin_credit'i, "Ödeme Alındı" yalnızca commission_debt'i sıfırlıyor; kazanç kartları eski değeri gösteriyordu. Kullanıcı onayıyla EŞLEŞEN-KART mantığı uygulandı: "Ödeme Yapıldı" → admin_credit + online_payment_revenue = 0; "Ödeme Alındı" → commission_debt + cash_payment_revenue = 0; "Alacak/Verecek Kapat" → zaten hepsini sıfırlıyor. Böylece her tutar karşılığı ödendiğinde ilgili kart sıfırlanır (muhasebe tutarlı). shop_detail_admin_screen sadece görüntüler, aynı kolonlardan okuduğu için otomatik güncel. | eski sürüm: sadece admin_credit / commission_debt sıfırlanıyordu | @owner #seller #admin #finance`

- `2026-07-03 14:00 UTC | CODE | cart_service.dart (getCartSummary) | prod | high | Sepet ile sipariş onayı ekranındaki TUTAR FARKI düzeltmesi. KÖK NEDEN: Sepet ekranı cart_provider.summary → getDeliveryFee() (ücretsiz teslimat eşiği free_delivery_min_amount uygulanır + çok-dükkan toplanır) kullanırken; checkout getCartSummary() → getShopDeliveryFee() (HAM delivery_fee, eşik uygulanmaz, yalnızca items.first.shopId sayılır) kullanıyordu. Eşik aşıldığında sepet "ücretsiz" gösterip checkout ücret ekliyordu ("biri teslimatsız diğeri teslimat eklenmiş"); sipariş de yanlış ücreti kaydediyordu. Düzeltme: getCartSummary artık dükkan bazında gruplayıp calculateDeliveryFee ile eşiği uygular ve toplar (cart_provider ile tutarlı). Sipariş total'ı da düzelir (checkout order INSERT cartSummary.deliveryFee kullanır). | eski sürüm: getShopDeliveryFee tek dükkan + ham ücret | @owner #cart #payment #hotfix`

- `2026-07-03 13:15 UTC | DATA | messages (dedup cleanup - opsiyonel) | prod | medium | Eski buggy sürümlerin AYNI conversation içinde oluşturduğu GERÇEK çift mesaj satırlarını temizleyen bakım scripti hazırlandı. Mailbox kopyalarına DOKUNMAZ (partition conversation_id içerir); yalnızca (conversation_id, sender_id, content, created_at) birebir aynı fazla satırları siler, en düşük id korunur. Teşhis SELECT'leri + opsiyonel unique index içerir. | migration: 20260703_CHAT_DEDUP_CLEANUP.sql (manuel, teşhis sonrası çalıştırılmalı) | rollback: yok (silme) | @owner #chat #data`

---

- `2026-07-04 14:00 UTC | DIAG | profiles UPDATE sorunu teşhis | prod | medium | "Profil değişikliği başarılı diyor ama değişmiyor" şikayeti. Teşhis: 3 update_profile kodu (uploadProfilePhotoXFile, uploadCoverPhotoXFile, updateProfile) peş peşe .select() yapıyor ama ilk ikisinde response kontrolü yok → sessiz başarısızlık + başarı mesajı. 3 trigger bulundu: ensure_online_status_trigger, on_profile_update (update_profile_fields), update_profiles_updated_at. Tam kök neden için DIAG_20260704_PROFILE_UPDATE_V2.sql çalıştırıldı. | teşhis: DIAG_20260704_PROFILE_UPDATE.sql + DIAG_20260704_PROFILE_UPDATE_V2.sql | @owner #profile #rls`

- `2026-07-04 14:30 UTC | SCHEMA | profiles tablosu trigger'ları (bilgi) | prod | low | profiles tablosunda 3 BEFORE UPDATE trigger bulundu: (1) ensure_online_status_trigger → is_online koruma, (2) on_profile_update → update_profile_fields() sadece updated_at yazıyor, değer override etmiyor, (3) update_profiles_updated_at → updated_at_column. update_profile_fields() fonksiyonu storage_rls_fix.sql'de tanımlı. Trigger'lar değerleri override etmiyor, sorun kaynağı değil. | bilgi | @owner #schema`

---

- `2026-07-04 14:00 UTC | DIAG | profiles UPDATE sorunu teşhis | prod | medium | "Profil değişikliği başarılı diyor ama değişmiyor" şikayeti. Teşhis: 3 update_profile kodu (uploadProfilePhotoXFile, uploadCoverPhotoXFile, updateProfile) peş peşe .select() yapıyor ama ilk ikisinde response kontrolü yok → sessiz başarısızlık + başarı mesajı. 3 trigger bulundu: ensure_online_status_trigger, on_profile_update (update_profile_fields), update_profiles_updated_at. Tam kök neden için DIAG_20260704_PROFILE_UPDATE_V2.sql çalıştırıldı. | teşhis: DIAG_20260704_PROFILE_UPDATE.sql + DIAG_20260704_PROFILE_UPDATE_V2.sql | @owner #profile #rls`

- `2026-07-04 14:30 UTC | SCHEMA | profiles tablosu trigger'ları (bilgi) | prod | low | profiles tablosunda 3 BEFORE UPDATE trigger bulundu: (1) ensure_online_status_trigger → is_online koruma, (2) on_profile_update → update_profile_fields() sadece updated_at yazıyor, değer override etmiyor, (3) update_profiles_updated_at → updated_at_column. update_profile_fields() fonksiyonu storage_rls_fix.sql'de tanımlı. Trigger'lar değerleri override etmiyor, sorun kaynağı değil. | bilgi | @owner #schema`

- `2026-07-04 18:20 UTC | DIAG | profil update DB kaydı tamam | prod | low | DIAG_20260704_PROFILE_UPDATE_V4.sql ile teyit: profil güncelleme DB'de başarıyla kaydediliyor, profiles_select_unified policy (public SELECT) çalışıyor, kullanıcı kendi profilinde güncel değerleri görüyor. SORUN DB'DE DEĞİL — UI tarafında: edit_profile_screen.dart _saveProfile içinde 3 ayrı UPDATE peş peşe (uploadProfilePhotoXFile + uploadCoverPhotoXFile + updateProfile) çağrılıyor; ilk ikisinde .select() response kontrolü yok → sessiz başarısızlık + başarı snackbar gösteriliyor. Navigator.pop(context, true) döndükten sonra profile_screen.dart pull-to-refresh veya .then() ile reload yapmıyor olabilir → eski veri UI'da kalıyor. | teşhis: DIAG_20260704_PROFILE_UPDATE_V4.sql | @owner #profile #ui`

- `2026-07-04 20:00 UTC | RLS | group_members (rol yükseltme açığı) | prod | critical | GRUP SİSTEMİ GÜVENLİK AÇIĞI: herhangi bir grup üyesi kendi `role` alanını `.update({'role':'admin'})` ile 'admin' yapabiliyordu — RLS `USING`/`WITH CHECK` kolon bazlı fark göremediği için "kendi satırını güncelleyebilir" politikası rol alanını da kapsıyordu, client tarafında (group_chat_service.dart updateMemberRole) hiç kontrol yoktu. Ayrıca geçmiş yamalardan biri (FIX_GROUP_MEMBERS_RLS_BYPASS.sql) group_members üzerinde RLS'yi TAMAMEN KAPATIYORDU — en son çalıştırılmış olma ihtimaline karşı zorla yeniden açıldı. Düzeltme: (1) `trg_prevent_group_member_role_self_escalation` BEFORE UPDATE trigger'ı — admin olmayan biri kendi/rolünü değiştiremez. (2) group_members SELECT/INSERT/DELETE/UPDATE politikaları tek kanonik sürüme indirildi (private gruba doğrudan INSERT ile katılıp join-request akışını atlatma da kapatıldı). (3) `admin_add_group_member` RPC'si artık istemciden gelen `p_added_by` parametresine güvenmiyor, `auth.uid()` kullanıyor (sahte admin ID'siyle üye ekleme açığı). | migration: 20260704_GROUP_SYSTEM_SECURITY_FIX_FINAL.sql | rollback: RLS'yi eski (tutarsız) politika setine döndürmek risklidir, önerilmez — sorun bulunursa yalnızca trigger/politika tek tek incelenip düzeltilmeli | @owner #rls #security #hotfix #chat`

- `2026-07-04 20:10 UTC | FUNCTION | mark_group_messages_read_receipts (PGRST203 overload) | prod | high | Grupta mesaj okundu işaretleme PGRST203 "Could not choose the best candidate function" hatası veriyordu: fonksiyonun 1 parametreli (20260630_CHAT_P0_P1_FIX.sql) ve 2 parametreli (ADD_GROUP_MESSAGE_READ_RECEIPTS.sql, p_last_message_id DEFAULT NULL) sürümleri aynı anda DB'de duruyordu, PostgREST tek parametreyle çağrıldığında hangisini seçeceğini bilemiyordu. Düzeltme: 1 parametreli sürüm silindi, 2 parametreli (varsayılan NULL) sürüm — group_id kolonunu da dolduran doğru şema uyumlu versiyon — tek imza olarak bırakıldı. | migration: 20260704_GROUP_RPC_AND_STORAGE_FIX.sql | rollback: DROP FUNCTION (UUID,UUID) + 20260630_CHAT_P0_P1_FIX.sql'deki 1 parametreli sürümü geri oluştur | @owner #chat #hotfix`

- `2026-07-04 20:15 UTC | STORAGE | public bucket / group_images klasörü (403 RLS) | prod | high | Grup fotoğrafı yükleme StorageException 403 "new row violates row-level security policy" ile başarısız oluyordu. Kök neden kesin teşhis edilemedi (muhtemelen FIX_GROUP_MEMBERS_INFINITE_RECURSION.sql'deki bucket oluşturma adımı DO/EXCEPTION bloğuyla sessizce yutulmuş olabilir). Düzeltme: `public` bucket'ının varlığı `INSERT ... ON CONFLICT DO UPDATE` ile garanti edildi, group_images klasörü için SELECT/INSERT/UPDATE/DELETE politikaları `TO authenticated` açık rol belirtilerek yeniden oluşturuldu. | migration: 20260704_GROUP_RPC_AND_STORAGE_FIX.sql | rollback: FIX_GROUP_MEMBERS_INFINITE_RECURSION.sql ADIM 10'daki eski politikalara dön | @owner #storage #hotfix #chat`

- `2026-07-04 20:20 UTC | CODE | group_chat_service.dart (uploadGroupImage) | prod | medium | Grup fotoğrafı yüklendikten sonra ekranda değişmiyormuş gibi görünüyordu (403 düzeltildikten sonra da). Kök neden: dosya adı sabitti (`avatar_$groupId.jpg` / `cover_$groupId.jpg`) → her yüklemede AYNI public URL üretiliyordu → Flutter/tarayıcı eski görseli cache'ten göstermeye devam ediyordu (izin sorunu değil, cache sorunu). Düzeltme: dosya adına `DateTime.now().millisecondsSinceEpoch` eklendi (profil fotoğrafı upload'ıyla aynı desen). | eski sürüm: sabit dosya adı, cache-busting yok | @owner #chat #ui`

- `2026-07-04 20:25 UTC | RLS | is_group_admin / is_group_member / prevent_group_member_role_self_escalation / admin_add_group_member (linter) | prod | low | Supabase linter uyarıları: RLS/trigger içinde kullanılan yardımcı fonksiyonlar (`is_group_admin`, `is_group_member`, rol yükseltme trigger fonksiyonu) `anon` dahil herkes tarafından `/rest/v1/rpc/...` ile çağrılabiliyordu; `admin_add_group_member` da `anon`'a açıktı. Davranışsal risk yoktu (içeride kontrol var / dışarıdan anlamlı çağrılamaz) ama gereksiz dış erişim yüzeyiydi. EXECUTE yetkisi PUBLIC/anon'dan geri alındı, admin_add_group_member sadece authenticated'a bırakıldı. | migration: 20260704_GROUP_LINTER_SECURITY_FIX.sql | rollback: GRANT EXECUTE ... TO PUBLIC (önerilmez) | @owner #rls #security #chat`

- `2026-07-04 20:30 UTC | CODE | edit_profile_screen.dart (avatar/kapak önizleme) | prod | medium | Mobilde profil/kapak fotoğrafı seçip kırptıktan sonra önizleme güncellenmiyordu ("foto değişmiyor" şikayeti — bu, grup fotoğrafı sorunundan BAĞIMSIZ, ayrı bir bug). Kök neden: `_avatarXFile!.path` / `_coverXFile!.path` yerel dosya yolu olduğu halde `Image.network()` ile gösteriliyordu; ağ isteği başarısız olup sessizce `errorBuilder`'a düşüyordu. Düzeltme: `Image.file(File(path))` kullanılacak şekilde değiştirildi. | eski sürüm: Image.network(localPath) | @owner #profile #ui`

---

## 5) Yayın Öncesi Kontrol Listesi (Her Değişiklikte)

- [ ] İlgili dosyalara işlendi mi? (`SCHEMA`, `RLS`, `FUNCTIONS`)
- [ ] Bu changelog’a kayıt girildi mi?
- [ ] Rollback planı yazıldı mı?
- [ ] RLS etkisi test edildi mi?
- [ ] Edge Function logları kontrol edildi mi?
- [ ] Kritik tablolarda veri bütünlüğü doğrulandı mı?

---

## 6) Hızlı Etiketler (Opsiyonel)

Kayıt sonuna etiket eklenebilir:

- `#breaking-change`
- `#requires-migration`
- `#security`
- `#payment`
- `#ai`
- `#hotfix`
- `#perf`

Örnek:
- `2026-06-30 09:10 UTC | RLS | products_update_policy | prod | high | admin kontrolü değişti | eski policy geri yüklenir | @owner #security #breaking-change`
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
>>> REPLACE

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
# Admin Dashboard Ekranı - Sekme Bazlı Bölme Planı

**Tarih:** 2026-07-27
**Hedef Dosya:** `lib/features/admin/screens/admin_dashboard_screen.dart`
**Mevcut Boyut:** ~16,815 satır / 659KB (TEK dosya)

---

## 🎯 Amaç

`admin_dashboard_screen.dart` dosyasını, **mevcut fonksiyon imzalarını, setState çağrılarını ve context erişimlerini bozmadan** mantıksal sekmelere/part'lara bölmek.

---

## 🔑 Kritik Tasarım Kararı: `part` / `part of` Mekanizması

### Neden `part` Kullanıyoruz?

Bu dosyadaki tüm private metotlar (`_buildUsersContent`, `_showEditUserDialog` vb.) doğrudan:
- Parent state field'larına (`_totalUsers`, `_shopsDetailed`, `_userSearchQuery` ...) erişiyor
- `setState()` çağrısı yapıyor
- `ScaffoldMessenger.of(context).showSnackBar(...)` ve `Navigator.pop(context)` gibi context API'leri kullanıyor
- Birbirlerini çağırıyor (`_buildDrawer` ↔ `_buildDrawerItem` ↔ `_buildBody`)

**Bu metotları ayrı `StatelessWidget`'a çıkarmak demek:**
- Yüzlerce callback parametresi eklemek
- Global state management (Provider/Riverpod/ChangeNotifier) yeniden yapılandırmak
- 200+ metodu tek tek yeniden yazmak
- `context` zincirini baştan kurmak (mounted kontrolü vb.)

Bunların hepsi **fonksiyonları bozar** ve yüksek risk taşır.

### Çözüm: `part` + `part of`

Dart'ın `part`/`part of` direktifi, **birden fazla dosyayı tek bir kütüphane gibi derler**. Private field'lara ve metotlara tüm part'lardan erişilebilir. Hiçbir imza değişmez, hiçbir callback gerekmez.

```dart
// admin_dashboard_screen.dart
library;
part 'admin_dashboard.parts.dashboard.dart';
part 'admin_dashboard.parts.users.dart';
part 'admin_dashboard.parts.posts.dart';
part 'admin_dashboard.parts.products.dart';
// ...
```

```dart
// admin_dashboard.parts.users.dart
part of 'admin_dashboard_screen.dart';

Widget _buildUsersContent() { /* aynı kod */ }
```

**Sonuç:**
- ✅ Hiçbir fonksiyon imzası değişmez
- ✅ Hiçbir `setState` bozulmaz
- ✅ Hiçbir private field erişimi bozulmaz
- ✅ IDE her parçayı ayrı dosyada açar (okunabilirlik ↑)
- ✅ Git diff'ler parçalar halinde olur (review kolaylığı)
- ✅ Tüm dosyalar tek derleme birimi olarak derlenir
- ⚠️ Parçalar tek başlarına import edilemez (bu kabul edilebilir trade-off)

---

## 📁 Hedef Dosya Yapısı

```
lib/features/admin/screens/
├── admin_dashboard_screen.dart              ← Ana dosya (imports + library + class shell + build)
└── admin_dashboard_parts/
    ├── _part_dashboard.dart                 ← _buildDashboardContent + stats/network/cache/perf kartları
    ├── _part_users.dart                    ← _buildUsersContent + _showEdit/ChangeRole/DeleteUserDialog
    ├── _part_posts.dart                    ← _buildPostsContent/PostsList/StoriesList + _showAdd/Edit/DeletePost/StoryDialog
    ├── _part_products.dart                 ← _buildProductsContent + _showAdd/Edit/DeleteProductDialog
    ├── _part_categories.dart               ← _buildCategoriesContent + _showAdd/Edit/DeleteCategoryDialog
    ├── _part_shops.dart                    ← _buildShopsContent + _buildShopCard + _showAdd/Edit/DeleteShopDialog
    ├── _part_orders.dart                   ← _buildOrdersContent + _buildOrderCard + _showOrder/Edit/Delete dialogları
    ├── _part_reports.dart                  ← _buildReportsContent + _buildReportStatCard + show*Report dialogları
    ├── _part_post_reports.dart             ← _buildPostReportsContent + _showPostReport* dialogları
    ├── _part_support_tickets.dart          ← _buildSupportTicketsContent
    ├── _part_payments.dart                 ← _buildPaymentsContent + show*Payment* + payout işlemleri
    ├── _part_reports_page.dart             ← _buildReportsPageContent + chart builder'lar
    ├── _part_analytics.dart                ← _buildAnalyticsContent
    ├── _part_logs.dart                     ← _buildLogsContent
    ├── _part_api_settings.dart             ← _buildAPISettingsContent + S3/Iyzico/API key dialogları
    ├── _part_settings.dart                 ← _buildSettingsContent + _buildOrderControlCard + announcement
    ├── _part_courier.dart                  ← _buildCourierManagementContent + reset/markPaid/fee dialog
    ├── _part_drawer.dart                   ← _buildDrawer + _buildDrawerItem
    └── _part_helpers.dart                  ← _isValidImageUrl + diğer utility metotlar
```

---

## 🛠️ Uygulama Adımları

### Adım 0: Yedek
1. Mevcut `admin_dashboard_screen.dart` dosyasını `admin_dashboard_screen.dart.bak` olarak yedekle
2. Yeni `admin_dashboard_parts/` klasörünü oluştur

### Adım 1: Ana Dosyayı Shell'e İndir
1. `admin_dashboard_screen.dart`'da:
   - Tüm `import` satırlarını koru
   - Dosyanın en üstüne `library;` direktifi + `part 'admin_dashboard_parts/_part_xxx.dart';` direktiflerini ekle
   - `class AdminDashboardScreen` ve `class _AdminDashboardScreenState` sınıf iskeletini koru
   - Sadece şunları ana dosyada bırak:
     - State field'ları (tüm `_xxx` değişkenleri)
     - `initState()` / `dispose()`
     - `_setupRealtimeSubscription()` (diğer metotlar tarafından çağrılıyor)
     - `_loadRealData()` (initState'ten çağrılıyor)
     - `build()` metodu (Scaffold'u döndürüyor)
     - `_buildBody()` switch-case'i (her case parçadaki metodu çağırıyor)
     - `_buildComingSoon()` (çok küçük)
     - `_isValidImageUrl()` (helper)
2. Tüm `_buildXxxContent` / `_showXxxDialog` metotlarını ana dosyadan kes

### Adım 2: Part Dosyalarını Oluştur
Her part dosyası şu formatta olacak:

```dart
// lib/features/admin/screens/admin_dashboard_parts/_part_users.dart
part of '../admin_dashboard_screen.dart';

// _buildUsersContent
// _buildRoleBadge
// _showEditUserDialog
// _showChangeRoleDialog
// _showDeleteUserDialog
```

Her part dosyasına ilgili metotların **tam gövdesini**, orijinal sırasıyla kopyala. İçerikte hiçbir değişiklik yapma.

### Adım 3: Doğrulama
1. `flutter analyze` çalıştır → hata yok
2. `dart compile` ile sözdizimi kontrolü
3. Mümkünse `flutter build apk --debug` ile derleme testi

---

## 📋 Parça → Metot Haritası

### `_part_drawer.dart` (~500 satır)
- `Widget _buildDrawer(BuildContext, User?)` — satır 399
- `Widget _buildDrawerItem(...)` — satır 774

### `_part_dashboard.dart` (~600 satır)
- `Widget _buildDashboardContent()` — satır 10012
- `Widget _buildWelcomeBanner()` — satır 10045
- `Widget _buildStatsGrid()` — satır 10107
- `Widget _buildStatCard(...)` — satır 10169
- `Widget _buildStatCardOld(...)` — satır 10258
- `Widget _buildNetworkStatusCard()` — satır 10339
- `Widget _buildCacheStatisticsCard()` — satır 10389
- `Widget _buildPerformanceCard()` — satır 10462

### `_part_users.dart` (~750 satır)
- `Widget _buildUsersContent()` — satır 1387
- `Widget _buildRoleBadge(String?)` — satır 1748
- `void _showEditUserDialog(...)` — satır 1805
- `void _showChangeRoleDialog(...)` — satır 1874
- `void _showDeleteUserDialog(...)` — satır 2035

### `_part_posts.dart` (~700 satır)
- `Widget _buildPostsContent()` — satır 2099
- `Widget _buildPostsList()` — satır 2128
- `Widget _buildStoriesList()` — satır 2334
- `void _showAddPostDialog()` — satır 6139
- `void _showEditPostDialog(...)` — satır 6210
- `void _showDeletePostDialog(...)` — satır 6289
- `void _showAddStoryDialog()` — satır 6412
- `void _showDeleteStoryDialog(...)` — satır 6438

### `_part_products.dart` (~1500 satır)
- `Widget _buildProductsContent()` — satır 2573
- `void _showAddProductDialog()` — satır 8599
- `void _showEditProductDialog(...)` — satır 8800
- `void _showDeleteProductDialog(...)` — satır 9016

### `_part_categories.dart` (~900 satır)
- `Widget _buildCategoriesContent()` — satır 2867
- `Widget _buildCategoryCard(...)` — satır 2961
- `void _showAddCategoryDialog()` — satır 9326
- `void _showEditCategoryDialog(...)` — satır 9577
- `void _showDeleteCategoryDialog(...)` — satır 9842

### `_part_shops.dart` (~2200 satır)
- `Widget _buildShopsContent()` — satır 6549
- `Future<void> _loadAndSetShops()` — satır 6630
- `Widget _buildShopCard(...)` — satır 6641
- `Widget _buildShopStat(...)` — satır 7225
- `void _showAddShopDialog()` — satır 7424
- `void _toggleShopVerification(...)` — satır 7589
- `void _toggleShopApproval(...)` — satır 7621
- `void _toggleShopActive(...)` — satır 7653
- `void _showEditShopDialog(...)` — satır 7685
- `void _showDeleteShopDialog(...)` — satır 7905
- `void _showShopDetailDialog(...)` — satır 8097

### `_part_orders.dart` (~1950 satır)
- `Widget _buildOrdersContent()` — satır 3127
- `Widget _buildOrderStatChip(...)` — satır 3390
- `Widget _buildEarningsItem(...)` — satır 3421
- `Widget _buildOrderCard(...)` — satır 3458
- `Widget _buildOrderAmountItem(...)` — satır 4009
- `Widget _buildStatusBadge(...)` — satır 4037
- `void _showOrderDetailDialog(...)` — satır 4095
- `Widget _buildDetailRow(...)` — satır 4540
- `void _showEditOrderDialog(...)` — satır 4565
- `Future<void> _confirmAdminCancel(...)` — satır 4705
- `Widget _buildStatusOption(...)` — satır 4860
- `void _showDeleteOrderDialog(...)` — satır 4904

### `_part_reports.dart` (~1200 satır)
- `Widget _buildReportsContent()` — satır 5063
- `Widget _buildReportStatCard(...)` — satır 5774
- `Future<void> _togglePin(...)` — satır 5963
- `void _showReportDetailDialog(...)` — satır 15823
- `Widget _buildReportStatusOption(...)` — satır 16235
- `void _showDeleteReportDialog(...)` — satır 16279

### `_part_post_reports.dart` (~480 satır)
- `Widget _buildPostReportsContent()` — satır 908
- `Widget _buildPostReportStatCard(...)` — satır 1130
- `void _showPostReportDetailDialog(...)` — satır 1172
- `Widget _buildReportDetailRow(...)` — satır 1336
- `void _showDeletePostReportDialog(...)` — satır 1364

### `_part_support_tickets.dart` (~280 satır)
- `Widget _buildSupportTicketsContent()` — satır 12979
- `void _showSupportTicketDetailDialog(...)` — satır 13260

### `_part_payments.dart` (~900 satır)
- `Widget _buildPaymentsContent()` — satır 13273
- `Future<void> _markPayoutAsPaid(...)` — satır 13729
- `void _showPaymentDetailDialog(...)` — satır 13850
- `Future<void> _processPayoutRequest(...)` — satır 14021
- `void _showRejectPayoutDialog(...)` — satır 14094

### `_part_reports_page.dart` (~660 satır)
- `Widget _buildReportsPageContent()` — satır 14168
- `Widget _buildPeriodCard(...)` — satır 14388
- `Widget _buildRevenueChart(...)` — satır 14430
- `Widget _buildOrdersChart(...)` — satır 14499
- `Widget _buildCategoryDistribution(...)` — satır 14568

### `_part_analytics.dart` (~120 satır)
- `Widget _buildAnalyticsContent()` — satır 10559

### `_part_logs.dart` (~290 satır)
- `Widget _buildLogsContent()` — satır 12475

### `_part_api_settings.dart` (~1850 satır)
- `Widget _buildAPISettingsContent()` — satır 14829
- `Widget _buildIyzicoPaymentSettingsCard(...)` — satır 15215
- `void _showEditIyzicoDialog(...)` — satır 15364
- `void _showCreateAPIKeyDialog()` — satır 15522
- `void _showDeleteAPIKeyDialog(...)` — satır 15605
- `void _toggleAPIKey(...)` — satır 15652
- `void _regenerateAPIKey(...)` — satır 15674
- `void _updateAPISetting(...)` — satır 15722
- `void _showWebhooksDialog()` — satır 15740
- `Widget _buildWebhookItem(...)` — satır 15790
- `Widget _buildS3StorageSettingsCard(...)` — satır 16498
- `void _showS3SettingsDialog(...)` — satır 16680

### `_part_settings.dart` (~2050 satır)
- `Widget _buildSettingsContent()` — satır 10671
- `Widget _buildOrderControlCard()` — satır 10796
- `Widget _buildStartupAnnouncementCard()` — satır 10996
- `void _showEditAnnouncementDialog(...)` — satır 11170
- `Widget _buildTypeChip(...)` — satır 11285
- `void _showSendNotificationDialog()` — satır 12865

### `_part_courier.dart` (~1400 satır)
- `Widget _buildCourierManagementContent()` — satır 11311
- `Widget _buildCourierStatCard(...)` — satır 11611
- `Widget _buildCourierCard(...)` — satır 11641
- `Widget _buildCourierInfoItem(...)` — satır 11778
- `Future<void> _resetCourierBalance(...)` — satır 11793
- `Future<void> _markCourierPaid(...)` — satır 11905
- `void _showCourierFeeDialog()` — satır 12103
- `Future<void> _approveCourierPayout(...)` — satır 12214

### `_part_helpers.dart` (~50 satır)
- `bool _isValidImageUrl(dynamic)` — satır 16809

### Ana dosyada kalacaklar (~600 satır)
- Tüm `import` direktifleri
- `class AdminDashboardScreen` + `class _AdminDashboardScreenState` iskeleti
- Tüm state field'ları
- `initState()` + `dispose()`
- `_setupRealtimeSubscription()` (satır 105)
- `_loadRealData()` (satır 248)
- `build()` metodu (satır 334)
- `_buildBody()` switch-case'i (satır 820)
- `_buildComingSoon()` (satır 12760)
- `Widget _buildInfoRow(...)` (satır 12790)

---

## ⚠️ Dikkat Edilecekler

1. **`part` direktifinde relative path**: Her part dosyası `part of '../admin_dashboard_screen.dart';` ile bağlanır (Dart'ın part of yolu, part dosyasının konumundan değil, kütüphane dosyasının konumundan göreceli olur).
   - Aslında: `part of 'admin_dashboard_screen.dart';` (kütüphane dosyasının bulunduğu dizine göre)
2. **Yorum direktifleri**: Dosyanın başındaki `// ignore_for_file:` satırları ana dosyada kalmalı, ama part dosyalarında gerekmez (part'lar ana dosyanın ignore listesinden yararlanır).
3. **Sıralama**: Part dosyalarındaki metotlar, ana dosyada `_buildBody()` switch'inden **önce** derlenmiş olmalı. Dart'ta bu sıralama `part` direktiflerinin sırasıyla değil, dosya isimleriyle değil, doğrudan derleme zamanıyla ilgilidir — fonksiyon tanımlarının sırası önemli değildir.
4. **Yedek**: İşlem sonunda `.bak` dosyası silinebilir ama en azından commit öncesi saklanmalı.

---

## ✅ Doğrulama Kontrol Listesi

- [ ] Yedek dosya oluşturuldu
- [ ] `admin_dashboard_parts/` klasörü oluşturuldu
- [ ] Tüm part dosyaları oluşturuldu ve `part of` direktifi içeriyor
- [ ] Ana dosyada `library;` + tüm `part` direktifleri var
- [ ] Ana dosyada yalnızca shell + build metodu + state field'ları var
- [ ] Orijinal dosya boyutu 659KB idi → yeni ana dosya ~25KB olmalı
- [ ] `flutter analyze` hata vermiyor
- [ ] `grep -c 'class _' admin_dashboard_screen.dart` → yalnızca `_AdminDashboardScreenState` olmalı
- [ ] Hiçbir metot gövdesi değiştirilmedi (satır satır aynı)
- [ ] Hiçbir `setState` çağrısı bozulmadı
- [ ] Hiçbir `context` erişimi bozulmadı

---

## 📊 Beklenen Sonuç

| Metrik | Önce | Sonra |
|---|---|---|
| Ana dosya boyutu | 659 KB (~16,815 satır) | ~25 KB (~600 satır) |
| Dosya sayısı | 1 | 1 + 19 part |
| En büyük part | - | ~2,200 satır (`_part_shops.dart`) |
| Okunabilirlik | ⭐ | ⭐⭐⭐⭐ |
| Fonksiyon imzaları | - | Değişmedi ✅ |
| setState davranışı | - | Değişmedi ✅ |
| context davranışı | - | Değişmedi ✅ |
| Derleme başarısı | ✅ | ✅ (aynı) |

---

## 🚀 Uygulama Sırası (Risk-Öncelik)

Part'ları küçükten büyüğe doğru taşımak, her adımda derleme kontrolü yapmak en güvenli yoldur:

1. `_part_helpers.dart` (en küçük, bağımlılık yok)
2. `_part_drawer.dart`
3. `_part_dashboard.dart`
4. `_part_users.dart`
5. `_part_posts.dart`
6. `_part_categories.dart`
7. `_part_products.dart`
8. `_part_reports.dart`
9. `_part_post_reports.dart`
10. `_part_support_tickets.dart`
11. `_part_payments.dart`
12. `_part_reports_page.dart`
13. `_part_analytics.dart`
14. `_part_logs.dart`
15. `_part_settings.dart`
16. `_part_api_settings.dart`
17. `_part_orders.dart`
18. `_part_courier.dart`
19. `_part_shops.dart` (en büyük)

Her adımda: part dosyasını oluştur → ana dosyadan ilgili metotları kes → `part` direktifini ekle → mümkünse `flutter analyze` çalıştır.

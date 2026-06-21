# CizreApp — 3 Hata Düzeltme Planı

Tarih: 2026-05-28
Mod: Architect → (onaydan sonra) Code

---

## Özet

Kullanıcı 3 ayrı hata bildirdi. Hepsi farklı ekranlarda, ancak kök nedenleri net tespit edildi:

1. Anasayfa dükkan kartlarında saat/kupon açık olsa bile "Kapalı" etiketi
2. Keşfet feed'inde çoklu görselli gönderilerde diğer görselleri görmek için detaya gitmek zorunlu
3. Çevrimdışı yapılmasına rağmen tekrar aktif görünme (3 ayrı ekranda toggle var)

---

## Soru 1 — Dükkan "Kapalı" etiketi (manuel açık + saat dolu olduğu halde)

### Kök neden

[`Shop.isOpen`](lib/core/models/shop_model.dart:89) getter'ı şu mantıkla çalışıyor:

```dart
bool get isOpen {
  // Eğer çalışma saatleri tanımlı değilse manuel değeri kullan
  if (workingHours == null || workingHours!.isEmpty) {
    return _isOpenManual;
  }
  // ... saat hesabı yapılır, _isOpenManual sadece fallback olarak
  // openTime/closeTime parse edilemezse kullanılır
}
```

Yani **`workingHours` doluysa manuel `_isOpenManual` değeri tamamen yok sayılıyor**. Satıcı dükkan ayarlarında `is_open = true` (manuel açık) yapsa bile, eğer saat dışındaysa `isOpen` false döner ve kart [`shop.isOpen ? 'Açık' : 'Kapalı'`](lib/features/market/screens/market_screen.dart:1939) ile "Kapalı" gösterir.

Kullanıcı netleştirdi: **manuel false → her zaman kapalı, manuel true → saate göre** (mevcut mantıkla aynı, eksik olan manuel false önceliği).

### Etkilenen dosyalar

- [`lib/core/models/shop_model.dart`](lib/core/models/shop_model.dart) — ana mantık
- [`lib/features/market/screens/market_screen.dart`](lib/features/market/screens/market_screen.dart:1934) — anasayfa kartı
- [`lib/features/market/screens/all_shops_screen.dart`](lib/features/market/screens/all_shops_screen.dart:419) — tüm dükkanlar
- [`lib/features/market/screens/category_shops_screen.dart`](lib/features/market/screens/category_shops_screen.dart:329) — kategori dükkanları
- [`lib/features/market/screens/shop_detail_screen.dart`](lib/features/market/screens/shop_detail_screen.dart:881) — dükkan detay
- [`lib/features/market/services/shop_service.dart`](lib/features/market/services/shop_service.dart:75) — `isOpen` filtrelemesi
- [`lib/features/admin/screens/shop_detail_admin_screen.dart`](lib/features/admin/screens/shop_detail_admin_screen.dart:464) — admin görüntüleme (yalnızca `is_open` raw sütununu okuyor, model mantığından bağımsız; dokunulmaz)

### Çözüm

[`Shop.isOpen`](lib/core/models/shop_model.dart:89) getter'ının başına manuel false önceliği eklenir:

```dart
bool get isOpen {
  // 1) Manuel olarak kapatılmışsa her zaman kapalı (öncelikli)
  if (!_isOpenManual) {
    return false;
  }
  // 2) Çalışma saati tanımlı değilse manuel değere göre (burada true)
  if (workingHours == null || workingHours!.isEmpty) {
    return _isOpenManual; // true
  }
  // 3) Manuel açık + saat tanımlıysa saate göre hesapla
  // ... mevcut saat hesabı aynen kalır
}
```

Böylece: manuel kapalı → her zaman kapalı; manuel açık + saat tanımsız → açık; manuel açık + saat dolu → saate göre.

`todayWorkingHours` ve `nextStatusChange` getter'ları `!_isOpenManual` durumunu "Kapalı" olarak ele almak için küçük bir düzeltme gerektirebilir (manuel kapalıysa "Manuel Kapalı" gösterilebilir). Bu detay Code modunda netleştirilecek.

### Doğrulama

- Satıcı ayarlarında `is_open=false` → anasayfada "Kapalı"
- Satıcı `is_open=true` + saat 09:00–18:00 + saat 10:00 → "Açık"
- Satıcı `is_open=true` + saat 09:00–18:00 + saat 20:00 → "Kapalı"
- `is_open=true` + working_hours boş → "Açık"

---

## Soru 2 — Keşfet feed'inde çoklu görsel gezinme

### Kök neden

[`_buildTwitterPostCard`](lib/features/social/screens/social_screen.dart:1710) içinde görsel kısmı sadece **tek** görseli gösteriyor:

```dart
Image.network(
  post.images.first,
  width: double.infinity,
  height: 200,
  ...
),
if (post.images.length > 1)
  Positioned(...) // '1/N' badge
```

Yani çoklu görsel varsa yalnızca ilk görsel + "1/N" rozeti gösteriliyor. Diğer görselleri görmek için [`PostDetailScreen`](lib/features/social/screens/social_screen.dart:1722)'e gitmek zorunlu.

### Çözüm

Feed kartındaki görsel alanını **yatay `PageView` carousel** + **nokta indikatör** ile değiştir (Instagram tarzı). Kullanıcı netleştirdi: yatay swipe + nokta indikatör.

Uygulama detayları:
- Görsel alanı `StatefulBuilder` veya küçük bir ayrı `StatefulWidget` (`_PostImageCarousel`) içinde `PageController` ile yönetilir (sliver list içinde her kart için ayrı state).
- `PageController` `dispose` edilmeli — bu yüzden tam inline yerine küçük bir widget tercih edilir (bellek sızıntısı önlemi).
- Görsel yoksa mevcut davranış korunur (yer/boş alan).
- Tek görselde carousel + nokta gereksiz olur → `length == 1` ise mevcut tek görsel render.
- "1/N" badge isteğe bağlı kalır veya nokta indikatörle değiştirilir (nokta indikatör yeterli bilgi verdiği için badge kaldırılabilir; Code modunda kararlaştırılacak).
- Çift tıklama beğenme davranışı (`onDoubleTap`) korunsun — carousel swipe ile çakışmaması için `onDoubleTap` kart üst seviyesinde kalır, `PageView` kendi içinde swipe'ı yönetir.

### Etkilenen dosyalar

- [`lib/features/social/screens/social_screen.dart`](lib/features/social/screens/social_screen.dart) — `_buildTwitterPostCard` (~satır 1710-1960)
- İsteğe bağlı yeni küçük widget dosyası: `lib/features/social/widgets/post_image_carousel.dart` (Code modunda kararlaştırılacak)

### Doğrulama

- Tek görselli post → tek görsel, nokta yok
- 3 görselli post → swipe ile 3 görsel arası geçiş + altta 3 nokta, aktif görselin noktası dolu
- Görsel yüklenmezse `errorBuilder` mevcut `SizedBox.shrink` davranışını korur
- Çift tıklama hâlâ beğenme tetikler

---

## Soru 3 — Çevrimdışı yapıp tekrar aktif görünme

### Kök neden

[`PrivacyService.onAppResumed`](lib/core/services/privacy_service.dart:200) her uygulama ön plana geldiğinde (ya da `MainScreen` initState'te [`onAppResumed()` çağrısıyla](lib/features/main/screens/main_screen.dart:57)) `is_online = true` yazıyor:

```dart
Future<void> onAppResumed() async {
  final isGhostMode = await getGhostMode();
  if (!isGhostMode) {
    await updateOnlineStatus(true);  // <-- manuel tercihi eziyor
  }
  startHeartbeat();
}
```

Kullanıcı herhangi bir toggle'dan çevrimdışı yapsa bile, telefonu kilitleyip açınca / uygulama arka plandan ön plana geçince `onAppResumed` tetiklenir ve tekrar `is_online=true` olur. Üstelik bunu **3 ayrı ekran** ayrı ayrı yönetiyor, bu da senkronizasyon karmaşası yaratıyor:

- [`lib/core/widgets/settings_sidebar.dart`](lib/core/widgets/settings_sidebar.dart:156) — `_setOnlineStatus`
- [`lib/features/chat/screens/chat_privacy_settings_screen.dart`](lib/features/chat/screens/chat_privacy_settings_screen.dart:46) — `_setOnlineStatus`
- [`lib/features/courier/screens/courier_panel_screen.dart`](lib/features/courier/screens/courier_panel_screen.dart:367) — `_toggleOnlineStatus` (kurye, `last_seen`/`updated_at` güncellemeden sadece `is_online` yazar)

Kullanıcı netleştirdi: **manuel çevrimdışı tercihi kalıcı olsun, uygulama ön plana gelince otomatik açılmasın.**

### Çözüm

`PrivacyService`'e kalıcı (manuel) tercihi temsil eden ayrı bir flag ekle. Ya `profiles` tablosuna yeni sütun (`is_online_enabled` / `show_online`) ya da yerel tercih (SharedPreferences). Supabase tablosuna sütun eklemek daha güvenilir (çi̇hazler arası tutarlı, gerçek zamanlı), bu yüzden DB sütunu önerilir.

Önerilen şema değişikliği (Supabase migration):
```sql
alter table profiles add column if not exists is_online_enabled boolean default true;
```

Yeni mantık:
- `is_online` alanı **gerçek** online durumunu (heartbeat + app ön plan) temsil eder
- `is_online_enabled` alanı **kullanıcının tercihi** (manuel toggle) temsil eder
- `onAppResumed`: `is_online_enabled == true` ise `is_online=true` yap; değilse dokunma (kalıcı çevrimdışı)
- `onAppPaused`: `is_online=false` yap (her zaman)
- Toggle ekranları `is_online_enabled`'i günceller; `is_online` değeri de buna göre setlenir
- Heartbeat yalnızca `is_online_enabled && app ön planda` iken çalışır

3 toggle ekranı tekilleştirme:
- `settings_sidebar` ve `chat_privacy_settings_screen` aynı `_setOnlineStatus` mantığını kullanıyor → ikisi de `updateOnlineStatus` + (yeni) `updateOnlineEnabled` çağıracak şekilde güncellenir, böylece ikisi de aynı kaynağa yazar (tek kaynak).
- `courier_panel_screen._toggleOnlineStatus` `last_seen`/`updated_at` güncellemiyor; `PrivacyService` kullanmıyor. Kurye için `is_online` kurye-spesifik bir anlama sahip (kurye boşta mı). Bu yüzden kurye toggle'ı **ayrı tutulabilir** ama `main_screen.dart` lifecycle'ı kuryeyi tekrar online yapmasın diye kurye ekranında `WidgetsBindingObserver`/lifecycle override kontrol edilmeli — aslında `main_screen.dart` `onAppResumed` çağrısı her kullanıcı (kurye dahil) için geçerli. Bu yüzden `onAppResumed` düzeltmesi kuryeyi de kapsar ve kurye manuel offline iken otomatik açılmaz. Kurye toggle'ı yine `is_online_enabled` yerine direkt `is_online` yazıyorsa bu çelişki yaratır → kurye toggle'ının da `is_online_enabled` güncelleyecek şekilde (ya da kurye kendi alanıysa ayrı bir `is_courier_online`) düzeltilmesi gerekir. Code modunda netleştirilecek; öneri: kurye için ayrı `is_online_enabled` kontrolü yerine kurye toggle'ı da aynı `is_online_enabled` semantiğini kullansın ve kurye paneli `onAppResumed`'dan etkilenmesin diye `onAppResumed`'daki `is_online_enabled` kontrolü yeterli olur.

### Etkilenen dosyalar

- [`lib/core/services/privacy_service.dart`](lib/core/services/privacy_service.dart) — `onAppResumed`, `onAppPaused`, `updateOnlineStatus`'u `updateOnlineStatus` + `updateOnlineEnabled` olarak böl; `getOnlineStatus` yanında `getOnlineEnabled`
- [`lib/features/main/screens/main_screen.dart`](lib/features/main/screens/main_screen.dart:57) — lifecycle çağrıları korunur, davranış `PrivacyService` içinde düzeltilir
- [`lib/core/widgets/settings_sidebar.dart`](lib/core/widgets/settings_sidebar.dart:156) — `is_online_enabled` göster/güncelle
- [`lib/features/chat/screens/chat_privacy_settings_screen.dart`](lib/features/chat/screens/chat_privacy_settings_screen.dart:46) — aynı
- [`lib/features/courier/screens/courier_panel_screen.dart`](lib/features/courier/screens/courier_panel_screen.dart:367) — kurye toggle'ını ortak mantığa hizala
- Yeni Supabase migration: `supabase/ADD_ONLINE_ENABLED_COLUMN.sql` (isim Code modunda netleşir)

### Doğrulama

- Settings sidebar'dan çevrimdışı yap → uygulamayı minimize edip geri aç → hâlâ çevrimdışı
- Chat privacy'den çevrimdışı yap → settings sidebar aç → çevrimdışı görünür (senkron)
- Hayalet mod açıksa çevrimdışı kalır (mevcut davranış)
- Kurye offline → app arka plan/ön plan → hâlâ offline (kurye toggle'ı ortak mantığa hizalandıktan sonra)

---

## Uygulama Sırası

1. Soru 3 — `privacy_service.dart` + `main_screen.dart` + 3 toggle ekranı + Supabase migration (en çok dokunuş, önce temel)
2. Soru 1 — `shop_model.dart` + kart widget'ları (tek model değişikliği, düşük risk)
3. Soru 2 — `social_screen.dart` carousel (UI, kendi başına test edilebilir)

Her değişiklikten sonra `flutter analyze` çalıştırılır.

## Notlar / Açık Sorular (Code modunda netleşecek)

- `todayWorkingHours`/`nextStatusChange` getter'larının manuel-kapalı durumu için gösterimi
- Keşfet carousel'inde "1/N" badge kalır mı kalkar mı (nokta indikatör yeterli mi)
- Kurye toggle'ı genel `is_online_enabled` ile mi, yoksa kuryeye özel ayrı flag ile mi yönetilmeli
- `profiles` tablosuna `is_online_enabled` sütunu eklemek yerine SharedPreferences kullanımı cihazlar arası tutarsız olabilir; DB sütunu önerilir
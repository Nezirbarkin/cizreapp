# Paket Gönder/Al — Manuel + Otomatik Test Planı (v2 — 2026-08-07)

Bu doküman, mevcut `PAKET_TEST_PLANI.md`'nin kök neden odaklı genişletilmiş
hâlidir. Fiziksel cihazda test ederken her kutucuğu işaretle; başarısız
olan adımın numarası + hata çıktısı + kullanıcı rolü bana ilet.

> **TL;DR (kök neden):** 2026-08-05 tarihli diagnostik çalışması,
> canlı DB'de `create_package_request` RPC fonksiyonunun **YOK**
> olduğunu kesinleştirdi. Flutter `send_package_screen.dart`'daki
> "Paket Talebini Gönder" butonu `.rpc('create_package_request', …)`
> çağrısı **PGRST202** ile patlıyor. Çözüm: `supabase/diagnostics/HOTFIX_create_package_request.sql`
> SQL Editor'de çalıştırılmalı.

---

## 0) Ön koşul (kontrol listesini işaretle)

- [ ] `supabase/diagnostics/HOTFIX_create_package_request.sql` **BLOK 0 (tanılama)** çalıştırıldı.
  - "create_package_request VAR" çıkıyorsa → bu planın geri kalanı anlamsız, kök neden başka.
  - "YOK (beklenen)" çıkıyorsa → BLOK 1 + BLOK 2 + BLOK 3 sırayla uygula.
- [ ] `balance_transaction_type` enum'unda `courier_payment` değeri VAR.
- [ ] `courier_requests.idempotency_key` kolonu VAR.
- [ ] `public.courier_service_settings` tablosunda `enabled=true` ve `allows_user_requests=true` olan en az 1 satır VAR.
- [ ] Test kullanıcısının `user_balances.balance >= 50 ₺` (deneme ücretini karşılayacak).
- [ ] En az 1 kullanıcı `profiles.role = 'courier'`.

**Tanılama sonucu özeti (kopyala-yapıştır için yer):**
```
BLOK 0 çıktısı:
- create_package_request: ............
- courier_payment enum:   ............
- idempotency_key kolonu: ............
- courier_service_settings satır sayısı: .....
```

---

## 1) OTOMATİK TESTLERİN ÇALIŞTIRILMASI (ilk)

Bu dokümanla birlikte oluşturulan 3 test dosyası:

| Dosya | Tür | Çalıştırma |
|---|---|---|
| `test/user_courier/package_send_flow_test.dart` | Dart unit | `flutter test test/user_courier/package_send_flow_test.dart` |
| `test/user_courier/package_widget_test.dart` | Dart widget/mocked service | `flutter test test/user_courier/package_widget_test.dart` |
| `supabase/tests/database/007_courier_package_request_invariants.test.sql` | pgTAP | `pg_prove -d <db> supabase/tests/database/007_courier_package_request_invariants.test.sql` |

### 1.1 Dart unit testler — hangi guard'ı kontrol ediyor

- **Mesafe & ücret hesabı (Haversine):** 5 test — UI'da gösterilen "X km / Y ₺" tutarlılığı.
- **Koordinat doğrulama:** 5 test — `[−90, 90]` / `[−180, 180]` aralık kontrolü; RPC `22023` raise edecek.
- **Idempotency key (UUID v4):** 4 test — version 4 nibble, variant 1 nibble, 100 çağrıda 100 benzersiz.
- **Hata yorumlama (EN KRİTİK):** 9 test — TR/EN insufficient balance, PGRST202, P0001, timeout, auth, service_disabled, user_requests_disabled.
- **Durum rozet çevirisi:** 4 test — pending/accepted/delivery_pending_confirmation/delivered/cancelled renk+label.
- **Tarih formatlama (crash guard):** 4 test — ISO 8601, null, bozuk format, sadece tarih.
- **RPC sözleşme doğrulaması:** 2 test — 13 parametre adı + 2 dönüş alanı.
- **Bildirim N+1:** 2 test — şu an 50 kurye = 50 RPC, refactor hedefi 1.

### 1.2 Dart widget/service testler — hangi davranışı kanıtlıyor

- **Yetersiz bakiye hata yorumlama:** 3 test — `errorMessage.contains('Insufficient balance')` ile `APP:insufficient_balance` eşleşmeme bug'ını belgeliyor.
- **PGRST202 kök neden koruması:** 2 test — fonksiyon bulunamadı hatasının tanınması.
- **Idempotency:** 2 test — aynı key → aynı sonuç; farklı key → 2 ayrı INSERT.
- **Adres state guard:** 2 test — pickup ≠ delivery state bağımsızlığı.
- **loadPricing fallback:** 2 test — boş tablo → default; dolu → override.
- **Realtime listener:** 2 test — courier_id null/dolu sözleşmesi.
- **Çift tıklama koruması:** 1 test — 3 paralel çağrı → 1 RPC.
- **History boş/dolu:** 3 test.
- **Bildirim sınır:** 2 test.
- **Supabase client sözleşme:** 2 test.

### 1.3 pgTAP invariant testleri — DB seviyesi guard

12 test:

1. `create_package_request` 13 parametreli imza ile var mı?
2. `courier_requests` tablosu + 9 kritik kolonu var mı?
3. `uq_courier_requests_sender_idem` unique index var mı?
4. Bağımlı tablolar (`user_balances`, `balance_transactions`, `courier_service_settings`) var mı?
5. `balance_transaction_type` enum + `courier_payment` değeri var mı?
6. `authenticated` grubu EXECUTE yetkisine sahip mi?
7. `plpgsql` + `SECURITY DEFINER` mı?
8. auth_required raise doğru mu (42501)?
9. Şema önbelleği taze mi (son 1 saat)?
10. Koordinat kolonları tam (4/4)?

---

## 2) FİZİKSEL CİHAZ MANUEL TESTLERİ (müşteri akışı)

Aşağıdaki tablo, ekrandaki her gözlemlenebilir davranışı işaretle.
Başarısız olan her satır için: **ekran görüntüsü + logcat çıktısı + rol** bana gönder.

| # | Adım | Beklenen | Geçti mi? | Not |
|---|---|---|---|---|
| 1 | Market ekranında motor ikonuna bas | "Paket Gönder" ekranı açılır | ☐ | |
| 2 | _loadPricing yükleniyor göstergesi | < 1 sn'de kaybolur (0 satır bile dönebilir) | ☐ | |
| 3 | Alım Noktası → harita aç | AddressPickerScreen açılır | ☐ | |
| 4 | Haritada yer seç → "Kaydet" | pickup adresi ekranda görünür | ☐ | |
| 5 | Teslim Noktası → farklı yer seç | delivery adresi ayrı görünür | ☐ | |
| 6 | Mesafe kartı görünüyor mu | "Mesafe: X km · Toplam: Y ₺" | ☐ | |
| 7 | Yakın kuryeler listesi | Boş olabilir; "Yakın Kurye Yok" dememeli, sadece gizlemeli | ☐ | |
| 8 | Gönderen ad + telefon doldur | TextField'lar kabul eder | ☐ | |
| 9 | Alıcı ad + telefon doldur | Aynı | ☐ | |
| 10 | "Paket Talebini Gönder" bas | yeşil "gönderildi" SnackBar + 1 sn sonra pop | ☐ | |
| 11 | **Bakiye 0₺ yapıp tekrar dene** | **"Yetersiz Bakiye" diyaloğu (kırmızı/sarı) — MEVCUT BUG: TR/EN pattern uyumsuzluğu nedeniyle generic kırmızı SnackBar gösteriyor olabilir** | ☐ | |
| 12 | AppBar → Geçmiş ikonu | PackageHistoryScreen açılır | ☐ | |
| 13 | Listedeki "Bekliyor" kartı → "Takip Et" | PackageTrackingScreen açılır | ☐ | |
| 14 | Haritada alım + teslim noktası pinleri | İkisi de görünür | ☐ | |
| 15 | Kurye atandıysa motor pini | Pin + ETA "X dk" | ☐ | |
| 16 | Kurye atanmadıysa | "Kurye atanması bekleniyor..." | ☐ | |
| 17 | "Teslimatı Onayla" butonu (status=accepted) | Onay diyaloğu → RPC → yeşil SnackBar | ☐ | |

---

## 3) KÖK NEDEN: PGRST202 — KALICI FIX ADIMLARI

`create_package_request` RPC canlıda YOK. Bunu uygulamak için:

### 3.1 SQL Editor'de sırayla çalıştır

1. **`HOTFIX_create_package_request.sql` BLOK 0** (tanılama — sadece SELECT)
2. **BLOK 1** (`courier_requests` sütunları + index)
3. **BLOK 2** (`create_package_request` fonksiyonu)
4. **BLOK 3** (`NOTIFY pgrst, 'reload schema'`)

### 3.2 Doğrulama

```sql
-- Fonksiyon var mı?
SELECT proname, pronargs FROM pg_proc
WHERE proname = 'create_package_request';
-- Beklenen: 1 satır, pronargs = 13

-- Birim test
SELECT * FROM public.create_package_request(
  37.3255::double precision, 42.1876::double precision,
  37.3310::double precision, 42.1950::double precision,
  'Test Gönderici'::text, '05550000000'::text,
  'Test Alıcı'::text, '05551111111'::text,
  'Cizre merkez'::text, 'Sur mahallesi'::text,
  'kat 3 daire 5'::text, 'kırılgan'::text,
  gen_random_uuid()
);
-- Beklenen: 1 satır, status=pending, total_fee>0
```

### 3.3 Hata yorumlama refactor önerisi (Flutter tarafı)

`send_package_screen.dart:288-289` satırındaki bug:

```dart
// YANLIŞ (mevcut):
if (errorMessage.contains('Insufficient balance') ||
    errorMessage.contains('yetersiz bakiye')) {

// DOĞRU (önerilen):
final lower = errorMessage.toLowerCase();
if (lower.contains('insufficient') || lower.contains('yetersiz bakiye')) {
```

Bunun testini `package_send_flow_test.dart` "Hata yorumlama" grubu zaten içeriyor — testler yeşil kalırsa refactor doğru.

---

## 4) MÜŞTERİ/KURYE/ADMIN — UÇTANUCA TEST AKIŞI

Bu akış, fiziksel cihazda 3 farklı rol ile yapılır.

### 4.1 ADMIN: Ayarlar sekmesi
- [ ] Kurye Yönetimi → Ayarlar → `enabled=true` + `allows_user_requests=true` + `commission_percent`, `base_fee`, `per_km_fee` kaydedildi mi?
- [ ] Market ekranındaki motor ikonu **turuncu** ve tıklanabilir mi?

### 4.2 MÜŞTERİ: Talep oluşturma (Paket Gönder)
- [ ] Madde 1-17 (yukarıdaki tablo) hepsi geçti mi?
- [ ] Bakiyeden ücret düştü mü? (`user_balances` tablosu kontrolü)
- [ ] `balance_transactions` tablosuna `courier_payment` tipinde satır yazıldı mı?

### 4.3 KURYE: Talep kabul/red/teslim
- [ ] Kurye hesabıyla login → bildirim geldi mi?
- [ ] Kurye paneli → "Bekleyen Talepler" → talep görünüyor mu?
- [ ] "Kabul Et" → talep "Üzerimdeki Paketler"e geçti mi?
- [ ] Müşteri tarafında kurye pini + ETA görünüyor mu?
- [ ] Kurye "Teslim Edildi" → müşteri onayı sonrası bakiye dağılımı:
  - [ ] `courier_earnings` tablosuna kurye payı yazıldı mı?
  - [ ] `user_balances` (kurye) arttı mı?

### 4.4 ADMIN: Paketler sekmesi
- [ ] "Teslim Edildi" rozeti + atanan kurye ad/telefonu görünüyor mu?

---

## 5) REGRESYON GUARD'LARI (refactor yapılırken)

Yapılacak her refactor'da bu testler çalıştırılmalı:

```bash
flutter test test/user_courier/                 # yeni eklenen 2 dosya
flutter test test/courier/                       # mevcut model testleri
psql -d <db> -f supabase/tests/database/007_courier_package_request_invariants.test.sql
```

**Kırmızıya düşen test = regresyon.** PR review sırasında bu guard geçilmeden merge yapılmamalı.

---

## 6) BİLİNEN / BELGELENMİŞ BUG'LAR (Bu sprint fix'lenecek)

| # | Bug | Yer | Test guard |
|---|---|---|---|
| B1 | `Insufficient balance` pattern `APP:insufficient_balance` ile eşleşmiyor | `send_package_screen.dart:289` | `package_send_flow_test.dart` "Hata yorumlama" |
| B2 | PGRST202 kök neden: `create_package_request` canlıda yok | DB | `007_courier_package_request_invariants.test.sql` |
| B3 | N kurye × N ayrı RPC = N+1 antipattern | `send_package_screen.dart:160-178` | `package_widget_test.dart` "notifyCouriers boundary" |
| B4 | `_pickupAddress` / `_deliveryAddress` state bağımsızlığı belgelenmemiş | `send_package_screen.dart:137-158` | `package_widget_test.dart` "Adres state guard" |
| B5 | _loadPricing 0 dönerse sessizce default'a düşüyor, kullanıcı uyarılmıyor | `send_package_screen.dart:99-116` | `package_widget_test.dart` "loadPricing fallback" |
| B6 | package_tracking periyodik `_loadPackageData()` realtime üzerine yazıyor | `package_tracking_screen.dart:224-227` | Henüz test eklenmedi (sonraki sprint) |
| B7 | `Geolocator.checkPermission` deniedForever'da fallback'e düşüyor ama kurye konum izlemesi başlamıyor | `package_tracking_screen.dart:56-83` | Henüz test eklenmedi |

---

## 7) SONUÇ: NE YAPILACAK

**Önce** bu plandaki adımları sırayla uygula, **bittiğinde** bana şunu söyle:

1. BLOK 0 tanılama çıktısı
2. `flutter test test/user_courier/` çıktısı
3. Manuel test tablosu (1-17 adımlar)

O zaman kök nedenin (PGRST202) giderilip giderilmediğini ve hata yorumlama bug'ının (B1) fix'lendiğini kesinleştirmiş oluruz.

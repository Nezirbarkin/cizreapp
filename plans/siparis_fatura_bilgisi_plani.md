# Siparişlere Müşteri Fatura Bilgileri Ekleme Planı

## Bağlam
- Pazaryeri (marketplace) modeli: platform sizin; faturayı mağaza kesiyor.
- Sistem görevi: müşterinin fatura bilgilerini siparişe kaydetmek ve mağaza/admin/sipariş PDF'inde göstermek.
- **E-fatura/e-arşiv entegrasyonu YOK** — sadece bilgi saklama + PDF gösterimi.
- Türkiye mevzuatı: Şahıs firmaları için T.C. kimlik no; şirket/tüzel kişi için vergi no gerekir → "alıcı tipi" alanı (bireysel/kurumsal) eklenir.

## Onaylanan Kararlar
1. **Zorunlu mu opsiyonel mi**: OPSİYONEL — boş bırakılabilir, düşük friction.
2. **Profil'e kayıt**: EVET — "bilgilerimi kaydet" checkbox ile.
3. **Satıcı paneli**: Satıcı kendi siparişinde müşterinin fatura bilgisini GÖRÜR (PDF/fatura kesimi için).

## Mimari Desen
Adres modelinde zaten uygulanan "kayıtlı profil + sipariş snapshot" deseni kullanılır:
- `profiles` tablosu → tekrar kullanılabilir kayıtlı fatura bilgileri.
- `orders` tablosu → sipariş anındaki dondurulmuş snapshot (sonradan değişmez).

## Adımlar

### 1. Veritabanı (Supabase Migration)
Dosya: `supabase/migrations/<timestamp>_add_invoice_info.sql`

`profiles` tablosuna:
- `invoice_type` TEXT DEFAULT 'individual' CHECK IN ('individual','corporate')
- `invoice_full_name` TEXT
- `invoice_tax_number` TEXT
- `invoice_tc_no` TEXT
- `invoice_tax_office` TEXT
- `invoice_address` TEXT
- `invoice_email` TEXT
- `invoice_saved_at` TIMESTAMPTZ

`orders` tablosuna (aynı 7 alan, snapshot):
- `invoice_type`, `invoice_full_name`, `invoice_tax_number`, `invoice_tc_no`, `invoice_tax_office`, `invoice_address`, `invoice_email`

Tüm kolonlar NULLABLE (geriye uyumluluk). RLS mevcut politikalarla aynı kalır.

### 2. Model Katmanı
- Yeni: `lib/core/models/invoice_info_model.dart`
  - `InvoiceType` enum (individual/corporate) + label
  - `InvoiceInfo` sınıfı: tüm alanlar + fromJson/toJson/copyWith
  - `validate()`: kurumsalda vergi no 10 hane, bireyselde TC 11 hane (uzunluk kontrolü)
- Güncelle: `lib/core/models/order_model.dart` (`Order`) — 7 yeni alan, fromJson/toJson/copyWith
- Güncelle: `lib/core/models/user_model.dart` (`UserProfile`) — 7 yeni alan

### 3. Servis Katmanı
- Yeni: `lib/core/services/invoice_service.dart`
  - `getMyInvoiceInfo()`, `saveInvoiceInfo(InvoiceInfo)`, `clearInvoiceInfo()`

### 4. UI Katmanı
- Checkout ekranları (3 dosya):
  - `lib/features/shop/screens/checkout_screen.dart`
  - `lib/features/market/screens/checkout_screen.dart`
  - `lib/features/market/screens/multi_shop_checkout_screen.dart`
  - Adres seçiminin altına "Fatura Bilgileri" bölümü
  - 3 radio: "Adres bilgilerimle aynı" / "Kayıtlı fatura bilgilerimi kullan" / "Farklı bilgi gir"
  - Dinamik form: bireysel (ad+TC) vs kurumsal (unvan+vergi dairesi+vergi no+adres)
  - "Bilgilerimi kaydet" checkbox
- Profil ekranı: `lib/features/profile/screens/profile_screen.dart` veya yeni `invoice_info_screen.dart`
- Sipariş detay: `lib/features/market/screens/order_detail_screen.dart`
- Satıcı paneli: `lib/features/seller/screens/seller_orders_screen.dart`

### 5. Doğrulama ve Güvenlik
- Frontend: regex/uzunluk kontrolü.
- Backend doğrulama: kapsam dışı (GİB entegrasyonu yok).
- KVKK: T.C. no hassas; RLS yeterli; loglara yazılmamasına dikkat.

### 6. Geçiş
- Yeni kolonlar NULLABLE → mevcut siparişler etkilenmez.
- Fatura bilgisi olmayan eski siparişlerde null gösterilir.

## Uygulama Sırası
1. Supabase migration dosyası yaz
2. `InvoiceInfo` modeli oluştur
3. `Order` ve `UserProfile` modellerini güncelle
4. `InvoiceService` yaz
5. Checkout ekranlarını güncelle (shop + market + multi-shop)
6. Profil ekranını güncelle
7. Sipariş detay + satıcı panelini güncelle
8. `flutter analyze` ile doğrula
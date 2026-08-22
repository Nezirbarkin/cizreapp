# İlanlar Modülü

## Kapsam

İlan modülü kayıp, satılık, kiralık ve hizmet ilanlarını kapsar. Flutter kodu bakım kolaylığı için `lib/ilanlar/` altında; veritabanı şeması ise `20260817000006_ilanlar_system.sql` migration'ında tutulur.

## Kurallar

- Kayıp ilanlarında fiyat alanı arayüzde gösterilmez; kötü niyetli istemci fiyat gönderse bile veritabanı fiyatı temizler.
- Satılık ve kiralık kategorilerinde pozitif fiyat zorunludur.
- Kullanıcı yalnız kendi adına ilan ve görsel oluşturabilir.
- **Varsayılan olarak yeni ilanlar admin onayı beklemeden doğrudan yayınlanır** (`ilan_settings.require_approval` varsayılanı `false` — bkz. `20260817000022_default_ilan_require_approval_false.sql`). Admin isterse Ayarlar sekmesinden onay zorunluluğunu tekrar açabilir.
- Admin tüm ilanları denetleyebilir; yayınlayabilir, reddedebilir, arşivleyebilir veya silebilir — bu moderasyon altyapısı varsayılan davranıştan bağımsız olarak her zaman aktiftir.
- Admin bir ilanı onaylayınca/reddedince/arşivleyince ilan sahibi `notifications` tablosu üzerinden bildirim alır (bkz. `20260817000023_notify_owner_on_ilan_status_change.sql`).
- İlan sistemi, kullanıcı paylaşımı, misafir erişimi ve onay zorunluluğu ayrı ayrı kapatılabilir.
- Görseller MIME türü, 10 MB dosya sınırı, ilan başına görsel sınırı ve kullanıcı UUID klasörü politikasıyla korunur.
- **Kategori bazlı yayınlama ücreti**: her kategoride `publish_fee` (₺, varsayılan 0 = ücretsiz) tanımlanabilir — örn. "Kayıp" kategorisi 0 TL kalır, "Satılık" için admin ücret belirleyebilir. Ücret, ilan gönderilirken (onay durumundan bağımsız) mevcut bakiye sisteminden (`user_balances`/`balance_transactions`, İyzico ile yüklenen TL) düşülür; bakiye yetersizse ilan hiç oluşturulmaz. Admin ilanı **reddederse** ücret otomatik iade edilir; kullanıcı kendi ilanını silerse veya admin arşivlerse iade edilmez. Bkz. `20260817000024_ilan_publish_fee_balance_type.sql` (yeni enum değerleri) ve `20260817000025_ilan_category_publish_fee.sql` (kolonlar + tahsilat/iade mantığı `validate_ilan_write()` trigger'ında). Kasıtlı olarak `deduct_from_balance`/`add_to_balance` RPC'leri çağrılmaz — bu RPC'ler `20260727000008_harden_balance_rpc_permissions.sql` ile başka amaçlara (kurye ödemesi, servis akışları) kilitlenmiş; trigger zaten SECURITY DEFINER olduğu için aynı muhasebe deseni (`total_spent`/`total_refunds`) doğrudan uygulanır.

## Kullanıcı Ekranları

- **İlanlarım** (`lib/ilanlar/screens/my_ilanlar_screen.dart`): kullanıcının kendi ilanlarını Tümü/Yayında/Bekleyen/Reddedilen/Arşiv sekmelerinde gösterir. İlan listesi AppBar'ından ve profil ayarları menüsünden erişilebilir.
- İlan listesinde fiyat aralığı, ürün durumu ve sıralama (en yeni/fiyat artan/fiyat azalan) için filtre paneli (`lib/ilanlar/widgets/ilan_filter_sheet.dart`).

## Admin Paneli

Admin menüsündeki **İlanlar & Kategoriler** alanı üç sekmedir:

1. **İlanlar:** Moderasyon ve durum filtresi.
2. **Kategoriler:** Kategori oluşturma, düzenleme, sıralama ve aktif/pasif yönetimi.
3. **Ayarlar:** Modül anahtarı, tüm kullanıcıların paylaşım izni, onay süreci, limitler ve ana sayfa gösterimi.

## Kurulum

Supabase migration'ları sıralı şekilde uygulanmalıdır. Migration; tabloları, indeksleri, RLS politikalarını, doğrulama tetikleyicilerini, varsayılan kategorileri ve `ilan-images` bucket'ını atomik transaction içinde oluşturur.

## Testler

- Model ayrıştırma testleri: `test/ilanlar/ilan_models_test.dart`
- Backend güvenlik sözleşmesi: `test/contracts/ilanlar_backend_contract_test.dart`

Önerilen doğrulama komutları:

```powershell
dart format lib/ilanlar test/ilanlar test/contracts/ilanlar_backend_contract_test.dart
flutter analyze lib/ilanlar lib/features/market/screens/market_screen.dart lib/features/admin/screens lib/features/profile/screens/profile_screen.dart
flutter test test/ilanlar test/contracts/ilanlar_backend_contract_test.dart
```

Migration'lar proje deseni gereği `supabase db push` ile değil, Supabase SQL Editor üzerinden elle sırayla uygulanır (bkz. `supabase/README.md`). `20260817000021` – `20260817000024` dosyaları sırayla uygulandıktan sonra:

```sql
SELECT require_approval FROM public.ilan_settings WHERE id = 1; -- false bekleniyor
SELECT tgname FROM pg_trigger WHERE tgrelid = 'public.ilanlar'::regclass; -- trg_notify_owner_on_ilan_status_change görünmeli

-- Yayınlama ücreti testi:
UPDATE public.ilan_categories SET publish_fee = 25 WHERE slug = 'satilik';
-- (yetersiz bakiyeli bir kullanıcıyla o kategoride ilan denemesi INSERT'i reddetmeli)
-- (yeterli bakiyeli kullanıcı ilan oluşturunca) SELECT paid_fee FROM public.ilanlar WHERE id = '<yeni-ilan-id>';
-- (admin reddedince) SELECT fee_refunded FROM public.ilanlar WHERE id = '<yeni-ilan-id>'; -- true
```

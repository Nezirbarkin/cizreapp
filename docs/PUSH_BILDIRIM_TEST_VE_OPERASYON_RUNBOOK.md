# Push Bildirim Test ve Operasyon Runbook

## Güvenlik sınırı

- Üretimde `all_users` veya `logged_in_users` topic'ine test gönderimi yapılmaz.
- Firebase Console üzerinden topic/campaign testi yapılmaz.
- Fiziksel test yalnız özel test hesabının kendi cihazında ve tek kullanıcı UUID'si ile yapılır.
- Test hesabı gerçek müşteri, satıcı, kurye veya yönetici hesabı olamaz.
- Test öncesi seçilen UUID ve cihaz token eşleşmesi iki kişi tarafından doğrulanır.

## Otomatik test birimleri

1. **Flutter istemci:** Android/iOS izinleri, background handler, token gizliliği ve genel topic aboneliği yasağı.
2. **Outbox worker:** FCM HTTP v1 payload şekli, kullanıcı tercihleri, kesin geçersiz token temizliği ve güvenli hata sınıflandırması.
3. **Veritabanı:** outbox RLS, atomik claim, retry/dead geçişleri ve yalnız service-role erişimi.
4. **Edge Functions:** aktif fonksiyonlarda emekliye ayrılmış doğrudan push endpoint çağrısı bulunmaması.

## Zararsız doğrulama sırası

1. Statik ve birim testlerini çalıştır; bu aşama ağa push göndermez.
2. Güvenli health-check SQL'ini yalnız okuma amacıyla çalıştır. Bildirim INSERT etme.
3. Outbox'ta son 24 saat için `pending`, `failed`, `dead`, `sent` sayılarını ve en eski kaydın yaşını kontrol et.
4. Edge Function loglarında token, içerik veya service-account verisi bulunmadığını doğrula.
5. Fiziksel test gerekiyorsa aşağıdaki tek-alıcı prosedürüne geç.

## Tek cihaz fiziksel test prosedürü

1. Ayrı bir test kullanıcısı ve yalnız test ekibinin kontrolündeki cihaz kullan.
2. Test cihazında oturum aç; token kaydı başarı logunu doğrula fakat token değerini kopyalama veya loglama.
3. Admin panelinde hedefi **Kişisel** seç ve test kullanıcısını kullanıcı adı + UUID ile doğrula.
4. `all`, `customers`, `sellers`, topic veya broadcast hedefi seçme.
5. Başlıkta `[TEST-TEK-CIHAZ]` öneki kullan ve kişisel/veri içeren metin yazma.
6. Tek bildirimi gönder; ikinci gönderimden önce outbox ve cihaz sonucunu doğrula.
7. Uygulama açık, arka planda ve kapalı durumlarını üç ayrı tekli bildirimle test et.
8. Bildirime dokunma yönlendirmesini, kanal/ses davranışını ve uygulama içi kaydı kontrol et.
9. Test bitince test hesabından çıkış yap; token temizleme ve legacy topic unsubscribe logunu doğrula.

## Başarı ölçütleri

- Alıcı yalnız doğrulanan test UUID'sidir.
- Outbox kaydı `sent` olur; retry/dead birikimi oluşmaz.
- Uygulama açıkken local notification, arka plan/kapalıyken sistem bildirimi görünür.
- Bildirime dokununca uygulama güvenli bir rotaya açılır.
- Üretim kullanıcılarından bildirim raporu gelmez.

## Durdurma koşulları

- Hedef kullanıcı UUID'si belirsizse gönderim durdurulur.
- Topic/broadcast seçiliyse gönderim durdurulur.
- Outbox'ta hızlı pending/failed artışı varsa worker cron geçici olarak durdurulur; yeni bildirim oluşturulmaz.
- FCM `INVALID_ARGUMENT` hatasında token silinmez; payload/proje ayarı incelenir.
- Yalnız kesin `UNREGISTERED` sonucunda cihaz tokenı temizlenir.

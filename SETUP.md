# CizreApp - Setup Checklist

## 📋 Supabase Kurulumu

### Adım 1: Supabase Projesi Oluştur
- [ ] https://supabase.com adresine git
- [ ] "New Project" tıkla
- [ ] Proje adı: `cizreapp`
- [ ] Şifre belirle
- [ ] Region seç (Europe - Istanbul)
- [ ] "Create new project" tıkla

### Adım 2: Veritabanını Oluştur
- [ ] Proje oluştuktan sonra, "SQL Editor" bölümüne git
- [ ] "New query" tıkla
- [ ] `supabase_schema.sql` dosyasının tüm içeriğini kopyala
- [ ] SQL Editor'a yapıştır
- [ ] "Run" tıkla

### Adım 3: API Keys Kopyala
- [ ] Settings > API sekmesine git
- [ ] "Project URL"'i kopyala
- [ ] "anon" (public) API key'i kopyala
- [ ] Bu bilgileri `lib/core/constants/app_constants.dart`'a yapıştır:
  ```dart
  static const String supabaseUrl = 'BURAYA_KOPYALA';
  static const String supabaseAnonKey = 'BURAYA_KOPYALA';
  ```

### Adım 4: Authentication Ayarla
- [ ] Settings > Auth settings'e git
- [ ] "Email" doğrulamasını aç
- [ ] SMTP (email) ayarlarını yapılandır (isteğe bağlı)

### Adım 5: Storage Bucket'ları Oluştur
- [ ] Storage bölümüne git
- [ ] Yeni bucket oluştur: `profiles` (Public)
- [ ] Yeni bucket oluştur: `products` (Public)
- [ ] Yeni bucket oluştur: `posts` (Public)
- [ ] Yeni bucket oluştur: `stories` (Public)

---

## 🔧 Flutter Kurulumu

### Adım 1: Paketleri Yükle
```bash
cd c:/Users/lenovo/cizreapp
flutter pub get
```

### Adım 2: Uygulamayı Çalıştır
```bash
flutter run
```

---

## 📱 İlk Çalıştırma

- [ ] Eğer `flutter run` hata verirse, `flutter doctor` çalıştır
- [ ] Gerekli araçları kur
- [ ] Emülatörü başlat veya Android/iOS cihazını bağla
- [ ] Tekrar `flutter run` çalıştır

---

## ✅ Başarı Kriteri

- [ ] Uygulama başlarsa
- [ ] Splash screen gösterilirse
- [ ] Hatalar yoksa ✅ Başarılı!

---

## 🚨 Sık Sorunlar

### Sorun: "Target of URI doesn't exist"
**Çözüm:** `flutter pub get` çalıştır

### Sorun: "Supabase initialize failed"
**Çözüm:** API keys doğru girildi mi kontrol et

### Sorun: "Device not found"
**Çözüm:** Emülatörü başlat veya cihazı bağla: `flutter devices`

---

## 📞 Sonraki Adımlar

Kurulum tamamlandıktan sonra:

1. **Authentication Modülü** - Login/Register screens
2. **Ana Navigation** - Bottom tab navigation
3. **Market Modülü** - Kategoriler ve ürünler
4. **Sosyal Medya** - Post feed
5. **Sipariş Sistemi** - Alışveriş flow

Her modül için ayrı PR (Pull Request) yapılacak.

---

**Not:** Supabase ücretsiz tier ile başlayabilirsin, daha sonra production ortamına taşıyabilirsin.

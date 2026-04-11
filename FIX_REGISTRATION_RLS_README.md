# Kayıt Sırasında RLS Hatası Çözümü

## 🔴 Sorun
Kayıt sırasında şu hata alınıyor:
```
PostgrestException(message: new row violates row-level security policy for table "profiles", code: 42501, details: Unauthorized, hint: null)
```

Bu hata, `profiles` tablosuna manuel INSERT yaparken RLS (Row Level Security) politikasının izin vermemesinden kaynaklanıyor.

## ✅ Çözüm

### Adım 1: SQL Trigger'ı Çalıştır

[`FIX_PROFILES_REGISTRATION_RLS.sql`](FIX_PROFILES_REGISTRATION_RLS.sql) dosyasını Supabase SQL Editor'de çalıştırın.

Bu script:
1. ✅ Mevcut RLS policy'lerini kontrol eder
2. ✅ Gerekli INSERT, SELECT, UPDATE policy'lerini oluşturur
3. ✅ **Otomatik profil oluşturma trigger'ı ekler** (ÖNERİLEN ÇÖZÜM)
4. ✅ Trigger'ın düzgün çalışıp çalışmadığını verify eder

### Adım 2: Flutter Kodunu Güncelle

Aşağıdaki dosyalar güncellendi (manuel profil oluşturma kodları kaldırıldı):

#### ✅ Güncellenen Dosyalar

1. **lib/features/auth/screens/register_screen_v2.dart** (Satır 78-85)
   - ❌ Manuel `profiles.insert()` kaldırıldı
   - ✅ Trigger otomatik profil oluşturacak

2. **lib/features/auth/services/auth_service.dart** (Satır 128-138)
   - ❌ `signUp()` sonrası manuel `profiles.upsert()` kaldırıldı
   - ✅ `_ensureProfileExists()` sadece kontrol yapacak şekilde güncellendi

3. **lib/features/profile/screens/profile_screen.dart** (Satır 209-243)
   - ❌ `_createDefaultProfile()` içindeki manuel INSERT kaldırıldı
   - ✅ Sadece profil kontrol edip trigger'ın çalışmasını bekliyor

## 🎯 Nasıl Çalışır?

### Otomatik Profil Oluşturma (Trigger)

```sql
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
SECURITY DEFINER -- Service role yetkisi ile çalışır, RLS bypass edilir
```

**Avantajları:**
- 🔒 Güvenli: Service role yetkisi ile çalışır
- 🚀 RLS bypass edilir, hata almaz
- 🎯 Otomatik: Kullanıcı kaydı olur olmaz profil oluşur
- 📦 Temiz: Flutter kodu daha basit

**İş Akışı:**
```
1. Kullanıcı kayıt olur (auth.signUp)
   ↓
2. auth.users tablosuna yeni satır eklenir
   ↓
3. on_auth_user_created trigger tetiklenir
   ↓
4. handle_new_user() fonksiyonu çalışır
   ↓
5. profiles tablosuna OTOMATIK profil oluşturulur (RLS bypass)
   ↓
6. Kullanıcı meta datası (username, full_name) profil tablosuna kopyalanır
```

## 🧪 Test Etme

### 1. SQL Trigger Test

```sql
-- Trigger'ın var olduğunu kontrol et
SELECT 
    trigger_name,
    event_manipulation,
    event_object_table,
    action_statement
FROM information_schema.triggers
WHERE trigger_name = 'on_auth_user_created';
```

### 2. Flutter Test

```dart
// Kayıt ol
final response = await Supabase.instance.client.auth.signUp(
  email: 'test@example.com',
  password: '123456',
  data: {
    'username': 'testuser',
    'full_name': 'Test User',
  },
);

// Profil otomatik oluşturulmalı
final profile = await Supabase.instance.client
    .from('profiles')
    .select()
    .eq('id', response.user!.id)
    .single();

print('Profil oluşturuldu: ${profile['username']}');
```

## 📋 Alternatif Çözüm (Önerilmez)

Eğer trigger çalışmazsa, geçici olarak RLS'yi devre dışı bırakabilirsiniz:

```sql
-- ⚠️ SADECE TEST İÇİN
ALTER TABLE profiles DISABLE ROW LEVEL SECURITY;
```

**UYARI:** Production'da RLS'yi asla devre dışı bırakmayın!

## 🔍 Sorun Giderme

### Trigger Çalışmıyor mu?

```sql
-- Fonksiyonun var olduğunu kontrol et
SELECT proname, prosrc 
FROM pg_proc 
WHERE proname = 'handle_new_user';

-- Trigger'ın aktif olduğunu kontrol et
SELECT * FROM pg_trigger WHERE tgname = 'on_auth_user_created';
```

### Profil Oluşturulmadı mı?

```sql
-- Son auth kullanıcısı ve profilini kontrol et
SELECT 
    u.id,
    u.email,
    u.created_at as user_created,
    p.username,
    p.full_name,
    p.created_at as profile_created
FROM auth.users u
LEFT JOIN public.profiles p ON u.id = p.id
ORDER BY u.created_at DESC
LIMIT 5;
```

## 📝 Notlar

1. **Username Benzersizliği:** Username'ler unique olmalı. Eğer kullanıcı username göndermezse, trigger boş string atar.

2. **Meta Data:** `signUp()` sırasında `data` parametresinde gönderilen veriler `raw_user_meta_data` olarak saklanır ve trigger tarafından kullanılır.

3. **Hata Yönetimi:** Trigger içinde hata olursa bile kullanıcı kaydı devam eder (EXCEPTION bloğu sayesinde).

4. **Google/Apple Sign In:** OAuth ile giriş yapılırsa da trigger çalışır ve profil otomatik oluşturulur.

## 🚀 Sonuç

Bu çözüm ile:
- ✅ RLS hatası almadan kayıt olunabilir
- ✅ Profil otomatik oluşturulur
- ✅ Kod daha temiz ve bakımı kolay
- ✅ Güvenlik korunur (RLS aktif kalır)

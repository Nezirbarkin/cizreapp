# Grup Katılım Bildirimleri Deployment Dokümanı

## Açıklama
Bu değişikliklerle gizli veya açık gruplara katılım istekleri ve direkt katılımlar için bildirim sistemi güncellenmiştir.

## Değişiklikler

### 1. Dart Kod Değişiklikleri

#### `lib/features/chat/services/group_chat_service.dart`
**Değiştirilen Metotlar:**
- `_sendJoinRequestNotificationToOwner()` - Gizli gruba katılma isteği bildirimi
- `_sendJoinNotificationToOwner()` - Açık gruba direkt katılım bildirimi
- `_sendMemberJoinedNotificationToOwner()` - Onaylanan katılım bildirimi

**Önceki Davranış:**
- Sadece grup kurucusuna (`created_by`) bildirim gönderiliyordu

**Yeni Davranış:**
- Tüm admin ve moderatörlere bildirim gönderiliyor
- Kendi kendine bildirim gönderilmiyor (katılan kişiye bildirim gitmiyor)
- Admin/moderator bulunamazsa uyarı log'u atılıyor

#### `lib/core/models/notification_preferences_model.dart`
**Eklenen Alanlar:**
- `groupJoinRequestsEnabled` - Grup katılma isteği bildirimi tercihi
- `groupMemberJoinedEnabled` - Gruba üye katıldı bildirimi tercihi

#### `lib/core/services/notification_preferences_service.dart`
**Güncellenen Metotlar:**
- `_createDefaultPreferences()` - Grup bildirimlerini varsayılan olarak ekler
- `updatePreferences()` - Grup bildirim parametrelerini ekler
- `isNotificationEnabled()` - `group_join_request` ve `group_member_joined` kontrolü ekler
- `toggleAllNotifications()` - Grup bildirimlerini de kapsar

#### `lib/features/profile/screens/notification_settings_screen.dart`
**Eklenen UI:**
- "Gruplar" bölümü eklendi
- "Katılma İstekleri" açma/kapama switch'i
- "Yeni Üye Katılımı" açma/kapama switch'i

### 2. SQL Script
**Dosya:** `ADD_GROUP_NOTIFICATION_PREFERENCES.sql`

Bu script şu işlemleri yapar:
1. `notification_preferences` tablosuna yeni kolonlar ekler:
   - `group_join_requests_enabled` (BOOLEAN, DEFAULT true)
   - `group_member_joined_enabled` (BOOLEAN, DEFAULT true)
2. Mevcut kayıtlar için NULL değerleri true olarak günceller

## Bildirim Tipleri

| Type | İsim | Açıklama |
|------|------|----------|
| `group_join_request` | Grup Katılma İsteği | Birisi grubunuza katılmak istediğinde admin/moderatorlere bildirim gider |
| `group_member_joined` | Gruba Katılım | Birisi grubunuza katıldığında admin/moderatorlere bildirim gider |

## Deployment Adımları

### Adım 1: SQL Script'i Çalıştır
```bash
# Supabase Dashboard > SQL Editor veya
supabase db execute --file ADD_GROUP_NOTIFICATION_PREFERENCES.sql
```

### Adım 2: Uygulamayı Yeniden Derle
```bash
flutter clean
flutter pub get
flutter build apk --release  # Android için
# veya
flutter build ios --release   # iOS için
```

### Adım 3: Test
1. Test kullanıcısı oluşturun
2. Bir grup oluşturun (admin ve moderatör ekleyin)
3. Başka bir kullanıcıyla:
   - Açık gruba direkt katılın
   - Gizli gruba katılma isteği gönderin
4. Admin ve moderatörlerin bildirim aldığını doğrulayın
5. Bildirim ayarları ekranından grup bildirimlerini kapatıp açın

## Kontrol Sorguları

```sql
-- Kolonların eklenip eklenmediğini kontrol
SELECT column_name, data_type, column_default
FROM information_schema.columns
WHERE table_name = 'notification_preferences'
AND column_name IN ('group_join_requests_enabled', 'group_member_joined_enabled');

-- Kullanıcı tercihleri kontrol
SELECT user_id, group_join_requests_enabled, group_member_joined_enabled 
FROM notification_preferences 
LIMIT 10;

-- Son bildirimleri kontrol
SELECT * FROM notifications 
WHERE type IN ('group_join_request', 'group_member_joined')
ORDER BY created_at DESC
LIMIT 20;
```

## Rollback (Geri Alma)

Eğer bir sorun olursa:

```sql
-- Kolonları sil
ALTER TABLE notification_preferences 
DROP COLUMN IF EXISTS group_join_requests_enabled,
DROP COLUMN IF EXISTS group_member_joined_enabled;
```

Dart kodunu değişiklikten önceki haline geri almak için git kullanabilirsiniz.

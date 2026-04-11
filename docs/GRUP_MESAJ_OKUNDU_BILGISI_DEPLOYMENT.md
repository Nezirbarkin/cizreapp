# Grup Mesajı Okundu Bilgisi (Read Receipts) & Yanıt Özellikleri Deployment Rehberi

Bu özellik, grup sohbetlerinde:
1. Mesajları kimlerin okuduğunu gösterir
2. Tüm üyeler okuduysa çift tik, değilse tek tik gösterir
3. Mesaja tıklayınca kimler okudu popup'ı açılır
4. Mesajlara yanıt verme (reply) özelliği

## 📋 Özellikler

### Okundu Bilgisi (Read Receipts)
- **Read Receipts Tablosu**: `group_message_read_receipts` tablosu her mesaj için kimlerin okuduğunu takip eder
- **Otomatik Okundu**: Kullanıcı sohbet ekranını açtığında mesajlar otomatik okundu olarak işaretlenir
- **Realtime Sync**: Okundu bilgileri realtime olarak güncellenir

### Tik Durumları (Mesaj Durumu İkonları)
- **Tek tik (gri)**: Hiç kimse okumadı
- **Çift tik (gri)**: Bazı üyeler okudu (ama hepsi değil)
- **Çift tik (mavi)**: Tüm üyeler okudu

### Kimler Okudu? Popup
- Kendi mesajınıza **tıklayınca** veya **long press** yapınca açılır
- Okuyan üyelerin listesi, profil fotoğrafı ve okunma zamanı gösterilir
- Kaç üyenin okuduğu ve kaçının henüz okumadığı bilgisi

### Yanıt (Reply) Özelliği
- Mesaja **long press** yapınca menü açılır
- "Yanıtla" seçeneği ile mesaja yanıt verebilirsiniz
- Yanıtlanan mesajın içeriği ve gönderen adı gösterilir

## 🚀 Deployment Adımları

### 1. SQL Migration Çalıştır

Supabase SQL Editor'da [`ADD_GROUP_MESSAGE_READ_RECEIPTS.sql`](../ADD_GROUP_MESSAGE_READ_RECEIPTS.sql) dosyasını çalıştırın:

```bash
# Dosyayı Supabase SQL Editor'a yapıştırın veya:
psql -h your-project.supabase.co -U postgres -d postgres -f ADD_GROUP_MESSAGE_READ_RECEIPTS.sql
```

Bu işlem şunları oluşturur:
- `group_message_read_receipts` tablosu
- `reply_to_id` sütunu (mesaj yanıt desteği için)
- Gerekli indeksler
- RLS politikaları (performans optimize: `(select auth.uid())`)
- RPC fonksiyonları:
  - `get_message_read_receipts` - Okuyanları listeler
  - `mark_group_messages_read_receipts` - Mesajları okundu işaretler
  - `get_message_read_count` - Okunma sayısını döner
  - `get_group_messages_with_read_count` - Mesajları read_by_count ile getirir
- Realtime publication
- View: `group_messages_with_read_count` - Performans için

### 2. Kod Değişiklikleri

Aşağıdaki dosyalar zaten güncellenmiştir:

- ✅ [`lib/core/models/group_message_model.dart`](../lib/core/models/group_message_model.dart) 
  - `MessageReadReceipt` modeli
  - `replyToId`, `replyToContent`, `replyToSenderName` alanları
  - `isReadByAll()` metodu

- ✅ [`lib/features/chat/services/group_chat_service.dart`](../lib/features/chat/services/group_chat_service.dart)
  - Read receipts fonksiyonları
  - Reply destekli `sendGroupMessage()`
  - `_getGroupMessagesFallback()` ile reply bilgisi çekme

- ✅ [`lib/features/chat/screens/group_chat_screen.dart`](../lib/features/chat/screens/group_chat_screen.dart)
  - "Kimler okudu?" bottom sheet UI
  - Tik durumu görselleştirme (tek/çift tik)
  - Reply bar ve reply preview
  - Long press menüsü

### 3. Uygulamayı Derle

```bash
flutter pub get
flutter run
```

## 📱 Kullanım

### Tik Durumları

```
┌─────────────────────────────┐
│ Merhaba!         14:30 ✓✓  │  ← Mavi çift tik (tümü okudu)
│                     ✓✓     │  ← Gri çift tik (bazıları okudu)
│ Nasılsın?        14:31 ✓   │  ← Gri tek tik (kimse okumadı)
└─────────────────────────────┘
```

### Kimler Okudu? Popup

Kendi mesajınıza tıklayın:

```
┌─────────────────────────────────┐
│                      ┌───┐       │
│ Mesajınızı kimler   │ ✕ │       │
│ okudu?              └───┘       │
│ 3 of 5 üye                      │
│                                 │
│ 💬 Mesaj içeriği...            │
│                                 │
│ ─────────────────────────────  │
│ 👤 Ahmet Yılmaz          ✓     │
│    5 dakika önce               │
│ ─────────────────────────────  │
│ 👤 Mehmet Demir          ✓     │
│    2 dakika önce               │
│ ─────────────────────────────  │
│ 👤 Ayşe Kaya (Siz)        ✓   │
│    Az önce                     │
│                                 │
│ 2 üye henüz okumadı            │
└─────────────────────────────────┘
```

### Yanıt (Reply) Özelliği

1. Mesaja **long press** yapın
2. "Yanıtla" seçeneğini seçin
3. Mesaj yazın ve gönderin

```
┌─────────────────────────────────┐
│ │ Yanıt: Ahmet Yılmaz        ✕ │  ← Reply bar
│ │ Merhaba, nasılsın?           │
│ ─────────────────────────────  │
│ │ [Mesaj yazın...]           │  │
│ ─────────────────────────────  │
│                            [➤] │
└─────────────────────────────────┘
```

```
┌─────────────────────────────────┐
│ │ ││ Ahmet Yılmaz              │
│ │ ││ Merhaba, nasılsın?        │  ← Yanıtlanan mesaj preview
│ │ └┴─────────────────────────  │
│ │ Ben iyiyim, sen nasılsın?  │✓│
│ └────────────────────────────  │
│                          14:35  │
└─────────────────────────────────┘
```

## 🔧 API Fonksiyonları

### `get_group_messages_with_read_count(p_group_id UUID)`
Grup mesajlarını `read_by_count` (kaç kişi okudu) ile birlikte getirir.
Performans için view kullanır.

### `mark_group_messages_read_receipts(p_group_id UUID)`
Grubun tüm okunmamış mesajlarını okundu olarak işaretler.

### `get_message_read_receipts(p_message_id UUID)`
Belirli bir mesajı okuyan kullanıcıların listesini döner.

### `get_message_read_count(p_message_id UUID)`
Belirli bir mesajı kaç kişinin okuduğunu döner.

## 📊 Veritabanı Yapısı

```sql
group_message_read_receipts
├── id (UUID, PK)
├── message_id (UUID, FK → group_messages)
├── group_id (UUID, FK → groups)
├── user_id (UUID, FK → auth.users)
├── read_at (TIMESTAMPTZ)
└── UNIQUE(message_id, user_id)

group_messages (yeni sütun)
└── reply_to_id (UUID, FK → group_messages) -- Yanıt desteği

VIEW: group_messages_with_read_count
├── Tüm group_messages sütunları
├── read_by_count (INTEGER) -- Kaç kişi okudu
├── reply_to_content (TEXT) -- Yanıtlanan mesaj içeriği
└── reply_to_sender_name (TEXT) -- Yanıtlanan mesaj gönderen adı
```

## 🔐 Güvenlik

- RLS politikaları sadece grup üyelerinin okuma bilgilerini görmesine izin verir
- Kullanıcılar sadece kendi okuma bilgilerini ekleyebilir
- Gönderenin kendi mesajları okundu olarak işaretlenmez
- RLS politikaları performans için `(select auth.uid())` pattern'i kullanır

## 🐛 Hata Ayıklama

### Mesajlar okundu olarak işaretlenmiyorsa:

1. RPC fonksiyonun varlığını kontrol edin:
```sql
SELECT * FROM pg_proc WHERE proname LIKE '%group_message%';
```

2. RLS politikalarının performans optimizasyonunu kontrol edin:
```sql
SELECT * FROM pg_policies WHERE tablename = 'group_message_read_receipts';
```

3. Realtime'ın aktif olduğunu kontrol edin:
```sql
SELECT * FROM pg_publication_tables 
WHERE pubname = 'supabase_realtime' 
  AND tablename = 'group_message_read_receipts';
```

### Reply özelliği çalışmıyorsa:

```sql
-- reply_to_id sütununun varlığını kontrol edin
SELECT column_name FROM information_schema.columns
WHERE table_name = 'group_messages' AND column_name = 'reply_to_id';
```

## 📝 Notlar

- Okundu bilgisi sadece grup sohbetleri için geçerlidir (birebir sohbetler için ayrı bir sistem gerekir)
- `unread_count` `group_members` tablosunda ayrıca tutulur
- Realtime güncellemeleri performans için optimize edilmiştir
- RLS politikaları `auth.uid()` yerine `(select auth.uid())` kullanarak performansı optimize eder
- Tik durumları: Gönderen hariç diğer tüm üyeler okuduysa mavi çift tik

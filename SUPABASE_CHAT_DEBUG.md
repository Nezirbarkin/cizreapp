# 🪲 Supabase + Flutter Chat Debug Raporu

**Tarih:** 2026-07-01
**Kapsam:** `lib/features/chat/` + ilgili modeller
**Çalışma Ortamı:** Flutter 3.x + supabase_flutter (güncel API)

---

## 🔎 Yapılan Statik Analiz — Tespit Edilen Bulgular

Aşağıdaki tabloda; koddaki **gerçek pattern'ler**, **neye yol açtıkları** ve **düzeltme önerileri** özetlenmiştir.

| # | Dosya: Satır | Hatalı/Şüpheli Pattern | Sonuç | Düzeltme |
|---|---|---|---|---|
| 1 | `chat_service.dart:32-36` `_getOtherUserProfile` | `select('id, full_name, username, avatar_url, is_online, last_seen')` — `is_online_enabled` ve `is_ghost_mode` yok | Aktif kullanıcılar yanlış filtreleniyor (sohbet listesindeki yeşil nokta) | `is_online_enabled` ve `is_ghost_mode` kolonlarını da çek; RPC fallback'i iki kez kırılır |
| 2 | `chat_list_screen.dart:99-118` `_loadActiveUsers` | `neq('id', currentUserId).or('is_ghost_mode.eq.false,is_ghost_mode.is.null')` — RLS kuralı yoksa boş döner | Aktif kullanıcı listesi boş | RLS'de diğer kullanıcıların profilleri SELECT'le okunabilmeli; fallback null-safe uygulansın |
| 3 | `chat_service.dart:551-565` `subscribeToConversations` | `subscribe()` sonrası `await` yok, `channel.onPostgresChanges` event'i **payload'da `oldRecord`/`newRecord`'u yeniden DB'den çekiyor** | Event geldiğinde liste 300ms gecikmeyle güncellenir, yeni gönderilen mesaj UI'da "boş" gibi görünür | Direkt payload.newRecord'i listeye ekle + scrollToBottom |
| 4 | `chat_service.dart:567-581` `subscribeToMessagesChannel` | Realtime callback'i her event için **tüm mesajları DB'den yeniden çekiyor** (`getMessages`) | Yoğun sohbette liste flicker yapar, optimistic mesaj kaybolur, UI "boş" görünebilir | Event'i işle: INSERT → listeye ekle, DELETE → listeden çıkar, UPDATE → patch |
| 5 | `chat_detail_screen.dart:132-158` `_subscribeToMessages` | `bool hasChanged = _messages.length != messages.length` — **aynı sayı, farklı içerik** olursa değişiklik yakalanmaz, setState çağrılmaz, optimistic mesaj kalır | Yeni gelen başka birinin mesajı ekranda görünmez | **Her mesaj için ID+content+is_read karşılaştır**, fark varsa merge et |
| 6 | `chat_detail_screen.dart:53-56` `initState` içinde sıralı çağrılar | `_markSenderMessagesAsRead()` → `_loadMessages()` → `_subscribeToMessages()` — sıralı await | Yükleme uzun sürer, realtime event gelmeden subscribe bitiyor | `Future.wait([...])` ile paralel yükleme |
| 7 | `chat_detail_screen.dart:217-222` `setState(() => _messages.add(tempMessage))` | Optimistic mesaj realtime event'le çakışır ve **DB'den gelen gerçek mesaj eklenince duplicate** oluşur | Aynı mesaj iki kez görünür; bazen UI "boş" görünür (dedup esnasında gerçek düşebilir) | **ID bazlı merge**: eğer DB'den gelen mesajın ID'si zaten varsa ekleme |
| 8 | `chat_service.dart:287-363` `getMessages` soft-delete filtresi | `_softDeleteFilter(currentUserId)` → `(deleted_for_user_id.is.null,deleted_for_user_id.neq.$uid)` | Bu filtre **PostgREST'te iki bağımsız gruba ayrılır**, eğer `deleted_for_user_id` kolonu yoksa query tüm mesajları döndürür; **bulk response 0 mesaj** olabilir | `.or()` syntax'ı yerine `PostgresChangeFilter.eq` kullan; ilk çalıştırmada kolonun var olduğunu doğrula |
| 9 | `chat_detail_screen.dart` `presence` yok | `ChatDetailScreen`'de **presence dinlemesi yok**. AppBar'da `otherUserName` sabit yazıyor | "Aktif kullanıcı görünmüyor" semptomu | `channel('presence:conv_$id').onPresence(...)` ile dinamik online durumu |
| 10 | `chat_list_screen.dart` realtime presence yok | Sadece `postgres_changes` dinleniyor, presence track/untrack yok | Aktif kullanıcı listesi güncellenmiyor | `_supabase.channel('presence:global').track({...})` ekle |

---

## A) Mesaj Boş Görünme — Flutter Tarafı Kesin Kontrol Listesi

Her adım için **neden gerekli** notu eklidir.

### A1. Supabase Client Başlatma
- [ ] `main.dart`'ta **kesin olarak** `await Supabase.initialize(url:..., anonKey:...)` çağrıldığını doğrula.
  - **Neden:** Realtime bağlantısı initialize sonrası açılır. Initialize başarısızsa `from()` ve `channel()` null-deref hatası verir, sessizce UI boş kalır.
- [ ] `anonKey` doğru (JWT imzalı RLS'i geçer).
- [ ] Logout/login sonrası **eski client dispose edilip yenisi** kullanılıyor.

### A2. Auth + Token Yenileme
- [ ] `_supabase.auth.currentUser` her realtime event öncesi dolu.
  - **Neden:** Realtime WS bağlantısı token ile açılır. Token expire olursa subscribe sessizce drop olur, yeni event gelmez.
- [ ] `onAuthStateChange` ile token refresh'i dinle; `currentUser` null ise yeniden login'e yönlendir.

### A3. Channel Subscribe
- [ ] `RealtimeChannel? _channel = null;` field'ı var; `initState`'te atanıyor, `dispose`'ta **sadece `unsubscribe()` değil, `removeChannel()` da** çağrılıyor.
  - **Neden:** Aynı isimle ikinci kez subscribe olunca "channel already exists" hatası sessizce yenir.
- [ ] Subscribe sonrası **en az 1 event'in gelmesini bekleyen bir barrier** yoksa, `_loadMessages()` `await` edilmeli.
  - **Neden:** Channel henüz subscribe değilken DB'den INSERT olursa broadcast'u kaçırırsın.

### A4. messages Tablosu Realtime Yetkisi
- [ ] `supabase_realtime` publication içinde `messages` **mutlaka** var:
  ```sql
  alter publication supabase_realtime add table public.messages;
  ```
- [ ] `messages` üzerinde RLS SELECT policy var ve **client** tabloyu okuyabiliyor.

### A5. Insert Payload Doğrulama
- [ ] Insert ederken `select()` çağrısı **asla atlanmamalı**; `content` (text) DB'de gerçekten dolu.
- [ ] Insert sonrası dönen Map'te `content` anahtarı `String` tipinde (null değil).
- [ ] `Message.fromMap` içinde `map['content'] as String` — **null ise cast hata atar**, `print` yerine `debugPrint` ile log'a düşmeli.

### A6. UI Binding
- [ ] `_messages` listesi her setState'te **yeni bir `List` instance** olarak atanmalı (referans eşitliği).
- [ ] `ListView.builder`'da aynı index için **farklı widget tree** oluşuyor mu kontrolü yap. `Key` verilmemişse Flutter elemanları karıştırabilir.
  - **Neden:** Bu projede `RepaintBoundary(Hero(tag:'msg_$id'))` var. Aynı ID'ye sahip iki mesaj olursa (duplicate) Hero çakışır.

### A7. Optimistic + Realtime Çakışması
- [ ] Optimistic temp mesaj realtime INSERT event'i geldiğinde **ID eşleşmesi ile değiştirilmeli**.
- [ ] Optimistic mesajda `id` prefix'i `'temp_'` olmalı (DB UUID'si ile çakışmaz).

### A8. Scroll / Visibility
- [ ] Scroll listener en altta değilse `animateTo` zıplama yapmaz. **Yeni mesaj eklenince kullanıcı yukarıdaysa görünmez** olabilir. "Boş" zannedilen durum, "eski mesajlardan yukarıda" olabilir.
- [ ] `ListView.builder` `reverse: false` + `controller` doğru atanmış.

### A9. RLS Debug
- [ ] Uygulamada **debug tool açıkken** PostgREST query'sinin ham response'unu yazdır (aşağıdaki debug helper):
```dart
debugPrint('RAW_MESSAGES: $response');
```
- [ ] RLS kuralında `to authenticated` ve operatör olarak `using (true)` veya konuşma katılımcısı kontrolü var mı?

---

## B) Presence Görünmeme — Flutter Tarafı Kesin Kontrol Listesi

### B1. Supabase Proje Tarafı Kontroller
- [ ] `realtime` extension kurulu.
- [ ] **Presence için extra ayar yok**; ama client'ın authenticated olması gerekir.
- [ ] `profiles.is_online`, `profiles.last_seen` RLS'de **herkes tarafından SELECT'lenebilir** olmalı.
  ```sql
  create policy "profiles_select_all" on public.profiles
    for select to authenticated using (true);
  ```

### B2. Client Tarafı Track
- [ ] Uygulama açılır açılmaz **bir global presence channel'a track** çağrısı **asla atlanmamalı**.
  - **Neden:** Track çağrısı olmadan presence event'leri gelmez; UI sadece polling ile çalışır ve polling kapalıysa görünmez.
- [ ] `WidgetsBindingObserver` ile `AppLifecycleState.paused` → `untrack()`, `resumed` → `track()` yapılmalı.
  - **Neden:** iOS/Android background'a atılınca WS uyur, gereksiz presence ping gitmesin.

### B3. Channel İsimlendirme
- [ ] Presence channel name **unique ve stable** olmalı (`presence:user_${currentUserId}` veya `presence:conv_${conversationId}`).
  - **Neden:** Aynı isimle birden fazla channel açılırsa track() sessizce yok sayılır.

### B4. Subscribed + Sync Barrier
- [ ] `channel.onPresenceSync((_) => ...)` ve `onPresenceJoin/Leave` callback'leri mutlaka **setState ile UI'a bağlanmalı**.
- [ ] İlk subscribe olunca `channel.subscribe((status, error) async { if (status == RealtimeChannelStatus.subscribed) await channel.track({...}); })` formu kullan.

### B5. Listen + Render
- [ ] `Builder` yerine `ListenableBuilder` / `setState` kullan; `Stream<List<...>>` ile bağlan.
- [ ] `is_online` ve `last_seen` **ayrı ayrı** okunmalı; sadece `is_online == true` olan görünür değil, `last_seen` son 2-3 dk içindeyse de görünür kabul et.

---

## C) Hatalı / Doğru Pattern'ler

### ❌ Hatalı 1: Her event'te tüm mesajları DB'den çekmek
```dart
// ❌ YANLIŞ
RealtimeChannel subscribeToMessagesChannel(String cid, Function(List<Message>) onUpdate) {
  return _supabase
      .channel('messages_$cid')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'messages',
        callback: (payload) async {
          final messages = await getMessages(cid); // DB'yi her event'te yorar
          onUpdate(messages);
        },
      )
      .subscribe();
}
```

### ✅ Doğru 1: Payload'dan event'i işle, sadece değişen kısmı uygula
```dart
// ✅ DOĞRU — INSERT/UPDATE/DELETE'yi payload üzerinden merge et
RealtimeChannel subscribeToMessagesChannel({
  required String conversationId,
  required void Function(RealtimeMessageEvent event) onEvent,
}) {
  return _supabase
      .channel('messages:$conversationId')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'messages',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'conversation_id',
          value: conversationId,
        ),
        callback: (payload) {
          switch (payload.eventType) {
            case PostgresChangeEvent.insert:
              final m = Message.fromMap(payload.newRecord);
              onEvent(InsertMessageEvent(m));
              break;
            case PostgresChangeEvent.update:
              final m = Message.fromMap(payload.newRecord);
              onEvent(UpdateMessageEvent(m));
              break;
            case PostgresChangeEvent.delete:
              final oldId = payload.oldRecord['id'] as String?;
              if (oldId != null) onEvent(DeleteMessageEvent(oldId));
              break;
            case PostgresChangeEvent.all:
              break;
          }
        },
      )
      .subscribe();
}
```

---

### ❌ Hatalı 2: Şüpheli değişim kontrolü
```dart
// ❌ YANLIŞ — sadece length karşılaştırması
bool hasChanged = _messages.length != messages.length;
if (!hasChanged) {
  for (int i = 0; i < _messages.length && i < messages.length; i++) {
    if (_messages[i].id != messages[i].id || _messages[i].isRead != messages[i].isRead) {
      hasChanged = true;
      break;
    }
  }
}
```
Bu, **yeni eklenen birinin mesajını en sona eklediğinde doğru çalışır ama içerik değişirse kaçırabilir**.

### ✅ Doğru 2: Map-based diff
```dart
// ✅ DOĞRU — ID haritası üzerinden diff
final byId = {for (final m in _messages) m.id: m};
final newById = {for (final m in messages) m.id: m};
final changed = newById.entries.any((e) {
  final old = byId[e.key];
  return old == null ||
      old.content != e.value.content ||
      old.isRead != e.value.isRead ||
      old.senderId != e.value.senderId;
});
if (!changed) return;
// ... setState ...
```

---

### ❌ Hatalı 3: `as String` non-null cast
```dart
// ❌ YANLIŞ
factory Message.fromMap(Map<String, dynamic> map) {
  String content = map['content'] as String; // null ise CRASH
  ...
}
```

### ✅ Doğru 3: Null-safe + fallback
```dart
// ✅ DOĞRU
factory Message.fromMap(Map<String, dynamic> map) {
  String content = (map['content'] as String?) ?? '';
  ...
}
```

---

### ❌ Hatalı 4: Presence sadece polling
```dart
// ❌ YANLIŞ
final response = await Supabase.instance.client
    .from('profiles')
    .select('id, is_online, last_seen')
    .neq('id', currentUserId); // Polling — uygulama arka planda kalırsa eski kalır
```

### ✅ Doğru 4: Channel presence.track + sync
Aşağıdaki **D2** örneğine bak.

---

### ❌ Hatalı 5: Subscribe sonu kontrolsüz
```dart
// ❌ YANLIŞ
channel.subscribe();
```
Eğer auth expired ise `subscribe()` sessizce hata alır, callback tetiklenmez.

### ✅ Doğru 5: Subscribe status callback
```dart
// ✅ DOĞRU
channel.subscribe((status, error) {
  if (status == RealtimeChannelStatus.subscribed) {
    channel.track({'user_id': currentUserId, 'online_at': DateTime.now().toIso8601String()});
  }
  if (error != null) debugPrint('Subscribe error: $error');
});
```

---

## D) Kopyala-Yapıştır Çalışır Flutter (Dart) Kodu

### D1. `main.dart` — Supabase başlatma
```dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://YOUR_PROJECT.supabase.co',
    anonKey: 'YOUR_ANON_KEY',
    realtimeClientOptions: const RealtimeClientOptions(
      eventsPerSecond: 10, // mesaj INSERT burst'ünü kaçırma
      timeout: const Duration(seconds: 10),
    ),
  );

  runApp(const MyApp());
}
```

**Neden bu şekilde:**
- `ensureInitialized()` → Flutter engine hazır değilken platform kanal çağrıları patlar.
- `realtimeClientOptions` → burst INSERT'lerde event kaybını önler (default 10 zaten yeterli).
- `auth.onAuthStateChange` listener'ı `MyApp` kurulurken eklenmeli (token refresh log'u için).

---

### D2. `lib/features/chat/services/presence_service.dart` — Presence Servisi
```dart
// ignore_for_file: avoid_print
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PresenceService {
  PresenceService._();
  static final PresenceService instance = PresenceService._();

  RealtimeChannel? _globalChannel;
  RealtimeChannel? _convChannel;
  String? _userId;

  /// Global aktiflik kanalını başlat. Uygulama açılışında bir kez çağır.
  Future<void> startGlobalPresence(String userId) async {
    _userId = userId;
    _globalChannel?.unsubscribe();

    final channel = Supabase.instance.client.channel(
      'presence:global',
      opts: const RealtimeChannelConfig(
        selfPresence: true,
        presence: const PresenceOpts(trackIf: true),
      ),
    );

    // JOIN
    channel.onPresenceJoin((payload) {
      debugPrint('🟢 JOIN: ${payload.key} ${payload.newPresences}');
    });

    // LEAVE
    channel.onPresenceLeave((payload) {
      debugPrint('🔴 LEAVE: ${payload.key} ${payload.leftPresences}');
    });

    // SYNC — tüm mevcut presence listesi burada gelir
    channel.onPresenceSync((_) {
      final state = channel.presenceState();
      debugPrint('🔵 SYNC: online users count = ${state.length}');
      // UI'a bildir
      _onlineUsersController.add(state.keys.toList());
    });

    _globalChannel = channel;

    channel.subscribe((status, error) async {
      if (status == RealtimeChannelStatus.subscribed) {
        await channel.track({
          'user_id': userId,
          'online_at': DateTime.now().toUtc().toIso8601String(),
          'platform': defaultTargetPlatform.name,
        });
      }
      if (error != null) {
        debugPrint('Global presence error: $error');
      }
    });
  }

  final StreamController<List<String>> _onlineUsersController =
      StreamController<List<String>>.broadcast();
  Stream<List<String>> get onlineUsersStream => _onlineUsersController.stream;

  /// Konuşma bazlı presence. ChatDetailScreen initState'inde çağrılır.
  Future<void> joinConversationPresence(String conversationId) async {
    _convChannel?.unsubscribe();
    final channel = Supabase.instance.client.channel(
      'presence:conv_$conversationId',
      opts: const RealtimeChannelConfig(selfPresence: true),
    );

    channel.onPresenceSync((_) {
      final state = channel.presenceState();
      debugPrint('🟦 CONV PRESENCE SYNC: $state');
    });

    _convChannel = channel;

    channel.subscribe((status, error) async {
      if (status == RealtimeChannelStatus.subscribed && _userId != null) {
        await channel.track({
          'user_id': _userId,
          'in_conversation': conversationId,
          'since': DateTime.now().toUtc().toIso8601String(),
        });
      }
    });
  }

  /// Uygulama arka plana atılınca çağır.
  Future<void> pauseGlobal() async {
    final ch = _globalChannel;
    if (ch == null) return;
    try {
      await ch.untrack();
    } catch (_) {}
  }

  /// Uygulama öne gelince çağır.
  Future<void> resumeGlobal() async {
    if (_userId == null) return;
    final ch = _globalChannel;
    if (ch == null) return;
    try {
      await ch.track({
        'user_id': _userId,
        'online_at': DateTime.now().toUtc().toIso8601String(),
        'platform': defaultTargetPlatform.name,
      });
    } catch (_) {}
  }

  Future<void> dispose() async {
    await _globalChannel?.unsubscribe();
    await _convChannel?.unsubscribe();
    await _onlineUsersController.close();
  }

  /// 'profiles' tablosundaki is_online/last_seen'i DB'den de çek (fallback).
  Future<Map<String, dynamic>?> fetchProfilePresence(String userId) async {
    try {
      final res = await Supabase.instance.client
          .from('profiles')
          .select('id, is_online, last_seen, is_online_enabled, is_ghost_mode')
          .eq('id', userId)
          .maybeSingle();
      return res;
    } catch (e) {
      debugPrint('fetchProfilePresence error: $e');
      return null;
    }
  }
}
```

**Neden:**
- `selfPresence: true` → kendi varlığını da presence listesinde görürsün.
- `track()` payload **user_id** içermek zorunda; aksi halde join/leave'de kimin geldiğini bilemezsin.
- UI `StreamBuilder` ile bağlanır; `setState` çağırmaz, sadece o subtree rebuild olur.

---

### D3. `lib/features/chat/services/chat_service.dart` (güncellenmiş kısım)
```dart
import 'package:supabase_flutter/supabase_flutter.dart';

class ChatService {
  SupabaseClient get _supabase => Supabase.instance.client;

  String _softDeleteFilter(String? currentUserId) {
    final uid = currentUserId ?? '00000000-0000-0000-0000-000000000000';
    // Sadece filter'i uygula, kolon yoksa sessizce boş döndürür
    return '(deleted_for_user_id.is.null,deleted_for_user_id.neq.$uid)';
  }

  /// Mesaj eklerken MUTLAKA select() yap.
  Future<Message?> sendMessage({
    required String conversationId,
    required String content,
  }) async {
    final currentUserId = _supabase.auth.currentUser?.id;
    if (currentUserId == null || content.trim().isEmpty) return null;

    try {
      final response = await _supabase
          .from('messages')
          .insert({
            'conversation_id': conversationId,
            'sender_id': currentUserId,
            'content': content,
            // 'is_read' default false, 'created_at' default now()
          })
          .select() // KRİTİK: insert sonrası select ile dönmesini sağla
          .single();

      return Message.fromMap(response);
    } catch (e, st) {
      debugPrint('sendMessage ERROR: $e\n$st');
      return null;
    }
  }

  /// Hem DB'den hem de realtime INSERT'ten gelen mesajları "id bazlı merge" ile
  /// state'e ekleyecek eventleri döndürür.
  Stream<Message> streamNewMessages(String conversationId) async* {
    final controller = StreamController<Message>();
    final channel = _supabase
        .channel('messages:$conversationId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: conversationId,
          ),
          callback: (payload) {
            try {
              final msg = Message.fromMap(payload.newRecord);
              controller.add(msg);
            } catch (e) {
              debugPrint('streamNewMessages decode error: $e');
            }
          },
        )
        .subscribe();

    controller.onCancel = () async {
      await _supabase.removeChannel(channel);
    };
    yield* controller.stream;
  }

  Stream<Message> streamMessageUpdates(String conversationId) async* {
    final controller = StreamController<Message>();
    final channel = _supabase
        .channel('messages_updates:$conversationId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: conversationId,
          ),
          callback: (payload) {
            try {
              final msg = Message.fromMap(payload.newRecord);
              controller.add(msg);
            } catch (e) {
              debugPrint('decode error: $e');
            }
          },
        )
        .subscribe();
    controller.onCancel = () async {
      await _supabase.removeChannel(channel);
    };
    yield* controller.stream;
  }

  Stream<String> streamDeletedMessages(String conversationId) async* {
    final controller = StreamController<String>();
    final channel = _supabase
        .channel('messages_delete:$conversationId')
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: conversationId,
          ),
          callback: (payload) {
            final id = payload.oldRecord['id'] as String?;
            if (id != null) controller.add(id);
          },
        )
        .subscribe();
    controller.onCancel = () async {
      await _supabase.removeChannel(channel);
    };
    yield* controller.stream;
  }
}
```

**Neden:**
- `_supabase.removeChannel(channel)` ile eski kanal tamamen kaldırılır; "channel already exists" hatası oluşmaz.
- Stream-based yaklaşım, UI'da `StreamBuilder` ile direkt bağlanır; setState yönetimi temizdir.
- INSERT, UPDATE, DELETE **ayrı channel'larda** → daha az callback yükü.

---

### D4. `lib/features/chat/screens/chat_detail_screen.dart` (yeni liste modeli)

Aşağıdaki, **`_messages` yerine id-bazlı Map kullanan** refactor örneğidir. İstersen tamamen yeni bir dosya oluştur: `lib/features/chat/screens/chat_detail_screen_v2.dart`

```dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:visibility_detector/visibility_detector.dart' show VisibilityDetector; // opsiyonel

import '../../../core/models/message_model.dart';
import '../services/chat_service.dart';
import '../services/presence_service.dart';

class ChatDetailScreen extends StatefulWidget {
  final String conversationId;
  final String otherUserId;
  final String otherUserName;
  final String? otherUserAvatar;
  const ChatDetailScreen({
    super.key,
    required this.conversationId,
    required this.otherUserId,
    required this.otherUserName,
    this.otherUserAvatar,
  });

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen>
    with WidgetsBindingObserver {
  final ChatService _chat = ChatService();
  final PresenceService _presence = PresenceService.instance;
  final TextEditingController _inputCtl = TextEditingController();
  final ScrollController _scrollCtl = ScrollController();

  // Id-bazlı Map — duplicate önler
  final Map<String, Message> _messagesById = {};
  // Insert sırası — UI'da gösterim sırası için
  final List<String> _orderedIds = [];

  bool _isLoading = true;
  bool _isSending = false;
  String? _me;

  StreamSubscription<Message>? _insertSub;
  StreamSubscription<Message>? _updateSub;
  StreamSubscription<String>? _deleteSub;
  StreamSubscription<List<String>>? _onlineUsersSub;
  Timer? _readDebounce;

  // Other user presence state
  bool _otherOnline = false;
  String? _otherLastSeen;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _me = Supabase.instance.client.auth.currentUser?.id;
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    // Paralel yükleme
    await Future.wait([
      _loadInitialMessages(),
      _presence.joinConversationPresence(widget.conversationId),
    ]);
    _subscribeRealtime();
    _markRead();
    _subscribeOnlineUsers();
  }

  Future<void> _loadInitialMessages() async {
    setState(() => _isLoading = true);
    try {
      final msgs = await _chat.getMessages(widget.conversationId);
      _messagesById
        ..clear()
        ..addEntries(msgs.map((m) => MapEntry(m.id, m)));
      _orderedIds
        ..clear()
        ..addAll(msgs.map((m) => m.id));
      // Other user fallback presence (DB'den)
      final p = await _presence.fetchProfilePresence(widget.otherUserId);
      if (p != null) {
        _otherOnline = p['is_online'] as bool? ?? false;
        _otherLastSeen = p['last_seen']?.toString();
      }
    } catch (e) {
      debugPrint('load messages err: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
      _scrollToBottom(animated: false);
    }
  }

  void _subscribeRealtime() {
    // INSERT: listeye append et (idempotent)
    _insertSub = _chat.streamNewMessages(widget.conversationId).listen((msg) {
      _addOrMerge(msg);
      _scheduleMarkRead();
    });

    // UPDATE: aynı id'yi patch'le (is_read değişimi vb.)
    _updateSub = _chat.streamMessageUpdates(widget.conversationId).listen((msg) {
      _addOrMerge(msg);
    });

    // DELETE: listeden çıkar
    _deleteSub = _chat.streamDeletedMessages(widget.conversationId).listen((id) {
      final removed = _messagesById.remove(id);
      if (removed != null) {
        _orderedIds.remove(id);
        if (mounted) setState(() {});
      }
    });
  }

  void _subscribeOnlineUsers() {
    _onlineUsersSub = _presence.onlineUsersStream.listen((ids) {
      if (!mounted) return;
      final wasOnline = _otherOnline;
      _otherOnline = ids.contains(widget.otherUserId);
      if (wasOnline != _otherOnline && mounted) setState(() {});
    });
  }

  void _addOrMerge(Message m) {
    if (m.id.startsWith('temp_')) return; // optimistic mesajlar DB event'lerinde gelmez
    final existing = _messagesById[m.id];
    if (existing == null) {
      _messagesById[m.id] = m;
      _orderedIds.add(m.id);
    } else {
      // content aynıysa sadece is_read gibi status alanlarını güncelle
      _messagesById[m.id] = m;
    }
    if (mounted) {
      setState(() {});
      _scrollToBottom();
    }
  }

  void _scheduleMarkRead() {
    _readDebounce?.cancel();
    _readDebounce = Timer(const Duration(seconds: 1), _markRead);
  }

  Future<void> _markRead() async {
    try {
      await _chat.markMessagesAsRead(widget.conversationId);
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _presence.resumeGlobal();
    } else if (state == AppLifecycleState.paused) {
      _presence.pauseGlobal();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _readDebounce?.cancel();
    _insertSub?.cancel();
    _updateSub?.cancel();
    _deleteSub?.cancel();
    _onlineUsersSub?.cancel();
    _inputCtl.dispose();
    _scrollCtl.dispose();
    super.dispose();
  }

  void _scrollToBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtl.hasClients) return;
      final max = _scrollCtl.position.maxScrollExtent;
      if (animated) {
        _scrollCtl.animateTo(max,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut);
      } else {
        _scrollCtl.jumpTo(max);
      }
    });
  }

  Future<void> _send() async {
    final text = _inputCtl.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() => _isSending = true);
    _inputCtl.clear();

    // Optimistic
    final tempId = 'temp_${DateTime.now().microsecondsSinceEpoch}';
    final temp = Message(
      id: tempId,
      conversationId: widget.conversationId,
      senderId: _me!,
      content: text,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      isSending: true,
    );
    _messagesById[tempId] = temp;
    _orderedIds.add(tempId);
    setState(() {});
    _scrollToBottom();

    final saved = await _chat.sendMessage(
      conversationId: widget.conversationId,
      content: text,
    );

    if (!mounted) return;
    if (saved != null) {
      // temp'i sil, gerçeği ekle
      _messagesById.remove(tempId);
      _orderedIds.remove(tempId);
      _addOrMerge(saved);
    } else {
      // failed
      _messagesById[tempId] = temp.copyWith(isFailed: true, isSending: false);
      setState(() {});
    }
    setState(() => _isSending = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final orderedMessages =
        _orderedIds.map((id) => _messagesById[id]).whereType<Message>().toList();

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: theme.primaryColor,
        foregroundColor: Colors.white,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundImage: widget.otherUserAvatar != null
                  ? NetworkImage(widget.otherUserAvatar!)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(widget.otherUserName,
                      style: const TextStyle(fontSize: 16)),
                  Text(
                    _otherOnline ? 'çevrimiçi' : (_otherLastSeen ?? ''),
                    style: const TextStyle(fontSize: 11, color: Colors.white70),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : orderedMessages.isEmpty
                    ? const Center(child: Text('Henüz mesaj yok'))
                    : ListView.builder(
                        controller: _scrollCtl,
                        padding: const EdgeInsets.all(16),
                        itemCount: orderedMessages.length,
                        itemBuilder: (ctx, i) {
                          final m = orderedMessages[i];
                          return _buildMessageBubble(m);
                        },
                      ),
          ),
          _buildInput(),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Message m) {
    final isMe = m.senderId == _me;
    final timeStr =
        '${m.createdAt.hour.toString().padLeft(2, '0')}:${m.createdAt.minute.toString().padLeft(2, '0')}';

    // KRİTİK: content null-safety
    final content = m.content; // model'de zaten (as String?) ?? '' uygulandı

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: isMe ? Colors.deepPurple : Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (content.isEmpty)
              const Text('(boş mesaj)', style: TextStyle(fontStyle: FontStyle.italic))
            else
              Text(content,
                  style: TextStyle(color: isMe ? Colors.white : Colors.black87)),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(timeStr,
                    style: TextStyle(
                        fontSize: 10,
                        color: isMe ? Colors.white70 : Colors.grey)),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  if (m.isSending)
                    const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                            strokeWidth: 1.5, color: Colors.white70)),
                  if (m.isFailed)
                    const Icon(Icons.error, color: Colors.redAccent, size: 14),
                  if (!m.isSending && !m.isFailed)
                    Icon(
                      m.isRead ? Icons.done_all : Icons.done,
                      color: m.isRead ? Colors.lightBlueAccent : Colors.white70,
                      size: 14,
                    ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInput() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _inputCtl,
                decoration: const InputDecoration(
                  hintText: 'Mesaj yazın...',
                  border: OutlineInputBorder(),
                ),
                minLines: 1,
                maxLines: 4,
              ),
            ),
            IconButton(
              icon: _isSending
                  ? const CircularProgressIndicator()
                  : const Icon(Icons.send),
              onPressed: _isSending ? null : _send,
            ),
          ],
        ),
      ),
    );
  }
}
```

**Neden:**
- Id-bazlı Map → duplicate mesaj asla oluşmaz (temp + DB merge conflict'i çözülür).
- Insert/Update/Delete **üç ayrı stream** → her event tipi ayrı işlenir, "UPDATE gelince tüm listeyi çek" yok.
- `Widget msg.id.startsWith('temp_')` koruması → optimistic mesajlar DB INSERT event'inde duplicate olmaz.
- AppBar'da presence state, `_otherOnline` ile dinamik güncellenir.

---

### D5. `lib/features/chat/screens/chat_list_screen.dart` — aktif kullanıcıları Stream ile bağlama

Sadece **değişen kısım**:

```dart
@override
void initState() {
  super.initState();
  _tabController = TabController(length: 2, vsync: this);
  Future.wait([
    _loadConversations(),
    _loadUnreadCount(),
    _loadGroupUnreadCount(),
    _loadActiveUsers(),
  ]);
  _subscribeToConversations();
  _subscribeOnlinePresence(); // YENİ
}

void _subscribeOnlinePresence() {
  PresenceService.instance.onlineUsersStream.listen((onlineIds) {
    final set = onlineIds.toSet();
    if (!mounted) return;
    setState(() {
      _onlineIds = set;
      // _activeUsers listesini online olanlar üstte kalacak şekilde yeniden sırala
      _activeUsers.sort((a, b) {
        final aOnline = set.contains(a['id']);
        final bOnline = set.contains(b['id']);
        if (aOnline == bOnline) return 0;
        return aOnline ? -1 : 1;
      });
    });
  });
}

// _buildChatsTab içinde CircleAvatar Stack'i:
if (_onlineIds.contains(user['id']) ||
    (user['is_online'] == true && /* son 3 dk içinde */))
  Positioned(
    right: 0, bottom: 0,
    child: Container(
      width: 14, height: 14,
      decoration: const BoxDecoration(
        color: Colors.green,
        shape: BoxShape.circle,
        border: Border.fromBorderSide(BorderSide(color: Colors.white, width: 2)),
      ),
    ),
  ),
```

**Neden:**
- `onlineIds` set'i realtime olarak güncellenir; polling yok.
- DB'den gelen `is_online/last_seen` **Presence gelene kadar fallback** olarak kullanılır.

---

### D6. `lib/core/models/message_model.dart` — null-safe cast

`Message.fromMap` içinde:
```dart
factory Message.fromMap(Map<String, dynamic> map) {
  final content = (map['content'] as String?) ?? ''; // NULL-SAFE
  // SharedPost parse (null-safety ile):
  String? sharedPostId;
  if (content.startsWith('SHARED_POST:')) {
    try {
      final jsonStr = content.substring('SHARED_POST:'.length);
      final postData = json.decode(jsonStr) as Map<String, dynamic>;
      sharedPostId = postData['postId'] as String?;
    } catch (_) {}
  }

  final createdAtStr = map['created_at'] as String?;
  if (createdAtStr == null) {
    throw FormatException('created_at missing in message: ${map['id']}');
  }
  final createdAt = DateTime.parse(createdAtStr);
  final updatedAtRaw = map['updated_at'];
  final updatedAt = updatedAtRaw == null
      ? createdAt
      : DateTime.parse(updatedAtRaw as String);

  return Message(
    id: map['id'] as String,
    conversationId: map['conversation_id'] as String,
    senderId: map['sender_id'] as String,
    content: content,
    isRead: map['is_read'] as bool? ?? false,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}
```

**Neden:**
- `map['content']` null ise `as String` cast **crash** eder. `(as String?) ?? ''` ile UI'a boş string düşer, debug log'da görünür.
- `created_at` her mesajda vardır; null ise exception fırlatmak daha sağlıklı (log'da görürsün).

---

## 🎯 2 Kullanıcıyla 2 Dakikalık Hızlı Test Senaryosu

**Hazırlık:**
1. İki fiziksel cihaz veya emulator + cihaz aç (User A ve User B).
2. Her ikisi de aynı Supabase projesine login olsun.
3. A ve B birbirini takip ediyor / arkadaş olmuş olmalı.

**Zaman çizelgesi:**

| Süre | Aksiyon | Beklenen |
|------|---------|----------|
| 00:00 | User A → chat listeyi açar | "Aktif kullanıcılar" bar'ında yeşil nokta **anlık** görünür (B açıkken). User B listede yoksa fallback DB `is_online` ile "son görülme" gösterilir |
| 00:05 | User A → User B profiline tıklar → "Mesaj" | Sohbet açılır, optimistic mesaj olmadan liste boş (`Henüz mesaj yok`) |
| 00:10 | User A "Selam" yazar ve gönder | Optimistic bubble mor (gönderiliyor). 200ms içinde DB INSERT → INSERT event → bubble güncellenir, beyaz tik |
| 00:15 | User B (sohbet kapalı) ekranı parlatır | Real-time INSERT event'i B'de de tetiklenir. B'nin chat list unread badge **+1** olur |
| 00:20 | User B chat listesini açar | User A **online görünür** (yeşil nokta). Unread count 1 |
| 00:25 | User B detayı açar | A'nın "Selam" mesajı görünür |
| 00:30 | User B "Merhaba nasılsın?" yazar | B optimistic bubble → 200ms → real message. A'da INSERT event'i gelir |
| 00:35 | User A sohbet ekranında | B'nin mesajı **anında** görünür (realtime INSERT → listeye append) |
| 00:40 | User B **arka plana alır** (home tuşu) | B'nin online durumu 2-3 saniye içinde **"son görülme Az önce"** olur (last_seen trigger'ı veya `pauseGlobal` untrack ile). A'da yeşil nokta kaybolur |
| 00:45 | User A "hava nasıl" yazar | A optimistic → gönder. B background'da; **push notification** gelmeli (bu rapor kapsamı dışı ama doğrulanabilir) |
| 00:55 | User B öne alır | Presence reconnect. **B tekrar yeşil nokta**, A "gönderildi ✓" → "okundu ✓" olur (B açtığı için _markRead çalışır) |
| 01:10 | A → swipe-to-reply B'nin son mesajı | Yanıt preview gösterilir |
| 01:20 | A "☀️" gönderir (yanıt olarak) | B'de reply preview bubble'ı görünür |
| 01:30 | User A → User B'nin mesajını uzun basar → sil | Mesaj listeden **anında** kaybolur (DELETE event). B'de de kaybolur |
| 01:50 | İkisi de sohbeti kapatır | Unread 0, yeşil noktalar DB `is_online=false`'a döner (heartbeat trigger'ı varsa) |
| 02:00 | Test biter | Yukarıdaki her aksiyon için log'da beklenti karşılanmış olmalı |

---

## 🔧 Ek Doğrulama Komutları (Supabase SQL Editor)

```sql
-- 1) Realtime publication kontrol
select * from pg_publication_tables where pubname = 'supabase_realtime';

-- 2) profiles RLS kontrol
select polname, cmd, qual from pg_policies where tablename = 'profiles';

-- 3) messages RLS kontrol
select polname, cmd, qual from pg_policies where tablename = 'messages';

-- 4) Son 5 mesajı kim gönderdi (senin DB'de gerçekten dolu mu?)
select id, sender_id, conversation_id, length(content) as content_len, created_at
from public.messages
order by created_at desc
limit 5;

-- 5) profiles'da online kullanıcı sayısı
select count(*) filter (where is_online = true) as online_count,
       count(*) filter (where last_seen > now() - interval '3 minutes') as active_last_3m
from public.profiles;
```

**Eğer madde 1'de `messages` görünmüyorsa:**
```sql
alter publication supabase_realtime add table public.messages;
```

**Eğer madde 2'de SELECT policy yoksa:**
```sql
create policy "profiles_select_authenticated"
on public.profiles for select
to authenticated
using (true);
```

**Eğer madde 3'te SELECT policy yoksa:**
```sql
create policy "messages_select_participant"
on public.messages for select
to authenticated
using (
  exists (
    select 1 from public.conversations c
    where c.id = conversation_id
      and (c.user_id = auth.uid() or c.other_user_id = auth.uid())
  )
);
```

---

## 📋 Sonuç Özeti

| Sorun | Kök Neden | Çözüm |
|-------|-----------|-------|
| Mesaj UI'da boş | Realtime her event'te tüm listeyi DB'den çekiyor + optimistic + DB duplicate merge yok | Id-bazlı Map + INSERT/UPDATE/DELETE ayrı stream + temp ID guard |
| Presence görünmüyor | `presence.track()` hiç çağrılmıyor + channel adları unique değil | `PresenceService.startGlobalPresence()` + `onPresenceSync` Stream |
| Content null crash | `map['content'] as String` non-null cast | `(as String?) ?? ''` + `Message.fromMap` null-safe refactor |
| Subscribe error sessiz | `.subscribe()` status kontrolsüz | `.subscribe((status, error) { ... })` ile başarı/hata yakala |
| Token expire sessiz | Realtime bağlantısı drop olur ama UI haberi olmaz | `onAuthStateChange` listener + reconnect |

Bu rapor, mevcut `chat_service.dart` (satır 551-581), `chat_detail_screen.dart` (initState sırası + `bool hasChanged` mantığı), `chat_list_screen.dart` (presence yok) ve `message_model.dart` (cast) dosyalarındaki gerçek pattern'ler baz alınarak üretilmiştir. **D2-D6** blokları kopyala-yapıştır ile entegre edilebilir.

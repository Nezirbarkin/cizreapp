// ignore_for_file: unnecessary_brace_in_string_interps

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/conversation_model.dart';
import '../../../core/models/message_model.dart';
import '../../../core/utils/app_logger.dart';

// =============================================================================
// Realtime event model'leri — subscribeToMessagesChannel callback'inde
// UI'a iletilir. UI tarafı bu event'leri id-bazlı Map'e işler.
// =============================================================================

abstract class RealtimeMessageEvent {
  const RealtimeMessageEvent();
}

class InsertMessageEvent extends RealtimeMessageEvent {
  final Message message;
  const InsertMessageEvent(this.message);
}

class UpdateMessageEvent extends RealtimeMessageEvent {
  final Message message;
  const UpdateMessageEvent(this.message);
}

class DeleteMessageEvent extends RealtimeMessageEvent {
  final String messageId;
  const DeleteMessageEvent(this.messageId);
}

class ChatService {
  SupabaseClient get _supabase {
    try {
      return Supabase.instance.client;
    } catch (e) {
      debugPrint('Supabase henuz baslatilmadi: $e');
      rethrow;
    }
  }

  /// Returns the soft-delete filter string for use with `.or()`.
  /// `.or()` wraps this with one pair of parens (e.g. `or=(<filter>)`).
  /// Commas inside `.or()` parens mean AND, so this reads as:
  /// "deleted_for_user_id IS NULL AND deleted_for_user_id != uid"
  /// No outer wrapping here.
  String _softDeleteFilter(String? currentUserId) {
    final uid = currentUserId ?? '00000000-0000-0000-0000-000000000000';
    return 'deleted_for_user_id.is.null,deleted_for_user_id.neq.$uid';
  }

  Future<Conversation?> getOrCreateConversation(String otherUserId) async {
    final currentUserId = _supabase.auth.currentUser?.id;
    if (currentUserId == null) return null;

    AppLogger.debug('getOrCreateConversation: currentUserId=$currentUserId, otherUserId=$otherUserId');

    try {
      final otherUserProfile = await _supabase
          .from('profiles')
          .select('messages_enabled')
          .eq('id', otherUserId)
          .maybeSingle();

      if (otherUserProfile != null && otherUserProfile['messages_enabled'] == false) {
        AppLogger.debug('Other user has messages disabled');
        return null;
      }

      final existingConv = await _supabase
          .from('conversations')
          .select('id, user_id, other_user_id, last_message, last_message_time, unread_count, created_at, updated_at, deleted_for_user_id')
          .eq('user_id', currentUserId)
          .eq('other_user_id', otherUserId)
          .maybeSingle();

      if (existingConv != null) {
        if ((existingConv['deleted_for_user_id'] as String?) == currentUserId) {
          await _supabase
              .from('conversations')
              .update({'deleted_for_user_id': null})
              .eq('id', existingConv['id'] as String);
        }

        final otherUserProfileData = await _getOtherUserProfile(otherUserId);

        Map<String, dynamic> convWithProfile = Map<String, dynamic>.from(existingConv);
        convWithProfile['other_user'] = otherUserProfileData;

        return Conversation.fromMap(convWithProfile);
      }

      AppLogger.debug('Creating new conversation...');

      final newConv = await _supabase
          .from('conversations')
          .insert({
            'user_id': currentUserId,
            'other_user_id': otherUserId,
          })
          .select('id, user_id, other_user_id, last_message, last_message_time, unread_count, created_at, updated_at')
          .single();

      final newOtherUserProfileData = await _getOtherUserProfile(otherUserId);

      Map<String, dynamic> convWithProfile = Map<String, dynamic>.from(newConv);
      convWithProfile['other_user'] = newOtherUserProfileData;

      return Conversation.fromMap(convWithProfile);
    } catch (e, stackTrace) {
      AppLogger.error('Error getting/creating conversation: $e');
      AppLogger.error('Stack trace: $stackTrace');

      if (e.toString().contains('duplicate key') || e.toString().contains('23505')) {
        try {
          final existingConv = await _supabase
              .from('conversations')
              .select('id, user_id, other_user_id, last_message, last_message_time, unread_count, created_at, updated_at, deleted_for_user_id')
              .eq('user_id', currentUserId)
              .eq('other_user_id', otherUserId)
              .maybeSingle();

          if (existingConv != null) {
            if ((existingConv['deleted_for_user_id'] as String?) == currentUserId) {
              await _supabase
                  .from('conversations')
                  .update({'deleted_for_user_id': null})
                  .eq('id', existingConv['id'] as String);
            }

            final existingUserProfile = await _getOtherUserProfile(otherUserId);
            Map<String, dynamic> convWithProfile = Map<String, dynamic>.from(existingConv);
            convWithProfile['other_user'] = existingUserProfile;
            return Conversation.fromMap(convWithProfile);
          }
        } catch (_) {}
      }

      return null;
    }
  }

  Future<Map<String, dynamic>?> _getOtherUserProfile(String? userId) async {
    if (userId == null) return null;
    try {
      final profile = await _supabase
          .from('profiles')
          .select('id, full_name, username, avatar_url, is_online, last_seen')
          .eq('id', userId)
          .maybeSingle();
      return profile;
    } catch (e) {
      AppLogger.error('Error getting other user profile: $e');
      return null;
    }
  }

  Future<List<Conversation>> getConversations() async {
    final currentUserId = _supabase.auth.currentUser?.id;
    if (currentUserId == null) return [];

    try {
      AppLogger.debug('getConversations START: currentUserId=$currentUserId');

      final myConvs = await _supabase
          .from('conversations')
          .select('id, user_id, other_user_id, last_message, last_message_time, unread_count, created_at, updated_at, deleted_for_user_id')
          .eq('user_id', currentUserId)
          .or(_softDeleteFilter(currentUserId))
          .order('updated_at', ascending: false);

      final reverseConvs = await _supabase
          .from('conversations')
          .select('id, user_id, other_user_id, last_message, last_message_time, unread_count, created_at, updated_at, deleted_for_user_id')
          .eq('other_user_id', currentUserId)
          .or(_softDeleteFilter(currentUserId))
          .order('updated_at', ascending: false);

      AppLogger.debug('getConversations: myConvs=${myConvs.length}, reverseConvs=${reverseConvs.length}');

      if (myConvs.isEmpty && reverseConvs.isEmpty) return [];

      final Map<String, Map<String, dynamic>> partnerToConv = {};
      String pairKey(String a, String b) {
        final sorted = [a, b]..sort();
        return '${sorted[0]}_${sorted[1]}';
      }

      for (var rc in reverseConvs) {
        final partnerId = rc['user_id'] as String;
        final key = pairKey(currentUserId, partnerId);
        rc['user_id'] = currentUserId;
        rc['other_user_id'] = partnerId;
        partnerToConv[key] = rc;
      }
      for (var mc in myConvs) {
        final otherUserId = mc['other_user_id'] as String;
        final key = pairKey(currentUserId, otherUserId);
        partnerToConv[key] = mc;
      }

      final userConvs = partnerToConv.values.toList();

      final otherUserIds = userConvs.map((c) => c['other_user_id'] as String).toSet().toList();
      final profiles = await _supabase
          .from('profiles')
          .select('id, full_name, username, avatar_url, is_online, last_seen')
          .inFilter('id', otherUserIds);
      final profileMap = <String, Map<String, dynamic>>{};
      for (var p in profiles) {
        profileMap[p['id'] as String] = p;
      }

      // Partner conversation id haritasi (partnerId -> partner'in conv id'si).
      // ÖNEMLI: reverseConvs yukarida mutasyona ugradi (user_id=currentUserId,
      // other_user_id=partnerId). convByUserAndOther bu mutasyon yuzunden partner
      // conv'unu [otherUserId][currentUserId] altinda BULAMIYOR. Bu temiz harita
      // partner conv'unu mutasyonlu other_user_id (=partnerId) uzerinden bulur.
      final reverseConvIdByPartner = <String, String>{};
      for (var rc in reverseConvs) {
        reverseConvIdByPartner[rc['other_user_id'] as String] = rc['id'] as String;
      }

      final allConvIds = <String>[
        for (var c in myConvs) c['id'] as String,
        for (var c in reverseConvs) c['id'] as String,
      ];

      // Son mesajlari çek: ID'ye göre tekilestirme
      final lastMessages = await _supabase
          .from('messages')
          .select('id, conversation_id, sender_id, is_read, created_at, content')
          .inFilter('conversation_id', allConvIds)
          .or(_softDeleteFilter(currentUserId))
          .order('created_at', ascending: false);

      AppLogger.debug('getConversations: Toplam ${lastMessages.length} mesaj çekildi');

      // ID'ye göre tekilestirme (ayni mesaj iki conversation'da ise 1 kez)
      final uniqueById = <String, Map<String, dynamic>>{};
      for (var msg in lastMessages) {
        final mId = msg['id'] as String;
        uniqueById[mId] = msg;
      }

      final lastMessageMap = <String, Map<String, dynamic>>{};

      for (var c in userConvs) {
        final myConvId = c['id'] as String;
        final otherUserId = c['other_user_id'] as String;
        final key = pairKey(currentUserId, otherUserId);

        // Partner'in conversation'i (user_id=partner, other_user_id=ben)
        final partnerConvId = reverseConvIdByPartner[otherUserId] ?? '';

        // Bu partner için tüm conversation_id'lerden mesaj topla
        final partnerConvIds = <String>{
          myConvId,
          partnerConvId,
        }..removeWhere((e) => e.isEmpty);

        final partnerMessages = uniqueById.values.where((m) => partnerConvIds.contains(m['conversation_id'])).toList();

        if (partnerMessages.isNotEmpty) {
          // En yeni mesaj
          partnerMessages.sort((a, b) => DateTime.parse(b['created_at'] as String).compareTo(DateTime.parse(a['created_at'] as String)));
          final newest = Map<String, dynamic>.from(partnerMessages.first);

          // ÖNEMLI: Son mesaj BENIM ise "okundu" bilgisi SADECE partner
          // kopyasından gelir (karşı taraf okuyunca is_read=true). Kendi conv
          // kopyamdaki is_read her zaman true olduğu için ona güvenemeyiz;
          // aksi halde karşı taraf bakmadan kartta "görüldü" görünüyordu.
          if (newest['sender_id'] == currentUserId) {
            Map<String, dynamic>? partnerCopy;
            for (final m in partnerMessages) {
              if (m['conversation_id'] != myConvId &&
                  m['sender_id'] == currentUserId &&
                  m['content'] == newest['content'] &&
                  m['created_at'] == newest['created_at']) {
                partnerCopy = m;
                break;
              }
            }
            newest['is_read'] = (partnerCopy?['is_read'] as bool?) ?? false;
          }

          lastMessageMap[key] = newest;
        }
      }

      final allConversations = <Conversation>[];
      for (var conv in userConvs) {
        final otherUserId = conv['other_user_id'] as String;
        final otherUserProfile = profileMap[otherUserId];
        final key = pairKey(currentUserId, otherUserId);

        Map<String, dynamic> convWithProfile = Map<String, dynamic>.from(conv);
        convWithProfile['other_user'] = otherUserProfile;
        convWithProfile['unread_count'] = (conv['unread_count'] as int?) ?? 0;

        final lastMsgData = lastMessageMap[key];
        if (lastMsgData != null) {
          final senderId = lastMsgData['sender_id'] as String?;
          final isMe = senderId == currentUserId;
          final isRead = lastMsgData['is_read'] ?? false;
          convWithProfile['last_message_by_me'] = isMe;
          convWithProfile['last_message_read'] = isMe ? isRead : true;
          convWithProfile['last_message'] = lastMsgData['content'];
          convWithProfile['last_message_time'] = lastMsgData['created_at'];

          AppLogger.debug('  $key: sender=${isMe ? "ME" : "OTHER"} is_read=$isRead');
        } else {
          convWithProfile['last_message_by_me'] = false;
          convWithProfile['last_message_read'] = false;
        }

        allConversations.add(Conversation.fromMap(convWithProfile));
      }

      allConversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

      return allConversations;
    } catch (e, stackTrace) {
      AppLogger.error('Error getting conversations: $e', error: e, stackTrace: stackTrace);
      return [];
    }
  }

  // DÜZELTME: Hem bu conversation_id'den hem partner'in conversation_id'sinden
  // mesajlari çekip ID'ye göre tekilestiriyoruz. Çift yönlü sistemde mesaj
  // tek satirdir ama iki conversation_id'de görünür. ID tekilestirmesi
  // "kendi mesajim kardan gelmis gibi" yanilgisini önler.
  Future<List<Message>> getMessages(String conversationId) async {
    try {
      AppLogger.debug('getMessages START: conversationId=$conversationId');
      final currentUserId = _supabase.auth.currentUser?.id;

      // Bu conversation'in iki tarafi
      final convData = await _supabase
          .from('conversations')
          .select('user_id, other_user_id')
          .eq('id', conversationId)
          .maybeSingle();

      if (convData == null) {
        AppLogger.error('getMessages: Conversation not found');
        return [];
      }

      final convUserId = convData['user_id'] as String?;
      final convOtherUserId = convData['other_user_id'] as String?;

      // Partner'in conversation_id'sini bul
      String? partnerConvId;
      if (convUserId != null && convOtherUserId != null) {
        final otherConv = await _supabase
            .from('conversations')
            .select('id')
            .eq('user_id', convOtherUserId)
            .eq('other_user_id', convUserId)
            .maybeSingle();
        if (otherConv != null) partnerConvId = otherConv['id'] as String?;
      }

      // HER İKİ conversation_id'den mesajlari çek
      final convIds = <String>[conversationId];
      if (partnerConvId != null && partnerConvId != conversationId) {
        convIds.add(partnerConvId);
      }

      final softFilter = _softDeleteFilter(currentUserId);

      final response = await _supabase
          .from('messages')
          .select()
          .inFilter('conversation_id', convIds)
          .or(softFilter)
          .order('created_at', ascending: true);

      AppLogger.debug('getMessages: Fetched ${response.length} messages from ${convIds.length} conversations');

      // KOMPOZIT-ANAHTAR TEKILLESTIRME (Bug B fix):
      // Mailbox modelinde her mantıksal mesaj İKİ satır olarak durur:
      //   - gönderenin conv'unda (is_read=true)
      //   - alıcının conv'unda (is_read=false)
      // İki satır aynı sender_id + content + created_at, ama FARKLI id taşır.
      // id-bazlı tekilleştirme bu yüzden çalışmıyordu → her mesaj 2 kez görünüyordu.
      // Anahtar = sender_id|content|created_at. Kopyaları tek mesaja indirger ve
      // is_read'i DOĞRU kopyadan alır:
      //   - benim mesajım  -> partner kopyasının is_read'i (karşı taraf okudu mu)
      //   - gelen mesaj     -> kendi kopyamın is_read'i (ben okudum mu)
      final grouped = <String, List<Map<String, dynamic>>>{};
      final keyOrder = <String>[];
      for (var msg in response) {
        final key = '${msg['sender_id']}|${msg['content']}|${msg['created_at']}';
        final list = grouped.putIfAbsent(key, () {
          keyOrder.add(key);
          return <Map<String, dynamic>>[];
        });
        list.add(msg);
      }

      final uniqueMessages = <Map<String, dynamic>>[];
      for (final key in keyOrder) {
        final copies = grouped[key]!;
        Map<String, dynamic>? myCopy;
        Map<String, dynamic>? partnerCopy;
        for (final c in copies) {
          if (c['conversation_id'] == conversationId) {
            myCopy = c;
          } else {
            partnerCopy = c;
          }
        }
        // Görünüm tutarlılığı için kendi conv kopyamızı temel al (id sabit kalır,
        // realtime INSERT ile eşleşir). Yoksa eldeki tek kopyayı kullan.
        final base = Map<String, dynamic>.from(myCopy ?? partnerCopy ?? copies.first);
        final isMine = base['sender_id'] == currentUserId;
        if (isMine) {
          // Kendi mesajım için "okundu" SADECE partner kopyasından gelir
          // (karşı taraf okuduğunda true olur). Kendi conv kopyamdaki is_read
          // her zaman true'dur ve anlamsızdır → asla ona güvenme.
          base['is_read'] = (partnerCopy?['is_read'] as bool?) ?? false;
        } else {
          // Gelen mesaj: ben okudum mu → kendi conv kopyam
          base['is_read'] = (myCopy?['is_read'] as bool?) ??
              (base['is_read'] as bool?) ?? false;
        }
        uniqueMessages.add(base);
      }

      AppLogger.debug('getMessages: ${uniqueMessages.length} unique messages after dedup');

      for (var msg in uniqueMessages) {
        final isMe = msg['sender_id'] == currentUserId;
        final isRead = msg['is_read'] ?? false;
        final contentStr = (msg['content'] as String?) ?? '';
        final contentPreview = contentStr.length > 30 ? contentStr.substring(0, 30) : contentStr;
        AppLogger.debug('  msg_id=${msg['id']?.toString().substring(0, 8)}... sender=${isMe ? "ME" : "OTHER"} is_read=$isRead content=$contentPreview');
      }

      return uniqueMessages
          .map((json) => Message.fromMap(json))
          .toList();
    } catch (e, stackTrace) {
      AppLogger.error('Error getting messages: $e', error: e, stackTrace: stackTrace);
      return [];
    }
  }

  /// Mesaj gönder - Hem gönderenin hem alıcının conversation'ına ekler
  /// ÖNEMLI (2026-07-02): V2 RPC kullanıyor - trigger sonsuz döngü riski yok
  Future<Message?> sendMessage({
    required String conversationId,
    required String content,
    String? replyToId,
    String? replyToContent,
    String? replyToSenderName,
  }) async {
    final currentUserId = _supabase.auth.currentUser?.id;
    if (currentUserId == null) return null;

    AppLogger.debug('sendMessage: conversationId=$conversationId');

    try {
      // ÖNEMLI: V2 RPC'yi kullan - mesajı her iki conversation'a da ekler
      // Bu RPC trigger tetiklemez, sonsuz döngü riski yoktur
      final rpcResponse = await _supabase.rpc(
        'send_message_with_recipient',
        params: {
          'p_conversation_id': conversationId,
          'p_content': content,
          'p_sender_id': currentUserId,
          'p_reply_to_id': replyToId,
          'p_reply_to_content': replyToContent,
          'p_reply_to_sender_name': replyToSenderName,
        },
      );

      AppLogger.debug('sendMessage RPC response: $rpcResponse');

      if (rpcResponse == null) return null;

      // RPC RETURNS TABLE - tek satır döner
      Map<String, dynamic> messageData;
      if (rpcResponse is List && rpcResponse.isNotEmpty) {
        messageData = Map<String, dynamic>.from(rpcResponse.first as Map);
      } else if (rpcResponse is Map) {
        messageData = Map<String, dynamic>.from(rpcResponse);
      } else {
        return null;
      }

      // message_id'yi id olarak kullan (gönderenin kendi conversation kopyası)
      if (messageData['message_id'] != null) {
        messageData['id'] = messageData['message_id'];
      }
      messageData['sender_id'] = currentUserId;
      // ÖNEMLI (Bug A fix): RPC artık created_at/updated_at döndürüyor.
      // created_at yoksa Message.fromMap FormatException fırlatır ve mesaj
      // gönderilmiş olmasına rağmen "gönderilemedi" hatası çıkardı.
      // Eski RPC'ye karşı da güvenli olmak için fallback bırakıyoruz.
      final nowIso = DateTime.now().toUtc().toIso8601String();
      messageData['created_at'] ??= nowIso;
      messageData['updated_at'] ??= messageData['created_at'];
      // Gönderenin ekranında: karşı taraf henüz okumadı → 'sent' (mavi tik yok).
      messageData['is_read'] = false;

      return Message.fromMap(messageData);
    } catch (e) {
      AppLogger.error('sendMessage RPC ERROR: $e');
      // FALLBACK YOK - fallback INSERT tetiklerdi ve 3 kopya olusturuyordu
      // Kullaniciya hata gosterilecek
      return null;
    }
  }

  Future<Message?> sendSharedPost({
    required String conversationId,
    required String postId,
    required String postContent,
    String? postImageUrl,
    String? authorName,
  }) async {
    final currentUserId = _supabase.auth.currentUser?.id;
    if (currentUserId == null) return null;

    try {
      final postData = {
        'postId': postId,
        'content': postContent,
        'imageUrl': postImageUrl ?? '',
        'authorName': authorName ?? '',
      };

      final jsonStr = json.encode(postData);
      final content = 'SHARED_POST:$jsonStr';

      final message = await _supabase
          .from('messages')
          .insert({
            'conversation_id': conversationId,
            'sender_id': currentUserId,
            'content': content,
          })
          .select()
          .single();

      return Message.fromMap(message);
    } catch (e, stackTrace) {
      AppLogger.error('Error sending shared post: $e');
      AppLogger.error('Stack trace: $stackTrace');
      return null;
    }
  }

  /// Kaldırıldı (2026-07-02): markSenderMessagesAsRead artık gerekli değil.
  /// Okundu bilgisi sadece mesajı ALAN kişi tarafından işaretlenmeli.
  /// Gönderen kişi, mesajın okundu bilgisini görmek için:
  /// 1. Realtime UPDATE event'ini dinlemeli (is_read değişikliği)
  /// 2. Karşı taraf sohbeti açtığında otomatik güncellenir
  @Deprecated('Artık gerekli değil. Okundu bilgisi sadece alıcı tarafından işaretlenir.')
  Future<void> markSenderMessagesAsRead(String conversationId) async {
    // Bu metod artık bir şey yapmıyor.
    // Okundu bilgisi markMessagesAsRead() tarafından yönetiliyor.
    AppLogger.debug('markSenderMessagesAsRead DEPRECATED: artik cagrilmiyor');
  }

  /// Mesajları okundu olarak işaretle
  /// ÖNEMLİ: Sadece KARŞI TARAFIN gönderdiği mesajları okundu yapar
  /// Bu metod sohbet ekranı açıldığında çağrılır
  Future<void> markMessagesAsRead(String conversationId) async {
    final currentUserId = _supabase.auth.currentUser?.id;
    if (currentUserId == null) return;

    AppLogger.debug('markMessagesAsRead START: conv=$conversationId userId=$currentUserId');

    try {
      await _supabase.rpc('mark_messages_as_read', params: {
        'p_conversation_id': conversationId,
      });
      AppLogger.debug('markMessagesAsRead: RPC success');
    } catch (e) {
      AppLogger.error('markMessagesAsRead RPC failed, trying direct: $e');
      try {
        // Direct fallback: conversation bilgilerini al
        final convData = await _supabase
            .from('conversations')
            .select('user_id, other_user_id')
            .eq('id', conversationId)
            .maybeSingle();

        if (convData == null) return;

        final convUserId = convData['user_id'] as String?;
        final otherUserId = convData['other_user_id'] as String?;

        if (convUserId != currentUserId) return; // Sadece conversation sahibi işaretlesin
        if (otherUserId == null) return; // Partner yoksa çık

        // Karşı tarafın mesajlarını okundu yap
        await _supabase
            .from('messages')
            .update({'is_read': true, 'updated_at': DateTime.now().toIso8601String()})
            .eq('conversation_id', conversationId)
            .eq('sender_id', otherUserId)
            .eq('is_read', false);

        // Unread count'u sıfırla
        await _supabase
            .from('conversations')
            .update({'unread_count': 0, 'updated_at': DateTime.now().toIso8601String()})
            .eq('id', conversationId);

        AppLogger.debug('markMessagesAsRead: Direct update success');
      } catch (e2) {
        AppLogger.error('markMessagesAsRead direct update also failed: $e2');
      }
    }
  }

  Future<bool> deleteConversation(String conversationId) async {
    AppLogger.debug('deleteConversation: conversationId=$conversationId');
    try {
      final dynamic result = await _supabase.rpc(
        'delete_conversation_for_user',
        params: {'p_conversation_id': conversationId},
      );
      final ok = result == true;
      AppLogger.debug('deleteConversation: soft-deleted ok=$ok');
      return ok;
    } catch (e, stackTrace) {
      AppLogger.error('Error deleting conversation: $e');
      AppLogger.error('Stack trace: $stackTrace');
      rethrow;
    }
  }

  RealtimeChannel subscribeToConversations(Function(List<Conversation>) onUpdate) {
    return _supabase
        .channel('conversations_channel')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'conversations',
          callback: (payload) async {
            await Future.delayed(const Duration(milliseconds: 300));
            final conversations = await getConversations();
            onUpdate(conversations);
          },
        )
        .subscribe();
  }

  /// Konuşma bazlı presence dinlemesi. ChatDetailScreen initState'inde kullanılır.
  /// presenceService.joinConversationPresence() ayrıca çağrılmalı.
  ///
  /// ÖNEMLI DÜZELTME (2026-07-02):
  /// Eski kod sadece tek conversation_id'yi dinliyordu. İki yönlü sistemde
  /// mesaj hem gönderenin hem alıcının conversation'ına ekleniyor (trigger ile).
  /// Bu yüzden TÜM mesajları dinleyip client tarafında filtreleme yapıyoruz.
  RealtimeChannel subscribeToMessagesChannel({
    required String conversationId,
    required String currentUserId,
    required void Function(RealtimeMessageEvent event) onEvent,
  }) {
    final channel = _supabase.channel('messages:$conversationId');

    // INSERT: TÜM mesajları dinle, client tarafında conversationId kontrolü yap
    channel.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'messages',
      callback: (payload) {
        AppLogger.debug('Realtime INSERT: ${payload.eventType} conv=${payload.newRecord['conversation_id']}');
        try {
          final msg = Message.fromMap(payload.newRecord);
          // Sadece bu conversation'a ait mesajları al
          if (msg.conversationId == conversationId || msg.senderId != currentUserId) {
            onEvent(InsertMessageEvent(msg));
          }
        } catch (e, st) {
          AppLogger.error('INSERT decode error: $e', stackTrace: st);
        }
      },
    );

    // UPDATE: TÜM güncellemeleri dinle (okundu bilgisi için gerekli)
    channel.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'messages',
      callback: (payload) {
        AppLogger.debug('Realtime UPDATE: ${payload.eventType} conv=${payload.newRecord['conversation_id']}');
        try {
          final msg = Message.fromMap(payload.newRecord);
          // Sadece bu conversation'a ait mesajları al
          if (msg.conversationId == conversationId) {
            onEvent(UpdateMessageEvent(msg));
          }
        } catch (e, st) {
          AppLogger.error('UPDATE decode error: $e', stackTrace: st);
        }
      },
    );

    // DELETE: TÜM silme işlemlerini dinle
    channel.onPostgresChanges(
      event: PostgresChangeEvent.delete,
      schema: 'public',
      table: 'messages',
      callback: (payload) {
        AppLogger.debug('Realtime DELETE: ${payload.eventType}');
        final id = payload.oldRecord['id'] as String?;
        final convId = payload.oldRecord['conversation_id'] as String?;
        // Sadece bu conversation'a ait mesajları al
        if (id != null && convId == conversationId) {
          onEvent(DeleteMessageEvent(id));
        }
      },
    );

    return channel.subscribe((status, error) {
      if (status == RealtimeSubscribeStatus.subscribed) {
        AppLogger.debug('Messages channel subscribed: $conversationId');
      }
      if (error != null) {
        AppLogger.error('Messages channel error: $error');
      }
    });
  }

  // -------------------------------------------------------------------------
  // Stream-based realtime mesajlar — UI'da StreamBuilder veya subscription ile
  // kullanılır. Her event tipi ayrı channel'da, DB'yi yeniden çekmez.
  // -------------------------------------------------------------------------

  /// ÖNEMLI: Bu stream TÜM mesajları dinler.
  /// Client tarafında conversationId'ye göre filtreleme yapılmalı.
  ///
  /// ÖNEMLI (2026-07-02 duplicate fix):
  ///   - Aynı channel adı varsa removeChannel ile temizlenir
  ///   - Böylece çift subscription önlenir (3'er gidiyor sorunu)
  Stream<Message> streamNewMessages(String conversationId) {
    final controller = StreamController<Message>();
    final channelName = 'messages:insert:$conversationId';

    // Aynı isimli channel varsa önce kaldır (duplicate subscription önle)
    final existingChannel = _supabase.channel(channelName);
    _supabase.removeChannel(existingChannel);

    final channel = _supabase
        .channel(channelName)
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (payload) {
            try {
              final msg = Message.fromMap(payload.newRecord);
              // Client tarafı filtreleme: sadece bu conversation'a ait
              if (msg.conversationId == conversationId) {
                controller.add(msg);
              }
            } catch (e) {
              debugPrint('streamNewMessages decode error: $e');
            }
          },
        )
        .subscribe();

    controller.onCancel = () async {
      await _supabase.removeChannel(channel);
    };

    return controller.stream;
  }

  /// ÖNEMLI: Bu stream artık TÜM mesaj güncellemelerini dinler.
  /// Client tarafında conversationId'ye göre filtreleme yapılmalı.
  Stream<Message> streamMessageUpdates(String conversationId) {
    final controller = StreamController<Message>();

    final channel = _supabase
        .channel('messages:update:$conversationId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'messages',
          callback: (payload) {
            try {
              final msg = Message.fromMap(payload.newRecord);
              // Client tarafı filtreleme
              if (msg.conversationId == conversationId) {
                controller.add(msg);
              }
            } catch (e) {
              debugPrint('streamMessageUpdates decode error: $e');
            }
          },
        )
        .subscribe();

    controller.onCancel = () async {
      await _supabase.removeChannel(channel);
    };

    return controller.stream;
  }

  /// ÖNEMLI: Bu stream artık TÜM mesaj silme işlemlerini dinler.
  /// Client tarafında conversationId'ye göre filtreleme yapılmalı.
  Stream<String> streamDeletedMessages(String conversationId) {
    final controller = StreamController<String>();

    final channel = _supabase
        .channel('messages:delete:$conversationId')
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'messages',
          callback: (payload) {
            final id = payload.oldRecord['id'] as String?;
            final convId = payload.oldRecord['conversation_id'] as String?;
            if (id != null && convId == conversationId) {
              controller.add(id);
            }
          },
        )
        .subscribe();

    controller.onCancel = () async {
      await _supabase.removeChannel(channel);
    };

    return controller.stream;
  }

  Future<int> getUnreadCount() async {
    final currentUserId = _supabase.auth.currentUser?.id;
    if (currentUserId == null) return 0;

    try {
      final softFilter = _softDeleteFilter(currentUserId);
      final myConvs = await _supabase
          .from('conversations')
          .select('unread_count')
          .eq('user_id', currentUserId)
          .or(softFilter);

      int total = 0;
      for (var conv in myConvs) {
        total += (conv['unread_count'] as int? ?? 0);
      }
      return total;
    } catch (e) {
      AppLogger.error('Error getting unread count: $e');
      return 0;
    }
  }
}

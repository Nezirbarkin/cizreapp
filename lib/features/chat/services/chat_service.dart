import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/conversation_model.dart';
import '../../../core/models/message_model.dart';
import '../../../core/utils/app_logger.dart';

class ChatService {
  final _supabase = Supabase.instance.client;

  // Konuşma al veya oluştur
  Future<Conversation?> getOrCreateConversation(String otherUserId) async {
    final currentUserId = _supabase.auth.currentUser?.id;
    if (currentUserId == null) {
      AppLogger.error('getOrCreateConversation: currentUserId is null');
      return null;
    }

    AppLogger.debug('getOrCreateConversation: currentUserId=$currentUserId, otherUserId=$otherUserId');

    try {
      // Diğer kullanıcının mesaj kabul etme durumunu kontrol et
      final otherUserProfile = await _supabase
          .from('profiles')
          .select('messages_enabled')
          .eq('id', otherUserId)
          .maybeSingle();

      if (otherUserProfile != null && otherUserProfile['messages_enabled'] == false) {
        AppLogger.debug('getOrCreateConversation: Other user has messages disabled');
        return null; // Diğer kullanıcı mesajları kapatmış
      }

      // Mevcut konuşmayı ara - sadece user_id = currentUserId olan kaydı
      final existingConv = await _supabase
          .from('conversations')
          .select('id, user_id, other_user_id, last_message, last_message_time, unread_count, created_at, updated_at')
          .eq('user_id', currentUserId)
          .eq('other_user_id', otherUserId)
          .maybeSingle();

      AppLogger.debug('getOrCreateConversation: existingConv=$existingConv');

      if (existingConv != null) {
        // Diğer kullanıcı bilgilerini ayrı getir
        final otherUserProfileData = await _getOtherUserProfile(otherUserId);
        
        Map<String, dynamic> convWithProfile = Map<String, dynamic>.from(existingConv);
        convWithProfile['other_user'] = otherUserProfileData;
        
        return Conversation.fromMap(convWithProfile);
      }

      // Yeni konuşma oluştur
      AppLogger.debug('getOrCreateConversation: Creating new conversation...');
      
      // Basit insert - trigger karşı tarafı oluşturacak
      final newConv = await _supabase
          .from('conversations')
          .insert({
            'user_id': currentUserId,
            'other_user_id': otherUserId,
          })
          .select('id, user_id, other_user_id, last_message, last_message_time, unread_count, created_at, updated_at')
          .single();

      AppLogger.debug('getOrCreateConversation: newConv=$newConv');

      // Diğer kullanıcı bilgilerini getir
      final newOtherUserProfileData = await _getOtherUserProfile(otherUserId);
      
      Map<String, dynamic> convWithProfile = Map<String, dynamic>.from(newConv);
      convWithProfile['other_user'] = newOtherUserProfileData;

      return Conversation.fromMap(convWithProfile);
    } catch (e, stackTrace) {
      AppLogger.error('Error getting/creating conversation: $e');
      AppLogger.error('Stack trace: $stackTrace');
      
      // Duplicate key hatasıysa, mevcut kaydı tekrar dene
      if (e.toString().contains('duplicate key') || e.toString().contains('23505')) {
        AppLogger.debug('Duplicate key detected, retrying fetch...');
        try {
          final existingConv = await _supabase
              .from('conversations')
              .select('id, user_id, other_user_id, last_message, last_message_time, unread_count, created_at, updated_at')
              .eq('user_id', currentUserId)
              .eq('other_user_id', otherUserId)
              .maybeSingle();
          
          if (existingConv != null) {
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

  // Yardımcı: Diğer kullanıcı profilini getir
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

  // Tüm konuşmaları al
  Future<List<Conversation>> getConversations() async {
    final currentUserId = _supabase.auth.currentUser?.id;
    if (currentUserId == null) return [];

    try {
      // Sadece user_id = currentUserId olan konuşmaları al
      // Her konuşma için 2 kayıt var (iki yönlü), sadece bizim tarafımızı alıyoruz
      // unread_count zaten bizim okunmamışlarımızı gösteriyor
      final userConvs = await _supabase
          .from('conversations')
          .select('id, user_id, other_user_id, last_message, last_message_time, unread_count, created_at, updated_at')
          .eq('user_id', currentUserId)
          .order('updated_at', ascending: false);

      // Profil bilgilerini getir
      List<Conversation> allConversations = [];
      
      for (var conv in userConvs) {
        final otherUserProfile = await _getOtherUserProfile(conv['other_user_id']);
        
        // Son mesajın gönderen ve okunma bilgisini al
        Map<String, dynamic>? lastMessageData;
        try {
          final messages = await _supabase
              .from('messages')
              .select('sender_id, is_read')
              .eq('conversation_id', conv['id'])
              .order('created_at', ascending: false)
              .limit(1);
          
          if (messages.isNotEmpty) {
            lastMessageData = messages.first;
          }
        } catch (_) {}
        
        Map<String, dynamic> convWithProfile = Map<String, dynamic>.from(conv);
        convWithProfile['other_user'] = otherUserProfile;
        // Son mesajın benim tarafımdan gönderilip gönderilmediğini ve okunma durumunu ekle
        if (lastMessageData != null) {
          convWithProfile['last_message_by_me'] = lastMessageData['sender_id'] == currentUserId;
          convWithProfile['last_message_read'] = lastMessageData['is_read'] ?? false;
        } else {
          convWithProfile['last_message_by_me'] = false;
          convWithProfile['last_message_read'] = false;
        }
        
        allConversations.add(Conversation.fromMap(convWithProfile));
      }

      return allConversations;
    } catch (e) {
      AppLogger.error('Error getting conversations: $e');
      return [];
    }
  }

  // Konuşmadaki mesajları al - her iki tarafın conversation_id'sini de kontrol et
  Future<List<Message>> getMessages(String conversationId) async {
    try {
      // Önce bu konuşmanın diğer tarafını bul
      final convData = await _supabase
          .from('conversations')
          .select('user_id, other_user_id')
          .eq('id', conversationId)
          .maybeSingle();
      
      if (convData == null) {
        AppLogger.error('getMessages: Conversation not found: $conversationId');
        return [];
      }
      
      final userId = convData['user_id'] as String;
      final otherUserId = convData['other_user_id'] as String;
      
      // Karşı tarafın conversation_id'sini bul
      final otherConv = await _supabase
          .from('conversations')
          .select('id')
          .eq('user_id', otherUserId)
          .eq('other_user_id', userId)
          .maybeSingle();
      
      // Her iki conversation_id'den gelen mesajları al
      final List<String> convIds = [conversationId];
      if (otherConv != null) {
        convIds.add(otherConv['id'] as String);
      }
      
      final response = await _supabase
          .from('messages')
          .select()
          .inFilter('conversation_id', convIds)
          .order('created_at', ascending: true);

      return (response as List)
          .map((json) => Message.fromMap(json))
          .toList();
    } catch (e) {
      AppLogger.error('Error getting messages: $e');
      return [];
    }
  }

  // Mesaj gönder
  Future<Message?> sendMessage({
    required String conversationId,
    required String content,
  }) async {
    final currentUserId = _supabase.auth.currentUser?.id;
    if (currentUserId == null) {
      AppLogger.error('sendMessage: currentUserId is null');
      return null;
    }

    AppLogger.debug('🔍 sendMessage DEBUG:');
    AppLogger.debug('  conversationId: $conversationId (${conversationId.runtimeType})');
    AppLogger.debug('  currentUserId: $currentUserId (${currentUserId.runtimeType})');
    AppLogger.debug('  content length: ${content.length} chars');

    try {
      AppLogger.debug('📤 Attempting direct insert into messages...');
      
      // Doğrudan insert kullan
      final response = await _supabase
          .from('messages')
          .insert({
            'conversation_id': conversationId,
            'sender_id': currentUserId,
            'content': content,
          })
          .select()
          .single();

      AppLogger.debug('✅ sendMessage SUCCESS: $response');
      return Message.fromMap(response);
    } catch (e) {
      AppLogger.error('❌ sendMessage direct insert ERROR: $e');
      AppLogger.error('❌ Error type: ${e.runtimeType}');
      
      // Fallback: RPC dene
      try {
        AppLogger.debug('📤 Fallback: Attempting RPC send_message_direct...');
        final dynamic rpcResponse = await _supabase.rpc(
          'send_message_direct',
          params: {
            'p_conversation_id': conversationId,
            'p_content': content,
          },
        );

        if (rpcResponse == null) {
          AppLogger.error('❌ sendMessage: RPC returned null');
          return null;
        }

        Map<String, dynamic> message;
        if (rpcResponse is List && rpcResponse.isNotEmpty) {
          message = Map<String, dynamic>.from(rpcResponse.first as Map);
        } else if (rpcResponse is Map) {
          message = Map<String, dynamic>.from(rpcResponse);
        } else {
          AppLogger.error('❌ sendMessage: Unexpected response type: ${rpcResponse.runtimeType}');
          return null;
        }

        AppLogger.debug('✅ sendMessage SUCCESS via RPC fallback: $message');
        return Message.fromMap(message);
      } catch (e2, stackTrace2) {
        AppLogger.error('❌ sendMessage RPC fallback ERROR: $e2');
        AppLogger.error('❌ Stack trace: $stackTrace2');
        return null;
      }
    }
  }

  // Gönderi paylaşımı mesajı gönder
  Future<Message?> sendSharedPost({
    required String conversationId,
    required String postId,
    required String postContent,
    String? postImageUrl,
    String? authorName,
  }) async {
    final currentUserId = _supabase.auth.currentUser?.id;
    if (currentUserId == null) {
      AppLogger.error('sendSharedPost: currentUserId is null');
      return null;
    }

    AppLogger.debug('sendSharedPost: conversationId=$conversationId, postId=$postId');

    try {
      // Gönderi bilgisini JSON formatında content'e ekle
      final postData = {
        'postId': postId,
        'content': postContent,
        'imageUrl': postImageUrl ?? '',
        'authorName': authorName ?? '',
      };
      
      final jsonStr = json.encode(postData);
      final content = 'SHARED_POST:$jsonStr';
      
      AppLogger.debug('sendSharedPost: JSON length = ${jsonStr.length}');
      
      final message = await _supabase
          .from('messages')
          .insert({
            'conversation_id': conversationId,
            'sender_id': currentUserId,
            'content': content,
          })
          .select()
          .single();

      AppLogger.debug('sendSharedPost: success, message=$message');
      return Message.fromMap(message);
    } catch (e, stackTrace) {
      AppLogger.error('Error sending shared post: $e');
      AppLogger.error('Stack trace: $stackTrace');
      return null;
    }
  }

  // Gönderenin mesajlarını okundu olarak işaretle (karşı taraf sohbeti açtığında)
  Future<void> markSenderMessagesAsRead(String conversationId) async {
    final currentUserId = _supabase.auth.currentUser?.id;
    if (currentUserId == null) return;

    try {
      // RPC fonksiyonunu çağır
      await _supabase.rpc(
        'mark_sender_messages_read',
        params: {
          'p_conversation_id': conversationId,
          'p_reader_id': currentUserId,
        },
      );
      AppLogger.debug('markSenderMessagesAsRead: RPC success for $conversationId');
    } catch (e) {
      AppLogger.error('markSenderMessagesAsRead RPC failed, trying direct update: $e');
      // Fallback: Doğrudan güncelle
      try {
        // Konuşma bilgilerini al
        final convData = await _supabase
            .from('conversations')
            .select('user_id, other_user_id')
            .eq('id', conversationId)
            .maybeSingle();
        
        if (convData == null) return;
        
        final userId = convData['user_id'] as String;
        final otherUserId = convData['other_user_id'] as String;
        
        // Diğer tarafın conversation_id'sini bul
        final otherConv = await _supabase
            .from('conversations')
            .select('id')
            .eq('user_id', otherUserId)
            .eq('other_user_id', userId)
            .maybeSingle();
        
        if (otherConv != null) {
          // Karşı tarafın konuşmasındaki, benim gönderdiğim mesajları okundu yap
          await _supabase
              .from('messages')
              .update({'is_read': true})
              .eq('conversation_id', otherConv['id'])
              .eq('sender_id', currentUserId)
              .eq('is_read', false);
          
          AppLogger.debug('markSenderMessagesAsRead: Direct update success for $conversationId');
        }
      } catch (e2) {
        AppLogger.error('markSenderMessagesAsRead direct update also failed: $e2');
      }
    }
  }

  // Mesajları okundu olarak işaretle
  Future<void> markMessagesAsRead(String conversationId) async {
    final currentUserId = _supabase.auth.currentUser?.id;
    if (currentUserId == null) return;
    
    try {
      // Önce RPC dene
      await _supabase.rpc('mark_messages_as_read', params: {
        'p_conversation_id': conversationId,
      });
      AppLogger.debug('markMessagesAsRead: RPC success for $conversationId');
    } catch (e) {
      AppLogger.error('markMessagesAsRead RPC failed, trying direct update: $e');
      
      // RPC yoksa doğrudan güncelle
      try {
        // Bu konuşmanın her iki tarafının conversation_id'sini bul
        final convData = await _supabase
            .from('conversations')
            .select('user_id, other_user_id')
            .eq('id', conversationId)
            .maybeSingle();
        
        if (convData == null) return;
        
        final userId = convData['user_id'] as String;
        final otherUserId = convData['other_user_id'] as String;
        
        // İki tarafın conversation_id'lerini topla
        final List<String> convIds = [conversationId];
        
        final otherConv = await _supabase
            .from('conversations')
            .select('id')
            .eq('user_id', otherUserId)
            .eq('other_user_id', userId)
            .maybeSingle();
        
        if (otherConv != null) {
          convIds.add(otherConv['id'] as String);
        }
        
        // Karşı tarafın gönderdiği (benim almış olduğum) mesajları okundu yap
        await _supabase
            .from('messages')
            .update({'is_read': true})
            .inFilter('conversation_id', convIds)
            .neq('sender_id', currentUserId)
            .eq('is_read', false);
        
        // Benim konuşmamın unread_count'unu sıfırla
        await _supabase
            .from('conversations')
            .update({'unread_count': 0})
            .eq('id', conversationId);
        
        AppLogger.debug('markMessagesAsRead: Direct update success for $conversationId');
      } catch (e2) {
        AppLogger.error('markMessagesAsRead direct update also failed: $e2');
      }
    }
  }

  // Konuşmayı sil
  Future<void> deleteConversation(String conversationId) async {
    AppLogger.debug('deleteConversation: conversationId=$conversationId');
    try {
      await _supabase
          .from('conversations')
          .delete()
          .eq('id', conversationId);
      AppLogger.debug('deleteConversation: success');
    } catch (e, stackTrace) {
      AppLogger.error('Error deleting conversation: $e');
      AppLogger.error('Stack trace: $stackTrace');
      rethrow; // Hatayı yukarı fırlat ki UI'da gösterilebilsin
    }
  }

  // Realtime: Konuşmalar için subscription
  RealtimeChannel subscribeToConversations(Function(List<Conversation>) onUpdate) {
    return _supabase
        .channel('conversations_channel')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'conversations',
          callback: (payload) async {
            // Konuşmalar değiştiğinde güncel listeyi al
            final conversations = await getConversations();
            onUpdate(conversations);
          },
        )
        .subscribe();
  }

  // Realtime: Mesajlar için subscription - messages tablosundaki değişiklikleri dinle
  // Değişiklik olduğunda getMessages ile tüm mesajları yeniden çeker (her iki tarafın mesajları dahil)
  RealtimeChannel subscribeToMessagesChannel(String conversationId, Function(List<Message>) onUpdate) {
    return _supabase
        .channel('messages_$conversationId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'messages',
          callback: (payload) async {
            // Debug: Mesaj değişikliği geldi
            AppLogger.debug('📨 Realtime message change: ${payload.eventType}, newRecord: ${payload.newRecord}');
            
            // Herhangi bir mesaj değişikliğinde tüm mesajları yeniden çek
            final messages = await getMessages(conversationId);
            onUpdate(messages);
          },
        )
        .subscribe();
  }

  // Toplam okunmamış mesaj sayısı
  Future<int> getUnreadCount() async {
    final currentUserId = _supabase.auth.currentUser?.id;
    if (currentUserId == null) return 0;

    try {
      final response = await _supabase
          .from('conversations')
          .select('unread_count')
          .eq('user_id', currentUserId);

      int total = 0;
      for (var conv in response) {
        total += (conv['unread_count'] as int? ?? 0);
      }
      return total;
    } catch (e) {
      AppLogger.error('Error getting unread count: $e');
      return 0;
    }
  }
}

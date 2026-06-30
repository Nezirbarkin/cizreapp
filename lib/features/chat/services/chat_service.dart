// ignore_for_file: unnecessary_brace_in_string_interps

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/conversation_model.dart';
import '../../../core/models/message_model.dart';
import '../../../core/utils/app_logger.dart';

class ChatService {
  /// Supabase client'ı güvenli şekilde al (lazy) - class-level initializer yerine
  SupabaseClient get _supabase {
    try {
      return Supabase.instance.client;
    } catch (e) {
      debugPrint('⚠️ Supabase henüz başlatılmadı: $e');
      rethrow;
    }
  }

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

  // Tüm konuşmaları al - PERFORMANCE OPTIMIZED
  // DÜZELTME: Hem user_id=currentUserId OLAN hem de other_user_id=currentUserId OLAN
  // conversation'ları birleştirir. Çift yönlü sistemde her iki tarafın da conversation
  // kaydı olur; bu yüzden karşı tarafın başlattığı sohbetler de görünür olur.
  Future<List<Conversation>> getConversations() async {
    final currentUserId = _supabase.auth.currentUser?.id;
    if (currentUserId == null) return [];

    try {
      AppLogger.debug('📋 getConversations START: currentUserId=$currentUserId');

      // 1) Benim başlattığım / user_id bana ait olan konuşmalar
      final myConvs = await _supabase
          .from('conversations')
          .select('id, user_id, other_user_id, last_message, last_message_time, unread_count, created_at, updated_at')
          .eq('user_id', currentUserId)
          .order('updated_at', ascending: false);

      // 2) Karşı tarafın başlattığı / other_user_id bana ait olan konuşmalar
      //    Bu, sendMessage yapıldığında trigger'ın diğer tarafta oluşturduğu conversation
      final reverseConvs = await _supabase
          .from('conversations')
          .select('id, user_id, other_user_id, last_message, last_message_time, unread_count, created_at, updated_at')
          .eq('other_user_id', currentUserId)
          .order('updated_at', ascending: false);

      AppLogger.debug('📋 getConversations: myConvs=${myConvs.length}, reverseConvs=${reverseConvs.length}');

      if (myConvs.isEmpty && reverseConvs.isEmpty) return [];

      // 3) Her partner için tek bir conversation kalsın. Aynı partner için hem myConvs hem
      //    reverseConvs varsa, myConvs tercih edilir (çünkü unread_count=0 benim için
      //    anlamlıdır; reverse'de unread_count karşı tarafın okunmamışıdır).
      // Anahtar: smaller_userId + larger_userId çifti
      final Map<String, Map<String, dynamic>> partnerToConv = {};
      String pairKey(String a, String b) {
        final sorted = [a, b]..sort();
        return '${sorted[0]}_${sorted[1]}';
      }

      // Önce reverseConvs (bunlar karşı tarafın başlattığı; daha az öncelikli)
      for (var rc in reverseConvs) {
        final otherUserId = rc['other_user_id'] as String;
        final key = pairKey(currentUserId, otherUserId);
        // Normalize: currentUser perspektifinden other_user_id her zaman partner olmalı
        rc['other_user_id'] = otherUserId;
        partnerToConv[key] = rc;
      }
      // Sonra myConvs (bunlar benim tarafıma ait; daha öncelikli - üzerine yaz)
      for (var mc in myConvs) {
        final otherUserId = mc['other_user_id'] as String;
        final key = pairKey(currentUserId, otherUserId);
        partnerToConv[key] = mc;
      }

      final userConvs = partnerToConv.values.toList();

      // 4) Toplu profil çekme
      final otherUserIds = userConvs.map((c) => c['other_user_id'] as String).toSet().toList();
      final profiles = await _supabase
          .from('profiles')
          .select('id, full_name, username, avatar_url, is_online, last_seen')
          .inFilter('id', otherUserIds);
      final profileMap = <String, Map<String, dynamic>>{};
      for (var p in profiles) {
        profileMap[p['id'] as String] = p;
      }

      // 5) Her partner için karşı tarafın conversation_id'sini bul (çift yönlü mesajlar için)
      // user_id -> (other_user_id -> conversation_id)
      final Map<String, Map<String, String>> convByUserAndOther = {};
      // Hem myConvs hem reverseConvs'tan map oluştur
      for (var c in myConvs) {
        convByUserAndOther
            .putIfAbsent(c['user_id'] as String, () => {})
            [c['other_user_id'] as String] = c['id'] as String;
      }
      for (var c in reverseConvs) {
        convByUserAndOther
            .putIfAbsent(c['user_id'] as String, () => {})
            [c['other_user_id'] as String] = c['id'] as String;
      }

      // 6) Hem myConvs hem reverseConvs'un ID'lerini topla (mesajları toplu çekmek için)
      final allConvIds = <String>[
        for (var c in myConvs) c['id'] as String,
        for (var c in reverseConvs) c['id'] as String,
      ];

      // 7) Tüm bu conversation'lardaki mesajları tek sorguda çek
      // KRİTİK: is_read'i tam olarak al
      final lastMessages = await _supabase
          .from('messages')
          .select('id, conversation_id, sender_id, is_read, created_at, content')
          .inFilter('conversation_id', allConvIds)
          .order('created_at', ascending: false);

      AppLogger.debug('📋 getConversations: Toplam ${lastMessages.length} mesaj çekildi (${allConvIds.length} conversation\'dan)');

      // 8) Her conversation_id için en yeni mesajı haritala
      final msgByConvId = <String, Map<String, dynamic>>{};
      for (var msg in lastMessages) {
        final cId = msg['conversation_id'] as String;
        if (!msgByConvId.containsKey(cId)) {
          msgByConvId[cId] = msg;
        }
      }

      // 9) Her partner için, iki conversation'daki en yeni mesajı bul ve birleştir
      final lastMessageMap = <String, Map<String, dynamic>>{}; // partnerKey -> en yeni mesaj
      final myConvIdToPartnerKey = <String, String>{}; // myConvId -> partnerKey

      for (var c in userConvs) {
        final myConvId = c['id'] as String;
        final otherUserId = c['other_user_id'] as String;
        final key = pairKey(currentUserId, otherUserId);
        myConvIdToPartnerKey[myConvId] = key;

        // Bu partner için her iki yöndeki conversation_id'leri bul
        // c user_id=currentUserId, other_user_id=otherUserId ise: myConv
        // c user_id=otherUserId, other_user_id=currentUserId ise: reverse
        // (normalize edilmiş userConvs'ta user_id her zaman currentUserId DEĞİL!)
        // Aslında yukarıdaki partnerToConv map'inde reverse'leri de normalize etmedik,
        // bu yüzden doğrudan c['id'] = myConvId (tercih edilen), ve karşı tarafın
        // otherConvId'sini convByUserAndOther'dan bulalım.

        final myLastMsg = msgByConvId[myConvId];
        // Karşı tarafın conversation_id'si: otherUserId+currentUserId anahtarı
        final otherConvId = convByUserAndOther[otherUserId]?[currentUserId];
        final otherLastMsg = otherConvId != null ? msgByConvId[otherConvId] : null;

        Map<String, dynamic>? newestMsg;
        if (myLastMsg != null && otherLastMsg != null) {
          final myTime = DateTime.parse(myLastMsg['created_at'] as String);
          final otherTime = DateTime.parse(otherLastMsg['created_at'] as String);
          newestMsg = myTime.isAfter(otherTime) ? myLastMsg : otherLastMsg;
        } else if (myLastMsg != null) {
          newestMsg = myLastMsg;
        } else if (otherLastMsg != null) {
          newestMsg = otherLastMsg;
        }

        if (newestMsg != null) {
          lastMessageMap[key] = newestMsg;
        }
      }

      // 10) Conversation listesini oluştur
      final allConversations = <Conversation>[];
      for (var conv in userConvs) {
        final otherUserId = conv['other_user_id'] as String;
        final otherUserProfile = profileMap[otherUserId];
        final convId = conv['id'] as String;
        final key = pairKey(currentUserId, otherUserId);

        Map<String, dynamic> convWithProfile = Map<String, dynamic>.from(conv);
        convWithProfile['other_user'] = otherUserProfile;

        // unread_count: reverse conversation'dan (karşı tarafın bana gönderdiği
        // okunmamış mesaj sayısı) alınmalı, çünkü myConv'daki unread_count benim
        // tarafıma ait olmayabilir.
        final otherConvUnread = convByUserAndOther[otherUserId]?[currentUserId];
        if (otherConvUnread != null) {
          // Reverse conversation'ın unread_count'unu çekmemiz lazım
          // (daha önce çekmediysek, lastMessages içinden türetebiliriz)
          int unread = 0;
          for (var msg in lastMessages) {
            if (msg['conversation_id'] == otherConvUnread &&
                msg['sender_id'] != currentUserId &&
                msg['is_read'] == false) {
              unread++;
            }
          }
          convWithProfile['unread_count'] = unread;
        }

        // Son mesaj bilgisini haritadan al
        final lastMsgData = lastMessageMap[key];
        if (lastMsgData != null) {
          final senderId = lastMsgData['sender_id'] as String?;
          final isMe = senderId == currentUserId;
          final isRead = lastMsgData['is_read'] ?? false;
          final lastMsgConvId = lastMsgData['conversation_id'] as String?;
          convWithProfile['last_message_by_me'] = isMe;
          convWithProfile['last_message_read'] = isMe ? isRead : true;
          convWithProfile['last_message'] = lastMsgData['content'];
          convWithProfile['last_message_time'] = lastMsgData['created_at'];

          AppLogger.debug('  📋 $key: myConv=$convId lastMsg conv=$lastMsgConvId sender=${isMe ? "ME" : "OTHER"} is_read=$isRead');
        } else {
          convWithProfile['last_message_by_me'] = false;
          convWithProfile['last_message_read'] = false;
        }

        allConversations.add(Conversation.fromMap(convWithProfile));
      }

      // updated_at'a göre sırala (en yeni üstte)
      allConversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

      return allConversations;
    } catch (e, stackTrace) {
      AppLogger.error('Error getting conversations: $e', error: e, stackTrace: stackTrace);
      return [];
    }
  }

  // Konuşmadaki mesajları al - her iki tarafın conversation_id'sini de kontrol et
  Future<List<Message>> getMessages(String conversationId) async {
    try {
      AppLogger.debug('📥 getMessages START: conversationId=$conversationId');
      
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
      AppLogger.debug('📥 getMessages: userId=$userId, otherUserId=$otherUserId');
      
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
      
      AppLogger.debug('📥 getMessages: convIds=$convIds (myConv=${convIds[0]}, otherConv=${otherConv?['id'] ?? "null"})');
      
      final response = await _supabase
          .from('messages')
          .select()
          .inFilter('conversation_id', convIds)
          .order('created_at', ascending: true);

      AppLogger.debug('📥 getMessages: Fetched ${response.length} messages');
      
      // DEBUG: Her mesajın is_read ve sender_id durumunu logla
      final currentUserId = _supabase.auth.currentUser?.id;
      for (var msg in response) {
        final isMe = msg['sender_id'] == currentUserId;
        final isRead = msg['is_read'] ?? false;
        final contentStr = (msg['content'] as String?) ?? '';
        final contentPreview = contentStr.length > 30 ? contentStr.substring(0, 30) : contentStr;
        AppLogger.debug('  📨 msg_id=${msg['id']?.toString().substring(0, 8)}... conv=${msg['conversation_id']?.toString().substring(0, 8)}... sender=${isMe ? "ME" : "OTHER"} is_read=$isRead content=$contentPreview');
      }

      return (response as List)
          .map((json) => Message.fromMap(json))
          .toList();
    } catch (e, stackTrace) {
      AppLogger.error('Error getting messages: $e', error: e, stackTrace: stackTrace);
      return [];
    }
  }

  // Mesaj gönder
  Future<Message?> sendMessage({
    required String conversationId,
    required String content,
    String? replyToId,
    String? replyToContent,
    String? replyToSenderName,
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
      
      // Insert verisi hazırla
      final insertData = <String, dynamic>{
        'conversation_id': conversationId,
        'sender_id': currentUserId,
        'content': content,
      };
      
      // Yanıt bilgilerini ekle
      if (replyToId != null) {
        insertData['reply_to_id'] = replyToId;
        insertData['reply_to_content'] = replyToContent;
        insertData['reply_to_sender_name'] = replyToSenderName;
      }
      
      // Doğrudan insert kullan
      final response = await _supabase
          .from('messages')
          .insert(insertData)
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
  // DÜZELTME: Benim mesajlarım her İKİ conversation'da da olabilir (çift yönlü sistem).
  // Bu yüzden her iki conversation'daki sender_id=benim mesajları da okundu yapmalıyız.
  Future<void> markSenderMessagesAsRead(String conversationId) async {
    final currentUserId = _supabase.auth.currentUser?.id;
    if (currentUserId == null) return;

    AppLogger.debug('✅ markSenderMessagesAsRead START: conv=$conversationId reader=$currentUserId');

    try {
      // RPC fonksiyonunu çağır
      await _supabase.rpc(
        'mark_sender_messages_read',
        params: {
          'p_conversation_id': conversationId,
          'p_reader_id': currentUserId,
        },
      );
      AppLogger.debug('✅ markSenderMessagesAsRead: RPC success for $conversationId');
    } catch (e) {
      AppLogger.error('❌ markSenderMessagesAsRead RPC failed, trying direct update: $e');
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
        
        AppLogger.debug('  ↪️ Fallback: convUserId=$userId otherUserId=$otherUserId');
        
        // İki tarafın conversation_id'lerini bul
        final List<String> convIds = [conversationId];
        
        // Eğer conversation user_id=bense, karşı tarafın conv'ını bul
        // Eğer conversation other_user_id=bense, benim conv'ımı zaten biliyoruz
        final otherConv = await _supabase
            .from('conversations')
            .select('id')
            .eq('user_id', otherUserId)
            .eq('other_user_id', userId)
            .maybeSingle();
        
        if (otherConv != null) {
          convIds.add(otherConv['id'] as String);
          AppLogger.debug('  ↪️ Fallback: otherConvId=${otherConv['id']} - her iki conv güncellenecek');
        }
        
        // DÜZELTME: Hem benim hem karşı tarafın conversation'ındaki
        // benim gönderdiğim mesajları okundu yap (sender_id = currentUserId)
        // Ancak RLS politikası sender_id=auth.uid() gerektirdiği için,
        // sadece benim conversation'ımdaki mesajlarımı güncelleyebilirim.
        // Karşı tarafın conv'ındaki mesajlarımı RPC (SECURITY DEFINER) ile güncellemeliyiz.
        // Burada en azından benim conv'ımdaki mesajlarımı güncelleyelim:
        await _supabase
            .from('messages')
            .update({'is_read': true})
            .inFilter('conversation_id', convIds)
            .eq('sender_id', currentUserId)
            .eq('is_read', false);
        
        AppLogger.debug('✅ markSenderMessagesAsRead: Direct update done. convIds=$convIds');
        
        // unread_count'u da güncelle
        await _supabase
            .from('conversations')
            .update({'unread_count': 0})
            .eq('id', conversationId);
      } catch (e2) {
        AppLogger.error('❌ markSenderMessagesAsRead direct update also failed: $e2');
      }
    }
  }

  // Mesajları okundu olarak işaretle
  // DÜZELTME: Hem benim hem karşı tarafın conversation'ındaki bana gelen mesajları
  // okundu yapmalıyız. RLS sadece benim gördüğüm mesajları güncelleyebildiği için
  // önce benim conv'ımdaki mesajları güncelle, sonra RPC ile karşı tarafınkileri.
  Future<void> markMessagesAsRead(String conversationId) async {
    final currentUserId = _supabase.auth.currentUser?.id;
    if (currentUserId == null) return;

    AppLogger.debug('📖 markMessagesAsRead START: conv=$conversationId userId=$currentUserId');

    try {
      // Önce RPC dene (her iki conv'ı güncellemesi gerekir)
      await _supabase.rpc('mark_messages_as_read', params: {
        'p_conversation_id': conversationId,
      });
      AppLogger.debug('📖 markMessagesAsRead: RPC success for $conversationId');
    } catch (e) {
      AppLogger.error('📖 markMessagesAsRead RPC failed, trying direct update: $e');

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
          AppLogger.debug('  ↪️ Fallback: otherConvId=${otherConv['id']} - her iki conv güncellenecek');
        }

        // Karşı tarafın gönderdiği (benim almış olduğum) mesajları okundu yap
        try {
          await _supabase
              .from('messages')
              .update({'is_read': true})
              .inFilter('conversation_id', convIds)
              .neq('sender_id', currentUserId)
              .eq('is_read', false);
          AppLogger.debug('  ↪️ Direct update of receiver messages OK');
        } catch (msgErr) {
          AppLogger.error('  ↪️ Direct update failed: $msgErr');
          // Hata olursa sadece benim conversation_id'mdeki mesajları güncelle
          await _supabase
              .from('messages')
              .update({'is_read': true})
              .eq('conversation_id', conversationId)
              .neq('sender_id', currentUserId)
              .eq('is_read', false);
        }

        // Benim konuşmamın unread_count'unu sıfırla — await ile
        await _supabase
            .from('conversations')
            .update({'unread_count': 0})
            .eq('id', conversationId);

        AppLogger.debug('📖 markMessagesAsRead: Direct update success for $conversationId');
      } catch (e2) {
        AppLogger.error('📖 markMessagesAsRead direct update also failed: $e2');
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
            // PERFORMANCE: Debounce - 500ms gecikme ile güncelleme yap
            // Böylece çok sık güncellemeleri önle
            await Future.delayed(const Duration(milliseconds: 300));
            final conversations = await getConversations();
            onUpdate(conversations);
          },
        )
        .subscribe();
  }

  // Realtime: Mesajlar için subscription
  // PERFORMANCE: Değişiklik olduğunda sadece yeni mesajları ekle
  RealtimeChannel subscribeToMessagesChannel(String conversationId, Function(List<Message>) onUpdate) {
    return _supabase
        .channel('messages_$conversationId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'messages',
          callback: (payload) async {
            AppLogger.debug('📨 Realtime message change: ${payload.eventType}, newRecord: ${payload.newRecord}');
            
            // PERFORMANCE: INSERT ve UPDATE için sadece tüm mesajları çek
            // DELETE için mevcut listeyi filtrele
            if (payload.eventType == PostgresChangeEvent.delete) {
              // Silinen mesajı mevcut listeden çıkar
              // onUpdate çağrısı zaten güncel listeyle yapılacak
              final messages = await getMessages(conversationId);
              onUpdate(messages);
            } else {
              // Yeni veya güncellenmiş mesaj için tüm listeyi çek
              final messages = await getMessages(conversationId);
              onUpdate(messages);
            }
          },
        )
        .subscribe();
  }

  // Toplam okunmamış mesaj sayısı — çift yönlü
  Future<int> getUnreadCount() async {
    final currentUserId = _supabase.auth.currentUser?.id;
    if (currentUserId == null) return 0;

    try {
      // user_id bana ait olan konuşmaların unread sayısı
      final myConvs = await _supabase
          .from('conversations')
          .select('unread_count')
          .eq('user_id', currentUserId);

      // other_user_id bana ait olan konuşmaların unread sayısı
      final reverseConvs = await _supabase
          .from('conversations')
          .select('unread_count')
          .eq('other_user_id', currentUserId);

      int total = 0;
      for (var conv in myConvs) {
        total += (conv['unread_count'] as int? ?? 0);
      }
      for (var conv in reverseConvs) {
        total += (conv['unread_count'] as int? ?? 0);
      }
      return total;
    } catch (e) {
      AppLogger.error('Error getting unread count: $e');
      return 0;
    }
  }
}

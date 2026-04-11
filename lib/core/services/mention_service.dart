import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Yorum ve postlarda @mention (etiketleme) işlemleri için servis
class MentionService {
  final _supabase = Supabase.instance.client;

  /// Metindeki @kullaniciadi mention'larını parse et
  /// Örnek: "Harika @mehmet ve @ayşe!" -> ["mehmet", "ayşe"]
  List<String> parseMentions(String text) {
    final mentionRegex = RegExp(r'@([a-zA-Z0-9_]+)');
    final matches = mentionRegex.allMatches(text);
    
    return matches
        .map((match) => match.group(1)!)
        .toSet() // Duplicate'leri kaldır
        .toList();
  }

  /// Username'lerden user ID'lerini al
  Future<Map<String, String>> getUserIdsByUsernames(List<String> usernames) async {
    if (usernames.isEmpty) return {};

    try {
      final response = await _supabase
          .from('profiles')
          .select('id, username')
          .inFilter('username', usernames);

      final userMap = <String, String>{};
      for (final user in response) {
        userMap[user['username']] = user['id'];
      }

      return userMap;
    } catch (e) {
      debugPrint('❌ Username\'lerden ID alma hatası: $e');
      return {};
    }
  }

  /// Yorum mention'larını kaydet
  Future<void> saveMentionsForComment({
    required String commentId,
    required String commentText,
  }) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) {
        debugPrint('⚠️ Kullanıcı giriş yapmamış');
        return;
      }

      // 1. Metinden mention'ları parse et
      final mentionedUsernames = parseMentions(commentText);
      if (mentionedUsernames.isEmpty) {
        debugPrint('ℹ️ Mention bulunamadı');
        return;
      }

      debugPrint('📝 Mention edilen kullanıcılar: $mentionedUsernames');

      // 2. Username'lerden user ID'lerini al
      final userIdMap = await getUserIdsByUsernames(mentionedUsernames);
      if (userIdMap.isEmpty) {
        debugPrint('⚠️ Geçerli kullanıcı bulunamadı');
        return;
      }

      debugPrint('👥 Bulunan kullanıcılar: ${userIdMap.length}');

      // 3. Kendini mention etme (opsiyonel - izin verebiliriz de)
      final validUserIds = userIdMap.values
          .where((userId) => userId != currentUserId)
          .toList();

      if (validUserIds.isEmpty) {
        debugPrint('ℹ️ Kendinden başka mention yok');
        return;
      }

      // 4. Mention kayıtlarını oluştur
      final mentionsToInsert = validUserIds.map((userId) => {
        'comment_id': commentId,
        'mentioned_user_id': userId,
        'mentioned_by_user_id': currentUserId,
      }).toList();

      await _supabase
          .from('comment_mentions')
          .upsert(mentionsToInsert);

      debugPrint('✅ ${mentionsToInsert.length} mention kaydedildi');
    } catch (e) {
      debugPrint('❌ Mention kaydetme hatası: $e');
    }
  }

  /// Yorumun mention'larını sil (yorum silindiğinde)
  Future<void> deleteMentionsForComment(String commentId) async {
    try {
      await _supabase
          .from('comment_mentions')
          .delete()
          .eq('comment_id', commentId);

      debugPrint('✅ Yorum mention\'ları silindi');
    } catch (e) {
      debugPrint('❌ Mention silme hatası: $e');
    }
  }

  /// Kullanıcının mention edildiği yorumları getir
  Future<List<Map<String, dynamic>>> getUserMentions({
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return [];

      final response = await _supabase
          .from('comment_mentions')
          .select('''
            id,
            created_at,
            comment_id,
            mentioned_by:mentioned_by_user_id (
              id,
              username,
              full_name,
              avatar_url
            ),
            comment:comment_id (
              id,
              content,
              post_id,
              created_at
            )
          ''')
          .eq('mentioned_user_id', currentUserId)
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('❌ Mention\'lar getirme hatası: $e');
      return [];
    }
  }

  /// Mention edilebilir kullanıcıları ara (autocomplete için)
  Future<List<Map<String, dynamic>>> searchMentionableUsers(String query) async {
    if (query.isEmpty) return [];

    try {
      final response = await _supabase
          .from('profiles')
          .select('id, username, full_name, avatar_url')
          .or('username.ilike.%$query%,full_name.ilike.%$query%')
          .limit(10);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('❌ Kullanıcı arama hatası: $e');
      return [];
    }
  }

  /// Metindeki mention'ları highlight için işaretle
  /// UI'da kullanmak üzere mention pozisyonlarını döndürür
  List<MentionSpan> getMentionSpans(String text) {
    final mentionRegex = RegExp(r'@([a-zA-Z0-9_]+)');
    final matches = mentionRegex.allMatches(text);
    
    return matches.map((match) {
      return MentionSpan(
        start: match.start,
        end: match.end,
        username: match.group(1)!,
        fullText: match.group(0)!,
      );
    }).toList();
  }
}

/// Mention span bilgisi - UI'da highlight için
class MentionSpan {
  final int start;
  final int end;
  final String username;
  final String fullText;

  MentionSpan({
    required this.start,
    required this.end,
    required this.username,
    required this.fullText,
  });
}

import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/group_model.dart';
import '../../../core/models/group_message_model.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/utils/app_logger.dart';

class GroupChatService {
  final _supabase = Supabase.instance.client;
  final _notificationService = NotificationService();

  String? get _currentUserId => _supabase.auth.currentUser?.id;

  // ============================================
  // GRUP İŞLEMLERİ
  // ============================================

  /// Yeni grup oluştur
  Future<ChatGroup?> createGroup({
    required String name,
    String? description,
    bool isPrivate = false,
    bool isDiscoverable = true,
    String? avatarUrl,
  }) async {
    if (_currentUserId == null) return null;

    try {
      final response = await _supabase
          .from('groups')
          .insert({
            'name': name,
            'description': description,
            'is_private': isPrivate,
            'is_discoverable': isDiscoverable,
            'avatar_url': avatarUrl,
            'created_by': _currentUserId,
          })
          .select()
          .single();

      AppLogger.debug('createGroup: success, group=${response['id']}');
      
      final group = ChatGroup.fromMap(response);
      return group.copyWith(userRole: 'admin', unreadCount: 0);
    } catch (e, stackTrace) {
      AppLogger.error('Error creating group: $e');
      AppLogger.error('Stack trace: $stackTrace');
      return null;
    }
  }

  /// Kullanıcının gruplarını getir (RPC ile)
  Future<List<ChatGroup>> getUserGroups() async {
    if (_currentUserId == null) return [];

    try {
      final response = await _supabase.rpc('get_user_groups');

      if (response == null) return [];

      return (response as List)
          .map((json) => ChatGroup.fromMap(Map<String, dynamic>.from(json)))
          .toList();
    } catch (e) {
      AppLogger.error('Error getting user groups: $e');
      
      // RPC yoksa fallback: doğrudan sorgu
      try {
        return await _getUserGroupsFallback();
      } catch (e2) {
        AppLogger.error('Error getting user groups fallback: $e2');
        return [];
      }
    }
  }

  /// Tüm grupları getir (üye olup olmama durumunu da belirtir)
  Future<List<ChatGroup>> getAllGroups() async {
    if (_currentUserId == null) return [];

    try {
      // Kullanıcının üyeliklerini al
      final memberships = await _supabase
          .from('group_members')
          .select('group_id, role, unread_count, is_muted')
          .eq('user_id', _currentUserId!);

      final membershipMap = <String, Map<String, dynamic>>{};
      for (final m in (memberships as List)) {
        membershipMap[m['group_id'] as String] = Map<String, dynamic>.from(m);
      }

      // Kullanıcının bekleyen isteklerini al
      final pendingRequests = await _supabase
          .from('group_join_requests')
          .select('group_id')
          .eq('user_id', _currentUserId!)
          .eq('status', 'pending');

      final pendingRequestGroupIds = <String>{};
      for (final r in (pendingRequests as List)) {
        pendingRequestGroupIds.add(r['group_id'] as String);
      }

      // Tüm grupları getir
      final groups = await _supabase
          .from('groups')
          .select()
          .order('updated_at', ascending: false);

      return (groups as List).where((g) {
        // Üye olmayan ve is_discoverable=false olan grupları gizle
        final groupId = g['id'] as String;
        final isMember = membershipMap.containsKey(groupId);
        final isDiscoverable = g['is_discoverable'] as bool? ?? true;
        return isMember || isDiscoverable;
      }).map((g) {
        Map<String, dynamic> groupMap = Map<String, dynamic>.from(g);
        final groupId = g['id'] as String;
        final membership = membershipMap[groupId];
        
        if (membership != null) {
          groupMap['user_role'] = membership['role'];
          groupMap['unread_count'] = membership['unread_count'];
          groupMap['is_muted'] = membership['is_muted'] ?? false;
          groupMap['has_pending_join_request'] = false;
        } else {
          // Üye değil - null olarak işaretle
          groupMap['user_role'] = null;
          groupMap['unread_count'] = 0;
          groupMap['is_muted'] = false;
          groupMap['has_pending_join_request'] = pendingRequestGroupIds.contains(groupId);
        }
        
        return ChatGroup.fromMap(groupMap);
      }).toList();
    } catch (e) {
      AppLogger.error('Error getting all groups: $e');
      return [];
    }
  }

  /// RPC olmadan kullanıcı gruplarını getir (fallback)
  Future<List<ChatGroup>> _getUserGroupsFallback() async {
    if (_currentUserId == null) return [];

    final memberships = await _supabase
        .from('group_members')
        .select('group_id, role, unread_count, is_muted')
        .eq('user_id', _currentUserId!);

    if (memberships.isEmpty) return [];

    final groupIds = (memberships as List)
        .map((m) => m['group_id'] as String)
        .toList();

    final groups = await _supabase
        .from('groups')
        .select()
        .inFilter('id', groupIds)
        .order('updated_at', ascending: false);

    return (groups as List).map((g) {
      final membership = memberships.firstWhere(
        (m) => m['group_id'] == g['id'],
        orElse: () => {'role': 'member', 'unread_count': 0},
      );
      
      Map<String, dynamic> groupMap = Map<String, dynamic>.from(g);
      groupMap['user_role'] = membership['role'];
      groupMap['unread_count'] = membership['unread_count'];
      groupMap['is_muted'] = membership['is_muted'] ?? false;
      
      return ChatGroup.fromMap(groupMap);
    }).toList();
  }

  /// Grup detayını getir
  Future<ChatGroup?> getGroupDetail(String groupId) async {
    if (_currentUserId == null) return null;

    try {
      final group = await _supabase
          .from('groups')
          .select()
          .eq('id', groupId)
          .maybeSingle();

      if (group == null) return null;

      // Kullanıcının rolünü al
      final membership = await _supabase
          .from('group_members')
          .select('role, unread_count, is_muted')
          .eq('group_id', groupId)
          .eq('user_id', _currentUserId!)
          .maybeSingle();

      Map<String, dynamic> groupMap = Map<String, dynamic>.from(group);
      if (membership != null) {
        groupMap['user_role'] = membership['role'];
        groupMap['unread_count'] = membership['unread_count'];
        groupMap['is_muted'] = membership['is_muted'] ?? false;
      }

      return ChatGroup.fromMap(groupMap);
    } catch (e) {
      AppLogger.error('Error getting group detail: $e');
      return null;
    }
  }

  /// Grubu güncelle
  Future<bool> updateGroup({
    required String groupId,
    String? name,
    String? description,
    bool? isPrivate,
    bool? isDiscoverable,
    bool? hideCreator,
    String? avatarUrl,
  }) async {
    try {
      Map<String, dynamic> updates = {'updated_at': DateTime.now().toIso8601String()};
      if (name != null) updates['name'] = name;
      if (description != null) updates['description'] = description;
      if (isPrivate != null) updates['is_private'] = isPrivate;
      if (isDiscoverable != null) updates['is_discoverable'] = isDiscoverable;
      if (hideCreator != null) updates['hide_creator'] = hideCreator;
      if (avatarUrl != null) updates['avatar_url'] = avatarUrl;

      await _supabase
          .from('groups')
          .update(updates)
          .eq('id', groupId);

      return true;
    } catch (e) {
      AppLogger.error('Error updating group: $e');
      return false;
    }
  }

  /// Grubu sil
  Future<bool> deleteGroup(String groupId) async {
    try {
      await _supabase
          .from('groups')
          .delete()
          .eq('id', groupId);
      return true;
    } catch (e) {
      AppLogger.error('Error deleting group: $e');
      return false;
    }
  }

  // ============================================
  // ARAMA
  // ============================================

  /// Grupları ara (RPC ile)
  Future<List<Map<String, dynamic>>> searchGroups(String searchTerm) async {
    if (_currentUserId == null) return [];

    try {
      final response = await _supabase.rpc('search_groups', params: {
        'search_term': searchTerm,
        'include_private': false,
      });

      if (response == null) return [];

      return (response as List)
          .map((json) => Map<String, dynamic>.from(json))
          .toList();
    } catch (e) {
      AppLogger.error('Error searching groups (RPC): $e');
      
      // RPC yoksa fallback
      try {
        return await _searchGroupsFallback(searchTerm);
      } catch (e2) {
        AppLogger.error('Error searching groups fallback: $e2');
        return [];
      }
    }
  }

  /// Arama fallback - RPC olmadan
  Future<List<Map<String, dynamic>>> _searchGroupsFallback(String searchTerm) async {
    if (_currentUserId == null) return [];

    final groups = await _supabase
        .from('groups')
        .select('id, name, description, avatar_url, is_private, member_count, created_at')
        .eq('is_private', false)
        .ilike('name', '%$searchTerm%')
        .order('member_count', ascending: false)
        .limit(50);

    // Kullanıcının üye olduğu grupları kontrol et
    final memberships = await _supabase
        .from('group_members')
        .select('group_id')
        .eq('user_id', _currentUserId!);

    final memberGroupIds = (memberships as List)
        .map((m) => m['group_id'] as String)
        .toSet();

    return (groups as List).map((g) {
      Map<String, dynamic> result = Map<String, dynamic>.from(g);
      result['is_member'] = memberGroupIds.contains(g['id']);
      return result;
    }).toList();
  }

  // ============================================
  // ÜYELİK İŞLEMLERİ
  // ============================================

  /// Açık gruba katıl
  Future<bool> joinGroup(String groupId) async {
    if (_currentUserId == null) return false;

    try {
      // Önce RPC ile dene (SECURITY DEFINER, RLS bypass)
      final result = await _supabase.rpc('join_open_group', params: {
        'p_group_id': groupId,
      });
      
      if (result == true) {
        // Grup kurucusuna bildirim gönder
        await _sendJoinNotificationToOwner(groupId);
        AppLogger.debug('joinGroup via RPC: success');
        return true;
      }
      
      AppLogger.error('joinGroup RPC returned false');
      return false;
    } catch (e) {
      AppLogger.error('Error joining group via RPC: $e');
      
      // Fallback: Doğrudan INSERT dene
      try {
        await _supabase
            .from('group_members')
            .insert({
              'group_id': groupId,
              'user_id': _currentUserId,
              'role': 'member',
            });

        // Üye sayısını güncelle
        try {
          final countResult = await _supabase
              .from('group_members')
              .select()
              .eq('group_id', groupId);
          await _supabase
              .from('groups')
              .update({'member_count': (countResult as List).length})
              .eq('id', groupId);
        } catch (_) {}

        // Grup kurucusuna bildirim gönder
        await _sendJoinNotificationToOwner(groupId);

        AppLogger.debug('joinGroup via fallback INSERT: success');
        return true;
      } catch (e2) {
        AppLogger.error('Error joining group fallback: $e2');
        return false;
      }
    }
  }

  /// Gruptan ayrıl
  Future<bool> leaveGroup(String groupId) async {
    if (_currentUserId == null) return false;

    try {
      await _supabase
          .from('group_members')
          .delete()
          .eq('group_id', groupId)
          .eq('user_id', _currentUserId!);

      AppLogger.debug('leaveGroup: success');
      return true;
    } catch (e) {
      AppLogger.error('Error leaving group: $e');
      return false;
    }
  }

  /// Gruba üye ekle (admin) - RPC ile SECURITY DEFINER kullanarak
  Future<bool> addMember(String groupId, String userId) async {
    try {
      await _supabase.rpc('admin_add_group_member', params: {
        'p_group_id': groupId,
        'p_user_id': userId,
        'p_added_by': _currentUserId,
      });
      return true;
    } catch (e) {
      AppLogger.error('Error adding member: $e');
      return false;
    }
  }

  /// Üyeyi gruptan çıkar (admin)
  Future<bool> removeMember(String groupId, String userId) async {
    try {
      await _supabase
          .from('group_members')
          .delete()
          .eq('group_id', groupId)
          .eq('user_id', userId);
      return true;
    } catch (e) {
      AppLogger.error('Error removing member: $e');
      return false;
    }
  }

  /// Üye rolünü değiştir
  Future<bool> updateMemberRole(String groupId, String userId, String newRole) async {
    try {
      await _supabase
          .from('group_members')
          .update({'role': newRole})
          .eq('group_id', groupId)
          .eq('user_id', userId);
      return true;
    } catch (e) {
      AppLogger.error('Error updating member role: $e');
      return false;
    }
  }

  /// Grup üyelerini getir
  Future<List<GroupMember>> getGroupMembers(String groupId) async {
    try {
      final response = await _supabase
          .from('group_members')
          .select('*')
          .eq('group_id', groupId)
          .order('role', ascending: true);

      final list = List<Map<String, dynamic>>.from(response);

      // Her üye için profil bilgisini ayrı sorgula (FK garantili değil)
      for (var i = 0; i < list.length; i++) {
        try {
          final profile = await _supabase
              .from('profiles')
              .select('full_name, username, avatar_url, is_online, last_seen')
              .eq('id', list[i]['user_id'])
              .maybeSingle();
          if (profile != null) {
            list[i]['profiles'] = profile;
          }
        } catch (_) {
          // Profile bulunamazsa boş bırak
        }
      }

      return list
          .map((json) => GroupMember.fromMap(json))
          .toList();
    } catch (e) {
      AppLogger.error('Error getting group members: $e');
      return [];
    }
  }

  /// Kullanıcı bu grubun üyesi mi?
  Future<bool> isMember(String groupId) async {
    if (_currentUserId == null) return false;

    try {
      final result = await _supabase
          .from('group_members')
          .select('id')
          .eq('group_id', groupId)
          .eq('user_id', _currentUserId!)
          .maybeSingle();
      return result != null;
    } catch (e) {
      return false;
    }
  }

  // ============================================
  // KATILMA İSTEKLERİ (Gizli Gruplar)
  // ============================================

  /// Gizli gruba katılma isteği gönder
  Future<bool> sendJoinRequest(String groupId, {String? message}) async {
    if (_currentUserId == null) return false;

    try {
      await _supabase
          .from('group_join_requests')
          .insert({
            'group_id': groupId,
            'user_id': _currentUserId,
            'message': message,
          });

      // Grup kurucusuna bildirim gönder
      await _sendJoinRequestNotificationToOwner(groupId);

      AppLogger.debug('sendJoinRequest: success');
      return true;
    } catch (e) {
      AppLogger.error('Error sending join request: $e');
      return false;
    }
  }

  /// Katılma isteklerini getir (admin/moderator)
  Future<List<GroupJoinRequest>> getJoinRequests(String groupId) async {
    try {
      final response = await _supabase
          .from('group_join_requests')
          .select('*')
          .eq('group_id', groupId)
          .eq('status', 'pending')
          .order('created_at', ascending: false);

      final list = List<Map<String, dynamic>>.from(response);

      // Her istek için profil bilgisini ayrı sorgula (FK garantili değil)
      for (var i = 0; i < list.length; i++) {
        try {
          final profile = await _supabase
              .from('profiles')
              .select('full_name, avatar_url')
              .eq('id', list[i]['user_id'])
              .maybeSingle();
          if (profile != null) {
            list[i]['profiles'] = profile;
          }
        } catch (_) {
          // Profile bulunamazsa boş bırak
        }
      }

      return list
          .map((json) => GroupJoinRequest.fromMap(json))
          .toList();
    } catch (e) {
      AppLogger.error('Error getting join requests: $e');
      return [];
    }
  }

  /// Katılma isteğini onayla (RPC)
  Future<bool> approveJoinRequest(String requestId) async {
    try {
      // Önce istek bilgilerini alalım (bildirim için)
      final requestInfo = await _supabase
          .from('group_join_requests')
          .select('group_id, user_id')
          .eq('id', requestId)
          .maybeSingle();

      final result = await _supabase.rpc('approve_group_join_request', params: {
        'request_id': requestId,
      });

      // Başarılı ise bildirim gönder
      if (result == true && requestInfo != null) {
        await _sendMemberJoinedNotificationToOwner(
          requestInfo['group_id'] as String,
          requestInfo['user_id'] as String,
        );
      }

      return result == true;
    } catch (e) {
      AppLogger.error('Error approving join request (RPC): $e');
      
      // Fallback: Manuel olarak yap
      try {
        return await _approveJoinRequestFallback(requestId);
      } catch (e2) {
        AppLogger.error('Error approving join request fallback: $e2');
        return false;
      }
    }
  }

  Future<bool> _approveJoinRequestFallback(String requestId) async {
    // İstek bilgilerini al
    final request = await _supabase
        .from('group_join_requests')
        .select()
        .eq('id', requestId)
        .maybeSingle();

    if (request == null || request['status'] != 'pending') return false;

    // Üye ekle
    await _supabase
        .from('group_members')
        .insert({
          'group_id': request['group_id'],
          'user_id': request['user_id'],
          'role': 'member',
        });

    // İstek durumunu güncelle
    await _supabase
        .from('group_join_requests')
        .update({'status': 'approved', 'updated_at': DateTime.now().toIso8601String()})
        .eq('id', requestId);

    // Grup kurucusuna katılım bildirimi gönder
    await _sendMemberJoinedNotificationToOwner(
      request['group_id'],
      request['user_id'],
    );

    return true;
  }

  /// Katılma isteğini reddet (RPC)
  Future<bool> rejectJoinRequest(String requestId) async {
    try {
      final result = await _supabase.rpc('reject_group_join_request', params: {
        'request_id': requestId,
      });
      return result == true;
    } catch (e) {
      AppLogger.error('Error rejecting join request (RPC): $e');
      
      // Fallback
      try {
        await _supabase
            .from('group_join_requests')
            .update({'status': 'rejected', 'updated_at': DateTime.now().toIso8601String()})
            .eq('id', requestId);
        return true;
      } catch (e2) {
        AppLogger.error('Error rejecting join request fallback: $e2');
        return false;
      }
    }
  }

  /// Kullanıcının bekleyen isteği var mı?
  Future<bool> hasPendingRequest(String groupId) async {
    if (_currentUserId == null) return false;

    try {
      final result = await _supabase
          .from('group_join_requests')
          .select('id')
          .eq('group_id', groupId)
          .eq('user_id', _currentUserId!)
          .eq('status', 'pending')
          .maybeSingle();
      return result != null;
    } catch (e) {
      return false;
    }
  }

  // ============================================
  // MESAJ İŞLEMLERİ
  // ============================================

  /// Grup mesajlarını getir (read_by_count ile)
  Future<List<GroupMessage>> getGroupMessages(String groupId, {int limit = 50}) async {
    try {
      // Önce RPC ile dene (read_by_count ile)
      final response = await _supabase.rpc('get_group_messages_with_read_count', params: {
        'p_group_id': groupId,
      });

      if (response != null) {
        final messages = (response as List)
            .map((json) => GroupMessage.fromMap(Map<String, dynamic>.from(json)))
            .toList();

        // Sender bilgilerini çek (RPC'de sender bilgisi yoksa)
        if (messages.isNotEmpty) {
          final senderIds = messages.map((m) => m.senderId).toSet().toList();
          try {
            final profiles = await _supabase
                .from('profiles')
                .select('id, full_name, avatar_url')
                .inFilter('id', senderIds);

            final profileMap = <String, Map<String, dynamic>>{};
            for (final p in (profiles as List)) {
              profileMap[p['id'] as String] = Map<String, dynamic>.from(p);
            }

            for (var i = 0; i < messages.length; i++) {
              final profile = profileMap[messages[i].senderId];
              if (profile != null && messages[i].senderName == null) {
                messages[i] = messages[i].copyWith(
                  senderName: profile['full_name'] as String?,
                  senderAvatarUrl: profile['avatar_url'] as String?,
                );
              }
            }
          } catch (e) {
            AppLogger.error('Error fetching sender profiles: $e');
          }
        }

        return messages;
      }

      // Fallback: doğrudan sorgu
      return await _getGroupMessagesFallback(groupId, limit);
    } catch (e) {
      AppLogger.error('Error getting group messages (RPC): $e');
      return await _getGroupMessagesFallback(groupId, limit);
    }
  }

  /// Fallback: RPC olmadan mesajları çek
  Future<List<GroupMessage>> _getGroupMessagesFallback(String groupId, int limit) async {
    try {
      final response = await _supabase
          .from('group_messages')
          .select()
          .eq('group_id', groupId)
          .order('created_at', ascending: true)
          .limit(limit);

      final messages = (response as List)
          .map((json) => GroupMessage.fromMap(Map<String, dynamic>.from(json)))
          .toList();

      // Sender bilgilerini ayrıca çek
      if (messages.isNotEmpty) {
        final senderIds = messages.map((m) => m.senderId).toSet().toList();
        try {
          final profiles = await _supabase
              .from('profiles')
              .select('id, full_name, avatar_url')
              .inFilter('id', senderIds);

          final profileMap = <String, Map<String, dynamic>>{};
          for (final p in (profiles as List)) {
            profileMap[p['id'] as String] = Map<String, dynamic>.from(p);
          }

          // Mesajlara sender bilgisi ekle
          for (var i = 0; i < messages.length; i++) {
            final profile = profileMap[messages[i].senderId];
            if (profile != null) {
              messages[i] = messages[i].copyWith(
                senderName: profile['full_name'] as String?,
                senderAvatarUrl: profile['avatar_url'] as String?,
              );
            }
          }
        } catch (e) {
          AppLogger.error('Error fetching sender profiles: $e');
        }
      }

      // Reply bilgilerini de çek
      for (var i = 0; i < messages.length; i++) {
        if (messages[i].replyToId != null && messages[i].replyToContent == null) {
          try {
            final replyTo = await _supabase
                .from('group_messages')
                .select('content, sender_id')
                .eq('id', messages[i].replyToId!)
                .maybeSingle();

            if (replyTo != null) {
              // Reply gönderen adını al
              final replySender = await _supabase
                  .from('profiles')
                  .select('full_name')
                  .eq('id', replyTo['sender_id'])
                  .maybeSingle();

              messages[i] = messages[i].copyWith(
                replyToContent: replyTo['content'] as String?,
                replyToSenderName: replySender?['full_name'] as String?,
              );
            }
          } catch (_) {}
        }
      }

      return messages;
    } catch (e) {
      AppLogger.error('Error getting group messages: $e');
      return [];
    }
  }

  /// Grup mesajı gönder (reply desteği ile)
  Future<GroupMessage?> sendGroupMessage({
    required String groupId,
    required String content,
    String? replyToId,
  }) async {
    if (_currentUserId == null) return null;

    try {
      final insertData = {
        'group_id': groupId,
        'sender_id': _currentUserId,
        'content': content,
      };

      if (replyToId != null) {
        insertData['reply_to_id'] = replyToId;
      }

      final response = await _supabase
          .from('group_messages')
          .insert(insertData)
          .select()
          .single();

      AppLogger.debug('sendGroupMessage: success');
      return GroupMessage.fromMap(response);
    } catch (e) {
      AppLogger.error('Error sending group message: $e');
      return null;
    }
  }

  /// Grup mesajlarını okundu olarak işaretle
  Future<void> markGroupMessagesAsRead(String groupId) async {
    if (_currentUserId == null) return;

    try {
      await _supabase.rpc('mark_group_messages_as_read', params: {
        'p_group_id': groupId,
      });
      AppLogger.debug('markGroupMessagesAsRead: RPC success');
    } catch (e) {
      AppLogger.error('markGroupMessagesAsRead RPC failed, trying direct: $e');
      
      // Fallback
      try {
        await _supabase
            .from('group_members')
            .update({'unread_count': 0})
            .eq('group_id', groupId)
            .eq('user_id', _currentUserId!);
      } catch (e2) {
        AppLogger.error('markGroupMessagesAsRead direct also failed: $e2');
      }
    }
  }

  // ============================================
  // REALTIME
  // ============================================

  /// Kullanıcının gruplarındaki değişiklikleri dinle
  RealtimeChannel subscribeToUserGroups(Function(List<ChatGroup>) onUpdate) {
    return _supabase
        .channel('user_groups_channel')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'groups',
          callback: (payload) async {
            final groups = await getAllGroups();
            onUpdate(groups);
          },
        )
        .subscribe();
  }

  /// Belirli bir gruptaki mesaj değişikliklerini dinle
  RealtimeChannel subscribeToGroupMessages(
    String groupId,
    Function(List<GroupMessage>) onUpdate,
  ) {
    return _supabase
        .channel('group_messages_$groupId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'group_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'group_id',
            value: groupId,
          ),
          callback: (payload) async {
            AppLogger.debug('📨 Realtime group message change: ${payload.eventType}');
            final messages = await getGroupMessages(groupId);
            onUpdate(messages);
          },
        )
        .subscribe();
  }

  /// Grup üyelik değişikliklerini dinle
  RealtimeChannel subscribeToGroupMembers(
    String groupId,
    Function(List<GroupMember>) onUpdate,
  ) {
    return _supabase
        .channel('group_members_$groupId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'group_members',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'group_id',
            value: groupId,
          ),
          callback: (payload) async {
            final members = await getGroupMembers(groupId);
            onUpdate(members);
          },
        )
        .subscribe();
  }

  // ============================================
  // SESSİZE ALMA
  // ============================================

  /// Grubu sessize al / sessizden çıkar
  Future<bool> toggleMuteGroup(String groupId, bool mute) async {
    if (_currentUserId == null) return false;

    try {
      await _supabase
          .from('group_members')
          .update({'is_muted': mute})
          .eq('group_id', groupId)
          .eq('user_id', _currentUserId!);

      AppLogger.debug('toggleMuteGroup: $groupId muted=$mute');
      return true;
    } catch (e) {
      AppLogger.error('Error toggling mute: $e');
      return false;
    }
  }

  /// Grubun sessize alınıp alınmadığını kontrol et
  Future<bool> isGroupMuted(String groupId) async {
    if (_currentUserId == null) return false;

    try {
      final result = await _supabase
          .from('group_members')
          .select('is_muted')
          .eq('group_id', groupId)
          .eq('user_id', _currentUserId!)
          .maybeSingle();

      return result?['is_muted'] as bool? ?? false;
    } catch (e) {
      return false;
    }
  }

  // ============================================
  // GRUP PROFİL FOTOĞRAFI
  // ============================================

  /// Grup profil fotoğrafı URL'sini güncelle
  Future<bool> updateGroupAvatar(String groupId, String avatarUrl) async {
    try {
      await _supabase
          .from('groups')
          .update({
            'avatar_url': avatarUrl,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', groupId);

      return true;
    } catch (e) {
      AppLogger.error('Error updating group avatar: $e');
      return false;
    }
  }

  /// Grup kapak fotoğrafı URL'sini güncelle
  Future<bool> updateGroupCover(String groupId, String coverUrl) async {
    try {
      await _supabase
          .from('groups')
          .update({
            'cover_url': coverUrl,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', groupId);

      return true;
    } catch (e) {
      AppLogger.error('Error updating group cover: $e');
      return false;
    }
  }

  /// Grup profil fotoğrafını Supabase Storage'a yükle
  Future<String?> uploadGroupImage(String groupId, Uint8List imageBytes, {bool isCover = false}) async {
    try {
      final fileName = isCover ? 'cover_$groupId.jpg' : 'avatar_$groupId.jpg';
      final storagePath = 'group_images/$fileName';

      // Dosyayı yükle
      await _supabase.storage
          .from('public')
          .uploadBinary(
            storagePath,
            imageBytes,
            fileOptions: const FileOptions(
              upsert: true,
              contentType: 'image/jpeg',
            ),
          );

      // Public URL al
      final publicUrl = _supabase.storage.from('public').getPublicUrl(storagePath);
      
      AppLogger.debug('Group image uploaded: $publicUrl');
      return publicUrl;
    } catch (e) {
      AppLogger.error('Error uploading group image: $e');
      return null;
    }
  }

  // ============================================
  // OKUNDU BİLGİSİ (READ RECEIPTS)
  // ============================================

  /// Gruptaki mesajları okundu olarak işaretle (read receipts tablosuna da yaz)
  Future<void> markGroupMessagesReadReceipts(String groupId) async {
    if (_currentUserId == null) return;

    try {
      await _supabase.rpc('mark_group_messages_read_receipts', params: {
        'p_group_id': groupId,
      });
      AppLogger.debug('markGroupMessagesReadReceipts: RPC success');
    } catch (e) {
      AppLogger.error('markGroupMessagesReadReceipts RPC failed: $e');

      // Fallback: unread_count'u sıfırla
      try {
        await _supabase
            .from('group_members')
            .update({'unread_count': 0})
            .eq('group_id', groupId)
            .eq('user_id', _currentUserId!);
      } catch (e2) {
        AppLogger.error('markGroupMessagesReadReceipts fallback failed: $e2');
      }
    }
  }

  /// Belirli bir mesajı okuyan kişilerin listesini getir
  Future<List<MessageReadReceipt>> getMessageReadReceipts(String messageId) async {
    try {
      final response = await _supabase.rpc('get_message_read_receipts', params: {
        'p_message_id': messageId,
      });

      if (response == null) return [];

      return (response as List)
          .map((json) => MessageReadReceipt.fromMap(Map<String, dynamic>.from(json)))
          .toList();
    } catch (e) {
      AppLogger.error('Error getting message read receipts: $e');

      // Fallback: doğrudan sorgu
      try {
        final receipts = await _supabase
            .from('group_message_read_receipts')
            .select('user_id, read_at')
            .eq('message_id', messageId)
            .order('read_at', ascending: true);

        final list = <MessageReadReceipt>[];
        for (final r in (receipts as List)) {
          // Profil bilgisini ayrı çek
          try {
            final profile = await _supabase
                .from('profiles')
                .select('full_name, username, avatar_url')
                .eq('id', r['user_id'])
                .maybeSingle();

            list.add(MessageReadReceipt(
              userId: r['user_id'] as String,
              fullName: profile?['full_name'] as String?,
              username: profile?['username'] as String?,
              avatarUrl: profile?['avatar_url'] as String?,
              readAt: DateTime.parse(r['read_at'] as String),
            ));
          } catch (_) {
            list.add(MessageReadReceipt(
              userId: r['user_id'] as String,
              readAt: DateTime.parse(r['read_at'] as String),
            ));
          }
        }
        return list;
      } catch (e2) {
        AppLogger.error('Error getting message read receipts fallback: $e2');
        return [];
      }
    }
  }

  /// Belirli bir mesajın okunma sayısını getir
  Future<int> getMessageReadCount(String messageId) async {
    try {
      final response = await _supabase.rpc('get_message_read_count', params: {
        'p_message_id': messageId,
      });
      return (response as int?) ?? 0;
    } catch (e) {
      AppLogger.error('Error getting message read count: $e');
      return 0;
    }
  }

  /// Read receipts değişikliklerini dinle
  RealtimeChannel subscribeToReadReceipts(
    String groupId,
    Function() onUpdate,
  ) {
    return _supabase
        .channel('group_read_receipts_$groupId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'group_message_read_receipts',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'group_id',
            value: groupId,
          ),
          callback: (payload) {
            AppLogger.debug('📖 Realtime read receipt change');
            onUpdate();
          },
        )
        .subscribe();
  }

  // ============================================
  // YARDIMCI METODLAR
  // ============================================

  /// Toplam okunmamış grup mesajı sayısı (sessiz gruplar hariç)
  Future<int> getTotalUnreadCount() async {
    if (_currentUserId == null) return 0;

    try {
      final response = await _supabase
          .from('group_members')
          .select('unread_count, is_muted')
          .eq('user_id', _currentUserId!);

      int total = 0;
      for (var member in response) {
        // Sessize alınmış grupları okunmamış sayısına ekleme
        final isMuted = member['is_muted'] as bool? ?? false;
        if (!isMuted) {
          total += (member['unread_count'] as int? ?? 0);
        }
      }
      return total;
    } catch (e) {
      AppLogger.error('Error getting total unread count: $e');
      return 0;
    }
  }

  // ============================================
  // BİLDİRİM YARDIMCI METODLARI
  // ============================================

  /// Grup admin ve moderatörlerine katılma isteği bildirimi gönder
  Future<void> _sendJoinRequestNotificationToOwner(String groupId) async {
    if (_currentUserId == null) return;

    try {
      // Grup bilgilerini al
      final group = await _supabase
          .from('groups')
          .select('name')
          .eq('id', groupId)
          .maybeSingle();

      if (group == null) return;

      final groupName = group['name'] as String;

      // Grup admin ve moderatörlerini bul
      final admins = await _supabase
          .from('group_members')
          .select('user_id')
          .eq('group_id', groupId)
          .inFilter('role', ['admin', 'moderator']);

      if (admins.isEmpty) {
        AppLogger.debug('Admin/moderator bulunamadı, bildirim gönderilmiyor');
        return;
      }

      // Kullanıcı bilgilerini al
      final profile = await _supabase
          .from('profiles')
          .select('full_name, avatar_url')
          .eq('id', _currentUserId!)
          .maybeSingle();

      if (profile == null) return;

      final actorName = profile['full_name'] as String? ?? 'Bilinmeyen';
      final actorAvatar = profile['avatar_url'] as String?;

      // Her admin/moderator'a bildirim gönder
      for (final admin in admins as List) {
        final adminId = admin['user_id'] as String;
        
        // Kendine bildirim gönderme
        if (adminId == _currentUserId) continue;

        await _notificationService.createGroupJoinRequestNotification(
          groupOwnerId: adminId,
          actorId: _currentUserId!,
          actorName: actorName,
          actorAvatar: actorAvatar ?? '',
          groupId: groupId,
          groupName: groupName,
        );
      }

      AppLogger.debug('Katılma isteği bildirimi ${admins.length} admin/moderator\'e gönderildi');
    } catch (e) {
      AppLogger.error('Katılma isteği bildirimi gönderilemedi: $e');
    }
  }

  /// Grup admin ve moderatörlerine üye katılma bildirimi gönder (açık gruplara direkt katılım)
  Future<void> _sendJoinNotificationToOwner(String groupId) async {
    if (_currentUserId == null) return;

    try {
      // Grup bilgilerini al
      final group = await _supabase
          .from('groups')
          .select('name')
          .eq('id', groupId)
          .maybeSingle();

      if (group == null) return;

      final groupName = group['name'] as String;

      // Grup admin ve moderatörlerini bul
      final admins = await _supabase
          .from('group_members')
          .select('user_id')
          .eq('group_id', groupId)
          .inFilter('role', ['admin', 'moderator']);

      if (admins.isEmpty) {
        AppLogger.debug('Admin/moderator bulunamadı, bildirim gönderilmiyor');
        return;
      }

      // Kullanıcı bilgilerini al
      final profile = await _supabase
          .from('profiles')
          .select('full_name, avatar_url')
          .eq('id', _currentUserId!)
          .maybeSingle();

      if (profile == null) return;

      final actorName = profile['full_name'] as String? ?? 'Bilinmeyen';
      final actorAvatar = profile['avatar_url'] as String?;

      // Her admin/moderator'a bildirim gönder
      for (final admin in admins as List) {
        final adminId = admin['user_id'] as String;
        
        // Kendine bildirim gönderme
        if (adminId == _currentUserId) continue;

        await _notificationService.createGroupMemberJoinedNotification(
          groupOwnerId: adminId,
          actorId: _currentUserId!,
          actorName: actorName,
          actorAvatar: actorAvatar ?? '',
          groupId: groupId,
          groupName: groupName,
        );
      }

      AppLogger.debug('Katılım bildirimi ${admins.length} admin/moderator\'e gönderildi');
    } catch (e) {
      AppLogger.error('Katılım bildirimi gönderilemedi: $e');
    }
  }

  /// Grup admin ve moderatörlerine onaylanan katılma bildirimi gönder
  Future<void> _sendMemberJoinedNotificationToOwner(
    String groupId,
    String joinedUserId,
  ) async {
    try {
      // Grup bilgilerini al
      final group = await _supabase
          .from('groups')
          .select('name')
          .eq('id', groupId)
          .maybeSingle();

      if (group == null) return;

      final groupName = group['name'] as String;

      // Grup admin ve moderatörlerini bul
      final admins = await _supabase
          .from('group_members')
          .select('user_id')
          .eq('group_id', groupId)
          .inFilter('role', ['admin', 'moderator']);

      if (admins.isEmpty) {
        AppLogger.debug('Admin/moderator bulunamadı, bildirim gönderilmiyor');
        return;
      }

      // Katılan kullanıcının bilgilerini al
      final profile = await _supabase
          .from('profiles')
          .select('full_name, avatar_url')
          .eq('id', joinedUserId)
          .maybeSingle();

      if (profile == null) return;

      final actorName = profile['full_name'] as String? ?? 'Bilinmeyen';
      final actorAvatar = profile['avatar_url'] as String?;

      // Her admin/moderator'a bildirim gönder
      for (final admin in admins as List) {
        final adminId = admin['user_id'] as String;
        
        // Kendine bildirim gönderme
        if (adminId == joinedUserId) continue;

        await _notificationService.createGroupMemberJoinedNotification(
          groupOwnerId: adminId,
          actorId: joinedUserId,
          actorName: actorName,
          actorAvatar: actorAvatar ?? '',
          groupId: groupId,
          groupName: groupName,
        );
      }

      AppLogger.debug('Onaylanmış katılım bildirimi ${admins.length} admin/moderator\'e gönderildi');
    } catch (e) {
      AppLogger.error('Onaylanmış katılım bildirimi gönderilemedi: $e');
    }
  }
}

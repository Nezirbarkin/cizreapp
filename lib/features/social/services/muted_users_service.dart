import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Sessize alınan kişiler (20261024000004_mute_hide_search).
///
/// Sessize alınan kişinin gönderileri akışta (sunucu: feed_posts_with_profiles)
/// ve hikâyeleri şeritte (istemci: [filterStories] — bellekteki kümeyle, ek
/// istek yok) görünmez. Profili, mesajları ve bildirimleri etkilenmez; karşı
/// taraf fark etmez.
class MutedUsersService {
  MutedUsersService._();

  static final MutedUsersService instance = MutedUsersService._();

  final Set<String> _ids = <String>{};
  String? _loadedFor;
  Future<void>? _loading;

  static final StreamController<String> _mutedController =
      StreamController<String>.broadcast();

  /// Biri sessize alınınca (akış ekranları o kişinin içeriğini hemen çıkarır).
  static Stream<String> get onUserMuted => _mutedController.stream;

  SupabaseClient get _db => Supabase.instance.client;
  String? get _uid => _db.auth.currentUser?.id;

  bool isMuted(String userId) => _ids.contains(userId);

  Set<String> get mutedIds => Set.unmodifiable(_ids);

  /// Kümeyi oturum başına bir kez yükler (eşzamanlı çağrılar tek istek).
  Future<void> ensureLoaded() {
    final uid = _uid;
    if (uid == null) return Future.value();
    if (_loadedFor == uid) return Future.value();
    return _loading ??= _load(uid).whenComplete(() => _loading = null);
  }

  Future<void> _load(String uid) async {
    try {
      final rows = await _db.from('muted_users').select('muted_id').eq('muter_id', uid);
      _ids
        ..clear()
        ..addAll((rows as List).map((r) => r['muted_id'] as String));
      _loadedFor = uid;
    } catch (e) {
      debugPrint('Sessize alınanlar yüklenemedi: $e');
    }
  }

  Future<void> mute(String userId) async {
    final uid = _uid;
    if (uid == null || userId == uid) return;
    await _db.from('muted_users').upsert(
      {'muter_id': uid, 'muted_id': userId},
      onConflict: 'muter_id,muted_id',
      ignoreDuplicates: true,
    );
    _ids.add(userId);
    _mutedController.add(userId);
  }

  Future<void> unmute(String userId) async {
    final uid = _uid;
    if (uid == null) return;
    await _db.from('muted_users').delete().eq('muter_id', uid).eq('muted_id', userId);
    _ids.remove(userId);
  }

  /// Sessize alınanlar listesi (en yeni önce): profil satırlarıyla.
  Future<List<Map<String, dynamic>>> listMuted() async {
    final uid = _uid;
    if (uid == null) return const [];
    final rows = await _db
        .from('muted_users')
        .select('muted_id, created_at')
        .eq('muter_id', uid)
        .order('created_at', ascending: false);
    final ids = (rows as List).map((r) => r['muted_id'] as String).toList();
    _ids
      ..clear()
      ..addAll(ids);
    _loadedFor = uid;
    if (ids.isEmpty) return const [];
    final profiles = await _db
        .from('profiles')
        .select('id, username, full_name, avatar_url')
        .inFilter('id', ids);
    final byId = {
      for (final p in (profiles as List)) p['id'] as String: Map<String, dynamic>.from(p as Map),
    };
    return [
      for (final id in ids) byId[id] ?? {'id': id, 'username': null, 'full_name': 'Kullanıcı'},
    ];
  }

  /// Hikâye listesinden sessize alınanları çıkarır (bellekteki küme; istek yok).
  List<T> filterStories<T>(List<T> stories, String Function(T) userIdOf) {
    if (_ids.isEmpty) return stories;
    return stories.where((s) => !_ids.contains(userIdOf(s))).toList();
  }

  /// Oturum kapanınca.
  void reset() {
    _ids.clear();
    _loadedFor = null;
    _loading = null;
  }
}

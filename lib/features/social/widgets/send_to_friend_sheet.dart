import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/post_model.dart';

/// "Arkadaşına Gönder" aksiyonu: takip edilen kullanıcılar arasından seçim
/// yaptırır ve `share_post_with_user` RPC'siyle sunucu tarafında doğrulanmış
/// bir bildirim gönderir. Sunucu tarafında gönderen auth.uid() ile belirlenir,
/// alıcı + post doğrulanır, self-share reddedilir, idempotency (60sn)
/// uygulanır (bkz. 2026-08-02 push pipeline refaktörü).
///
/// Gönderi kartlarındaki tüm ekranlarda (favoriler, profil) ortak kullanılır.
Future<void> sendPostToFriend(BuildContext context, Post post) async {
  final currentUserId = Supabase.instance.client.auth.currentUser?.id;
  if (currentUserId == null) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Lütfen giriş yapın')));
    return;
  }

  try {
    final following = await Supabase.instance.client
        .from('follows')
        .select(
          'following_id, profiles!follows_following_id_fkey(full_name, username, avatar_url)',
        )
        .eq('follower_id', currentUserId)
        .order('created_at', ascending: false);

    if (!context.mounted) return;

    if ((following as List).isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Takip ettiğiniz kimse yok')),
      );
      return;
    }

    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'Arkadaşına Gönder',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(sheetContext).size.height * 0.5,
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: following.length,
                itemBuilder: (itemContext, index) {
                  final user = following[index];
                  final profile = user['profiles'] as Map<String, dynamic>?;
                  final name =
                      profile?['full_name'] as String? ??
                      profile?['username'] as String? ??
                      'Kullanıcı';
                  final avatar = profile?['avatar_url'] as String?;
                  final targetUserId = user['following_id'] as String;

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundImage: avatar != null && avatar.isNotEmpty
                          ? NetworkImage(avatar)
                          : null,
                      child: avatar == null || avatar.isEmpty
                          ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?')
                          : null,
                    ),
                    title: Text(name),
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      try {
                        await Supabase.instance.client.rpc(
                          'share_post_with_user',
                          params: {
                            'p_post_id': post.id,
                            'p_recipient_id': targetUserId,
                          },
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('$name adlı kullanıcıya gönderildi'),
                            ),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Gönderilemedi: $e')),
                          );
                        }
                      }
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Hata: $e')));
    }
  }
}

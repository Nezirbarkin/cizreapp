import 'package:flutter/material.dart';

import '../../../core/utils/image_url.dart';
import '../screens/user_profile_screen.dart';
import '../services/profile_service.dart';

/// Başkasının profilinde "ali, veli ve 3 kişi daha takip ediyor" satırı:
/// benim takip ettiklerimden bu kişiyi takip edenler (get_mutual_followers).
/// Ortak kimse yoksa hiç yer kaplamaz. Dokununca tam liste açılır.
class MutualFollowersLine extends StatefulWidget {
  final String userId;

  const MutualFollowersLine({super.key, required this.userId});

  @override
  State<MutualFollowersLine> createState() => _MutualFollowersLineState();
}

class _MutualFollowersLineState extends State<MutualFollowersLine> {
  final _profileService = ProfileService();
  MutualFollowers _mutual = const MutualFollowers();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(MutualFollowersLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) {
      _mutual = const MutualFollowers();
      _load();
    }
  }

  Future<void> _load() async {
    final userId = widget.userId;
    try {
      final mutual = await _profileService.getMutualFollowers(userId);
      // Bu arada başka bir profile geçildiyse eski sonucu yazma.
      if (!mounted || userId != widget.userId) return;
      setState(() => _mutual = mutual);
    } catch (e) {
      // Süs bilgisi: hata olursa satır gösterilmez.
      debugPrint('Ortak takipçiler yüklenemedi: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = _mutual.summary;
    if (summary.isEmpty) return const SizedBox.shrink();

    final avatars = _mutual.users.take(3).toList();
    const size = 22.0;
    const overlap = 14.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => showMutualFollowersSheet(
          context,
          userId: widget.userId,
          total: _mutual.count,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              SizedBox(
                width: size + overlap * (avatars.length - 1),
                height: size,
                child: Stack(
                  children: [
                    for (var i = 0; i < avatars.length; i++)
                      Positioned(
                        left: overlap * i,
                        child: _MiniAvatar(user: avatars[i], size: size),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  summary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFF4B5563),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniAvatar extends StatelessWidget {
  final Map<String, dynamic> user;
  final double size;

  const _MiniAvatar({required this.user, required this.size});

  @override
  Widget build(BuildContext context) {
    final image = avatarImage(user['avatar_url'] as String?, decodeWidth: 96);
    final name = MutualFollowers.nameOf(user);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      child: CircleAvatar(
        backgroundColor: Colors.grey.shade300,
        backgroundImage: image,
        child: image == null
            ? Text(
                name.isNotEmpty ? name.characters.first.toUpperCase() : '?',
                style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700),
              )
            : null,
      ),
    );
  }
}

/// Ortak takipçilerin tam listesi (en fazla 50).
Future<void> showMutualFollowersSheet(
  BuildContext context, {
  required String userId,
  required int total,
}) {
  // Sayfa kapanınca onun context'i ölür; profil, açan ekranın gezgininden açılır.
  final navigator = Navigator.of(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.6,
        ),
        child: FutureBuilder<MutualFollowers>(
          future: ProfileService().getMutualFollowers(userId, limit: 50),
          builder: (context, snapshot) {
            final users = snapshot.data?.users ?? const [];
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    'Ortak takip ($total)',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                ),
                if (snapshot.connectionState != ConnectionState.done)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  )
                else if (users.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Liste yüklenemedi'),
                  )
                else
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: users.length,
                      itemBuilder: (context, index) {
                        final user = users[index];
                        final id = user['id'] as String?;
                        final image = avatarImage(user['avatar_url'] as String?);
                        final fullName = user['full_name']?.toString().trim() ?? '';
                        final username = user['username']?.toString() ?? '';
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.grey.shade200,
                            backgroundImage: image,
                            child: image == null
                                ? Text(
                                    username.isNotEmpty
                                        ? username.characters.first.toUpperCase()
                                        : '?',
                                  )
                                : null,
                          ),
                          title: Text(fullName.isNotEmpty ? fullName : '@$username'),
                          subtitle: fullName.isNotEmpty ? Text('@$username') : null,
                          onTap: id == null
                              ? null
                              : () {
                                  Navigator.pop(sheetContext);
                                  navigator.push(
                                    MaterialPageRoute(
                                      builder: (_) => UserProfileScreen(userId: id),
                                    ),
                                  );
                                },
                        );
                      },
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    ),
  );
}

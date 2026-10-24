import 'package:flutter/material.dart';

import '../../features/profile/screens/edit_profile_screen.dart';
import '../../features/social/screens/create_post_screen.dart';

/// Yeni üye karşılama serisi bildirimlerinin açtığı ekranlar.
///
/// Sunucu `notifications.metadata.route` (push verisinde `meta_route`) olarak
/// [key] değerini yazar (20261024000001_new_member_messages).
enum NewMemberRoute {
  editProfile('edit_profile', 'Profili düzenle', Icons.person_outline_rounded),
  createPost('create_post', 'Gönderi paylaş', Icons.add_photo_alternate_outlined),
  market('market', 'Dükkânları keşfet', Icons.storefront_outlined),
  okey('okey', "101 Okey'e git", Icons.casino_outlined);

  const NewMemberRoute(this.key, this.label, this.icon);

  final String key;
  final String label;
  final IconData icon;

  static NewMemberRoute? tryParse(Object? value) {
    if (value is! String) return null;
    final v = value.trim();
    for (final r in values) {
      if (r.key == v) return r;
    }
    return null;
  }
}

/// Karşılama bildiriminin ekranını açar.
///
/// [resetToMain]: push'tan gelindiğinde önce ana ekran yığının dibine konur
/// (geri tuşu kullanıcıyı boş yığında bırakmasın). Ana ekranın ilk sekmesi
/// dükkânlar olduğu için [NewMemberRoute.market] yalnız ana ekrana döner.
void openNewMemberRoute(
  NavigatorState navigator,
  NewMemberRoute route, {
  bool resetToMain = false,
}) {
  if (resetToMain || route == NewMemberRoute.market) {
    navigator.pushNamedAndRemoveUntil('/main', (_) => false);
  }
  switch (route) {
    case NewMemberRoute.market:
      break;
    case NewMemberRoute.okey:
      navigator.pushNamed('/okey');
      break;
    case NewMemberRoute.editProfile:
      navigator.push(
        MaterialPageRoute(builder: (_) => const EditProfileScreen()),
      );
      break;
    case NewMemberRoute.createPost:
      navigator.push(
        MaterialPageRoute(builder: (_) => const CreatePostScreen()),
      );
      break;
  }
}

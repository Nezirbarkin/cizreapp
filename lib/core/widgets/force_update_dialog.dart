import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:url_launcher/url_launcher.dart';
import '../services/version_check_service.dart';

Future<void> showForceUpdateDialog(BuildContext context, String message) {
  return showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => PopScope(
      canPop: false,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Güncelleme Gerekli'),
        content: Text(message),
        actions: [
          ElevatedButton(
            onPressed: () => _openStore(),
            child: const Text('Şimdi Güncelle'),
          ),
        ],
      ),
    ),
  );
}

Future<void> _openStore() async {
  final Uri uri = defaultTargetPlatform == TargetPlatform.iOS
      ? Uri.parse('https://apps.apple.com/app/id/${VersionCheckService.iosBundleId}')
      : Uri.parse('market://details?id=${VersionCheckService.androidPackageId}');

  if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    final webUri = Uri.parse(
      'https://play.google.com/store/apps/details?id=${VersionCheckService.androidPackageId}',
    );
    await launchUrl(webUri, mode: LaunchMode.externalApplication);
  }
}

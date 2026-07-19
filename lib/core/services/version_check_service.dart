import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class VersionCheckResult {
  final bool needsUpdate;
  final bool isForced;
  final String message;

  VersionCheckResult({
    required this.needsUpdate,
    required this.isForced,
    required this.message,
  });
}

class VersionCheckService {
  static const String androidPackageId = 'com.cizreapp.com';
  static const String iosBundleId = 'com.cizreapp.app';

  static Future<VersionCheckResult?> checkForUpdate() async {
    if (kIsWeb) return null;

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final buildCode = int.tryParse(packageInfo.buildNumber) ?? 0;

      final response = await Supabase.instance.client.rpc(
        'check_app_version',
        params: {
          'p_current_version': packageInfo.version,
          'p_current_build_code': buildCode,
        },
      );

      if (response == null) return null;

      final map = response as Map<String, dynamic>;
      return VersionCheckResult(
        needsUpdate: map['needs_update'] == true,
        isForced: map['is_forced'] == true,
        message: map['message']?.toString() ?? 'Uygulamanızı güncellemeniz gerekiyor.',
      );
    } catch (e) {
      return null;
    }
  }
}

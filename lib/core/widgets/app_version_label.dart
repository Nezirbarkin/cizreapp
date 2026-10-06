import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Ayarlar/çıkış menüsünde "Çıkış Yap" düğmesinin altındaki sürüm satırı:
/// "CizreApp v1.3.2" (Görev 3.8). Sürüm `package_info_plus` ile paketten
/// okunur (pubspec'teki `version`'ın + öncesi); bir kez okunup önbelleğe alınır.
class AppVersionLabel extends StatefulWidget {
  const AppVersionLabel({super.key, this.loader, this.color});

  /// Testler için; varsayılan paket bilgisinden okur.
  final Future<String> Function()? loader;
  final Color? color;

  static Future<String>? _cached;

  static Future<String> _loadFromPackage() =>
      _cached ??= PackageInfo.fromPlatform().then((info) => info.version);

  /// "CizreApp vX.X.X"
  static String format(String version) => 'CizreApp v${version.trim()}';

  @visibleForTesting
  static void resetCache() => _cached = null;

  @override
  State<AppVersionLabel> createState() => _AppVersionLabelState();
}

class _AppVersionLabelState extends State<AppVersionLabel> {
  late final Future<String> _version = (widget.loader ?? AppVersionLabel._loadFromPackage)();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _version,
      builder: (context, snapshot) {
        final version = snapshot.data?.trim() ?? '';
        // Okunana kadar da aynı yeri tutar (menü zıplamasın).
        if (version.isEmpty) return const SizedBox(height: 18);
        return SizedBox(
          height: 18,
          child: Center(
            child: Text(
              AppVersionLabel.format(version),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: widget.color ?? Colors.grey.shade500,
                letterSpacing: 0.2,
              ),
            ),
          ),
        );
      },
    );
  }
}

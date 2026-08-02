// =============================================================================
// 2026-08-02 — Push pipeline kaynak taraması
//
// Bu test istemci kodunun artık send-push veya send-push-notification
// Edge Function'ını çağırmadığını, başka kullanıcı adına FCM token
// SELECT etmediğini doğrular. Statik kaynak taramasıdır; gerçek
// fonksiyon çağrıları mock'lanmaz.
// =============================================================================

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

const _libRoot = 'lib';

const _forbiddenPatterns = <String, String>{
  "functions.invoke('send-push'":
      'send-push Edge Function doğrudan çağrılmamalı',
  "functions.invoke('send-push-notification'":
      'send-push-notification Edge Function doğrudan çağrılmamalı',
  "functions.invoke(\"send-push\"":
      'send-push Edge Function doğrudan çağrılmamalı',
  "functions.invoke(\"send-push-notification\"":
      'send-push-notification Edge Function doğrudan çağrılmamalı',
};

const _fcmTokenReadPatterns = <String, String>{
  "from('profiles').select('fcm_token')":
      'profiles fcm_token istemci tarafından SELECT edilmemeli',
  "from('profiles').select(\"fcm_token\"":
      'profiles fcm_token istemci tarafından SELECT edilmemeli',
  "from('profiles').select('id, fcm_token')":
      'profiles fcm_token istemci tarafından SELECT edilmemeli',
  "from('profiles').select(\"id, fcm_token\"":
      'profiles fcm_token istemci tarafından SELECT edilmemeli',
};

Future<List<File>> _collectDartFiles(Directory dir) async {
  final files = <File>[];
  await for (final entity in dir.list(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) {
      files.add(entity);
    }
  }
  return files;
}

/// Bir dosyanın belirli bir satırında yasaklı pattern geçiyor mu?
/// Yorum (`//` veya `/* */`) içindeki geçişler yoksayılır; refaktör
/// sonrası yorum bırakılan eski davranış açıklamaları için izin
/// verilir. Ama gerçek kod satırlarında (yorum dışı) pattern varsa
/// ihlal sayılır.
bool _hasRealCodeMatch(String content, String pattern) {
  final lines = content.split('\n');
  var inBlockComment = false;
  for (final line in lines) {
    var stripped = line;

    // Çok satırlı yorum takibi (basit)
    if (inBlockComment) {
      final end = stripped.indexOf('*/');
      if (end == -1) continue;
      stripped = stripped.substring(end + 2);
      inBlockComment = false;
    }
    final blockStart = stripped.indexOf('/*');
    if (blockStart != -1) {
      final blockEnd = stripped.indexOf('*/', blockStart + 2);
      if (blockEnd == -1) {
        inBlockComment = true;
        stripped = stripped.substring(0, blockStart);
      } else {
        stripped = stripped.substring(0, blockStart) +
            stripped.substring(blockEnd + 2);
      }
    }

    // Satır yorumunu kaldır
    final lineComment = stripped.indexOf('//');
    if (lineComment != -1) {
      stripped = stripped.substring(0, lineComment);
    }

    if (stripped.contains(pattern)) {
      return true;
    }
  }
  return false;
}

void main() {
  test('lib/ içinde send-push Edge Function doğrudan çağrısı yok', () async {
    final root = Directory(_libRoot);
    if (!root.existsSync()) {
      // test ortamı lib'i görmüyorsa skip
      return;
    }
    final files = await _collectDartFiles(root);
    final violations = <String>[];

    for (final file in files) {
      final content = file.readAsStringSync();
      for (final entry in _forbiddenPatterns.entries) {
        if (_hasRealCodeMatch(content, entry.key)) {
          violations.add('${file.path}: ${entry.value} ("${entry.key}")');
        }
      }
    }

    if (violations.isNotEmpty) {
      fail('Push pipeline ihlalleri:\n${violations.join('\n')}');
    }
  });

  test('lib/ içinde profiles.fcm_token SELECT yok', () async {
    final root = Directory(_libRoot);
    if (!root.existsSync()) {
      return;
    }
    final files = await _collectDartFiles(root);
    final violations = <String>[];

    for (final file in files) {
      final content = file.readAsStringSync();
      for (final entry in _fcmTokenReadPatterns.entries) {
        if (_hasRealCodeMatch(content, entry.key)) {
          violations.add('${file.path}: ${entry.value} ("${entry.key}")');
        }
      }
    }

    if (violations.isNotEmpty) {
      fail('FCM token SELECT ihlalleri:\n${violations.join('\n')}');
    }
  });
}

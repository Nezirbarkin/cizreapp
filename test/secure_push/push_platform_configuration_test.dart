import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android 13 bildirim izni ve FCM service sözleşmesi mevcut', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(manifest, contains('android.permission.POST_NOTIFICATIONS'));
    expect(manifest, contains('com.google.firebase.MESSAGING_EVENT'));
    expect(File('android/app/google-services.json').existsSync(), isTrue);
  });

  test('iOS production APNs ve background remote notification açık', () {
    final entitlements = File(
      'ios/Runner/Runner.entitlements',
    ).readAsStringSync();
    final info = File('ios/Runner/Info.plist').readAsStringSync();

    expect(entitlements, contains('<string>production</string>'));
    expect(info, contains('<string>remote-notification</string>'));
  });

  test('background handler uygulama başlangıcında kaydediliyor', () {
    final mainSource = File('lib/main.dart').readAsStringSync();
    final pushSource = File(
      'lib/core/services/push_notification_service.dart',
    ).readAsStringSync();

    expect(mainSource, contains('FirebaseMessaging.onBackgroundMessage('));
    expect(pushSource, contains("@pragma('vm:entry-point')"));
    expect(pushSource, contains('firebaseMessagingBackgroundHandler'));
  });

  test('FCM token değeri uygulama loglarına yazılmıyor', () {
    final source = File(
      'lib/core/services/push_notification_service.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('token.substring')));
    expect(source, isNot(contains('Token (ilk')));
  });
}

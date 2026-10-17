import 'package:cizreapp/core/services/analytics_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Hata kaydı, kaynak satırını yayınlanan sürümün koduna eşlemek için
/// sürüm ve platform taşır.
void main() {
  test('sürüm biliniyorsa app_version ve platform yazılır', () {
    final m = AnalyticsService.errorMetadataForTest(
      'FlutterError',
      details: 'A RenderFlex overflowed',
      origin: 'features/market/widgets/live_stream_widgets.dart:46',
      appVersion: '1.3.3+43',
    );
    expect(m['type'], 'FlutterError');
    expect(m['details'], 'A RenderFlex overflowed');
    expect(m['origin'], 'features/market/widgets/live_stream_widgets.dart:46');
    expect(m['app_version'], '1.3.3+43');
    expect(m['platform'], isA<String>());
    expect((m['platform'] as String), isNotEmpty);
  });

  test('sürüm okunamadıysa alan hiç eklenmez (null yazılmaz)', () {
    final m = AnalyticsService.errorMetadataForTest('X');
    expect(m.containsKey('app_version'), isFalse);
    expect(m['platform'], isNotNull);
  });
}

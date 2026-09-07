import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Admin > Loglar / Analitik ekranlarinin GERCEK veri okudugunu koruyan
/// sozlesme testleri.
///
/// Bu ekranlar birden fazla kez "gercek veri gosteriyor" gorunumu verirken
/// aslinda adminin kendi cihazindaki yerel Hive kutusunu okudu ya da hicbir
/// zaman yazilmayan bir event tipini sorguladi. Asagidaki beklentiler o
/// gerilemeleri yakalar.
void main() {
  String read(String path) => File(path).readAsStringSync();

  const loaderPath =
      'lib/features/admin/screens/admin_dashboard_parts/_part_data_loaders.dart';
  const analyticsPartPath =
      'lib/features/admin/screens/admin_dashboard_parts/_part_analytics.dart';
  const dashboardPartPath =
      'lib/features/admin/screens/admin_dashboard_parts/_part_dashboard.dart';
  const analyticsServicePath = 'lib/core/services/analytics_service.dart';
  const loggerPath = 'lib/core/utils/app_logger.dart';
  const migrationV2Path =
      'supabase/migrations/20260819000006_admin_logs_real_data_v2.sql';

  test('admin log ekranı merkezi Supabase RPC verisini kullanır', () {
    final loader = read(loaderPath);
    final analytics = read(analyticsServicePath);
    final migration = read(
      'supabase/migrations/20260817000017_admin_logs_real_data.sql',
    );

    expect(loader, contains("'admin_logs_data'"));
    expect(loader, isNot(contains('_analyticsService.getErrors(limit: 20)')));
    expect(analytics, contains("from('app_analytics_events').insert"));
    expect(migration, contains('SECURITY DEFINER'));
    expect(migration, contains('private.current_user_is_admin()'));
    expect(
      migration,
      contains('CREATE POLICY "Users can insert own analytics events"'),
    );
    expect(migration, contains('user_id = (SELECT auth.uid())'));
  });

  test('en çok görüntülenen içerikler gerçek post_views tablosundan gelir', () {
    final migration = read(migrationV2Path);

    // 'post_view' analytics eventi uzun sure hic yazilmadigi icin kart daima
    // bostu; gercek kaynak post_views tablosu.
    expect(migration, contains('FROM public.post_views pv'));
    expect(migration, contains("'mostViewedPosts'"));
    expect(read(loaderPath), contains("data['mostViewedPosts'] as List?"));
  });

  test('gün sınırı ve saatlik dağılım aynı saat dilimini kullanır', () {
    final migration = read(migrationV2Path);

    // DAU / "bugün yeni kayıt" UTC gunune gore hesaplanirsa TR'de her gun
    // 03:00'te sifirlanir; saatlik dagilim zaten Europe/Istanbul kullaniyordu.
    expect(
      migration,
      contains(
        "date_trunc('day', v_now AT TIME ZONE 'Europe/Istanbul') "
        "AT TIME ZONE 'Europe/Istanbul'",
      ),
    );
    expect(migration, isNot(contains("AT TIME ZONE 'UTC'")));
  });

  test('dağılım metrikleri zaman penceresiyle sınırlıdır', () {
    final migration = read(migrationV2Path);
    final loader = read(loaderPath);

    expect(migration, contains('p_window_days integer DEFAULT 30'));
    expect(migration, contains('v_window_start'));
    expect(loader, contains("'p_window_days': _logsWindowDays"));
  });

  test('analitik sekmesi yerel Hive kutusunu değil sunucuyu okur', () {
    final analyticsPart = read(analyticsPartPath);
    final dashboardPart = read(dashboardPartPath);

    // Bu cagrilar yalnizca panele bakan adminin kendi cihazindaki eventleri
    // sayiyordu.
    expect(analyticsPart, isNot(contains('getEngagementMetrics()')));
    expect(analyticsPart, isNot(contains('getMostViewedPosts(')));
    expect(analyticsPart, contains('_loadLogsData()'));
    expect(dashboardPart, isNot(contains('_analyticsService.eventCount')));
  });

  test('merkezi analitik temizleme sunucu tarafında yapılır', () {
    final migration = read(migrationV2Path);
    final analytics = read(analyticsServicePath);
    final analyticsPart = read(analyticsPartPath);

    expect(migration, contains('admin_purge_analytics_events'));
    expect(analytics, contains("'admin_purge_analytics_events'"));
    expect(analyticsPart, contains('purgeRemoteEvents()'));
  });

  test('hata logları merkezi analitiğe akar ve döngüye girmez', () {
    final logger = read(loggerPath);
    final analytics = read(analyticsServicePath);
    final main = read('lib/main.dart');

    expect(logger, contains('String? details,'));
    expect(logger, contains('StackTrace? stackTrace,'));
    expect(logger, contains('String? diagnostics,'));
    expect(logger, contains(')? errorSink;'));
    expect(analytics, contains('static void attachToLogger()'));
    expect(main, contains('AnalyticsService.attachToLogger()'));
    expect(main, contains('PlatformDispatcher.instance.onError'));

    // Merkezi yazimin kendi hatasi tekrar AppLogger.error'a duserse sonsuz
    // dongu olusur; o yol bilerek warning'e cekildi ve re-entrancy kilidi var.
    expect(
      analytics,
      contains("AppLogger.warning('Remote analytics event error:"),
    );
    expect(analytics, contains('_errorSinkBusy'));
    expect(analytics, contains('_maxErrorEventsPerRun'));
  });

  test('hata kaydı kaynağını (dosya:satır) taşır', () {
    final analytics = read(analyticsServicePath);
    final main = read('lib/main.dart');
    final logsPart = read(
      'lib/features/admin/screens/admin_dashboard_parts/_part_logs.dart',
    );

    // "Null check operator used on a null value" gibi mesajlar tek başına
    // hiçbir dosyayı işaret etmiyordu; kaynak artık yığın izinden ya da
    // FlutterErrorDetails metninden çıkarılıp kayda yazılıyor.
    expect(analytics, contains('_extractOrigin('));
    expect(analytics, contains("metadata: {'type': errorType, 'details': details, 'origin': origin}"));

    // Layout hatalarında yığın izi tamamen framework içindedir; hatayı üreten
    // widget'ın konumu yalnızca tanı metninde geçer.
    expect(main, contains('diagnostics: diagnostics'));
    expect(main, contains('details.toString()'));

    // Admin panelinde de görünmeli, yoksa toplamanın anlamı yok.
    expect(logsPart, contains("e.metadata?['origin']"));
  });

  test('görüntüleme süresi gerçekten ölçülür', () {
    final detail = read('lib/features/social/screens/post_detail_screen.dart');

    // "Ort. Görüntüleme (ms)" karti duration_ms hic gonderilmedigi icin
    // kalici olarak 0 gosteriyordu.
    expect(detail, contains('_viewStopwatch'));
    expect(detail, contains('trackPostView(widget.post.id, duration:'));
  });

  test('platform kırılımı (iOS/Android/Web) gerçekten toplanır', () {
    const platformMigrationPath =
        'supabase/migrations/20260821000001_track_user_platform.sql';
    final migration = read(platformMigrationPath);
    final privacyService = read('lib/core/services/privacy_service.dart');
    final logsPart = read(
      'lib/features/admin/screens/admin_dashboard_parts/_part_logs.dart',
    );

    // Sunucu: profiles.platform sütunu ve set_my_presence bunu yazıyor.
    expect(migration, contains("ADD COLUMN IF NOT EXISTS platform text"));
    expect(migration, contains("p_platform text DEFAULT NULL"));
    expect(migration, contains("'platformCounts'"));

    // İstemci: heartbeat/online güncellemesi platformu gerçekten gönderiyor
    // (sabit/varsayılan bir değer değil, kIsWeb/Platform.isIOS/isAndroid'e göre).
    expect(privacyService, contains('_currentPlatform()'));
    expect(privacyService, contains("'p_platform': _currentPlatform()"));

    // Admin ekranı bu veriyi gösteriyor.
    expect(logsPart, contains("data['platformCounts']"));
    expect(logsPart, contains("u['platform']"));
  });
}

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:permission_handler/permission_handler.dart';

/// Agora RTC engine yönetimi - kamera/mikrofon izinleri, kanala katılma,
/// yerel video (host) ve uzak video (viewer) render.
///
/// Agora App ID .env'den okunur: AGORA_APP_ID
/// Token (varsa): AGORA_TOKEN — üretimde Edge Function ile dinamik token önerilir.
///
/// Kullanılan paket: agora_rtc_engine ^6.5.3 (v6 API).
class AgoraService {
  static const _appIdEnv = 'AGORA_APP_ID';
  static const _tokenEnv = 'AGORA_TOKEN';

  RtcEngine? _engine;
  String? _appId;
  String? _token;
  bool _initialized = false;

  String get appId {
    _appId ??= dotenv.maybeGet(_appIdEnv) ?? '';
    return _appId!;
  }

  String get token {
    _token ??= dotenv.maybeGet(_tokenEnv) ?? '';
    return _token!;
  }

  /// Engine'i başlat (bir kez). v6: createAgoraRtcEngine + initialize.
  Future<RtcEngine> getEngine() async {
    if (_engine != null && _initialized) return _engine!;
    if (appId.isEmpty) {
      throw Exception(
        'Agora App ID eksik. .env dosyasına AGORA_APP_ID ekleyin.',
      );
    }
    _engine = createAgoraRtcEngine();
    await _engine!.initialize(RtcEngineContext(
      appId: appId,
      // v6.5.3: areaCode int (AreaCode enum'un value'su).
      areaCode: AreaCode.areaCodeGlob.value(),
    ));
    _initialized = true;
    return _engine!;
  }

  /// Kamera + mikrofon izinleri (mobil). Web'de tarayıcı izinleri otomatik.
  Future<void> requestPermissions() async {
    if (kIsWeb) return;
    await [Permission.camera, Permission.microphone].request();
  }

  /// Host olarak kanala katıl: kamera + mikrofon açılır, yerel video yayınlanır.
  Future<void> joinAsHost({
    required String channelName,
    required int uid,
    void Function(RtcConnection conn, int uid)? onJoinSuccess,
    void Function(ErrorCodeType err, String msg)? onError,
  }) async {
    final engine = await getEngine();
    await requestPermissions();

    await engine.enableVideo();
    await engine.enableAudio();
    await engine.setChannelProfile(
        ChannelProfileType.channelProfileLiveBroadcasting);
    await engine.setClientRole(role: ClientRoleType.clientRoleBroadcaster);

    engine.registerEventHandler(RtcEngineEventHandler(
      onJoinChannelSuccess: (conn, u) {
        debugPrint('Agora host joined: $u');
        onJoinSuccess?.call(conn, u);
      },
      onError: (err, msg) {
        debugPrint('Agora error: $err - $msg');
        onError?.call(err, msg);
      },
    ));

    await engine.joinChannel(
      token: token.isEmpty ? '' : token,
      channelId: channelName,
      uid: uid,
      options: ChannelMediaOptions(
        channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
        clientRoleType: ClientRoleType.clientRoleBroadcaster,
        publishCameraTrack: true,
        publishMicrophoneTrack: true,
      ),
    );
  }

  /// İzleyici olarak katıl: sadece görüntü/ses alır (kamera/mikrofon yayınlamaz).
  Future<void> joinAsViewer({
    required String channelName,
    required int uid,
    void Function(RtcConnection conn, int uid)? onJoinSuccess,
    void Function(ErrorCodeType err, String msg)? onError,
  }) async {
    final engine = await getEngine();

    await engine.enableVideo();
    await engine.enableAudio();
    await engine.setChannelProfile(
        ChannelProfileType.channelProfileLiveBroadcasting);
    await engine.setClientRole(role: ClientRoleType.clientRoleAudience);

    engine.registerEventHandler(RtcEngineEventHandler(
      onJoinChannelSuccess: (conn, u) {
        debugPrint('Agora viewer joined: $u');
        onJoinSuccess?.call(conn, u);
      },
      onError: (err, msg) {
        debugPrint('Agora error: $err - $msg');
        onError?.call(err, msg);
      },
    ));

    await engine.joinChannel(
      token: token.isEmpty ? '' : token,
      channelId: channelName,
      uid: uid,
      options: ChannelMediaOptions(
        channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
        clientRoleType: ClientRoleType.clientRoleAudience,
        autoSubscribeAudio: true,
        autoSubscribeVideo: true,
        publishCameraTrack: false,
        publishMicrophoneTrack: false,
      ),
    );
  }

  /// Yayından ayrıl (host & viewer).
  Future<void> leaveChannel() async {
    await _engine?.leaveChannel();
  }

  /// Host için yerel önizleme.
  Future<void> startPreview() async {
    final engine = await getEngine();
    await engine.startPreview();
  }

  /// Tüm uzak sesi sustur/aç (viewer).
  Future<void> muteAllRemoteAudio(bool muted) async {
    await _engine?.muteAllRemoteAudioStreams(muted);
  }

  /// Kaynakları serbest bırak (uygulama çıkışında).
  Future<void> dispose() async {
    await _engine?.leaveChannel();
    await _engine?.release();
    _engine = null;
    _initialized = false;
  }

  RtcEngine? get engine => _engine;
}
import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/models/live_shopping_model.dart';

/// Agora bağlantı durumu (ekranda "yeniden bağlanıyor" şeridi için).
enum LiveConnectionState { connecting, connected, reconnecting, failed, disconnected }

/// Motor olayları. Ekranlar durumlarını yalnız bu geri çağrılarla günceller.
class LiveEngineEvents {
  const LiveEngineEvents({
    this.onJoined,
    this.onRemoteJoined,
    this.onRemoteLeft,
    this.onRemoteVideo,
    this.onConnection,
    this.onTokenExpiring,
    this.onError,
  });

  final VoidCallback? onJoined;
  final void Function(int uid)? onRemoteJoined;
  final void Function(int uid)? onRemoteLeft;

  /// Uzak görüntü akıyor mu (satıcı kamerayı kapatınca false).
  final void Function(int uid, bool playing)? onRemoteVideo;
  final void Function(LiveConnectionState state)? onConnection;

  /// Anahtarın süresi dolmak üzere ya da doldu → yenisi alınıp verilmeli.
  final VoidCallback? onTokenExpiring;
  final void Function(String code)? onError;
}

/// Canlı video motoru. Uygulama Agora kullanır ([AgoraService]); testler
/// sahte motorla ekranı sürer.
abstract class LiveVideoEngine {
  /// Web'de yok (Agora'nın web betiği uygulamaya eklenmedi).
  bool get isSupported;

  /// Satıcı: kamera/mikrofon izni + yerel önizleme (kanala girmeden).
  Future<void> startPreview(LiveCredentials credentials);

  Future<void> joinAsHost(LiveCredentials credentials, LiveEngineEvents events);

  Future<void> joinAsViewer(LiveCredentials credentials, LiveEngineEvents events);

  Future<void> renewToken(String token);

  Future<void> setMicMuted(bool muted);

  Future<void> setCameraEnabled(bool enabled);

  Future<void> switchCamera();

  Future<void> setRemoteAudioMuted(bool muted);

  Widget buildLocalView();

  Widget buildRemoteView(int uid);

  Future<void> leave();

  Future<void> dispose();
}

typedef LiveVideoEngineFactory = LiveVideoEngine Function();

/// Agora RTC (agora_rtc_engine 6.5) ile [LiveVideoEngine].
///
/// Maliyet/kararlılık ayarları:
///  * satıcı görüntüsü dikey 540×960 @15 fps (mobil yükleme ve Agora "HD"
///    dakika sınıfı için yeterli),
///  * izleyici "düşük gecikme" (Standard) seviyesinde katılır — ultra düşük
///    gecikmeden (Premium) ucuzdur; canlı alışverişte 1–2 sn gecikme sorun değil.
class AgoraService implements LiveVideoEngine {
  RtcEngine? _engine;
  String? _appId;
  String? _channel;
  RtcEngineEventHandler? _handler;
  VideoViewController? _localController;
  final Map<int, VideoViewController> _remoteControllers = {};

  @override
  bool get isSupported => !kIsWeb;

  Future<RtcEngine> _ensureEngine(String appId) async {
    if (!isSupported) throw const LiveException(LiveFailure.unsupported);
    final existing = _engine;
    if (existing != null && _appId == appId) return existing;
    if (existing != null) await dispose();
    final engine = createAgoraRtcEngine();
    await engine.initialize(RtcEngineContext(
      appId: appId,
      channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
    ));
    _engine = engine;
    _appId = appId;
    return engine;
  }

  Future<void> _requestHostPermissions() async {
    final statuses = await [Permission.camera, Permission.microphone].request();
    final granted = statuses.values.every((s) => s.isGranted || s.isLimited);
    if (!granted) throw const LiveException(LiveFailure.permissionDenied);
  }

  @override
  Future<void> startPreview(LiveCredentials credentials) async {
    final engine = await _ensureEngine(credentials.appId);
    await _requestHostPermissions();
    await engine.enableVideo();
    await engine.setVideoEncoderConfiguration(const VideoEncoderConfiguration(
      dimensions: VideoDimensions(width: 540, height: 960),
      frameRate: 15,
      orientationMode: OrientationMode.orientationModeFixedPortrait,
    ));
    await engine.setClientRole(role: ClientRoleType.clientRoleBroadcaster);
    await engine.startPreview();
  }

  void _listen(RtcEngine engine, LiveEngineEvents events) {
    final old = _handler;
    if (old != null) engine.unregisterEventHandler(old);
    final handler = RtcEngineEventHandler(
      onJoinChannelSuccess: (connection, elapsed) => events.onJoined?.call(),
      onRejoinChannelSuccess: (connection, elapsed) => events.onConnection?.call(LiveConnectionState.connected),
      onUserJoined: (connection, remoteUid, elapsed) => events.onRemoteJoined?.call(remoteUid),
      onUserOffline: (connection, remoteUid, reason) => events.onRemoteLeft?.call(remoteUid),
      onRemoteVideoStateChanged: (connection, remoteUid, state, reason, elapsed) {
        if (state == RemoteVideoState.remoteVideoStateDecoding) {
          events.onRemoteVideo?.call(remoteUid, true);
        } else if (state == RemoteVideoState.remoteVideoStateStopped) {
          events.onRemoteVideo?.call(remoteUid, false);
        }
      },
      onConnectionStateChanged: (connection, state, reason) {
        events.onConnection?.call(switch (state) {
          ConnectionStateType.connectionStateConnecting => LiveConnectionState.connecting,
          ConnectionStateType.connectionStateConnected => LiveConnectionState.connected,
          ConnectionStateType.connectionStateReconnecting => LiveConnectionState.reconnecting,
          ConnectionStateType.connectionStateFailed => LiveConnectionState.failed,
          ConnectionStateType.connectionStateDisconnected => LiveConnectionState.disconnected,
        });
      },
      onTokenPrivilegeWillExpire: (connection, token) => events.onTokenExpiring?.call(),
      onRequestToken: (connection) => events.onTokenExpiring?.call(),
      onError: (err, msg) {
        debugPrint('Agora error: $err $msg');
        events.onError?.call(err.name);
      },
    );
    engine.registerEventHandler(handler);
    _handler = handler;
  }

  @override
  Future<void> joinAsHost(LiveCredentials credentials, LiveEngineEvents events) async {
    final engine = await _ensureEngine(credentials.appId);
    _channel = credentials.channel;
    _listen(engine, events);
    await engine.joinChannel(
      token: credentials.token,
      channelId: credentials.channel,
      uid: credentials.uid,
      options: const ChannelMediaOptions(
        channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
        clientRoleType: ClientRoleType.clientRoleBroadcaster,
        publishCameraTrack: true,
        publishMicrophoneTrack: true,
        autoSubscribeAudio: false,
        autoSubscribeVideo: false,
      ),
    );
  }

  @override
  Future<void> joinAsViewer(LiveCredentials credentials, LiveEngineEvents events) async {
    final engine = await _ensureEngine(credentials.appId);
    _channel = credentials.channel;
    _listen(engine, events);
    await engine.enableVideo();
    await engine.setClientRole(
      role: ClientRoleType.clientRoleAudience,
      options: const ClientRoleOptions(
        audienceLatencyLevel: AudienceLatencyLevelType.audienceLatencyLevelLowLatency,
      ),
    );
    await engine.joinChannel(
      token: credentials.token,
      channelId: credentials.channel,
      uid: credentials.uid,
      options: const ChannelMediaOptions(
        channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
        clientRoleType: ClientRoleType.clientRoleAudience,
        audienceLatencyLevel: AudienceLatencyLevelType.audienceLatencyLevelLowLatency,
        autoSubscribeAudio: true,
        autoSubscribeVideo: true,
        publishCameraTrack: false,
        publishMicrophoneTrack: false,
      ),
    );
  }

  @override
  Future<void> renewToken(String token) async => _engine?.renewToken(token);

  @override
  Future<void> setMicMuted(bool muted) async => _engine?.muteLocalAudioStream(muted);

  @override
  Future<void> setCameraEnabled(bool enabled) async {
    final engine = _engine;
    if (engine == null) return;
    await engine.muteLocalVideoStream(!enabled);
    await engine.enableLocalVideo(enabled);
  }

  @override
  Future<void> switchCamera() async => _engine?.switchCamera();

  @override
  Future<void> setRemoteAudioMuted(bool muted) async => _engine?.muteAllRemoteAudioStreams(muted);

  @override
  Widget buildLocalView() {
    final engine = _engine;
    if (engine == null) return const ColoredBox(color: Colors.black);
    final controller = _localController ??= VideoViewController(
      rtcEngine: engine,
      canvas: const VideoCanvas(uid: 0, renderMode: RenderModeType.renderModeHidden),
    );
    return AgoraVideoView(key: const ValueKey('agora-local'), controller: controller);
  }

  @override
  Widget buildRemoteView(int uid) {
    final engine = _engine;
    final channel = _channel;
    if (engine == null || channel == null || uid == 0) return const ColoredBox(color: Colors.black);
    final controller = _remoteControllers[uid] ??= VideoViewController.remote(
      rtcEngine: engine,
      canvas: VideoCanvas(uid: uid, renderMode: RenderModeType.renderModeHidden),
      connection: RtcConnection(channelId: channel),
    );
    return AgoraVideoView(key: ValueKey('agora-remote-$uid'), controller: controller);
  }

  @override
  Future<void> leave() async {
    final engine = _engine;
    if (engine == null) return;
    try {
      await engine.leaveChannel();
      await engine.stopPreview();
    } catch (e) {
      debugPrint('Agora leave: $e');
    }
  }

  @override
  Future<void> dispose() async {
    final engine = _engine;
    _engine = null;
    _appId = null;
    final handler = _handler;
    _handler = null;
    final controllers = [?_localController, ..._remoteControllers.values];
    _localController = null;
    _remoteControllers.clear();
    if (engine == null) return;
    try {
      for (final c in controllers) {
        await c.dispose();
      }
      if (handler != null) engine.unregisterEventHandler(handler);
      await engine.leaveChannel();
      await engine.release();
    } catch (e) {
      debugPrint('Agora dispose: $e');
    }
  }
}

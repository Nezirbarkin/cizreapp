import 'dart:convert';
import 'dart:io';

import 'package:cizreapp/core/models/live_shopping_model.dart';
import 'package:cizreapp/features/market/services/agora_service.dart';
import 'package:cizreapp/features/market/services/live_replay_recorder.dart';
import 'package:cizreapp/features/market/services/live_replay_uploader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show StorageException;

import '../helpers/live_fakes.dart';

/// Canlı yayın tekrar izleme: model, yayıncı telefonundaki kalıcı yükleme
/// kuyruğu ve parça parça kaydedici. Ağ/Agora yok; dosyalar geçici klasörde.
void main() {
  group('model', () {
    test('kayıt özeti ayrıştırılır; izlenebilirlik durum + parçaya bağlı', () {
      final ready = LiveReplay.tryFromJson(replayJson(state: 'ready', parts: 2, durationMs: 240000))!;
      expect(ready.isWatchable, isTrue);
      expect(ready.duration, const Duration(minutes: 4));
      expect(ready.expiresAt, kLiveNow.add(const Duration(days: 30)));
      expect(LiveReplay.tryFromJson(replayJson(state: 'processing', parts: 1))!.isWatchable, isTrue);
      expect(LiveReplay.tryFromJson(replayJson(state: 'processing', parts: 0))!.isWatchable, isFalse);
      for (final state in ['recording', 'failed', 'deleted', 'expired']) {
        expect(LiveReplay.tryFromJson(replayJson(state: state))!.isWatchable, isFalse, reason: state);
      }
      expect(LiveReplay.tryFromJson(replayJson(state: 'expired'))!.isGone, isTrue);
      expect(LiveReplay.tryFromJson(null), isNull);
      expect(LiveReplay.tryFromJson({'parts': 2}), isNull, reason: 'durumsuz kayıt yok sayılır');
      expect(LiveReplay.partPath('abc', 7), 'abc/part-0007.mp4');
    });

    test('yayın JSON\'u kaydı taşır; Realtime satırı sunucu eşlemesiyle uygulanır', () {
      final live = LiveSession.fromJson(
        liveSessionJson(
          status: 'live',
          isLive: true,
          startedAt: kLiveNow,
          replay: replayJson(state: 'recording', parts: 1, durationMs: 180000),
        ),
      );
      expect(live.replay!.state, 'recording');

      final ended = live.applyRow({
        'status': 'ended',
        'replay_state': 'recording',
        'replay_parts': 2,
        'replay_duration_ms': 300000,
        'replay_size_bytes': 9000,
      });
      expect(ended.replay!.state, 'processing', reason: 'biten yayında kayıt "yükleniyor"');
      expect(ended.replay!.parts, 2);
      expect(ended.replay!.isWatchable, isTrue);
      expect(ended.replay!.expiresAt, live.replay!.expiresAt, reason: 'saklama süresi satırda yok, korunur');

      final ready = ended.applyRow({'replay_state': 'ready', 'replay_parts': 2, 'replay_duration_ms': 300000});
      expect(ready.replay!.state, 'ready');
      final deleted = ready.applyRow({'replay_state': 'deleted', 'replay_parts': 0, 'replay_deleted_reason': 'admin'});
      expect(deleted.replay!.isGone, isTrue);
      expect(deleted.replay!.deletedReason, 'admin');
      expect(deleted.applyRow({'viewer_count': 3}).replay!.state, 'deleted', reason: 'kayıt sütunsuz satır korur');
      expect(deleted.withReplay(null).replay, isNull);
      expect(deleted.withReplay(null).title, deleted.title);
    });

    test('parça listesi sıralanır, bozuk parça atlanır; başlatma cevabı sınırlanır', () {
      final manifest = LiveReplayManifest.tryFromJson({
        ...replayJson(state: 'ready', parts: 3),
        'items': [
          {'part_no': 2, 'path': 's/part-0002.mp4', 'duration_ms': 60000},
          {'part_no': 1, 'path': 's/part-0001.mp4', 'duration_ms': 180000},
          {'part_no': 3, 'path': null, 'duration_ms': 1000},
          {'part_no': 4, 'path': 's/part-0004.mp4', 'duration_ms': 0},
        ],
      })!;
      expect(manifest.items.map((i) => i.partNo), [1, 2]);
      expect(manifest.total, const Duration(minutes: 4));
      expect(LiveReplayManifest.tryFromJson(null), isNull);

      final start = LiveReplayStart.fromJson({'enabled': true, 'next_part': 4, 'part_seconds': 120, 'days': 7});
      expect(start.enabled, isTrue);
      expect(start.nextPart, 4);
      expect(start.partLength, const Duration(minutes: 2));
      expect(start.days, 7);
      final off = LiveReplayStart.fromJson({'enabled': false, 'reason': 'disabled'});
      expect(off.enabled, isFalse);
      expect(off.reason, 'disabled');
      expect(off.nextPart, 1);
      expect(off.partLength, const Duration(minutes: 3));
    });

    test('sunucu ipuçları Türkçe hataya çevrilir', () {
      expect(LiveFailure.fromCode('LIVE_REPLAY_CLOSED'), LiveFailure.replayClosed);
      expect(LiveFailure.fromCode('LIVE_REPLAY_PART_MISSING'), LiveFailure.replayPartMissing);
      expect(LiveFailure.fromCode('LIVE_REPLAY_PART_INVALID'), LiveFailure.replayPartInvalid);
      expect(LiveFailure.fromCode('LIVE_REPLAY_NOT_ENDED'), LiveFailure.replayNotEnded);
      expect(LiveFailure.replayNotEnded.message, 'Yayın sürerken kayıt silinemez.');
    });
  });

  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('live_replay_test'));
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  LiveReplayUploader uploader(FakeLiveService s, MemoryReplayQueueStore store) => LiveReplayUploader(
    service: s,
    store: store,
    baseDirectory: () async => tmp,
    retryDelay: const Duration(milliseconds: 20),
  );

  Future<File> partFile(LiveReplayUploader u, String session, int n) async {
    final dir = await u.directoryFor(session);
    return File('${dir.path}${Platform.pathSeparator}part-${n.toString().padLeft(4, '0')}.mp4')
      ..writeAsBytesSync(List.filled(2048, 1));
  }

  LiveReplayPendingPart pending(File f, String session, int n, {int ms = 180000, String user = 'owner-1'}) =>
      LiveReplayPendingPart(sessionId: session, partNo: n, filePath: f.path, durationMs: ms, userId: user);

  group('yükleme kuyruğu', () {
    test('parçalar sırayla yüklenir, kayda işlenir, dosya silinir; bitiş kuyruk boşalınca', () async {
      final s = FakeLiveService();
      final store = MemoryReplayQueueStore();
      final u = uploader(s, store)..markRecording('s1', true);
      final f1 = await partFile(u, 's1', 1);
      final f2 = await partFile(u, 's1', 2);
      await u.enqueue(pending(f1, 's1', 1));
      await u.enqueue(pending(f2, 's1', 2, ms: 61000));
      await u.drainForTest();
      expect(s.uploadedParts, ['s1#1', 's1#2']);
      expect(s.addedParts, ['s1#1:180000', 's1#2:61000']);
      expect(s.finishedReplays, isEmpty, reason: 'kayıt sürerken sonlandırılmaz');
      expect(f1.existsSync() || f2.existsSync(), isFalse, reason: 'yüklenen dosya telefonda kalmaz');
      expect(u.statusFor('s1').value.uploaded, 2);

      u.markRecording('s1', false);
      await u.finish('s1');
      await u.drainForTest();
      expect(s.finishedReplays, ['s1']);
      expect(u.statusFor('s1').value.finished, isTrue);
      expect(u.statusFor('s1').value.replay?.state, 'ready');
      final saved = jsonDecode(store.value!) as Map;
      expect(saved['parts'], isEmpty);
      expect(saved['finishing'], isEmpty);
    });

    test('ağ hatası: parça kuyrukta kalır, beklemeden sonra yeniden denenir', () async {
      // İki deneme: kuyruğa girerken ve testin elle tetiklediği tur.
      final s = FakeLiveService()
        ..uploadErrors.addAll([const SocketException('ağ yok'), const SocketException('ağ yok')]);
      final u = uploader(s, MemoryReplayQueueStore())..markRecording('s1', true);
      final f = await partFile(u, 's1', 1);
      await u.enqueue(pending(f, 's1', 1));
      await u.drainForTest();
      expect(s.uploadedParts, isEmpty);
      expect(u.pendingForTest, hasLength(1));
      expect(u.statusFor('s1').value.waitingNetwork, isTrue);
      expect(f.existsSync(), isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 80));
      await u.drainForTest();
      expect(s.uploadedParts, ['s1#1']);
      expect(u.pendingForTest, isEmpty);
      expect(u.statusFor('s1').value.waitingNetwork, isFalse);
    });

    test('kalıcı hata (depo reddi, kayıt kapandı) parçayı düşürür; sunucu hatası yeniden denenir', () async {
      final s = FakeLiveService()
        ..uploadErrors.addAll([
          const StorageException('new row violates row-level security policy', statusCode: '403'),
          const StorageException('sunucu', statusCode: '503'),
          const StorageException('sunucu', statusCode: '503'),
        ]);
      final u = uploader(s, MemoryReplayQueueStore())..markRecording('s1', true);
      final f1 = await partFile(u, 's1', 1);
      final f2 = await partFile(u, 's1', 2);
      await u.enqueue(pending(f1, 's1', 1));
      await u.drainForTest();
      expect(f1.existsSync(), isFalse, reason: '403 kalıcı: dosya silinir');
      expect(u.statusFor('s1').value.dropped, 1);

      await u.enqueue(pending(f2, 's1', 2));
      await u.drainForTest();
      expect(u.pendingForTest, hasLength(1), reason: '5xx geçici');

      s.addPartError = const LiveException(LiveFailure.replayClosed);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await u.drainForTest();
      expect(u.pendingForTest, isEmpty, reason: 'kayıt kapandıysa parça düşer');
      expect(u.statusFor('s1').value.dropped, 2);
      expect(f2.existsSync(), isFalse);
    });

    test('kuyruk kalıcı: yeni açılışta okunur, numara kaldığı yerden; başka hesabın parçası beklemede', () async {
      final store = MemoryReplayQueueStore();
      final first = uploader(FakeLiveService()..userId = null, store);
      final own = await partFile(first, 's1', 3);
      final other = await partFile(first, 's2', 1);
      await first.enqueue(pending(own, 's1', 3));
      await first.enqueue(pending(other, 's2', 1, user: 'baskasi'));

      final s = FakeLiveService();
      final reopened = uploader(s, store);
      expect(await reopened.nextPartFor('s1'), 4);
      expect(await reopened.nextPartFor('s9'), 1);
      await reopened.resume();
      await reopened.drainForTest();
      expect(s.uploadedParts, ['s1#3']);
      expect(reopened.pendingForTest.map((p) => p.sessionId), ['s2']);
      expect(other.existsSync(), isTrue);
      expect(s.finishedReplays, ['s1'], reason: 'bitiş işareti yoksa (yayında kapandı) sonlandırma denenir');
    });

    test('açılışta kuyrukta olmayan yarım kayıt dosyaları silinir', () async {
      final s = FakeLiveService()..userId = null;
      final u = uploader(s, MemoryReplayQueueStore());
      final queued = await partFile(u, 's1', 1);
      final orphan = await partFile(u, 's9', 1);
      await u.enqueue(pending(queued, 's1', 1));
      await u.resume();
      expect(queued.existsSync(), isTrue);
      expect(orphan.existsSync(), isFalse);
      expect(orphan.parent.existsSync(), isFalse, reason: 'boş klasör de silinir');
    });

    test('dosyası kaybolan parça sessizce düşer', () async {
      final s = FakeLiveService();
      final u = uploader(s, MemoryReplayQueueStore())..markRecording('s1', true);
      final f = await partFile(u, 's1', 1);
      f.deleteSync();
      await u.enqueue(pending(f, 's1', 1));
      await u.drainForTest();
      expect(s.uploadedParts, isEmpty);
      expect(u.pendingForTest, isEmpty);
    });
  });

  group('kaydedici', () {
    (LiveReplayRecorder, FakeLiveEngine, FakeLiveService, LiveReplayUploader) setUpRecorder({
      bool enabled = true,
      int nextPart = 1,
    }) {
      final s = FakeLiveService()
        ..replayStart = LiveReplayStart(enabled: enabled, nextPart: nextPart, partLength: const Duration(minutes: 3));
      final e = FakeLiveEngine();
      final u = uploader(s, MemoryReplayQueueStore());
      final r = LiveReplayRecorder(
        engine: e,
        service: s,
        uploader: u,
        stopTimeout: const Duration(milliseconds: 50),
        retryBase: const Duration(milliseconds: 10),
      );
      return (r, e, s, u);
    }

    String name(String path) => path.split(Platform.pathSeparator).last;

    test('yönetim kaydı kapattıysa kayıt başlamaz', () async {
      final (r, e, _, _) = setUpRecorder(enabled: false);
      await r.start('s1');
      expect(e.recordings, isEmpty);
      expect(r.isActive, isFalse);
      expect(r.sessionId, isNull);
    });

    test('kayıt başlatılamazsa (sunucu hatası) yayın etkilenmez', () async {
      final (r, e, s, _) = setUpRecorder();
      s.beginReplayError = const LiveException(LiveFailure.connection);
      await r.start('s1');
      expect(e.recordings, isEmpty);
      expect(r.isActive, isFalse);
    });

    test('parça uzunluğu dolunca kuyruğa girer ve sıradaki hemen başlar', () async {
      final (r, e, s, u) = setUpRecorder();
      await r.start('s1');
      expect(e.recordings.map(name), ['part-0001.mp4']);
      expect(e.recordingMax, const Duration(minutes: 3));

      e.finishPart(LiveRecordingStop.maxDuration, ms: 180000);
      await pumpEventQueue();
      expect(e.recordings.map(name), ['part-0001.mp4', 'part-0002.mp4']);
      await u.drainForTest();
      expect(s.addedParts, ['s1#1:180000']);
      expect(s.finishedReplays, isEmpty, reason: 'yayın sürüyor');
    });

    test('akış yoksa parça atlanır, kısa beklemeyle aynı numarayla yeniden denenir', () async {
      final (r, e, s, u) = setUpRecorder();
      await r.start('s1');
      e.finishPart(LiveRecordingStop.noStream, bytes: 0, ms: 0);
      await pumpEventQueue();
      expect(e.recordings, hasLength(1), reason: 'hemen yeniden başlamaz');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(e.recordings.map(name), ['part-0001.mp4', 'part-0001.mp4']);
      await u.drainForTest();
      expect(s.addedParts, isEmpty);
    });

    test('dosyaya yazılamazsa kayıt durur, yeniden denenmez', () async {
      final (r, e, _, _) = setUpRecorder();
      await r.start('s1');
      e.finishPart(LiveRecordingStop.writeFailed, bytes: 0, ms: 0);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(e.recordings, hasLength(1));
      expect(r.isActive, isFalse);
    });

    test('bitirince süren parça kapatılır, kuyruğa girer, kayıt sonlandırılır', () async {
      final (r, e, s, u) = setUpRecorder();
      await r.start('s1');
      e.writeCurrentPart(ms: 61000);
      await r.stop(finished: true);
      expect(e.stopRecordingCalls, 1);
      await u.drainForTest();
      expect(s.addedParts, ['s1#1:61000']);
      expect(s.finishedReplays, ['s1']);
      await r.stop(finished: true);
      await u.drainForTest();
      expect(s.finishedReplays, ['s1'], reason: 'ikinci kez sonlandırılmaz');
    });

    test('motor "durdu" demezse zaman aşımıyla parça yine işlenir', () async {
      final (r, e, s, u) = setUpRecorder();
      e.ackStop = false;
      await r.start('s1');
      e.writeCurrentPart(ms: 45000);
      await r.stop(finished: true);
      await u.drainForTest();
      expect(s.addedParts, ['s1#1:45000']);
    });

    test('bağlantı kopunca kayıt sonlandırılmaz; yeniden katılınca numara sürer', () async {
      final (r, e, s, u) = setUpRecorder();
      // Yayın sunucuda sürüyor: sonlandırma denemesi bir şey değiştirmez.
      s.finishResult = const LiveReplay(state: 'recording', parts: 1, durationMs: 30000);
      await r.start('s1');
      e.writeCurrentPart(ms: 30000);
      await r.stop(finished: false);
      await u.drainForTest();
      expect(s.addedParts, ['s1#1:30000']);
      expect(u.statusFor('s1').value.finished, isFalse);

      await r.start('s1');
      expect(name(e.recordings.last), 'part-0002.mp4');

      s.finishResult = const LiveReplay(state: 'ready', parts: 2, durationMs: 60000);
      e.writeCurrentPart(ms: 30000);
      await r.stop(finished: true);
      await u.drainForTest();
      expect(s.addedParts, ['s1#1:30000', 's1#2:30000']);
      expect(u.statusFor('s1').value.finished, isTrue);
    });

    test('sürdürülen yayında numara kuyruktaki ve sunucudaki en büyükten devam eder', () async {
      final (r, e, _, u) = setUpRecorder(nextPart: 2);
      final f = await partFile(u, 's1', 3);
      await u.enqueue(pending(f, 's1', 3, user: 'baskasi'));
      await r.start('s1');
      expect(name(e.recordings.single), 'part-0004.mp4');
    });
  });
}

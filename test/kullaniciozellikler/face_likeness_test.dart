// Selfie → avatar benzerlik motoru: sentetik "selfie"ler çizilip ölçüm
// zinciri (yüz çerçevesi, renk, saç uzunluğu/kâkül, sakal, gözlük,
// başörtüsü, saç stili sıralaması) uçtan uca denenir.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cizreapp/features/profile/models/face_avatar_config.dart';
import 'package:cizreapp/features/profile/services/face_likeness.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Sentetik fotoğraf: 500x700, gözler (200,300) ve (300,300) → birim 100 px.
const _w = 500, _h = 700;
const _origin = Offset(250, 300);
const _unit = 100.0;
const _skin = Color(0xFFE6B48F);
const _hair = Color(0xFF3A2416);
const _bg = Color(0xFFE3E7ED);

Offset _px(double fx, double fy) => _origin + Offset(fx, fy) * _unit;

/// Yüz ovali: merkez (0, 0.225), yarı genişlik 1.0, tepe -1.15, çene 1.6.
List<Offset> _contour() => [
      for (var i = 0; i < 36; i++)
        Offset(math.cos(i / 36 * 2 * math.pi), 0.225 + 1.375 * math.sin(i / 36 * 2 * math.pi)),
    ];

FaceGeometry _geometry() {
  List<Offset> line(double x0, double x1, double y, [int n = 5]) => [for (var i = 0; i < n; i++) Offset(x0 + (x1 - x0) * i / (n - 1), y)];
  List<Offset> eye(double cx) => [
        for (var i = 0; i < 16; i++) Offset(cx + 0.16 * math.cos(i / 16 * 2 * math.pi), 0.065 * math.sin(i / 16 * 2 * math.pi)),
      ];
  return FaceGeometry(
    contour: _contour(),
    browTop: [...line(-0.75, -0.25, -0.40), ...line(0.25, 0.75, -0.40)],
    browBottom: [...line(-0.75, -0.25, -0.29), ...line(0.25, 0.75, -0.29)],
    eyeA: eye(-0.5),
    eyeB: eye(0.5),
    upperLipTop: line(-0.38, 0.38, 1.08),
    lowerLipBottom: line(-0.34, 0.34, 1.26),
    noseBottom: line(-0.30, 0.30, 0.80),
  );
}

typedef _Draw = void Function(Canvas c);

Future<RgbaPixels> _render(List<_Draw> layers) async {
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  c.drawRect(const Rect.fromLTWH(0, 0, 500, 700), Paint()..color = _bg);
  for (final l in layers) {
    l(c);
  }
  final img = await rec.endRecording().toImage(_w, _h);
  final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
  return RgbaPixels(bd!.buffer.asUint8List(), _w, _h);
}

void _face(Canvas c) {
  // Boyun + yüz + gözler + kaşlar + dudak.
  c.drawRect(Rect.fromLTRB(_px(-0.55, 0).dx, _px(0, 1.0).dy, _px(0.55, 0).dx, 700), Paint()..color = _skin);
  final contour = Path()..addPolygon(_contour().map((p) => _px(p.dx, p.dy)).toList(), true);
  c.drawPath(contour, Paint()..color = _skin);
  for (final x in [-0.5, 0.5]) {
    c.drawOval(Rect.fromCenter(center: _px(x, 0), width: 32, height: 13), Paint()..color = Colors.white);
    c.drawCircle(_px(x, 0), 7, Paint()..color = const Color(0xFF4A2E1C));
    c.drawRect(Rect.fromLTRB(_px(x - 0.25, 0).dx, _px(0, -0.40).dy, _px(x + 0.25, 0).dx, _px(0, -0.29).dy), Paint()..color = _hair);
  }
  c.drawOval(Rect.fromLTRB(_px(-0.36, 0).dx, _px(0, 1.08).dy, _px(0.36, 0).dx, _px(0, 1.26).dy), Paint()..color = const Color(0xFFC07068));
}

void _shirt(Canvas c, Color color) => c.drawRect(Rect.fromLTRB(0, _px(0, 3.0).dy, 500, 700), Paint()..color = color);

void _longHair(Canvas c) {
  c.drawRRect(
    RRect.fromRectAndRadius(Rect.fromLTRB(_px(-1.32, 0).dx, _px(0, -1.85).dy, _px(1.32, 0).dx, _px(0, 2.9).dy), const Radius.circular(120)),
    Paint()..color = _hair,
  );
}

void _shortHair(Canvas c) {
  c.drawOval(Rect.fromLTRB(_px(-1.08, 0).dx, _px(0, -1.75).dy, _px(1.08, 0).dx, _px(0, -0.2).dy), Paint()..color = _hair);
}

FaceSampler _sampler(RgbaPixels px) => FaceSampler(px, const FaceFrame(_origin, 0, _unit));

void main() {
  group('Lab renk', () {
    test('sRGB ↔ Lab gidiş-dönüş', () {
      for (final c in [const Color(0xFFE6B48F), const Color(0xFF3A2416), const Color(0xFF3F6E96), Colors.white, Colors.black]) {
        final back = LabColor.fromColor(c).toColor();
        expect((back.r - c.r).abs() * 255, lessThan(1.5));
        expect((back.g - c.g).abs() * 255, lessThan(1.5));
        expect((back.b - c.b).abs() * 255, lessThan(1.5));
      }
    });

    test('en yakın palet rengi algısal olarak seçilir', () {
      final i = nearestIndex(LabColor.fromColor(const Color(0xFF6A4325)), kHairColors);
      expect(kHairColors[i], const Color(0xFF6B4226));
    });

    test('ten rengi stilize edilince makul aralıkta kalır', () {
      for (final c in [const Color(0xFF3B2416), const Color(0xFFFFE7D8), const Color(0xFF9E6238)]) {
        final s = LabColor.fromColor(stylizeSkin(LabColor.fromColor(c)));
        expect(s.l, inInclusiveRange(22, 92));
        expect(s.a, greaterThan(0)); // pembe-turuncu, yeşilimsi değil
      }
    });
  });

  group('yüz çerçevesi', () {
    test('eğik baş düzeltilir: göz hattı yatay, birim göz arası', () {
      final a = const Offset(100, 200), b = const Offset(180, 260);
      final f = FaceFrame.fromEyes(a, b, const Offset(120, 320));
      expect(f.unit, closeTo(100, 0.001));
      final fa = f.toFace(a), fb = f.toFace(b);
      expect(fa.dy, closeTo(0, 1e-9));
      expect(fb.dy, closeTo(0, 1e-9));
      expect((fb.dx - fa.dx).abs(), closeTo(1, 1e-9));
      // Burun aşağıda (pozitif y) kalır.
      expect(f.toFace(const Offset(120, 320)).dy, greaterThan(0));
      // Gidiş-dönüş.
      final p = const Offset(37, 412);
      final back = f.toImage(f.toFace(p));
      expect((back - p).distance, lessThan(1e-6));
    });

    test('ters sırada verilen gözlerde de çene aşağıdadır', () {
      final f = FaceFrame.fromEyes(const Offset(300, 300), const Offset(200, 300), const Offset(250, 380));
      expect(f.toFace(const Offset(250, 380)).dy, greaterThan(0));
    });
  });

  group('sentetik selfie ölçümü', () {
    testWidgets('uzun saçlı, kâkülsüz yüz → uzun saç, sakal yok', (tester) async {
      await tester.runAsync(() async {
        final px = await _render([(c) => _shirt(c, const Color(0xFF3F5E8C)), _longHair, _face]);
        final probe = LikenessProbe(_sampler(px), _geometry());
        expect(probe.skin, isNotNull);
        expect(probe.skin!.dist(LabColor.fromColor(_skin)), lessThan(4));
        expect(probe.hairColor, isNotNull);
        expect(probe.hairColor!.dist(LabColor.fromColor(_hair)), lessThan(6));
        final h = probe.hair;
        expect(h.bald, isFalse);
        expect(h.covered, isFalse);
        expect(h.length, greaterThanOrEqualTo(6), reason: '$h');
        expect(h.fringe, FringeKind.none, reason: '$h');
        expect(pickBeardLabel(probe.beard, strict: true), 'Yok', reason: '${probe.beard}');
        expect(probe.glasses, 'Yok');
        final best = kHairStyles[rankHairStyles(h).first];
        expect(best.length.index, greaterThanOrEqualTo(HairLength.shoulder.index), reason: best.label);
        expect(best.covered, isFalse);
      });
    });

    testWidgets('kısa saç + sakal → kısa stil ve dolgun sakal', (tester) async {
      await tester.runAsync(() async {
        final px = await _render([
          (c) => _shirt(c, const Color(0xFF2E6B5B)),
          _shortHair,
          _face,
          (c) {
            // Çene ve çene hattı: koyu sakal (dudak açıkta).
            final beard = Path()
              ..addPolygon([
                _px(-0.95, 0.75), _px(-0.55, 1.0), _px(-0.4, 1.3), _px(0.4, 1.3), _px(0.55, 1.0), _px(0.95, 0.75),
                _px(0.95, 1.1), _px(0.5, 1.6), _px(0, 1.72), _px(-0.5, 1.6), _px(-0.95, 1.1),
              ], true);
            c.save();
            c.clipPath(Path()..addPolygon(_contour().map((p) => _px(p.dx, p.dy * 1.04 + 0.02)).toList(), true));
            c.drawPath(beard, Paint()..color = const Color(0xFF2A1A10));
            c.restore();
            // Bıyık.
            c.drawRect(Rect.fromLTRB(_px(-0.3, 0).dx, _px(0, 0.86).dy, _px(0.3, 0).dx, _px(0, 1.04).dy), Paint()..color = const Color(0xFF2A1A10));
          },
        ]);
        final probe = LikenessProbe(_sampler(px), _geometry());
        final h = probe.hair;
        expect(h.length, lessThanOrEqualTo(3.5), reason: '$h');
        final label = pickBeardLabel(probe.beard);
        expect(['Kısa Sakal', 'Tam Sakal', 'Uzun Sakal'], contains(label), reason: '${probe.beard}');
        final best = kHairStyles[rankHairStyles(h).first];
        expect(best.length.index, lessThanOrEqualTo(HairLength.short.index), reason: best.label);
      });
    });

    testWidgets('başörtüsü → kapalı stil, örtü rengi ölçülür', (tester) async {
      const fabric = Color(0xFF7A3B52);
      await tester.runAsync(() async {
        final px = await _render([
          (c) {
            c.drawRRect(
              RRect.fromRectAndRadius(Rect.fromLTRB(_px(-1.45, 0).dx, _px(0, -1.9).dy, _px(1.45, 0).dx, 700), const Radius.circular(140)),
              Paint()..color = fabric,
            );
          },
          (c) {
            // Boyun yok: kumaş çenenin altını sarar; yalnız yüz ovali açık.
            final contour = Path()..addPolygon(_contour().map((p) => _px(p.dx, p.dy)).toList(), true);
            c.drawPath(contour, Paint()..color = _skin);
            for (final x in [-0.5, 0.5]) {
              c.drawOval(Rect.fromCenter(center: _px(x, 0), width: 32, height: 13), Paint()..color = Colors.white);
              c.drawCircle(_px(x, 0), 7, Paint()..color = const Color(0xFF4A2E1C));
            }
          },
        ]);
        final probe = LikenessProbe(_sampler(px), _geometry());
        expect(probe.coverColor, isNotNull);
        expect(probe.coverColor!.dist(LabColor.fromColor(fabric)), lessThan(6));
        expect(probe.hair.covered, isTrue);
        expect(kHairStyles[rankHairStyles(probe.hair).first].cover, HairCover.hijab);
      });
    });

    testWidgets('gözlük çerçevesi bulunur', (tester) async {
      await tester.runAsync(() async {
        final px = await _render([
          (c) => _shirt(c, const Color(0xFF2F3A4A)),
          _shortHair,
          _face,
          (c) {
            final frame = Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 4
              ..color = const Color(0xFF1F2227);
            for (final x in [-0.5, 0.5]) {
              c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: _px(x, 0.05), width: 64, height: 46), const Radius.circular(8)), frame);
            }
            c.drawLine(_px(-0.18, -0.02), _px(0.18, -0.02), frame);
            c.drawLine(_px(-0.82, -0.08), _px(-0.99, -0.1), frame);
            c.drawLine(_px(0.82, -0.08), _px(0.99, -0.1), frame);
          },
        ]);
        final probe = LikenessProbe(_sampler(px), _geometry());
        expect(probe.glasses, isNot('Yok'));
      });
    });

    testWidgets('yakın çekim: üst köşeleri saç dolduruyor → yine uzun saç, kel değil', (tester) async {
      await tester.runAsync(() async {
        final px = await _render([
          // Üst köşeler saçla dolu (kameraya çok yakın), omuz hizasında duvar görünür.
          (c) => c.drawRect(Rect.fromLTRB(0, 0, 500, _px(0, 0).dy), Paint()..color = _hair),
          (c) => _shirt(c, const Color(0xFF3F5E8C)),
          _longHair,
          _face,
        ]);
        final probe = LikenessProbe(_sampler(px), _geometry());
        final h = probe.hair;
        expect(h.bald, isFalse, reason: '$h');
        expect(probe.hairColor, isNotNull);
        expect(h.length, greaterThanOrEqualTo(5), reason: '$h');
      });
    });

    testWidgets('beyaz duvar önünde kel kafa → Kel', (tester) async {
      await tester.runAsync(() async {
        final px = await _render([
          (c) => c.drawRect(const Rect.fromLTWH(0, 0, 500, 700), Paint()..color = const Color(0xFFF4F5F7)),
          (c) => _shirt(c, const Color(0xFF2F3A4A)),
          // Kafatası: yüz ovalinin üstünde ten rengi kubbe.
          (c) => c.drawOval(Rect.fromLTRB(_px(-1.02, 0).dx, _px(0, -1.75).dy, _px(1.02, 0).dx, _px(0, 0.6).dy), Paint()..color = _skin),
          _face,
        ]);
        final probe = LikenessProbe(_sampler(px), _geometry());
        expect(probe.hair.bald, isTrue, reason: '${probe.hair} hair=${probe.hairColor}');
        expect(kHairStyles[rankHairStyles(probe.hair).first].label, 'Kel');
      });
    });

    testWidgets('saçla aynı renk koyu arka plan → uzun saç sanılmaz', (tester) async {
      await tester.runAsync(() async {
        final px = await _render([
          (c) => c.drawRect(const Rect.fromLTWH(0, 0, 500, 700), Paint()..color = _hair),
          (c) => _shirt(c, const Color(0xFF2E6B5B)),
          _face,
        ]);
        final probe = LikenessProbe(_sampler(px), _geometry());
        expect(probe.hair.length, lessThanOrEqualTo(4), reason: '${probe.hair}');
      });
    });

    testWidgets('gözlüksüz yüzde gözlük bulunmaz', (tester) async {
      await tester.runAsync(() async {
        final px = await _render([(c) => _shirt(c, const Color(0xFF2F3A4A)), _shortHair, _face]);
        expect(LikenessProbe(_sampler(px), _geometry()).glasses, 'Yok');
      });
    });
  });

  group('saç stili sıralaması', () {
    String best(HairObservation o) => kHairStyles[rankHairStyles(o).first].label;

    test('kel → Kel', () {
      expect(best(const HairObservation(bald: true, length: 0)), 'Kel');
    });

    test('başörtüsü → Başörtüsü', () {
      expect(best(const HairObservation(covered: true)), 'Başörtüsü');
    });

    test('uzun + yan kâkül → yan ayrımlı uzun stil', () {
      final s = kHairStyles[rankHairStyles(const HairObservation(length: 7, volume: 0.6, width: 0.4, fringe: FringeKind.side, fringeSide: -1)).first];
      expect(s.length.index, greaterThanOrEqualTo(HairLength.shoulder.index));
      expect([HairFringe.sweep, HairFringe.sweepLong, HairFringe.wave], contains(s.fringe));
    });

    test('düz kâküllü bob', () {
      final s = kHairStyles[rankHairStyles(const HairObservation(length: 5, volume: 0.45, width: 0.4, fringe: FringeKind.blunt)).first];
      expect(s.length, HairLength.jaw);
      expect(s.fringe, HairFringe.blunt);
    });

    test('kıvırcık hacimli → kıvırcık/afro', () {
      final s = kHairStyles[rankHairStyles(const HairObservation(length: 3, volume: 1.3, width: 1.3, curl: 1)).first];
      expect(s.group, HairGroup.curly);
    });

    test('özel biçimler (mohawk, örgü) kendiliğinden seçilmez', () {
      for (final o in const [
        HairObservation(length: 2, volume: 1.0, width: 0.05),
        HairObservation(length: 7, volume: 0.6, width: 0.4),
        HairObservation(length: 3, volume: 0.4, width: 0.2),
      ]) {
        final s = kHairStyles[rankHairStyles(o).first];
        expect(s.tie, anyOf(HairTie.none, HairTie.bunHigh, HairTie.bunTop, HairTie.bunMessy, HairTie.bunBallet, HairTie.ponyHigh), reason: s.label);
      }
    });

    test('her stil sıralamada bir kez yer alır', () {
      final r = rankHairStyles(const HairObservation());
      expect(r.toSet().length, kHairStyles.length);
    });
  });

  group('sakal etiketi', () {
    test('eşikler', () {
      expect(pickBeardLabel(const BeardObservation()), 'Yok');
      expect(pickBeardLabel(const BeardObservation(mustache: 16)), 'Bıyık');
      expect(pickBeardLabel(const BeardObservation(chin: 16, jaw: 14, mustache: 14)), 'Kısa Sakal');
      expect(pickBeardLabel(const BeardObservation(chin: 24, jaw: 20, mustache: 18, belowChin: 18)), 'Tam Sakal');
      expect(pickBeardLabel(const BeardObservation(chin: 9, jaw: 8, mustache: 8)), 'Üç Günlük');
      // Uzun saçlı yüzde çene altı gölgesi sakal sayılmaz.
      expect(pickBeardLabel(const BeardObservation(chin: 9, jaw: 7, mustache: 6), strict: true), 'Yok');
    });

    test('etiketler katalogda var', () {
      final labels = kBeardStyles.map((e) => e.label).toSet();
      for (final l in ['Yok', 'Hafif', 'Üç Günlük', 'Yoğun Üç Günlük', 'Bıyık', 'Keçi', 'Çene Ucu', 'Kısa Sakal', 'Tam Sakal', 'Uzun Sakal']) {
        expect(labels, contains(l));
      }
      final g = kGlassesStyles.map((e) => e.label).toSet();
      for (final l in ['Yok', 'İnce Çerçeve', 'Kalın Çerçeve', 'Güneş']) {
        expect(g, contains(l));
      }
    });
  });
}

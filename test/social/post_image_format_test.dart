import 'dart:typed_data';

import 'package:cizreapp/core/models/post_model.dart';
import 'package:cizreapp/features/social/models/post_image_format.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

/// Görev 2.8 — gönderi fotoğraf çerçevesi: öneri, kayıtlı orandan çerçeve,
/// akışta çizilen oran ve taslak fotoğrafın kırpma durumu.
void main() {
  group('PostImageFormat', () {
    test('çerçeveler: Dikey 4:5, Kare 1:1, Yatay 4:3', () {
      expect(PostImageFormat.values.map((f) => '${f.label} ${f.ratioLabel}'), [
        'Dikey 4:5',
        'Kare 1:1',
        'Yatay 4:3',
      ]);
      expect(PostImageFormat.portrait.aspectRatio, 0.8);
      expect(PostImageFormat.square.aspectRatio, 1);
      expect(PostImageFormat.landscape.aspectRatio, closeTo(1.3333, 0.0001));
    });

    test('ilk fotoğrafın oranına göre öneri — en az kırpan çerçeve', () {
      expect(PostImageFormat.suggestFor(3000, 4000), PostImageFormat.portrait); // telefon dikey 3:4
      expect(PostImageFormat.suggestFor(1080, 1920), PostImageFormat.portrait); // ekran görüntüsü
      expect(PostImageFormat.suggestFor(1000, 1000), PostImageFormat.square);
      expect(PostImageFormat.suggestFor(1080, 1000), PostImageFormat.square); // kareye yakın
      expect(PostImageFormat.suggestFor(4000, 3000), PostImageFormat.landscape); // telefon yatay 4:3
      expect(PostImageFormat.suggestFor(1920, 1080), PostImageFormat.landscape);
      // Bozuk ölçü → güvenli varsayılan.
      expect(PostImageFormat.suggestFor(0, 0), PostImageFormat.square);
      expect(PostImageFormat.suggestForAspect(double.nan), PostImageFormat.square);
    });

    test('kayıtlı orandan çerçeve (DB real yuvarlaması tolere edilir)', () {
      expect(PostImageFormat.fromAspectRatio(0.8), PostImageFormat.portrait);
      expect(PostImageFormat.fromAspectRatio(1), PostImageFormat.square);
      // float4: 4/3 → 1.3333334
      expect(PostImageFormat.fromAspectRatio(1.3333334), PostImageFormat.landscape);
      expect(PostImageFormat.fromAspectRatio(1.5), isNull);
      expect(PostImageFormat.fromAspectRatio(null), isNull);
    });
  });

  group('feedImageAspect', () {
    test('bilinmeyen oran kare çizilir', () {
      expect(feedImageAspect(null), 1);
      expect(feedImageAspect(double.nan), 1);
      expect(feedImageAspect(0), 1);
      expect(feedImageAspect(-2), 1);
    });

    test('oran 4:5 ile 1.91:1 arasına sıkıştırılır', () {
      expect(feedImageAspect(0.5625), kFeedImageMinAspect); // 9:16 ekran görüntüsü
      expect(feedImageAspect(3.2), kFeedImageMaxAspect); // panorama
      expect(feedImageAspect(0.8), 0.8);
      expect(feedImageAspect(4 / 3), closeTo(1.3333, 0.0001));
      expect(feedImageAspect(1.7), 1.7);
    });
  });

  group('PostDraftImage', () {
    final original = Uint8List.fromList([1, 2, 3]);
    final cropped = Uint8List.fromList([9, 9]);

    test('kırpılmamış fotoğraf orijinal baytlarla gösterilir', () {
      final draft = PostDraftImage(file: XFile.fromData(original, name: 'a.jpg'), bytes: original);
      expect(draft.isCroppedFor(0.8), isFalse);
      expect(draft.displayBytesFor(0.8), same(original));
    });

    test('kırpma yalnızca kırpıldığı çerçevede geçerli; eski çerçeveye dönünce geri gelir', () {
      final draft = PostDraftImage(file: XFile.fromData(original, name: 'a.jpg'), bytes: original)
        ..setCrop(cropped, 0.8);

      expect(draft.isCroppedFor(0.8), isTrue);
      expect(draft.displayBytesFor(0.8), same(cropped));

      // Çerçeve Kare'ye geçti: kırpma geçersiz, orijinal ortadan oturtulur.
      expect(draft.isCroppedFor(1), isFalse);
      expect(draft.displayBytesFor(1), same(original));

      // Orijinal hiç değişmez (yeniden kırpma her zaman ondan yapılır).
      expect(draft.bytes, same(original));
      expect(draft.displayBytesFor(0.8), same(cropped));
    });
  });

  group('Post.image_aspect_ratio', () {
    Map<String, dynamic> row([Object? aspect]) => {
      'id': 'p1',
      'user_id': 'u1',
      'content': 'merhaba',
      'images': ['https://x/1.jpg'],
      'image_aspect_ratio': aspect,
      'created_at': '2026-09-28T10:00:00Z',
      'updated_at': '2026-09-28T10:00:00Z',
    };

    test('satırdan okunur (num → double); yoksa null', () {
      expect(Post.fromJson(row(0.8)).imageAspectRatio, 0.8);
      expect(Post.fromJson(row(1)).imageAspectRatio, 1.0);
      expect(Post.fromJson(row()).imageAspectRatio, isNull);
      final withoutKey = row()..remove('image_aspect_ratio');
      expect(Post.fromJson(withoutKey).imageAspectRatio, isNull);
    });

    test('önbellek için serileşir ve copyWith korur', () {
      final post = Post.fromJson(row(0.8));
      expect(post.toJson()['image_aspect_ratio'], 0.8);
      expect(Post.fromJson(post.toJson()).imageAspectRatio, 0.8);
      expect(post.copyWith(content: 'x').imageAspectRatio, 0.8);
      expect(Post.fromJson(row()).toJson().containsKey('image_aspect_ratio'), isFalse);
    });
  });
}

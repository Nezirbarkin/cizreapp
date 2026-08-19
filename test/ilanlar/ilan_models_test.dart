import 'package:cizreapp/ilanlar/models/ilan_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('IlanCategory', () {
    test('kayıp kategorisinde fiyatı yasaklar', () {
      final category = IlanCategory.fromJson({
        'id': 'category-id',
        'name': 'Kayıp İlanları',
        'slug': 'kayip-ilanlari',
        'category_type': 'lost',
        'pricing_mode': 'forbidden',
        'is_active': true,
      });

      expect(category.type, IlanCategoryType.lost);
      expect(category.allowsPrice, isFalse);
      expect(category.requiresPrice, isFalse);
    });

    test('satılık kategorisinde fiyatı zorunlu yapar', () {
      final category = IlanCategory.fromJson({
        'id': 'category-id',
        'name': 'Satılık',
        'slug': 'satilik',
        'category_type': 'sale',
        'pricing_mode': 'required',
        'allowed_conditions': ['Sıfır', 'İyi'],
      });

      expect(category.allowsPrice, isTrue);
      expect(category.requiresPrice, isTrue);
      expect(category.allowedConditions, ['Sıfır', 'İyi']);
    });
  });

  test('Ilan ilişkili Supabase verisini güvenli ayrıştırır', () {
    final ilan = Ilan.fromJson({
      'id': 'ilan-id',
      'owner_id': 'owner-id',
      'category_id': 'category-id',
      'title': 'Temiz durumda bisiklet',
      'description': 'Açıklama yeterince uzun bir ilan metnidir.',
      'status': 'published',
      'price': 12500,
      'currency': 'TRY',
      'city': 'Şırnak',
      'district': 'Cizre',
      'created_at': '2026-08-14T12:00:00Z',
      'view_count': 4,
      'favorite_count': 2,
      'attributes': {'brand': 'Test'},
      'ilan_categories': {
        'id': 'category-id',
        'name': 'Satılık İlanlar',
        'slug': 'satilik-ilanlar',
        'category_type': 'sale',
        'pricing_mode': 'required',
      },
      'ilan_images': [
        {
          'id': 'image-id',
          'image_url': 'https://example.test/image.jpg',
          'sort_order': 0,
        },
      ],
      'profiles': {'full_name': 'Test Kullanıcı', 'avatar_url': null},
    });

    expect(ilan.status, IlanStatus.published);
    expect(ilan.hasPrice, isTrue);
    expect(ilan.price, 12500);
    expect(ilan.category?.type, IlanCategoryType.sale);
    expect(ilan.images.single.url, contains('image.jpg'));
    expect(ilan.ownerName, 'Test Kullanıcı');
    expect(ilan.locationText, 'Cizre, Şırnak');
  });
}

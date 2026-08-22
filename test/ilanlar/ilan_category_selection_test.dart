import 'package:flutter_test/flutter_test.dart';

import 'package:cizreapp/ilanlar/models/ilan_models.dart';
import 'package:cizreapp/ilanlar/utils/ilan_category_selection.dart';

void main() {
  IlanCategory category(String id, String name) => IlanCategory(
    id: id,
    name: name,
    slug: name.toLowerCase(),
    description: null,
    iconName: 'category',
    colorHex: '#000000',
    type: IlanCategoryType.other,
    pricingMode: IlanPricingMode.optional,
    allowedConditions: const [],
    isActive: true,
    sortOrder: 0,
  );

  test('aynı ID ile gelen kategorileri dropdown için tekilleştirir', () {
    final categories = uniqueIlanCategoriesById([
      category('sale', 'Eski Satılık'),
      category('sale', 'Satılık'),
      category('rent', 'Kiralık'),
    ]);

    expect(categories.map((item) => item.id), ['sale', 'rent']);
    expect(categories.singleWhere((item) => item.id == 'sale').name, 'Satılık');
    expect(validIlanCategoryDropdownValue(categories, 'sale'), 'sale');
  });

  test('items dışında veya birden çok kez bulunan seçimi null yapar', () {
    final duplicateCategories = [
      category('sale', 'Satılık 1'),
      category('sale', 'Satılık 2'),
    ];

    expect(validIlanCategoryDropdownValue(duplicateCategories, 'sale'), isNull);
    expect(validIlanCategoryDropdownValue(duplicateCategories, 'rent'), isNull);
  });

  test(
    'farklı model örneğini ID üzerinden items listesindeki örneğe bağlar',
    () {
      final fromDropdownItems = category('sale', 'Satılık');
      final fromPreviousQuery = category('sale', 'Başka sorgudaki Satılık');

      final selected = resolveIlanCategorySelection([
        fromDropdownItems,
      ], fromPreviousQuery.id);

      expect(identical(selected, fromDropdownItems), isTrue);
    },
  );
}

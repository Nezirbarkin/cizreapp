import '../models/ilan_models.dart';

/// API yanitinda tekrar eden kategori kimliklerini tekilleştirir.
List<IlanCategory> uniqueIlanCategoriesById(
  Iterable<IlanCategory> categories,
) => <String, IlanCategory>{
  for (final category in categories) category.id: category,
}.values.toList(growable: false);

/// Seçimi, dropdown item'larının kaynağı olan listedeki modelle eşleştirir.
IlanCategory? resolveIlanCategorySelection(
  List<IlanCategory> categories,
  String? selectedId,
) {
  if (categories.isEmpty) return null;
  if (selectedId == null) return categories.first;

  for (final category in categories) {
    if (category.id == selectedId) return category;
  }
  return categories.first;
}

/// Dropdown'a yalnızca items içinde tam bir kez bulunan kimliği verir.
String? validIlanCategoryDropdownValue(
  List<IlanCategory> categories,
  String? selectedId,
) {
  if (selectedId == null) return null;
  var matches = 0;
  for (final category in categories) {
    if (category.id == selectedId) matches++;
  }
  return matches == 1 ? selectedId : null;
}

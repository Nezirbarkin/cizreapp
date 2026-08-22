import 'package:flutter/material.dart';

class IlanFilterState {
  const IlanFilterState({
    this.minPrice,
    this.maxPrice,
    this.condition,
    this.sortBy = 'newest',
  });

  final double? minPrice;
  final double? maxPrice;
  final String? condition;
  final String sortBy;

  bool get isActive =>
      minPrice != null ||
      maxPrice != null ||
      condition != null ||
      sortBy != 'newest';

  int get activeCount => [
    minPrice != null,
    maxPrice != null,
    condition != null,
    sortBy != 'newest',
  ].where((value) => value).length;

  IlanFilterState copyWith({
    double? minPrice,
    double? maxPrice,
    String? condition,
    String? sortBy,
  }) => IlanFilterState(
    minPrice: minPrice,
    maxPrice: maxPrice,
    condition: condition,
    sortBy: sortBy ?? this.sortBy,
  );
}

const _sortOptions = [
  ('newest', 'En Yeni'),
  ('price_asc', 'Fiyat: Artan'),
  ('price_desc', 'Fiyat: Azalan'),
];

Future<IlanFilterState?> showIlanFilterSheet(
  BuildContext context, {
  required IlanFilterState current,
  required List<String> availableConditions,
}) {
  return showModalBottomSheet<IlanFilterState>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => _IlanFilterSheetContent(
      initial: current,
      availableConditions: availableConditions,
    ),
  );
}

class _IlanFilterSheetContent extends StatefulWidget {
  const _IlanFilterSheetContent({
    required this.initial,
    required this.availableConditions,
  });

  final IlanFilterState initial;
  final List<String> availableConditions;

  @override
  State<_IlanFilterSheetContent> createState() =>
      _IlanFilterSheetContentState();
}

class _IlanFilterSheetContentState extends State<_IlanFilterSheetContent> {
  late final _minController = TextEditingController(
    text: widget.initial.minPrice?.toStringAsFixed(0) ?? '',
  );
  late final _maxController = TextEditingController(
    text: widget.initial.maxPrice?.toStringAsFixed(0) ?? '',
  );
  late String? _condition = widget.initial.condition;
  late String _sortBy = widget.initial.sortBy;

  @override
  void dispose() {
    _minController.dispose();
    _maxController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: 16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Filtrele ve Sırala',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 18),
            const Text(
              'Fiyat Aralığı',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _minController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Min ₺',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _maxController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Max ₺',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            if (widget.availableConditions.isNotEmpty) ...[
              const SizedBox(height: 18),
              const Text(
                'Durum',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: widget.availableConditions
                    .map(
                      (value) => ChoiceChip(
                        label: Text(value),
                        selected: _condition == value,
                        onSelected: (selected) => setState(
                          () => _condition = selected ? value : null,
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
            const SizedBox(height: 18),
            const Text(
              'Sıralama',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _sortOptions
                  .map(
                    (option) => ChoiceChip(
                      label: Text(option.$2),
                      selected: _sortBy == option.$1,
                      onSelected: (_) => setState(() => _sortBy = option.$1),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () =>
                        Navigator.pop(context, const IlanFilterState()),
                    child: const Text('Temizle'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () => Navigator.pop(
                      context,
                      IlanFilterState(
                        minPrice: double.tryParse(
                          _minController.text.trim().replaceAll(',', '.'),
                        ),
                        maxPrice: double.tryParse(
                          _maxController.text.trim().replaceAll(',', '.'),
                        ),
                        condition: _condition,
                        sortBy: _sortBy,
                      ),
                    ),
                    child: const Text('Uygula'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

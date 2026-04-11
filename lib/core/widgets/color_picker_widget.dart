// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';

/// Önceden belirlenmiş renkleri tutar
class PredefinedColor {
  final String name;
  final String hex;
  final Color color;

  PredefinedColor({
    required this.name,
    required this.hex,
    required this.color,
  });
}

/// Renk Seçici Widget
class ColorPickerWidget extends StatefulWidget {
  final Function(String colorName, String hexCode) onColorSelected;
  final String? initialColorName;
  final String? initialHexCode;

  const ColorPickerWidget({
    super.key,
    required this.onColorSelected,
    this.initialColorName,
    this.initialHexCode,
  });

  @override
  State<ColorPickerWidget> createState() => _ColorPickerWidgetState();
}

class _ColorPickerWidgetState extends State<ColorPickerWidget> {
  /// Önceden belirlenmiş renkler listesi
  static final List<PredefinedColor> predefinedColors = [
    PredefinedColor(name: 'Kırmızı', hex: '#FF0000', color: const Color(0xFFFF0000)),
    PredefinedColor(name: 'Mavi', hex: '#0000FF', color: const Color(0xFF0000FF)),
    PredefinedColor(name: 'Yeşil', hex: '#00AA00', color: const Color(0xFF00AA00)),
    PredefinedColor(name: 'Sarı', hex: '#FFFF00', color: const Color(0xFFFFFF00)),
    PredefinedColor(name: 'Siyah', hex: '#000000', color: const Color(0xFF000000)),
    PredefinedColor(name: 'Beyaz', hex: '#FFFFFF', color: const Color(0xFFFFFFFF)),
    PredefinedColor(name: 'Turuncu', hex: '#FFA500', color: const Color(0xFFFFA500)),
    PredefinedColor(name: 'Mor', hex: '#800080', color: const Color(0xFF800080)),
    PredefinedColor(name: 'Pembe', hex: '#FFC0CB', color: const Color(0xFFFFC0CB)),
    PredefinedColor(name: 'Gri', hex: '#808080', color: const Color(0xFF808080)),
    PredefinedColor(name: 'Turkuaz', hex: '#40E0D0', color: const Color(0xFF40E0D0)),
    PredefinedColor(name: 'Kahverengi', hex: '#A52A2A', color: const Color(0xFFA52A2A)),
  ];

  late PredefinedColor _selectedColor;
  final TextEditingController _customColorNameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    
    // Başlangıç rengini ayarla
    if (widget.initialColorName != null && widget.initialHexCode != null) {
      _selectedColor = predefinedColors.firstWhere(
        (color) => color.hex == widget.initialHexCode,
        orElse: () => predefinedColors.first,
      );
      _customColorNameController.text = widget.initialColorName ?? '';
    } else {
      _selectedColor = predefinedColors.first;
    }
  }

  @override
  void dispose() {
    _customColorNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Başlık
        const Text(
          'Renk Seç',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 12),

        // Renk Paleti Grid
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1,
          ),
          itemCount: predefinedColors.length,
          itemBuilder: (context, index) {
            final color = predefinedColors[index];
            final isSelected = _selectedColor.hex == color.hex;

            return GestureDetector(
              onTap: () {
                setState(() {
                  _selectedColor = color;
                  _customColorNameController.text = color.name;
                });
              },
              child: Stack(
                children: [
                  // Renk kutucuğu
                  Container(
                    decoration: BoxDecoration(
                      color: color.color,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: color.hex == '#FFFFFF'
                            ? Colors.grey.shade300
                            : Colors.transparent,
                        width: 1,
                      ),
                    ),
                    child: const SizedBox.expand(),
                  ),

                  // Seçili işareti
                  if (isSelected)
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.check_circle,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),

                  // Renk adı tooltip
                  Positioned(
                    bottom: 4,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Text(
                        color.name,
                        style: TextStyle(
                          color: _getContrastColor(color.color),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),

        const SizedBox(height: 16),

        // Seçili renk bilgisi
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Row(
            children: [
              // Renk örneği
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _selectedColor.color,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: _selectedColor.hex == '#FFFFFF'
                        ? Colors.grey.shade300
                        : Colors.transparent,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Renk detayları
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Seçili Renk: ${_selectedColor.name}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Hex Kodu: ${_selectedColor.hex}',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Renk Adı Input
        TextFormField(
          controller: _customColorNameController,
          decoration: const InputDecoration(
            labelText: 'Renk Adı (İsteğe Bağlı)',
            border: OutlineInputBorder(),
            hintText: 'Örn: Koyu Kırmızı, Açık Mavi...',
          ),
        ),

        const SizedBox(height: 16),

        // Hex Kodu (salt okunur)
        TextField(
          enabled: false,
          decoration: InputDecoration(
            labelText: 'Hex Kodu',
            border: const OutlineInputBorder(),
            disabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            prefixIcon: const Icon(Icons.palette),
          ),
          controller: TextEditingController(text: _selectedColor.hex),
        ),
      ],
    );
  }

  /// Arka plan rengine göre yazı rengini belirler
  Color _getContrastColor(Color backgroundColor) {
    final luminance = backgroundColor.computeLuminance();
    return luminance > 0.5 ? Colors.black : Colors.white;
  }

  /// Seçili renk ve adı döndürür
  void submitColor() {
    final colorName = _customColorNameController.text.trim().isNotEmpty
        ? _customColorNameController.text.trim()
        : _selectedColor.name;

    widget.onColorSelected(colorName, _selectedColor.hex);
  }
}

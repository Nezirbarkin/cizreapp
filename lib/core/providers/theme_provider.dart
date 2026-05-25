import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider with ChangeNotifier {
  Color _primaryColor = const Color(0xFFD91A73); // Vibrant pink
  
  // Otomatik tema değişimi için
  bool _autoThemeEnabled = true;
  
  // Mevcut temalar (Yeşil, Mavi, Pembe)
  static const List<Color> availableThemes = [
    Color(0xFF2E7D32), // Yeşil
    Color(0xFF1976D2), // Mavi
    Color(0xFFD91A73), // Pembe
  ];

  Color get primaryColor => _primaryColor;
  bool get autoThemeEnabled => _autoThemeEnabled;

  ThemeProvider() {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final themeValue = prefs.getInt('theme_color') ?? 0xFFD91A73;
    _primaryColor = Color(themeValue);
    
    // Otomatik tema ayarını yükle
    _autoThemeEnabled = prefs.getBool('auto_theme_enabled') ?? true;
    notifyListeners();
  }

  Future<void> setTheme(Color color) async {
    _primaryColor = color;
    notifyListeners();
    
    final prefs = await SharedPreferences.getInstance();
    // ignore: deprecated_member_use
    await prefs.setInt('theme_color', color.value);
  }

  /// Uygulama başlatıldığında otomatik tema değişimi yapar
  /// Sadece otomatik tema etkinse çalışır
  /// Bu metod static olarak çağrılabilir
  static Future<void> applyAutoThemeOnLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    final autoThemeEnabled = prefs.getBool('auto_theme_enabled') ?? true;
    
    if (!autoThemeEnabled) return;
    
    // Kayıtlı temayı al
    final savedThemeValue = prefs.getInt('theme_color');
    
    // Kayıtlı temayı al veya varsayılan pembe
    final currentColor = savedThemeValue != null
        ? Color(savedThemeValue)
        : const Color(0xFFD91A73);
    final currentIndex = availableThemes.indexOf(currentColor);
    
    // Her açılışta rastgele farklı bir tema seç
    final random = Random();
    int newIndex;
    do {
      newIndex = random.nextInt(availableThemes.length);
    } while (newIndex == currentIndex && availableThemes.length > 1);
    
    // Yeni temayı kaydet
    // ignore: deprecated_member_use
    await prefs.setInt('theme_color', availableThemes[newIndex].value);
  }

  /// Otomatik tema değişimini aç/kapat
  Future<void> setAutoTheme(bool enabled) async {
    _autoThemeEnabled = enabled;
    notifyListeners();
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_theme_enabled', enabled);
  }

  /// Manuel olarak rastgele tema seç (otomatik kapalıyken kullanılabilir)
  Future<void> setRandomTheme() async {
    final random = Random();
    final currentIndex = availableThemes.indexOf(_primaryColor);
    
    // Mevcut temadan farklı bir tema seç
    int newIndex;
    do {
      newIndex = random.nextInt(availableThemes.length);
    } while (newIndex == currentIndex && availableThemes.length > 1);
    
    await setTheme(availableThemes[newIndex]);
  }

  /// Temayı SharedPreferences'tan yeniden yükle (otomatik tema değişiminden sonra çağrılır)
  Future<void> reloadTheme() async {
    await _loadTheme();
  }

  ThemeData get themeData {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _primaryColor,
        primary: _primaryColor,
      ),
      scaffoldBackgroundColor: const Color(0xFFF5F7FA),
      appBarTheme: AppBarTheme(
        backgroundColor: _primaryColor,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

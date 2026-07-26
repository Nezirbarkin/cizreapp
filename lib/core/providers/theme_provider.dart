import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider with ChangeNotifier {
  Color _primaryColor = const Color(0xFFD91A73); // Vibrant pink

  // Otomatik tema değişimi için
  bool _autoThemeEnabled = true;

  // Dark mode desteği
  ThemeMode _themeMode = ThemeMode.system;
  bool get isDarkMode => _themeMode == ThemeMode.dark;
  
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

    // Dark mode'u yükle
    final themeModeStr = prefs.getString('theme_mode');
    if (themeModeStr != null) {
      _themeMode = ThemeMode.values
          .firstWhere((m) => m.toString() == themeModeStr, orElse: () => ThemeMode.system);
    }

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

  /// Dark mode'u aç
  Future<void> setDarkMode() async {
    _themeMode = ThemeMode.dark;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode', ThemeMode.dark.toString());
    notifyListeners();
  }

  /// Light mode'u aç
  Future<void> setLightMode() async {
    _themeMode = ThemeMode.light;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode', ThemeMode.light.toString());
    notifyListeners();
  }

  /// Sistem tema'sını kullan
  Future<void> setSystemMode() async {
    _themeMode = ThemeMode.system;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('theme_mode');
    notifyListeners();
  }

  /// Tema'yı toggle et
  Future<void> toggleTheme() async {
    if (_themeMode == ThemeMode.dark) {
      await setLightMode();
    } else {
      await setDarkMode();
    }
  }

  ThemeMode get themeMode => _themeMode;

  ThemeData get themeData {
    final isDark = _themeMode == ThemeMode.dark;

    return ThemeData(
      useMaterial3: true,
      brightness: isDark ? Brightness.dark : Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _primaryColor,
        primary: _primaryColor,
        brightness: isDark ? Brightness.dark : Brightness.light,
      ),
      scaffoldBackgroundColor:
          isDark ? const Color(0xFF121212) : const Color(0xFFF5F7FA),
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
      cardColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      dialogTheme: DialogThemeData(
        backgroundColor:
            isDark ? const Color(0xFF1E1E1E) : Colors.white,
      ),
    );
  }
}

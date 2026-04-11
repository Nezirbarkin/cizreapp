// ignore_for_file: depend_on_referenced_packages, duplicate_ignore, unnecessary_import

// ignore_for_file: depend_on_referenced_packages

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class ImageCompressionHelper {
  /// Resmi sıkıştır ve geçici dosya olarak kaydet (Mobile)
  /// Web için compressImageBytes kullanın
  ///
  /// [imagePath] - Sıkıştırılacak resmin yolu
  /// [quality] - Kalite (0-100), varsayılan 85
  /// [maxWidth] - Maksimum genişlik, varsayılan 1920
  /// [maxHeight] - Maksimum yükseklik, varsayılan 1920
  ///
  /// Returns: Sıkıştırılmış resmin yolu veya null
  static Future<String?> compressImage({
    required String imagePath,
    int quality = 85,
    int? maxWidth,
    int? maxHeight,
    bool keepAspectRatio = true,
  }) async {
    try {
      debugPrint('🖼️ Resim sıkıştırılıyor: $imagePath');
      
      // Web için bu metod kullanılmamalı
      assert(!kIsWeb, 'Web platformunda compressImage kullanılmamalı - compressXFile kullanın');
      
      final File originalFile = File(imagePath);
      final int originalSize = await originalFile.length();
      debugPrint('📏 Orijinal boyut: ${(originalSize / 1024 / 1024).toStringAsFixed(2)} MB');
      
      // Geçici dizin al
      final Directory tempDir = await getTemporaryDirectory();
      final String targetPath = path.join(
        tempDir.path,
        'compressed_${DateTime.now().millisecondsSinceEpoch}${path.extension(imagePath)}',
      );
      
      // Resmi sıkıştır (aspect ratio korunur)
      final XFile? compressedFile = await FlutterImageCompress.compressAndGetFile(
        imagePath,
        targetPath,
        quality: quality,
        minWidth: maxWidth ?? 800,
        minHeight: maxHeight ?? 800,
        format: CompressFormat.jpeg,
        keepExif: false,
      );
      
      if (compressedFile == null) {
        debugPrint('❌ Resim sıkıştırılamadı');
        return null;
      }
      
      final int compressedSize = await File(compressedFile.path).length();
      final double compressionRatio = ((originalSize - compressedSize) / originalSize * 100);
      
      debugPrint('✅ Sıkıştırılmış boyut: ${(compressedSize / 1024 / 1024).toStringAsFixed(2)} MB');
      debugPrint('📊 Sıkıştırma oranı: ${compressionRatio.toStringAsFixed(1)}%');
      
      return compressedFile.path;
    } catch (e) {
      debugPrint('❌ Resim sıkıştırma hatası: $e');
      return null;
    }
  }
  
  /// XFile'dan resmi sıkıştır (Web ve Mobile uyumlu)
  /// Web platformu için bu yöntemi kullanın
  ///
  /// [xFile] - Sıkıştırılacak resim (image_picker'dan gelen)
  /// [quality] - Kalite (0-100), varsayılan 85
  /// [maxWidth] - Maksimum genişlik
  /// [maxHeight] - Maksimum yükseklik
  ///
  /// Returns: Sıkıştırılmış resim byte array veya null
  static Future<Uint8List?> compressXFile({
    required XFile xFile,
    int quality = 85,
    int? maxWidth,
    int? maxHeight,
  }) async {
    try {
      debugPrint('🖼️ XFile sıkıştırılıyor...');
      
      // Byte array'ı oku
      final imageBytes = await xFile.readAsBytes();
      final originalSize = imageBytes.length;
      debugPrint('📏 Orijinal boyut: ${(originalSize / 1024 / 1024).toStringAsFixed(2)} MB');
      
      // Byte array'i sıkıştır
      final compressedBytes = await FlutterImageCompress.compressWithList(
        imageBytes,
        quality: quality,
        minWidth: maxWidth ?? 1080,
        minHeight: maxHeight ?? 1920,
        format: CompressFormat.jpeg,
      );
      
      final compressedSize = compressedBytes.length;
      final compressionRatio = ((originalSize - compressedSize) / originalSize * 100);
      
      debugPrint('✅ Sıkıştırılmış boyut: ${(compressedSize / 1024 / 1024).toStringAsFixed(2)} MB');
      debugPrint('📊 Sıkıştırma oranı: ${compressionRatio.toStringAsFixed(1)}%');
      
      return compressedBytes;
    } catch (e) {
      debugPrint('❌ XFile sıkıştırma hatası: $e');
      return null;
    }
  }
  
  /// Dosya yolundan veya XFile'dan resmi sıkıştır (Web ve Mobile uyumlu)
  /// Otomatik olarak platforma göre doğru yöntemi seçer
  ///
  /// [imagePath] - Mobile için dosya yolu
  /// [xFile] - Web için XFile (opsiyonel)
  /// [quality] - Kalite (0-100), varsayılan 85
  /// [maxWidth] - Maksimum genişlik
  /// [maxHeight] - Maksimum yükseklik
  ///
  /// Returns: Sıkıştırılmış resim yolu (mobile) veya byte array (web) veya null
  static Future<dynamic> compressImageAuto({
    String? imagePath,
    XFile? xFile,
    int quality = 85,
    int? maxWidth,
    int? maxHeight,
  }) async {
    if (kIsWeb) {
      // Web'de XFile kullan
      if (xFile == null) {
        debugPrint('❌ Web platformunda xFile gereklidir');
        return null;
      }
      return await compressXFile(
        xFile: xFile,
        quality: quality,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
      );
    } else {
      // Mobile'da dosya yolu kullan
      if (imagePath == null) {
        debugPrint('❌ Mobile platformda imagePath gereklidir');
        return null;
      }
      return await compressImage(
        imagePath: imagePath,
        quality: quality,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
      );
    }
  }
  
  /// Profil fotoğrafı için optimize edilmiş sıkıştırma (Mobile)
  /// Profil fotoğrafları için daha küçük boyut ve yüksek kalite
  static Future<String?> compressProfilePhoto(String imagePath) async {
    return compressImage(
      imagePath: imagePath,
      quality: 90,
      maxWidth: 800,
      maxHeight: 800,
    );
  }
  
  /// Profil fotoğrafı için optimize edilmiş sıkıştırma (XFile - Web/Mobile)
  static Future<Uint8List?> compressProfilePhotoXFile(XFile xFile) async {
    return compressXFile(
      xFile: xFile,
      quality: 90,
      maxWidth: 800,
      maxHeight: 800,
    );
  }
  
  /// Kapak fotoğrafı için optimize edilmiş sıkıştırma (Mobile)
  /// Kapak fotoğrafları için geniş format
  static Future<String?> compressCoverPhoto(String imagePath) async {
    return compressImage(
      imagePath: imagePath,
      quality: 88,
      maxWidth: 1600,
      maxHeight: 800,
    );
  }
  
  /// Kapak fotoğrafı için optimize edilmiş sıkıştırma (XFile - Web/Mobile)
  static Future<Uint8List?> compressCoverPhotoXFile(XFile xFile) async {
    return compressXFile(
      xFile: xFile,
      quality: 88,
      maxWidth: 1600,
      maxHeight: 800,
    );
  }
  
  /// Story için optimize edilmiş sıkıştırma
  /// Aspect ratio korunarak sıkıştırılır
  static Future<String?> compressStoryImage(String imagePath) async {
    return compressImage(
      imagePath: imagePath,
      quality: 85,
      maxWidth: 1080,
      maxHeight: 1920,
      keepAspectRatio: true,
    );
  }
  
  /// Post için optimize edilmiş sıkıştırma
  /// Post'lar için dengeli boyut
  static Future<String?> compressPostImage(String imagePath) async {
    return compressImage(
      imagePath: imagePath,
      quality: 85,
      maxWidth: 1080,
      maxHeight: 1920,
    );
  }
  
  /// Thumbnail için optimize edilmiş sıkıştırma
  /// Thumbnail'ler için küçük boyut
  static Future<String?> compressThumbnail(String imagePath) async {
    return compressImage(
      imagePath: imagePath,
      quality: 75,
      maxWidth: 400,
      maxHeight: 400,
    );
  }
  
  /// Video thumbnail için optimize edilmiş sıkıştırma
  static Future<String?> compressVideoThumbnail(String imagePath) async {
    return compressImage(
      imagePath: imagePath,
      quality: 75,
      maxWidth: 400,
      maxHeight: 700,
    );
  }
  
  /// Byte array'den resmi sıkıştır
  static Future<List<int>?> compressImageBytes({
    required List<int> imageBytes,
    int quality = 85,
    int? maxWidth,
    int? maxHeight,
  }) async {
    try {
      debugPrint('🖼️ Byte array sıkıştırılıyor...');
      
      final int originalSize = imageBytes.length;
      debugPrint('📏 Orijinal boyut: ${(originalSize / 1024 / 1024).toStringAsFixed(2)} MB');
      
      // Byte array'i sıkıştır
      final List<int> compressedBytes = await FlutterImageCompress.compressWithList(
        Uint8List.fromList(imageBytes),
        quality: quality,
        minWidth: maxWidth ?? 800,
        minHeight: maxHeight ?? 800,
        format: CompressFormat.jpeg,
      );
      
      // ignore: unnecessary_null_comparison, dead_code
      if (compressedBytes == null) {
        debugPrint('❌ Byte array sıkıştırılamadı');
        return null;
      }
      
      final int compressedSize = compressedBytes.length;
      final double compressionRatio = ((originalSize - compressedSize) / originalSize * 100);
      
      debugPrint('✅ Sıkıştırılmış boyut: ${(compressedSize / 1024 / 1024).toStringAsFixed(2)} MB');
      debugPrint('📊 Sıkıştırma oranı: ${compressionRatio.toStringAsFixed(1)}%');
      
      return compressedBytes;
    } catch (e) {
      debugPrint('❌ Byte array sıkıştırma hatası: $e');
      return null;
    }
  }
}

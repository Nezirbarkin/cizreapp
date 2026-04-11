// ignore_for_file: unnecessary_import

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:minio/minio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Merkezi Storage Servisi
/// Supabase Storage veya S3 uyumlu servisleri (idrive e2 gibi) destekler
/// Web için devre dışı (S3/Minio web'de çalışmaz)
class StorageService {
  // S3 Ayarları
  bool _s3Enabled = false;
  Minio? _minioClient;
  String? _s3Bucket;
  String? _s3PublicUrl;
  
  // Singleton pattern
  static StorageService? _instance;
  
  factory StorageService() {
    _instance ??= StorageService._internal();
    return _instance!;
  }
  
  StorageService._internal();
  
  /// Supabase client'ı güvenli şekilde al (lazy)
  /// Supabase henüz başlatılmadıysa null döner
  SupabaseClient? get _supabase {
    try {
      return Supabase.instance.client;
    } catch (e) {
      debugPrint('⚠️ Supabase henüz başlatılmadı: $e');
      return null;
    }
  }
  
  /// Web'de S3 desteklenmez
  bool get _isWebSupported => !kIsWeb;
  
  /// Supabase başlatılmış mı?
  bool get isSupabaseReady {
    try {
      Supabase.instance.client;
      return true;
    } catch (e) {
      return false;
    }
  }
  
  /// S3 ayarlarını yükleyip S3 client'ı başlatır (Web hariç)
  Future<void> initS3({
    required String accessKey,
    required String secretKey,
    required String bucket,
    required String endpoint,
    required String region,
    String publicUrl = '',
  }) async {
    if (!_isWebSupported) {
      debugPrint('⚠️ S3 web platformunda desteklenmez');
      return;
    }
    
    try {
      _minioClient = Minio(
        endPoint: endpoint.replaceFirst('https://', '').replaceFirst('http://', ''),
        accessKey: accessKey,
        secretKey: secretKey,
        region: region,
        useSSL: endpoint.startsWith('https://'),
      );
      
      _s3Bucket = bucket;
      _s3PublicUrl = publicUrl.isEmpty ? endpoint : publicUrl;
      _s3Enabled = true;
      
      debugPrint('✅ S3 Storage başlatıldı: $endpoint/$bucket');
    } catch (e) {
      debugPrint('❌ S3 Storage başlatma hatası: $e');
      _s3Enabled = false;
    }
  }
  
  /// S3'ü devre dışı bırak (Supabase kullan)
  void disableS3() {
    _s3Enabled = false;
    _minioClient = null;
    debugPrint('⚠️ S3 devre dışı, Supabase Storage kullanılıyor');
  }
  
  /// S3 aktif mi?
  bool get isS3Enabled => _s3Enabled;
  
  // ============================================================
  // DOSYA YÜKLEME
  // ============================================================
  
  /// Dosya yükle (File path)
  Future<String?> uploadFile({
    required String filePath,
    required String bucket,
    required String path,
    Map<String, String>? metadata,
  }) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        debugPrint('❌ Dosya bulunamadı: $filePath');
        return null;
      }
      
      final bytes = await file.readAsBytes();
      return uploadBytes(
        bytes: bytes,
        bucket: bucket,
        path: path,
        metadata: metadata,
      );
    } catch (e) {
      debugPrint('❌ Dosya yükleme hatası: $e');
      return null;
    }
  }
  
  /// Byte yükle (Doğrudan bellekten)
  Future<String?> uploadBytes({
    required Uint8List bytes,
    required String bucket,
    required String path,
    Map<String, String>? metadata,
  }) async {
    try {
      if (_s3Enabled && _minioClient != null && _isWebSupported) {
        return _uploadToS3(bytes, bucket, path, metadata);
      } else {
        return _uploadToSupabase(bytes, bucket, path, metadata);
      }
    } catch (e) {
      debugPrint('❌ Byte yükleme hatası: $e');
      return null;
    }
  }
  
  /// S3'e yükle
  Future<String> _uploadToS3(
    Uint8List bytes,
    String bucket,
    String path,
    Map<String, String>? metadata,
  ) async {
    final s3Bucket = _s3Bucket ?? bucket;
    
    // Minio 3.5.8 için Stream kullanımı
    final stream = Stream.fromIterable([bytes]);
    await _minioClient!.putObject(
      s3Bucket,
      path,
      stream,
      metadata: metadata ?? {},
    );
    
    final url = _s3PublicUrl!.endsWith('/')
        ? '$_s3PublicUrl$s3Bucket/$path'
        : '$_s3PublicUrl/$s3Bucket/$path';
    
    debugPrint('✅ S3 yüklendi: $url');
    return url;
  }
  
  /// Supabase'e yükle
  Future<String?> _uploadToSupabase(
    Uint8List bytes,
    String bucket,
    String path,
    Map<String, String>? metadata,
  ) async {
    final client = _supabase;
    if (client == null) {
      debugPrint('❌ Supabase başlatılmadı, yükleme yapılamıyor');
      return null;
    }
    
    await client.storage.from(bucket).uploadBinary(
      path,
      bytes,
      fileOptions: FileOptions(
        upsert: true,
        metadata: metadata,
      ),
    );
    
    final url = client.storage.from(bucket).getPublicUrl(path);
    debugPrint('✅ Supabase yüklendi: $url');
    return url;
  }
  
  // ============================================================
  // DOSYA SİLME
  // ============================================================
  
  /// Dosya sil
  Future<bool> deleteFile({
    required String bucket,
    required String path,
  }) async {
    try {
      if (_s3Enabled && _minioClient != null) {
        return _deleteFromS3(bucket, path);
      } else {
        return _deleteFromSupabase(bucket, path);
      }
    } catch (e) {
      debugPrint('❌ Dosya silme hatası: $e');
      return false;
    }
  }
  
  /// S3'ten sil
  Future<bool> _deleteFromS3(String bucket, String path) async {
    final s3Bucket = _s3Bucket ?? bucket;
    await _minioClient!.removeObject(s3Bucket, path);
    debugPrint('✅ S3 silindi: $s3Bucket/$path');
    return true;
  }
  
  /// Supabase'den sil
  Future<bool> _deleteFromSupabase(String bucket, String path) async {
    final client = _supabase;
    if (client == null) {
      debugPrint('❌ Supabase başlatılmadı, silme yapılamıyor');
      return false;
    }
    
    await client.storage.from(bucket).remove([path]);
    debugPrint('✅ Supabase silindi: $bucket/$path');
    return true;
  }
  
  // ============================================================
  // PUBLIC URL
  // ============================================================
  
  /// Public URL al
  String? getPublicUrl({
    required String bucket,
    required String path,
  }) {
    if (_s3Enabled && _s3PublicUrl != null) {
      final s3Bucket = _s3Bucket ?? bucket;
      return _s3PublicUrl!.endsWith('/') 
          ? '$_s3PublicUrl$s3Bucket/$path'
          : '$_s3PublicUrl/$s3Bucket/$path';
    } else {
      final client = _supabase;
      if (client == null) {
        debugPrint('❌ Supabase başlatılmadı, URL alınamıyor');
        return null;
      }
      return client.storage.from(bucket).getPublicUrl(path);
    }
  }
  
  // ============================================================
  // DOSYA LİSTESİ
  // ============================================================
  
  /// Bucket içindeki dosyaları listele
  Future<List<String>> listFiles({
    required String bucket,
    String prefix = '',
    int limit = 100,
  }) async {
    try {
      if (_s3Enabled && _minioClient != null) {
        return _listFromS3(bucket, prefix, limit);
      } else {
        return _listFromSupabase(bucket, prefix, limit);
      }
    } catch (e) {
      debugPrint('❌ Dosya listeleme hatası: $e');
      return [];
    }
  }
  
  /// S3'ten listele
  Future<List<String>> _listFromS3(String bucket, String prefix, int limit) async {
    final s3Bucket = _s3Bucket ?? bucket;
    final itemsStream = _minioClient!.listObjects(
      s3Bucket,
      prefix: prefix,
      recursive: false,
    );
    
    final results = await itemsStream.toList();
    final fileNames = <String>[];
    
    for (final result in results) {
      for (final obj in result.objects) {
        if (obj.key != null) {
          fileNames.add(obj.key!);
          if (fileNames.length >= limit) break;
        }
      }
      if (fileNames.length >= limit) break;
    }
    
    return fileNames;
  }
  
  /// Supabase'den listele
  Future<List<String>> _listFromSupabase(String bucket, String prefix, int limit) async {
    final client = _supabase;
    if (client == null) {
      debugPrint('❌ Supabase başlatılmadı, listeleme yapılamıyor');
      return [];
    }
    
    final response = await client.storage
        .from(bucket)
        .list(path: prefix);
    
    return response
        .take(limit)
        .map((e) => e.name)
        .toList();
  }
  
  // ============================================================
  // DOSYA VAR MI?
  // ============================================================
  
  /// Dosya var mı kontrol et
  Future<bool> fileExists({
    required String bucket,
    required String path,
  }) async {
    try {
      if (_s3Enabled && _minioClient != null && _isWebSupported) {
        final s3Bucket = _s3Bucket ?? bucket;
        await _minioClient!.statObject(s3Bucket, path);
        return true;
      } else {
        final client = _supabase;
        if (client == null) return false;
        
        final response = await client.storage.from(bucket).list(path: path);
        return response.any((item) => item.name == path.split('/').last);
      }
    } catch (e) {
      return false;
    }
  }
  
  // ============================================================
  // S3 AYARLARINI VERITABANINDAN YÜKLE
  // ============================================================
  
  /// Supabase'den S3 ayarlarını yükle ve başlat (Web hariç)
  Future<bool> loadS3SettingsFromDatabase() async {
    if (!_isWebSupported) {
      debugPrint('⚠️ S3 web platformunda desteklenmez');
      disableS3();
      return false;
    }
    
    final client = _supabase;
    if (client == null) {
      debugPrint('⚠️ Supabase başlatılmadı, S3 ayarları yüklenemiyor');
      disableS3();
      return false;
    }
    
    try {
      final response = await client
          .from('api_settings')
          .select()
          .single();
      
      final s3Enabled = response['s3_enabled'] as bool? ?? false;
      
      if (!s3Enabled) {
        disableS3();
        return false;
      }
      
      final accessKey = response['s3_access_key'] as String? ?? '';
      final secretKey = response['s3_secret_key'] as String? ?? '';
      final bucket = response['s3_bucket'] as String? ?? '';
      final endpoint = response['s3_endpoint'] as String? ?? '';
      final region = response['s3_region'] as String? ?? 'us-east-1';
      final publicUrl = response['s3_public_url'] as String? ?? '';
      
      if (accessKey.isEmpty || secretKey.isEmpty || bucket.isEmpty || endpoint.isEmpty) {
        debugPrint('⚠️ S3 ayarları eksik, Supabase kullanılıyor');
        disableS3();
        return false;
      }
      
      await initS3(
        accessKey: accessKey,
        secretKey: secretKey,
        bucket: bucket,
        endpoint: endpoint,
        region: region,
        publicUrl: publicUrl,
      );
      
      return true;
    } catch (e) {
      debugPrint('❌ S3 ayarları yüklenirken hata: $e');
      disableS3();
      return false;
    }
  }
}

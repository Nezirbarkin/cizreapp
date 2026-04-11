import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../utils/app_logger.dart';

/// Network bağlantı durumunu izleyen servis
class ConnectivityService {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  
  // Bağlantı durumu
  bool _isConnected = true;
  ConnectivityResult _currentStatus = ConnectivityResult.wifi;
  
  // Stream controller for broadcasting connection status
  final StreamController<bool> _connectionController = StreamController<bool>.broadcast();
  
  /// Bağlantı durumu stream'i
  Stream<bool> get connectionStream => _connectionController.stream;
  
  /// Mevcut bağlantı durumu
  bool get isConnected => _isConnected;
  
  /// Mevcut bağlantı tipi
  ConnectivityResult get currentStatus => _currentStatus;
  
  /// Bağlantı tipi string olarak
  String get connectionType {
    switch (_currentStatus) {
      case ConnectivityResult.wifi:
        return 'WiFi';
      case ConnectivityResult.mobile:
        return 'Mobil Veri';
      case ConnectivityResult.ethernet:
        return 'Ethernet';
      case ConnectivityResult.vpn:
        return 'VPN';
      case ConnectivityResult.bluetooth:
        return 'Bluetooth';
      case ConnectivityResult.other:
        return 'Diğer';
      case ConnectivityResult.none:
        return 'Bağlantı Yok';
      // ignore: unreachable_switch_default
      default:
        return 'Bilinmiyor';
    }
  }

  /// Servisi başlat
  Future<void> initialize() async {
    try {
      // İlk bağlantı durumunu kontrol et
      final result = await _connectivity.checkConnectivity();
      _updateConnectionStatus(result);
      
      // Bağlantı değişikliklerini dinle
      _subscription = _connectivity.onConnectivityChanged.listen(
        _updateConnectionStatus,
        onError: (error) {
          AppLogger.error('Connectivity error: $error');
        },
      );
      
      AppLogger.info('🌐 Connectivity service initialized');
    } catch (e) {
      AppLogger.error('Failed to initialize connectivity service: $e');
    }
  }

  /// Bağlantı durumunu güncelle
  void _updateConnectionStatus(List<ConnectivityResult> results) {
    if (results.isEmpty) {
      _currentStatus = ConnectivityResult.none;
      _isConnected = false;
    } else {
      _currentStatus = results.first;
      _isConnected = _currentStatus != ConnectivityResult.none;
    }
    
    // Stream'e yayınla
    _connectionController.add(_isConnected);
    
    // Log
    if (_isConnected) {
      AppLogger.info('🌐 Connected: $connectionType');
    } else {
      AppLogger.warning('📵 Disconnected');
    }
  }

  /// Manuel bağlantı kontrolü
  Future<bool> checkConnection() async {
    try {
      final result = await _connectivity.checkConnectivity();
      _updateConnectionStatus(result);
      return _isConnected;
    } catch (e) {
      AppLogger.error('Connection check failed: $e');
      return false;
    }
  }

  /// Servisi temizle
  void dispose() {
    _subscription?.cancel();
    _connectionController.close();
    AppLogger.debug('🌐 Connectivity service disposed');
  }
}

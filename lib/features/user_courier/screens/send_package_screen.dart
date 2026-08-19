// ignore_for_file: avoid_print

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/address_model.dart';
import '../../../core/services/maps_api_key_service.dart';
import '../../market/screens/address_picker_screen.dart';
import 'package_history_screen.dart';
import '../widgets/couriers_map_card.dart';

class SendPackageScreen extends StatefulWidget {
  const SendPackageScreen({super.key});

  @override
  State<SendPackageScreen> createState() => _SendPackageScreenState();
}

class _SendPackageScreenState extends State<SendPackageScreen> {
  final _senderNameController = TextEditingController();
  final _senderPhoneController = TextEditingController();
  final _recipientController = TextEditingController();
  final _recipientPhoneController = TextEditingController();
  final _recipientAddressDetailController = TextEditingController();
  final _descriptionController = TextEditingController();

  Address? _pickupAddress;
  Address? _deliveryAddress;

  double _baseFee = 15;
  double _perKmFee = 3;
  bool _isLoading = true;
  bool _isSubmitting = false;

  // Google Directions ile alınan gerçek yol mesafesi (km). null ise _distanceKm
  // Haversine (kuş ucuşu) fallback döner. Sunucu (RPC) aynı kaynağı kullandığı
  // için UI önizlemesi ile kesilen tutar tutarlıdır.
  double? _roadDistanceKm;
  bool _isDistanceLoading = false;
  // Tekrar tekrar aynı koordinatlar için Directions çağırmamak için cache.
  double? _fetchedPickupLat;
  double? _fetchedPickupLng;
  double? _fetchedDeliveryLat;
  double? _fetchedDeliveryLng;
  // Haritada çizilecek rota polyline noktaları (Google Directions).
  List<LatLng> _routePoints = const [];
  // DEBUG: rota fetch akışını ekranda gösterir (logcat Flogger tarafından
  // boğulduğu için). Çözüm sonrası kaldırılacak.
  String _routeDebug = '';

  // Sunucudan dönen son gerçek tutar (UI'da onay sonrası gösterilir)
  double? _lastServerTotalFee;

  // Idempotency key: aynı submit'te çift tıklama sunucu tarafında tek talebe
  // dönüşür. Session başına tek bir key kullanırız.
  late final String _paketIdempotencyKey;

  static String _generateUuid() {
    // Hafif bir v4 üretici: 16 byte random.
    final r = DateTime.now().microsecondsSinceEpoch;
    final bytes = List<int>.generate(
      16,
      (i) => ((r * (i + 1)) ^ (i * 0x9E3779B1)) & 0xFF,
    );
    bytes[6] = (bytes[6] & 0x0F) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3F) | 0x80; // variant 1
    String hex(int b) => b.toRadixString(16).padLeft(2, '0');
    final h = bytes.map(hex).join();
    return '${h.substring(0, 8)}-'
        '${h.substring(8, 12)}-'
        '${h.substring(12, 16)}-'
        '${h.substring(16, 20)}-'
        '${h.substring(20)}';
  }

  List<Map<String, dynamic>> _serviceNotices = [];

  // build() içinde her seferinde yeni Future yaratmak yerine tek sefer cache'le.
  Future<List<Map<String, dynamic>>>? _nearbyCouriersFuture;

  double? get _distanceKm {
    if (_pickupAddress?.latitude == null ||
        _pickupAddress?.longitude == null ||
        _deliveryAddress?.latitude == null ||
        _deliveryAddress?.longitude == null) {
      return null;
    }
    // Gerçek yol mesafesi varsa onu kullan; yoksa Haversine (kuş uçuşu) fallback.
    if (_roadDistanceKm != null) return _roadDistanceKm;
    final meters = Geolocator.distanceBetween(
      _pickupAddress!.latitude!,
      _pickupAddress!.longitude!,
      _deliveryAddress!.latitude!,
      _deliveryAddress!.longitude!,
    );
    return meters / 1000;
  }

  double? get _totalFee {
    final km = _distanceKm;
    if (km == null) return null;
    return _baseFee + km * _perKmFee;
  }

  @override
  void initState() {
    super.initState();
    _paketIdempotencyKey = _generateUuid();
    _loadPricing();
    _loadServiceNotices();
    _refreshNearbyCouriers();
  }

  /// Yakın kuryeler future'unu yeniden oluşturur (pull-to-refresh vb. için).
  void _refreshNearbyCouriers() {
    _nearbyCouriersFuture = _fetchNearbyCoriers();
  }

  Future<void> _loadPricing() async {
    try {
      final response = await Supabase.instance.client
          .from('courier_service_settings')
          .select()
          .limit(1)
          .maybeSingle();

      if (response != null) {
        _baseFee = (response['base_fee'] as num?)?.toDouble() ?? _baseFee;
        _perKmFee = (response['per_km_fee'] as num?)?.toDouble() ?? _perKmFee;
      }
    } catch (e) {
      debugPrint('Ücret ayarları yükleme hatası: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadServiceNotices() async {
    try {
      final notices = await Supabase.instance.client
          .from('courier_service_notices')
          .select()
          .eq('show_on_send_package_screen', true)
          .order('priority', ascending: false)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(
          () => _serviceNotices = List<Map<String, dynamic>>.from(notices),
        );
      }
    } catch (e) {
      debugPrint('Uyarılar yükleme hatası: $e');
    }
  }

  Future<void> _pickAddress({required bool isPickup}) async {
    final current = isPickup ? _pickupAddress : _deliveryAddress;
    final result = await Navigator.push<Address>(
      context,
      MaterialPageRoute(
        builder: (context) => AddressPickerScreen(
          initialLatitude: current?.latitude,
          initialLongitude: current?.longitude,
          initialAddress: current?.addressLine1,
        ),
      ),
    );
    if (result != null) {
      setState(() {
        if (isPickup) {
          _pickupAddress = result;
        } else {
          _deliveryAddress = result;
        }
        // Adres değişti: eski rota/mesafe temizlenir, yeni fetch dolar.
        _roadDistanceKm = null;
        _routePoints = const [];
        _fetchedPickupLat = null;
        _fetchedPickupLng = null;
        _fetchedDeliveryLat = null;
        _fetchedDeliveryLng = null;
      });
      _fetchRoadDistance();
    }
  }

  /// Alım→teslim gerçek yol mesafesini (km) + rota polyline'ını getirir.
  /// Önce `route-distance` Edge Function (aynı anda road_distance_cache'i de
  /// doldurur → RPC kesilen tutarda yol mesafesini kullanır). Edge Function
  /// yoksa/hata verirse direkt Google Directions çağırır (rota çizgisi ve
  /// önizleme yine gösterilir; kesilen tutar Haversine'e düşer). Böylece rota
  /// çizgisi Edge Function deploy'una bağlı kalmadan görünür.
  /// DEBUG yardımcı: mesajı hem terminale basar hem ekrandaki _routeDebug'ya
  /// yazar (logcat'in Dart loglarını boğmasına karşı).
  void _rl(String msg) {
    print('[ROUTE] $msg');
    if (mounted) setState(() => _routeDebug = msg);
  }

  Future<void> _fetchRoadDistance() async {
    final pickupLat = _pickupAddress?.latitude;
    final pickupLng = _pickupAddress?.longitude;
    final deliveryLat = _deliveryAddress?.latitude;
    final deliveryLng = _deliveryAddress?.longitude;
    _rl('fetch: pickup=$pickupLat,$pickupLng delivery=$deliveryLat,$deliveryLng');
    if (pickupLat == null || pickupLng == null || deliveryLat == null ||
        deliveryLng == null) {
      _rl('erken return: koordinat yok (adres seçilmedi?)');
      return;
    }
    // Aynı koordinatlar için tekrar çağırma.
    if (_fetchedPickupLat == pickupLat && _fetchedPickupLng == pickupLng &&
        _fetchedDeliveryLat == deliveryLat && _fetchedDeliveryLng == deliveryLng) {
      _rl('erken return: ayni koordinat (cache)');
      return;
    }

    if (mounted) setState(() => _isDistanceLoading = true);
    _rl('Edge Function çağrılıyor…');

    // 1) Edge Function (cache + polyline).
    try {
      final result = await Supabase.instance.client.functions.invoke(
        'route-distance',
        body: {
          'pickup_lat': pickupLat,
          'pickup_lng': pickupLng,
          'delivery_lat': deliveryLat,
          'delivery_lng': deliveryLng,
        },
      ).timeout(const Duration(seconds: 10));
      _rl('Edge yaniti: ${result.data}');
      if (_applyRoadResult(result.data, pickupLat, pickupLng, deliveryLat, deliveryLng)) {
        return;
      }
      _rl('Edge beklenmeyen format → direkt Google');
    } catch (e) {
      _rl('Edge basarisiz ($e) → direkt Google');
    }

    // 2) Direkt Google Directions (Edge Function yoksa/404/hata).
    if (await _fetchRoadDistanceDirect(
      pickupLat, pickupLng, deliveryLat, deliveryLng,
    )) {
      return;
    }

    // 3) OSRM demo (ücretsiz, key yok) — Directions API GCP'de kapalıyken
    //    rota çizgisi gösterebilmek için. Yalnızca görsel; ücretlendirme
    //    sunucuda kalır.
    if (await _fetchRoadDistanceOSRM(
      pickupLat, pickupLng, deliveryLat, deliveryLng,
    )) {
      return;
    }
    _rl('hiçbir yol çalışmadı — rota yok, Haversine km');

    if (mounted) setState(() => _isDistanceLoading = false);
  }

  /// Direkt Google Directions API çağrısı (rota + mesafe önizleme). Key:
  /// .env → app_about_settings. Bu yol cache yazmaz; RPC ekseni Haversine
  /// kullanır. Başarı true döner.
  Future<bool> _fetchRoadDistanceDirect(
    double pickupLat, double pickupLng,
    double deliveryLat, double deliveryLng,
  ) async {
    String? apiKey;
    try {
      apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'];
    } catch (_) {}
    if (apiKey == null || apiKey.isEmpty || !apiKey.startsWith('AIza')) {
      try {
        apiKey = await MapsApiKeyService.getGoogleMapsApiKey();
      } catch (_) {}
    }
    if (apiKey == null || apiKey.isEmpty) {
      _rl('Direkt: API key yok');
      return false;
    }
    _rl('Direkt Google çağrılıyor, key=${apiKey.substring(0, 8)}…');
    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/directions/json'
        '?origin=$pickupLat,$pickupLng'
        '&destination=$deliveryLat,$deliveryLng'
        '&mode=driving&key=$apiKey',
      );
      final response = await http.get(url).timeout(const Duration(seconds: 8));
      _rl('Google HTTP ${response.statusCode}, ${response.body.length} byte');
      final body = jsonDecode(response.body);
      if (body is Map<String, dynamic> && body['status'] == 'OK') {
        return _applyRoadResult(body, pickupLat, pickupLng, deliveryLat, deliveryLng,
            googleShape: true);
      }
      _rl('Google başarısız: status=${body is Map ? body['status'] : '?'}');
    } catch (e) {
      _rl('Direkt hata: $e');
    }
    return false;
  }

  /// Elde edilen rota sonucunu state'e uygular. Edge Function ({ok,distance_km,
  /// polyline}) ve direkt Google ({status,routes}) formatlarını ikisini de
  /// işler. Başarı true döner.
  bool _applyRoadResult(
    dynamic data,
    double pickupLat, double pickupLng,
    double deliveryLat, double deliveryLng,
    {bool googleShape = false}) {
    if (data is! Map<String, dynamic>) return false;

    double? km;
    String? polylineStr;

    if (googleShape) {
      // Direkt Google Directions yanıtı.
      final routes = data['routes'] as List?;
      if (routes == null || routes.isEmpty) return false;
      final leg = (routes[0]['legs'] as List?)?.firstOrNull;
      final meters = (leg?['distance']?['value'] as num?)?.toDouble();
      if (meters == null || meters <= 0) return false;
      km = meters / 1000.0;
      polylineStr = routes[0]['overview_polyline']?['points'] as String?;
    } else {
      // Edge Function yanıtı.
      if (data['ok'] != true) return false;
      km = (data['distance_km'] as num?)?.toDouble();
      polylineStr = data['polyline'] as String?;
      if (km == null || km <= 0) return false;
    }

    final points = (polylineStr != null && polylineStr.isNotEmpty)
        ? _decodePolyline(polylineStr)
        : const <LatLng>[];
    _rl('BAŞARI km=$km polylineLen=${polylineStr?.length ?? 0} nokta=${points.length}');
    if (mounted) {
      setState(() {
        _roadDistanceKm = km;
        _routePoints = points;
        _fetchedPickupLat = pickupLat;
        _fetchedPickupLng = pickupLng;
        _fetchedDeliveryLat = deliveryLat;
        _fetchedDeliveryLng = deliveryLng;
        _isDistanceLoading = false;
      });
    }
    return true;
  }

  /// OSRM demo router (ücretsiz, key yok). Google Directions API GCP'de
  /// kapalıyken rota çizgisi + önizleme mesafesi için yedek. demo sunucusu
  /// (router.project-osrm.org) production için güvenilir değildir (rate limit,
  /// SLA yok) — yalnızca görsel rota içindir. geometries=polyline, Google ile
  /// aynı encoded format döndürür. Ücretlendirme yine sunucu otoritesinde
  /// (RPC Haversine/road_distance_cache) kalır; buradan gelen km yalnızca
  /// önizlemedir. Başarı true döner.
  Future<bool> _fetchRoadDistanceOSRM(
    double pickupLat, double pickupLng,
    double deliveryLat, double deliveryLng,
  ) async {
    try {
      // OSRM koordinat sırası: lng,lat;lng,lat
      final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
        '$pickupLng,$pickupLat;$deliveryLng,$deliveryLat'
        '?overview=full&geometries=polyline',
      );
      final response = await http.get(url).timeout(const Duration(seconds: 8));
      _rl('OSRM HTTP ${response.statusCode}, ${response.body.length} byte');
      final body = jsonDecode(response.body);
      if (body is Map<String, dynamic> && body['code'] == 'Ok') {
        final routes = body['routes'] as List?;
        if (routes == null || routes.isEmpty) {
          _rl('OSRM: rota yok');
          return false;
        }
        final meters = (routes[0]['distance'] as num?)?.toDouble();
        final geometry = routes[0]['geometry'] as String?;
        if (meters == null || meters <= 0 || geometry == null || geometry.isEmpty) {
          _rl('OSRM: mesafe/geometri yok');
          return false;
        }
        final km = meters / 1000.0;
        final points = _decodePolyline(geometry);
        _rl('OSRM BAŞARI km=$km nokta=${points.length}');
        if (mounted) {
          setState(() {
            _roadDistanceKm = km;
            _routePoints = points;
            _fetchedPickupLat = pickupLat;
            _fetchedPickupLng = pickupLng;
            _fetchedDeliveryLat = deliveryLat;
            _fetchedDeliveryLng = deliveryLng;
            _isDistanceLoading = false;
          });
        }
        return true;
      }
      _rl('OSRM başarısız: code=${body is Map ? body['code'] : '?'}');
    } catch (e) {
      _rl('OSRM hata: $e');
    }
    return false;
  }

  /// Google encoded polyline (overview_polyline.points) decode -> LatLng listesi.
  /// Standart algoritma: 5-bit gruplar, işaretli delta.
  static List<LatLng> _decodePolyline(String encoded) {
    final result = <LatLng>[];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;
    while (index < len) {
      int b, shift = 0, resultLat = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        resultLat |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlat = (resultLat & 1) == 1
          ? ~(resultLat >> 1)
          : (resultLat >> 1);
      lat += dlat;

      shift = 0;
      int resultLng = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        resultLng |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlng = (resultLng & 1) == 1
          ? ~(resultLng >> 1)
          : (resultLng >> 1);
      lng += dlng;

      result.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return result;
  }

  /// Paket oluşturulduktan sonra en uygun online kuryeye bildirim atar
  /// (otomatik yönlendirme). Eski istemci-taraflı toplu bildirim RLS altında
  /// sessizce bloklanıyordu (profiles.role grant dışı + çapraz-kullanıcı
  /// notifications insert user_id=auth.uid() kuralına takılıyordu) ve ayrıca
  /// TÜM kuryelere yayın yapıyordu. Artık sunucu-otoriteli route_new_package_request
  /// RPC: en uygun (online优先, en az teslimatlı) kuryeyi seçer ve yalnız ona
  /// bildirir; paket havuzda kalır, kurye kabul eder. Hata akışı bozmaz.
  Future<void> _notifyCouriers(String requestId) async {
    try {
      await Supabase.instance.client.rpc(
        'route_new_package_request',
        params: {'p_request_id': requestId},
      );
    } catch (e) {
      debugPrint('Kurye yönlendirme bildirimi gönderilemedi: $e');
    }
  }

  Future<void> _submitRequest() async {
    // Boş/yalnızca-boşluk girişleri engelle.
    if (_senderNameController.text.trim().isEmpty ||
        _senderPhoneController.text.trim().isEmpty ||
        _recipientController.text.trim().isEmpty ||
        _recipientPhoneController.text.trim().isEmpty ||
        _pickupAddress == null ||
        _deliveryAddress == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen tüm alanları doldurunuz')),
      );
      return;
    }

    // Adreslerin koordinatı yoksa ücret hesaplanamaz; bakiye düşülmeden
    // ücretsiz paket oluşturulmasını önle.
    if (_pickupAddress?.latitude == null ||
        _pickupAddress?.longitude == null ||
        _deliveryAddress?.latitude == null ||
        _deliveryAddress?.longitude == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Alım ve teslim noktaları için haritadan konum seçiniz',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    Map<String, dynamic>? insertedRequest;
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Oturumunuz sona erdi. Lütfen tekrar giriş yapınız.',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Sunucu-otoriteli atomik talep: mesafe, fiyat, bakiye düşümü ve ledger
      // kaydı tek bir RPC'de yapılır. İstemci hiçbir finansal değer göndermez.
      // Idempotency key: aynı gönderimde çift tıklama aynı sonucu üretir.
      final idempotencyKey = _paketIdempotencyKey;
      insertedRequest = await Supabase.instance.client
          .rpc(
            'create_package_request',
            params: {
              'p_pickup_lat': _pickupAddress!.latitude,
              'p_pickup_lng': _pickupAddress!.longitude,
              'p_delivery_lat': _deliveryAddress!.latitude,
              'p_delivery_lng': _deliveryAddress!.longitude,
              'p_sender_name': _senderNameController.text.trim(),
              'p_sender_phone': _senderPhoneController.text.trim(),
              'p_recipient_name': _recipientController.text.trim(),
              'p_recipient_phone': _recipientPhoneController.text.trim(),
              'p_pickup_address': _pickupAddress!.addressLine1,
              'p_delivery_address': _deliveryAddress!.addressLine1,
              'p_delivery_address_detail': _recipientAddressDetailController
                  .text
                  .trim(),
              'p_description': _descriptionController.text.trim(),
              'p_idempotency_key': idempotencyKey,
            },
          )
          .select('r_id,r_total_fee')
          .single();

      // Sunucu tarafından hesaplanan tutarı UI'a uygula
      final serverTotalFee = (insertedRequest['r_total_fee'] as num?)?.toDouble();
      if (serverTotalFee != null && mounted) {
        setState(() => _lastServerTotalFee = serverTotalFee);
      }

      _notifyCouriers(insertedRequest['r_id'] as String);

      if (mounted) {
        final fee = _lastServerTotalFee;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              fee == null
                  ? 'Paket talebiniz gönderildi!'
                  : 'Paket talebiniz gönderildi! Ücret: ₺${fee.toStringAsFixed(2)}',
            ),
            backgroundColor: Colors.green,
          ),
        );
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) Navigator.pop(context);
        });
      }
    } catch (e) {
      debugPrint('Paket talebini gönderme hatası: $e');
      // create_package_request RPC atomik: talep ya da bakiye düşümü kalıcı
      // değilse hiçbir satır oluşmaz. İstemci tarafında manuel rollback'e gerek
      // yoktur; hata mesajı doğrudan gösterilir.
      if (mounted) {
        // Yetersiz bakiye hatası kontrolü
        // RPC 'APP:insufficient_balance | mevcut: X, gerekli: Y' raise ediyor.
        // Eski kod sadece 'Insufficient balance' (boşluklu EN) arıyordu; bu
        // nedenle canlıda yetersiz bakiye diyaloğu ASLA tetiklenmiyordu.
        // Refactor (2026-08-07): case-insensitive, hem TR hem EN, hem de
        // 'mevcut/gerekli' anahtar kelimelerini yakala.
        final errorMessage = e.toString();
        final lowerMessage = errorMessage.toLowerCase();
        final isInsufficientBalance = lowerMessage.contains('insufficient') ||
            errorMessage.contains('yetersiz bakiye') ||
            errorMessage.contains('mevcut:') ||
            errorMessage.contains('gerekli:');

        if (isInsufficientBalance) {
          // Bakiye miktarlarını ayıkla: hem EN (Available:/Required:) hem
          // TR (mevcut:/gerekli:) formatlarını destekle.
          String? availableText;
          String? requiredText;
          try {
            if (errorMessage.contains('Available:')) {
              availableText = errorMessage
                  .split('Available:')[1]
                  .split(',')[0]
                  .trim();
              requiredText = errorMessage
                  .split('Required:')[1]
                  .split(',')[0]
                  .trim();
            } else if (errorMessage.contains('mevcut:')) {
              availableText = errorMessage
                  .split('mevcut:')[1]
                  .split(',')[0]
                  .trim();
              requiredText = errorMessage
                  .split('gerekli:')[1]
                  .split(',')[0]
                  .trim();
            }
          } catch (_) {}

          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Yetersiz Bakiye'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Paket gönderimi için yeterli bakiyeniz yok.'),
                  if (availableText != null && requiredText != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Mevcut bakiye: ₺$availableText',
                            style: const TextStyle(fontSize: 13),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Gerekli miktar: ₺$requiredText',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  const Text(
                    'Bakiye yüklemek ister misiniz?',
                    style: TextStyle(fontSize: 13),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('İptal'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/wallet');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                  ),
                  child: const Text('Bakiye Yükle'),
                ),
              ],
            ),
          );
        } else {
          // Diğer hatalar için genel mesaj
          String userFriendlyMessage =
              'Paket talebiniz gönderilirken bir sorun oluştu.';

          if (errorMessage.contains('P0001') ||
              errorMessage.contains('PostgrestException')) {
            userFriendlyMessage =
                'İşlem sırasında bir sorun oluştu. Lütfen tekrar deneyiniz.';
          } else if (errorMessage.contains('timeout') ||
              errorMessage.contains('Timeout')) {
            userFriendlyMessage =
                'Bağlantı zaman aşımına uğradı. Lütfen tekrar deneyiniz.';
          }

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(userFriendlyMessage),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Widget _buildAddressCard({
    required String title,
    required IconData icon,
    required Address? address,
    required VoidCallback onTap,
  }) {
    final primary = Theme.of(context).colorScheme.primary;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Icon(icon, color: primary),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          address?.addressLine1 ?? 'Haritadan konum seçin',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: TextButton(
          onPressed: onTap,
          child: Text(address == null ? 'Seç' : 'Değiştir'),
        ),
      ),
    );
  }

  Widget _buildServiceNotices() {
    if (_serviceNotices.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        ..._serviceNotices.map((notice) {
          final noticeType = notice['notice_type'] as String? ?? 'info';
          final title = notice['title'] as String? ?? '';
          final message = notice['message'] as String? ?? '';
          final priority = notice['priority'] as int? ?? 0;

          Color bgColor;
          Color borderColor;
          Color textColor;
          IconData icon;

          switch (noticeType) {
            case 'warning':
              bgColor = Colors.orange.shade50;
              borderColor = Colors.orange.shade200;
              textColor = Colors.orange.shade900;
              icon = Icons.warning_amber_rounded;
              break;
            case 'alert':
              bgColor = Colors.red.shade50;
              borderColor = Colors.red.shade200;
              textColor = Colors.red.shade900;
              icon = Icons.error_rounded;
              break;
            case 'success':
              bgColor = Colors.green.shade50;
              borderColor = Colors.green.shade200;
              textColor = Colors.green.shade900;
              icon = Icons.check_circle_rounded;
              break;
            default: // info
              bgColor = Colors.blue.shade50;
              borderColor = Colors.blue.shade200;
              textColor = Colors.blue.shade900;
              icon = Icons.info_rounded;
          }

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              decoration: BoxDecoration(
                color: bgColor,
                border: Border.all(color: borderColor),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Material(
                color: Colors.transparent,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(icon, color: textColor, size: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              title,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: textColor,
                                fontSize: 14,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (priority > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: priority > 1
                                    ? Colors.red.shade300
                                    : Colors.orange.shade300,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                priority > 1 ? 'ACİL' : 'ÖNEMLİ',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        message,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
        const SizedBox(height: 12),
      ],
    );
  }

  Future<List<Map<String, dynamic>>> _fetchNearbyCoriers() async {
    try {
      final couriers = await Supabase.instance.client
          .from('profiles')
          .select('id, full_name, last_known_lat, last_known_lng')
          .eq('role', 'courier')
          .not('last_known_lat', 'is', null)
          .not('last_known_lng', 'is', null)
          .limit(5);
      return List<Map<String, dynamic>>.from(couriers);
    } catch (e) {
      debugPrint('Yakın kuryeler yükleme hatası: $e');
      return [];
    }
  }

  Widget _buildNearbyCourriersList() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _nearbyCouriersFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.two_wheeler, color: Colors.blue.shade700, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Kuryeler yükleniyor...',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade900,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          );
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const SizedBox.shrink();
        }

        final couriers = snapshot.data!;
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.blue.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.two_wheeler,
                    color: Colors.blue.shade700,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Yakın Kuryeler (${couriers.length})',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade900,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ...couriers.map((courier) {
                final name = courier['full_name'] as String? ?? 'Kurye';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: Colors.red.shade100,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        alignment: Alignment.center,
                        child: const Text(
                          '🏍️',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          name,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue.shade900,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final totalFee = _totalFee;
    final distanceKm = _distanceKm;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Paket Gönder/Al'),
        backgroundColor: primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Geçmiş Paketlerim',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const PackageHistoryScreen(),
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Admin uyarıları
                  _buildServiceNotices(),

                  const Text(
                    'Alım ve Teslim Noktası',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  _buildAddressCard(
                    title: 'Alım Noktası',
                    icon: Icons.storefront,
                    address: _pickupAddress,
                    onTap: () => _pickAddress(isPickup: true),
                  ),
                  const SizedBox(height: 8),
                  _buildAddressCard(
                    title: 'Teslim Noktası',
                    icon: Icons.location_on,
                    address: _deliveryAddress,
                    onTap: () => _pickAddress(isPickup: false),
                  ),
                  // DEBUG: rota fetch akışı (geçici, çözüm sonrası kaldırılacak).
                  if (_routeDebug.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '🔍 ROTA: $_routeDebug'
                        '${_routePoints.isNotEmpty ? " | çizgi: ${_routePoints.length} nokta" : ""}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.deepOrange,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CouriersMapCard(
                        pickupLat: _pickupAddress?.latitude,
                        pickupLng: _pickupAddress?.longitude,
                        deliveryLat: _deliveryAddress?.latitude,
                        deliveryLng: _deliveryAddress?.longitude,
                        routePoints: _routePoints,
                      ),
                      const SizedBox(height: 12),
                      // Yakın kuryeler listesi
                      _buildNearbyCourriersList(),
                    ],
                  ),
                  if (totalFee != null) ...[
                    const SizedBox(height: 12),
                    Card(
                      color: primary.withValues(alpha: 0.08),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isDistanceLoading
                                  ? 'Mesafe: hesaplanıyor…'
                                  : 'Mesafe: ${distanceKm!.toStringAsFixed(1)} km',
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Açılış: ${_baseFee.toStringAsFixed(2)} ₺  +  ${distanceKm!.toStringAsFixed(1)} km × ${_perKmFee.toStringAsFixed(2)} ₺',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Toplam Ücret'),
                                Text(
                                  '${totalFee.toStringAsFixed(2)} ₺',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: primary,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  const Text(
                    'Gönderen Bilgileri',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _senderNameController,
                    decoration: InputDecoration(
                      labelText: 'Gönderen Adı',
                      prefixIcon: const Icon(Icons.person_outline),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _senderPhoneController,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: 'Gönderen Telefonu',
                      prefixIcon: const Icon(Icons.phone_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Alıcı Bilgileri',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _recipientController,
                    decoration: InputDecoration(
                      labelText: 'Alıcı Adı',
                      prefixIcon: const Icon(Icons.person),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _recipientPhoneController,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: 'Telefon',
                      prefixIcon: const Icon(Icons.phone),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _recipientAddressDetailController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: 'Açık Adres (Kat, Daire, Tarif vb.)',
                      prefixIcon: const Icon(Icons.map_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Paket Açıklaması',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _descriptionController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: 'Açıklama',
                      prefixIcon: const Icon(Icons.description),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _submitRequest,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text(
                              'Paket Talebini Gönder',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
    );
  }

  @override
  void dispose() {
    _senderNameController.dispose();
    _senderPhoneController.dispose();
    _recipientController.dispose();
    _recipientPhoneController.dispose();
    _recipientAddressDetailController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }
}

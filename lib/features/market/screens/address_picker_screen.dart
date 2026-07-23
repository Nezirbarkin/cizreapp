import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../../core/models/address_model.dart';
import '../../../core/services/maps_api_key_service.dart';

/// Harita üzerinden adres seçme ekranı (Google Maps ile)
class AddressPickerScreen extends StatefulWidget {
  final double? initialLatitude;
  final double? initialLongitude;
  final String? initialAddress;

  const AddressPickerScreen({
    super.key,
    this.initialLatitude,
    this.initialLongitude,
    this.initialAddress,
  });

  @override
  State<AddressPickerScreen> createState() => _AddressPickerScreenState();
}

class _AddressPickerScreenState extends State<AddressPickerScreen> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _neighborhoodController = TextEditingController();
  final TextEditingController _streetController = TextEditingController();
  final TextEditingController _noController = TextEditingController();
  final TextEditingController _floorController = TextEditingController();
  final TextEditingController _apartmentController = TextEditingController();
  
  GoogleMapController? _mapController;

  double? _selectedLatitude;
  double? _selectedLongitude;
  String _selectedAddress = '';
  bool _isSearching = false;
  bool _isLoadingLocation = false;
  bool _isApiKeyLoaded = false;
  bool _isGeocoding = false;
  Timer? _geocodeDebounce;
  
  // Cizre varsayılan koordinatları
  static const LatLng _defaultCizre = LatLng(37.3255, 42.1876);
  
  // Harita marker'ı
  Set<Marker> _markers = {};
  
  // API Key
  String? _googleMapsApiKey;

  @override
  void initState() {
    super.initState();
    _selectedLatitude = widget.initialLatitude;
    _selectedLongitude = widget.initialLongitude;
    _selectedAddress = widget.initialAddress ?? '';
    _addressController.text = _selectedAddress;
    _streetController.text = _selectedAddress;

    // Mahalle ve sokak değişikliklerini dinle
    _neighborhoodController.addListener(_onAddressFieldChanged);
    _streetController.addListener(_onAddressFieldChanged);

    // API Key'i yükle
    _loadApiKey();

    // Başlangıçta marker ayarla
    _updateMarker();
  }
  
  Future<void> _loadApiKey() async {
    // Önce .env dosyasından API key'i kontrol et
    String? apiKey;
    try {
      await dotenv.load();
      apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'];
    } catch (e) {
      debugPrint('⚠️ .env dosyası yüklenemedi: $e');
    }
    
    // .env'de yoksa veritabanından dene
    if (apiKey == null || apiKey.isEmpty || !apiKey.startsWith('AIza')) {
      try {
        final dbApiKey = await MapsApiKeyService.getGoogleMapsApiKey();
        if (dbApiKey != null && dbApiKey.isNotEmpty) {
          apiKey = dbApiKey;
        }
      } catch (e) {
        debugPrint('⚠️ Veritabanından API key alınamadı: $e');
      }
    }
    
    if (mounted) {
      setState(() {
        _googleMapsApiKey = apiKey;
        _isApiKeyLoaded = true;
      });
      
      // Sadece başlangıç konumu verilmediyse otomatik olarak mevcut konumu al
      final hasInitialLocation = widget.initialLatitude != null && widget.initialLongitude != null;
      if (!hasInitialLocation && apiKey != null && MapsApiKeyService.isValidApiKey(apiKey)) {
        // Kısa bir gecikme ile konum al (harita yüklenmesini bekle)
        Future.delayed(const Duration(milliseconds: 400), () {
          if (mounted) {
            _getCurrentLocation();
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _geocodeDebounce?.cancel();
    _searchController.dispose();
    _addressController.dispose();
    _neighborhoodController.dispose();
    _streetController.dispose();
    _noController.dispose();
    _floorController.dispose();
    _apartmentController.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  void _onAddressFieldChanged() {
    _geocodeDebounce?.cancel();
    _geocodeDebounce = Timer(const Duration(milliseconds: 800), _geocodeAddressFromFields);
  }

  Future<void> _geocodeAddressFromFields() async {
    final neighborhood = _neighborhoodController.text.trim();
    final street = _streetController.text.trim();

    if (neighborhood.isEmpty || street.isEmpty) {
      return;
    }

    if (_googleMapsApiKey == null || !MapsApiKeyService.isValidApiKey(_googleMapsApiKey)) {
      return;
    }

    setState(() => _isGeocoding = true);

    try {
      final query = '$neighborhood, $street, Cizre, Şırnak, Türkiye';
      final data = await _geocode(query);

      if (data != null && data['status'] == 'OK' && (data['results'] as List).isNotEmpty) {
        final location = data['results'][0]['geometry']['location'];
        final lat = (location['lat'] as num).toDouble();
        final lng = (location['lng'] as num).toDouble();

        if (mounted) {
          setState(() {
            _selectedLatitude = lat;
            _selectedLongitude = lng;
          });
          _updateMarker();
          _mapController?.animateCamera(CameraUpdate.newLatLngZoom(LatLng(lat, lng), 17));
        }
      }
    } catch (e) {
      debugPrint('❌ Mahalle/Sokak geocode hatası: $e');
    } finally {
      if (mounted) {
        setState(() => _isGeocoding = false);
      }
    }
  }

  void _updateMarker() {
    final lat = _selectedLatitude ?? _defaultCizre.latitude;
    final lng = _selectedLongitude ?? _defaultCizre.longitude;
    
    setState(() {
      _markers = {
        Marker(
          markerId: const MarkerId('selected_location'),
          position: LatLng(lat, lng),
          infoWindow: const InfoWindow(title: 'Seçili Konum'),
          draggable: true,
          onDragEnd: (newPosition) {
            _onMapTap(newPosition);
          },
        ),
      };
    });
  }

  void _onMapTap(LatLng position) {
    setState(() {
      _selectedLatitude = position.latitude;
      _selectedLongitude = position.longitude;
    });
    _updateMarker();
    
    // Tıklanan noktanın adresini al
    _fetchAddressFromCoordinates(position.latitude, position.longitude);
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _isLoadingLocation = true);
    
    try {
      // Konum izni kontrolü
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Konum izni reddedildi')),
            );
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Konum izni kalıcı olarak reddedildi. Ayarlardan açın.'),
            ),
          );
        }
        return;
      }

      // Mevcut konumu al
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      setState(() {
        _selectedLatitude = position.latitude;
        _selectedLongitude = position.longitude;
      });
      
      _updateMarker();
      
      // Haritayı yeni konuma taşı
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(position.latitude, position.longitude),
          17,
        ),
      );
      
      // Adres bilgilerini al (Reverse Geocoding)
      await _fetchAddressFromCoordinates(position.latitude, position.longitude);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mevcut konum alındı')),
        );
      }
    } catch (e) {
      debugPrint('❌ Konum alma hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Konum alınamadı: $e')),
        );
      }
    } finally {
      setState(() => _isLoadingLocation = false);
    }
  }

  /// Koordinatlardan adres bilgilerini al (Reverse Geocoding)
  Future<void> _fetchAddressFromCoordinates(double lat, double lng) async {
    if (_googleMapsApiKey == null || !MapsApiKeyService.isValidApiKey(_googleMapsApiKey)) {
      debugPrint('⚠️ API Key geçersiz veya yok');
      return;
    }
    
    debugPrint('🔍 Adres aranıyor: $lat, $lng');
    
    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json?latlng=$lat,$lng&key=$_googleMapsApiKey&language=tr'
      );
      
      debugPrint('📡 API isteği: $url');
      
      final response = await http.get(url).timeout(
        const Duration(seconds: 10),
      );
      
      debugPrint('📥 API yanıtı: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        debugPrint('📋 API sonucu: ${data['status']}');
        
        if (data['status'] == 'OK' && data['results'] != null && data['results'].isNotEmpty) {
          final result = data['results'][0];
          
          // Adres bileşenlerini ayıkla
          String streetAddress = '';
          String neighborhood = '';
          String district = '';

          final components = result['address_components'] as List;
          debugPrint('📋 Adres bileşenleri:');
          for (var component in components) {
            final types = component['types'] as List;
            final longName = component['long_name'] as String;
            debugPrint('  - $longName: $types');

            if (types.contains('route')) {
              streetAddress = longName;
            } else if (types.contains('neighborhood') || types.contains('sublocality')) {
              neighborhood = longName;
            } else if (types.contains('administrative_area_level_4')) {
              // Türkiye'de mahalle genellikle level_4
              if (neighborhood.isEmpty) {
                neighborhood = longName;
              }
            } else if (types.contains('administrative_area_level_3')) {
              // Alternatif mahalle seviyesi
              if (neighborhood.isEmpty) {
                neighborhood = longName;
              }
            } else if (types.contains('administrative_area_level_2')) {
              district = longName;
            }
          }

          // Adresi oluştur
          String fullAddress = '';
          if (neighborhood.isNotEmpty) {
            fullAddress = neighborhood;
          }
          if (streetAddress.isNotEmpty) {
            fullAddress += fullAddress.isEmpty ? streetAddress : ', $streetAddress';
          }
          if (district.isNotEmpty && district != neighborhood) {
            fullAddress += fullAddress.isEmpty ? district : ', $district';
          }
          
          debugPrint('✅ Adres ayrıştırıldı - Mahalle: $neighborhood, Sokak: $streetAddress, İlçe: $district');
          debugPrint('✅ Tam adres: $fullAddress');
          
          // Adres controller'ı güncelle
          if (mounted && fullAddress.isNotEmpty) {
            setState(() {
              _selectedAddress = fullAddress;
              _addressController.text = fullAddress;
              if (neighborhood.isNotEmpty) _neighborhoodController.text = neighborhood;
              if (streetAddress.isNotEmpty) _streetController.text = streetAddress;
            });
          }
        } else {
          debugPrint('⚠️ API sonucu başarısız: ${data['status']}');
          debugPrint('⚠️ Error message: ${data['error_message']}');
        }
      }
    } catch (e) {
      debugPrint('❌ Adres alma hatası: $e');
    }
  }

  Future<Map<String, dynamic>?> _geocode(String address) async {
    try {
      final encodedQuery = Uri.encodeComponent(address);
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json?address=$encodedQuery&key=$_googleMapsApiKey&language=tr',
      );
      final response = await http.get(url).timeout(const Duration(seconds: 10));
      final data = json.decode(response.body) as Map<String, dynamic>;
      debugPrint('🔍 Geocode "$address" -> status=${data['status']}');
      return data;
    } catch (e) {
      debugPrint('❌ Geocode isteği hatası: $e');
      return null;
    }
  }

  Future<void> _searchAddress() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    if (_googleMapsApiKey == null || !MapsApiKeyService.isValidApiKey(_googleMapsApiKey)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Harita servisi hazır değil')),
      );
      return;
    }

    setState(() => _isSearching = true);

    try {
      Map<String, dynamic>? data = await _geocode('$query, Cizre, Şırnak, Türkiye');
      if (data == null || data['status'] != 'OK' || (data['results'] as List).isEmpty) {
        // Bölge eki sonuç bulamadıysa sade sorguyla tekrar dene
        data = await _geocode(query);
      }

      if (data != null && data['status'] == 'OK' && (data['results'] as List).isNotEmpty) {
        final location = data['results'][0]['geometry']['location'];
        final lat = (location['lat'] as num).toDouble();
        final lng = (location['lng'] as num).toDouble();

        setState(() {
          _selectedLatitude = lat;
          _selectedLongitude = lng;
        });
        _updateMarker();
        _mapController?.animateCamera(CameraUpdate.newLatLngZoom(LatLng(lat, lng), 17));
        await _fetchAddressFromCoordinates(lat, lng);
      } else if (mounted) {
        final status = data?['status'] ?? 'ERROR';
        final errorMessage = data?['error_message'];
        debugPrint('❌ Geocode sonuç yok: status=$status error=$errorMessage');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Konum bulunamadı ($status)')),
        );
      }
    } catch (e) {
      debugPrint('❌ Arama hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Arama hatası: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSearching = false);
      }
    }
  }

  void _centerOnCizre() {
    _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(_defaultCizre, 15),
    );
  }

  void _saveAddress() {
    final neighborhood = _neighborhoodController.text.trim();
    final street = _streetController.text.trim();

    if (neighborhood.isEmpty || street.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen mahalle ve sokak girin')),
      );
      return;
    }

    final line1 = [
      neighborhood,
      street,
      if (_noController.text.trim().isNotEmpty) 'No:${_noController.text.trim()}',
    ].join(' ');

    final line2Parts = [
      if (_floorController.text.trim().isNotEmpty) 'Kat:${_floorController.text.trim()}',
      if (_apartmentController.text.trim().isNotEmpty) 'Daire:${_apartmentController.text.trim()}',
    ];

    final selectedAddress = Address(
      id: '',
      userId: '',
      title: 'Seçili Konum',
      fullName: '',
      phone: '',
      addressLine1: line1,
      addressLine2: line2Parts.isEmpty ? null : line2Parts.join(' '),
      city: 'Şırnak',
      district: 'Cizre',
      latitude: _selectedLatitude,
      longitude: _selectedLongitude,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    Navigator.pop(context, selectedAddress);
  }

  @override
  Widget build(BuildContext context) {
    // API key yüklenmediyse bekle
    if (!_isApiKeyLoaded) {
      return Scaffold(
        backgroundColor: Colors.grey.shade50,
        appBar: AppBar(
          title: const Text('Haritadan Adres Seç'),
          backgroundColor: Colors.purple,
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Harita yükleniyor...'),
            ],
          ),
        ),
      );
    }

    // API key yoksa hata göster
    if (_googleMapsApiKey == null || !MapsApiKeyService.isValidApiKey(_googleMapsApiKey)) {
      return Scaffold(
        backgroundColor: Colors.grey.shade50,
        appBar: AppBar(
          title: const Text('Haritadan Adres Seç'),
          backgroundColor: Colors.purple,
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.map_outlined,
                  size: 64,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Google Maps API Key\nYapılandırılmamış',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Lütfen Admin Panel > Hakkında Ayarları > API Anahtarları\nbölümünden Google Maps API Key\'i girin.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _saveAddressWithoutMap,
                  icon: const Icon(Icons.edit_location_alt),
                  label: const Text('Adresi Manuel Gir'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final initialPosition = LatLng(
      _selectedLatitude ?? _defaultCizre.latitude,
      _selectedLongitude ?? _defaultCizre.longitude,
    );

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Haritadan Adres Seç'),
        elevation: 0,
        backgroundColor: Colors.purple,
        foregroundColor: Colors.white,
        actions: [
          TextButton.icon(
            onPressed: _saveAddress,
            icon: const Icon(Icons.check, color: Colors.white),
            label: const Text(
              'Kaydet',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Google Maps
          Expanded(
            flex: 3,
            child: Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: initialPosition,
                    zoom: 15,
                  ),
                  onMapCreated: (controller) {
                    _mapController = controller;
                  },
                  onTap: _onMapTap,
                  markers: _markers,
                  myLocationEnabled: true,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: true,
                  mapToolbarEnabled: false,
                ),
                // Arama kutusu
                Positioned(
                  top: 12,
                  left: 12,
                  right: 12,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(25),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            decoration: const InputDecoration(
                              hintText: 'Adres ara...',
                              prefixIcon: Icon(Icons.search),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                            ),
                            onSubmitted: (_) => _searchAddress(),
                          ),
                        ),
                        IconButton(
                          icon: _isSearching
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.search),
                          onPressed: _isSearching ? null : _searchAddress,
                        ),
                      ],
                    ),
                  ),
                ),
                // Konum butonları
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: Column(
                    children: [
                      // Mevcut konum
                      FloatingActionButton.small(
                        heroTag: 'location',
                        onPressed: _isLoadingLocation ? null : _getCurrentLocation,
                        child: _isLoadingLocation
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.my_location),
                      ),
                      const SizedBox(height: 8),
                      // Cizre merkez
                      FloatingActionButton.small(
                        heroTag: 'cizre',
                        onPressed: _centerOnCizre,
                        child: const Icon(Icons.location_city),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Koordinat ve adres bilgisi
          Expanded(
            flex: 4,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Koordinat kartı
                  _buildCoordinatesCard(),
                  const SizedBox(height: 12),
                  // Adres girişi
                  _buildAddressCard(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoordinatesCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(13),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.location_on, color: Colors.red, size: 20),
              const SizedBox(width: 8),
              const Text(
                '📍 Koordinatlar',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const Spacer(),
              if (_selectedLatitude != null && _selectedLongitude != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check, size: 14, color: Colors.green.shade700),
                      const SizedBox(width: 4),
                      Text(
                        'Seçili',
                        style: TextStyle(
                          color: Colors.green.shade700,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildCoordinateItem(
                  'Enlem',
                  _selectedLatitude?.toStringAsFixed(6) ?? '—',
                  Icons.north,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildCoordinateItem(
                  'Boylam',
                  _selectedLongitude?.toStringAsFixed(6) ?? '—',
                  Icons.east,
                ),
              ),
            ],
          ),
          if (_selectedLatitude != null && _selectedLongitude != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  final url = 'https://www.google.com/maps?q=$_selectedLatitude,$_selectedLongitude';
                  launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                },
                icon: const Icon(Icons.map, size: 18),
                label: const Text('Google Maps\'te Aç'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCoordinateItem(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: Colors.grey.shade600),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddressCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(13),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.edit_location_alt, color: Colors.blue, size: 20),
              const SizedBox(width: 8),
              const Text(
                '📝 Adres Bilgisi',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const Spacer(),
              if (_isGeocoding)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _neighborhoodController,
            enabled: !_isGeocoding,
            decoration: InputDecoration(
              labelText: 'Mahalle',
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _streetController,
            enabled: !_isGeocoding,
            decoration: InputDecoration(
              labelText: 'Sokak / Cadde',
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _noController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'No',
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _floorController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Kat',
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _apartmentController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Daire',
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _saveAddress,
              icon: const Icon(Icons.check),
              label: const Text('Adresi Kaydet'),
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  /// API key olmadan adresi manuel kaydet
  void _saveAddressWithoutMap() {
    _saveAddress();
  }
}
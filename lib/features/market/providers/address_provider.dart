import 'package:flutter/foundation.dart';
import '../../../core/models/address_model.dart';
import '../services/address_service.dart';

class AddressProvider with ChangeNotifier {
  final AddressService _addressService = AddressService();
  final String userId;

  List<Address> _addresses = [];
  Address? _selectedAddress;
  bool _isLoading = false;
  String? _error;

  AddressProvider(this.userId) {
    loadAddresses();
  }

  List<Address> get addresses => _addresses;
  Address? get selectedAddress => _selectedAddress;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasAddresses => _addresses.isNotEmpty;

  Future<void> loadAddresses() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _addresses = await _addressService.getUserAddresses(userId);
      
      // Eğer varsayılan adres varsa seç, yoksa ilkini seç
      final defaultAddress = _addresses.firstWhere(
        (addr) => addr.isDefault,
        orElse: () => _addresses.isNotEmpty ? _addresses.first : _addresses.isNotEmpty ? _addresses[0] : Address(
          id: '',
          userId: userId,
          title: '',
          fullName: '',
          phone: '',
          addressLine1: '',
          city: '',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
      
      if (_addresses.isNotEmpty) {
        _selectedAddress = defaultAddress;
      }
      
      _error = null;
    } catch (e) {
      _error = e.toString();
      debugPrint('Adresler yüklenirken hata: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> addAddress({
    required String title,
    required String fullName,
    required String phone,
    required String addressLine1,
    String? addressLine2,
    required String city,
    String? district,
    String? postalCode,
    bool isDefault = false,
  }) async {
    try {
      final newAddress = await _addressService.addAddress(
        userId: userId,
        title: title,
        fullName: fullName,
        phone: phone,
        addressLine1: addressLine1,
        addressLine2: addressLine2,
        city: city,
        district: district,
        postalCode: postalCode,
        isDefault: isDefault,
      );

      _addresses.add(newAddress);
      
      if (isDefault || _addresses.length == 1) {
        _selectedAddress = newAddress;
      }
      
      _error = null;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> updateAddress({
    required String addressId,
    required String title,
    required String fullName,
    required String phone,
    required String addressLine1,
    String? addressLine2,
    required String city,
    String? district,
    String? postalCode,
    bool isDefault = false,
  }) async {
    try {
      final updatedAddress = await _addressService.updateAddress(
        addressId: addressId,
        userId: userId,
        title: title,
        fullName: fullName,
        phone: phone,
        addressLine1: addressLine1,
        addressLine2: addressLine2,
        city: city,
        district: district,
        postalCode: postalCode,
        isDefault: isDefault,
      );

      final index = _addresses.indexWhere((addr) => addr.id == addressId);
      if (index >= 0) {
        _addresses[index] = updatedAddress;
      }

      if (isDefault) {
        _selectedAddress = updatedAddress;
      }
      
      _error = null;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> deleteAddress(String addressId) async {
    try {
      await _addressService.deleteAddress(addressId);
      
      _addresses.removeWhere((addr) => addr.id == addressId);
      
      // Eğer silinen adres seçili adres ise, başka birini seç
      if (_selectedAddress?.id == addressId) {
        _selectedAddress = _addresses.isNotEmpty ? _addresses.first : null;
      }
      
      _error = null;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> setDefaultAddress(String addressId) async {
    try {
      await _addressService.setDefaultAddress(userId, addressId);
      
      // Local'de güncelle
      for (var addr in _addresses) {
        addr = addr.copyWith(isDefault: addr.id == addressId);
      }
      
      _selectedAddress = _addresses.firstWhere((addr) => addr.id == addressId);
      _error = null;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  void selectAddress(Address address) {
    _selectedAddress = address;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}

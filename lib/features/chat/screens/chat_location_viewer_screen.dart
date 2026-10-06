import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/chat_location_service.dart';

/// Sohbette paylaşılan konumu haritada gösterir (Görev 3.1): iğne, adres,
/// "Yol Tarifi" ve "Haritada Aç" (Google Haritalar).
class ChatLocationViewerScreen extends StatelessWidget {
  const ChatLocationViewerScreen({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.title,
    this.label,
    this.launcher,
  });

  final double latitude;
  final double longitude;

  /// Paylaşan ("Senin konumun" / "Ayşe'nin konumu").
  final String title;
  final String? label;

  /// Testler için bağlantı açıcı; varsayılan url_launcher.
  @visibleForTesting
  final Future<bool> Function(Uri uri)? launcher;

  Future<void> _open(BuildContext context, Uri uri) async {
    var opened = false;
    try {
      opened = await (launcher ??
          (u) => launchUrl(
                u,
                mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
              ))(uri);
    } catch (e) {
      debugPrint('Harita açılamadı: $e');
    }
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Harita uygulaması açılamadı.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final position = LatLng(latitude, longitude);
    final hasLabel = label != null && label!.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Column(
        children: [
          Expanded(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(target: position, zoom: 16),
              markers: {
                Marker(
                  markerId: const MarkerId('shared-location'),
                  position: position,
                  infoWindow: InfoWindow(title: hasLabel ? label!.trim() : 'Paylaşılan konum'),
                ),
              },
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
            ),
          ),
          Material(
            elevation: 8,
            color: Colors.white,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: const Color(0xFFE53935).withValues(alpha: 0.12),
                          child: const Icon(Icons.location_on, color: Color(0xFFE53935)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                hasLabel ? label!.trim() : 'Paylaşılan konum',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                ChatLocationService.formatCoordinates(latitude, longitude),
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
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
                          child: OutlinedButton.icon(
                            onPressed: () => _open(
                              context,
                              ChatLocationService.searchUri(latitude, longitude),
                            ),
                            icon: const Icon(Icons.map_outlined),
                            label: const Text('Haritada Aç'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => _open(
                              context,
                              ChatLocationService.directionsUri(latitude, longitude),
                            ),
                            icon: const Icon(Icons.directions),
                            label: const Text('Yol Tarifi'),
                            style: FilledButton.styleFrom(
                              backgroundColor: theme.colorScheme.primary,
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

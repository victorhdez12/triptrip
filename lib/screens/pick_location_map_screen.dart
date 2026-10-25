// lib/screens/pick_location_map_screen.dart
//
// Selector de ubicación por pin en el mapa (para sitios remotos que no
// están en ningún índice). Devuelve un PickedLocation con lat/lng y la
// ubicación en texto (reverse-geocoded con Nominatim).

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../services/places_catalog_service.dart';
import '../widgets/common_widgets.dart';

class PickedLocation {
  final double lat;
  final double lng;
  final String locationText;
  const PickedLocation({
    required this.lat,
    required this.lng,
    required this.locationText,
  });
}

class PickLocationMapScreen extends StatefulWidget {
  const PickLocationMapScreen({super.key});

  @override
  State<PickLocationMapScreen> createState() => _PickLocationMapScreenState();
}

class _PickLocationMapScreenState extends State<PickLocationMapScreen> {
  LatLng? _picked;
  String _locationText = '';
  bool _resolving = false;

  Future<void> _onTap(TapPosition _, LatLng point) async {
    setState(() {
      _picked = point;
      _resolving = true;
      _locationText = '';
    });
    final text = await PlacesCatalogService.reverseLocation(
        point.latitude, point.longitude);
    if (!mounted) return;
    setState(() {
      _locationText = text;
      _resolving = false;
    });
  }

  void _confirm() {
    final p = _picked;
    if (p == null) return;
    Navigator.pop(
      context,
      PickedLocation(
        lat: p.latitude,
        lng: p.longitude,
        locationText: _locationText,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF1A1A2E)),
        title: const Text('Drop a pin',
          style: TextStyle(
            color: Color(0xFF1A1A2E),
            fontWeight: FontWeight.w800,
            fontSize: 17,
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: FlutterMap(
              options: MapOptions(
                initialCenter: const LatLng(40.0, -3.7),
                initialZoom: 4,
                onTap: _onTap,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.triptrip.app',
                ),
                if (_picked != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _picked!,
                        width: 40,
                        height: 40,
                        child: const Icon(Icons.location_pin,
                            color: kOrange, size: 40),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _picked == null
                        ? 'Tap the map to drop a pin'
                        : _resolving
                            ? 'Resolving location…'
                            : _locationText.isEmpty
                                ? '${_picked!.latitude.toStringAsFixed(4)}, ${_picked!.longitude.toStringAsFixed(4)}'
                                : _locationText,
                    style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600,
                      color: Color(0xFF374151),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _picked == null || _resolving ? null : _confirm,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kPrimary,
                        disabledBackgroundColor: const Color(0xFFB7E5EE),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      child: const Text('Use this location',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

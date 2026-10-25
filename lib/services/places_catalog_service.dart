// lib/services/places_catalog_service.dart
//
// Catálogo canónico de sitios (tabla `places`):
//   • Autocomplete contra Nominatim (OpenStreetMap) — gratis, datos
//     almacenables con atribución, devuelve osm id + lat/lng.
//   • upsertCanonical: garantiza UN solo registro por sitio
//     (por osm id, o por nombre+ubicación si es manual).
//
// Nominatim pide máx. 1 req/seg → el autocomplete debe ir con debounce
// (lo aplica la pantalla). User-Agent obligatorio.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class PlaceSuggestion {
  final String name;
  final String location; // "Ciudad, País"
  final String osmKey;   // p. ej. "node/123456" — id canónico de OSM
  final double? lat;
  final double? lng;

  const PlaceSuggestion({
    required this.name,
    required this.location,
    required this.osmKey,
    this.lat,
    this.lng,
  });
}

class PlacesCatalogService {
  static final _db = Supabase.instance.client;

  // ── AUTOCOMPLETE (Nominatim) ──────────────────────────────
  static Future<List<PlaceSuggestion>> search(String query) async {
    final q = query.trim();
    if (q.length < 3) return const [];
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?q=${Uri.encodeComponent(q)}'
        '&format=jsonv2&limit=6&addressdetails=1&accept-language=en',
      );
      final res = await http.get(url, headers: {'User-Agent': 'TripTrip/1.0'});
      if (res.statusCode != 200) return const [];

      final data = jsonDecode(res.body) as List;
      return data.map((j) {
        final m = j as Map<String, dynamic>;
        final addr = m['address'] as Map<String, dynamic>? ?? const {};
        final city = addr['city'] ?? addr['town'] ?? addr['village'] ?? addr['county'] ?? '';
        final country = addr['country'] ?? '';
        final display = (m['display_name'] as String? ?? '').split(',').first.trim();
        final name = (m['name'] as String?)?.isNotEmpty == true
            ? m['name'] as String
            : display;
        return PlaceSuggestion(
          name: name,
          location: [city, country].where((s) => (s as String).isNotEmpty).join(', '),
          osmKey: '${m['osm_type']}/${m['osm_id']}',
          lat: double.tryParse(m['lat']?.toString() ?? ''),
          lng: double.tryParse(m['lon']?.toString() ?? ''),
        );
      }).where((s) => s.name.isNotEmpty).toList();
    } catch (e) {
      debugPrint('PlacesCatalogService.search error: $e');
      return const [];
    }
  }

  // ── REVERSE (coordenadas → "Ciudad, País") ────────────────
  static Future<String> reverseLocation(double lat, double lng) async {
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?lat=$lat&lon=$lng&format=json&accept-language=en',
      );
      final res = await http.get(url, headers: {'User-Agent': 'TripTrip/1.0'});
      if (res.statusCode != 200) return '';
      final addr = (jsonDecode(res.body)
          as Map<String, dynamic>)['address'] as Map<String, dynamic>?;
      if (addr == null) return '';
      final city = addr['city'] ?? addr['town'] ?? addr['village'] ?? addr['county'] ?? '';
      final country = addr['country'] ?? '';
      return [city, country].where((s) => (s as String).isNotEmpty).join(', ');
    } catch (_) {
      return '';
    }
  }

  // ── UPSERT canónico (cero duplicados por construcción) ────
  /// Devuelve el id del sitio canónico, creándolo si no existe.
  /// • Con [osmKey]: dedupe exacto por id de OSM.
  /// • Sin osmKey (manual/pin): dedupe por nombre+ubicación (lowercase).
  static Future<String?> upsertCanonical({
    String? osmKey,
    required String name,
    required String location,
    String countryFlag = '📍',
    String category = 'Activities',
    double? lat,
    double? lng,
  }) async {
    final cleanName = name.trim();
    final cleanLoc = location.trim();
    if (cleanName.isEmpty) return null;
    try {
      // 1) ¿Ya existe?
      if (osmKey != null) {
        final existing = await _db
            .from('places')
            .select('id')
            .eq('external_source', 'osm')
            .eq('external_id', osmKey)
            .maybeSingle();
        if (existing != null) return existing['id'].toString();
      } else {
        final existing = await _db
            .from('places')
            .select('id')
            .ilike('name', cleanName)
            .ilike('location', cleanLoc)
            .maybeSingle();
        if (existing != null) return existing['id'].toString();
      }

      // 2) Crear
      final res = await _db.from('places').insert({
        'external_source': osmKey != null ? 'osm' : 'manual',
        if (osmKey != null) 'external_id': osmKey,
        'name': cleanName,
        'location': cleanLoc,
        'country_flag': countryFlag,
        'category': category,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
      }).select('id').single();
      return res['id'].toString();
    } catch (e) {
      // Carrera con el índice único: otro usuario lo creó a la vez → releer.
      debugPrint('PlacesCatalogService.upsertCanonical retry: $e');
      try {
        final retry = osmKey != null
            ? await _db
                .from('places')
                .select('id')
                .eq('external_source', 'osm')
                .eq('external_id', osmKey)
                .maybeSingle()
            : await _db
                .from('places')
                .select('id')
                .ilike('name', cleanName)
                .ilike('location', cleanLoc)
                .maybeSingle();
        return retry?['id']?.toString();
      } catch (_) {
        return null;
      }
    }
  }
}

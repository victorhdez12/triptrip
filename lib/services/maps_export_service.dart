// ══════════════════════════════════════════════════════════════
// MAPS EXPORT SERVICE
// Abre la ruta de un día del itinerario en Google Maps, en orden.
// No usa API key: construye una URL de direcciones con los nombres
// de los lugares + la ciudad como texto ("Museo del Prado, Madrid").
// Google Maps resuelve cada parada y traza la ruta a pie.
// ══════════════════════════════════════════════════════════════

import 'package:url_launcher/url_launcher.dart';

import 'itinerary_service.dart'; // ItineraryPlace

class MapsExportService {
  // Google Maps admite ~9 waypoints intermedios → tope práctico de paradas.
  static const int _maxStops = 10;

  // ────────────────────────────────────────────────────────────
  // Abre en Google Maps la ruta del día (en el orden del itinerario).
  // - 0 lugares → no hace nada.
  // - 1 lugar   → abre la ubicación de ese lugar.
  // - 2+ lugares→ traza la ruta origen → paradas → destino (a pie).
  // ────────────────────────────────────────────────────────────
  static Future<void> openDayRoute(
    List<ItineraryPlace> places, {
    required String destination,
  }) async {
    // Nombres válidos, respetando el orden del día.
    final stops = places
        .map((p) => p.placeName.trim())
        .where((n) => n.isNotEmpty)
        .toList();
    if (stops.isEmpty) return;

    // Añade la ciudad para desambiguar y codifica para la URL.
    String enc(String name) {
      final full =
          destination.trim().isEmpty ? name : '$name, ${destination.trim()}';
      return Uri.encodeComponent(full);
    }

    final Uri url;
    if (stops.length == 1) {
      // Una sola parada → buscar esa ubicación.
      url = Uri.parse(
          'https://www.google.com/maps/search/?api=1&query=${enc(stops.first)}');
    } else {
      // Varias paradas → ruta con origen, destino y waypoints intermedios.
      final capped =
          stops.length > _maxStops ? stops.sublist(0, _maxStops) : stops;
      final origin = enc(capped.first);
      final dest = enc(capped.last);
      final waypoints =
          capped.sublist(1, capped.length - 1).map(enc).join('|');

      final buf = StringBuffer(
          'https://www.google.com/maps/dir/?api=1&origin=$origin&destination=$dest&travelmode=walking');
      if (waypoints.isNotEmpty) buf.write('&waypoints=$waypoints');
      url = Uri.parse(buf.toString());
    }

    // Abre la app de Google Maps (o el navegador si no está instalada).
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }
}
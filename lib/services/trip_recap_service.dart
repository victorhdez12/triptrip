// lib/services/trip_recap_service.dart
//
// Recap post-viaje: detecta viajes recién terminados y permite valorar
// sus paradas en un toque. Cada valoración genera un place_visit público
// → el feed se llena solo, sin fricción.
//
// El estado "recap hecho" se guarda en SharedPreferences
// (clave recap_done_<groupId>), sin SQL nuevo.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PendingRecap {
  final String groupId;
  final String tripName;
  final String destination;
  final List<RecapPlace> places;

  const PendingRecap({
    required this.groupId,
    required this.tripName,
    required this.destination,
    required this.places,
  });
}

class RecapPlace {
  final String placeName;
  final String category;
  const RecapPlace({required this.placeName, required this.category});
}

class TripRecapService {
  static final _db = Supabase.instance.client;

  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  /// Viajes míos ya terminados, sin recap hecho y con paradas valorables.
  static Future<List<PendingRecap>> pendingRecaps({int limit = 3}) async {
    final uid = _uid;
    if (uid == null) return const [];
    try {
      final prefs = await SharedPreferences.getInstance();
      final today = DateTime.now().toIso8601String().split('T').first;

      // Grupos donde soy miembro
      final memberships = await _db
          .from('trip_group_members')
          .select('group_id')
          .eq('firebase_uid', uid);
      final groupIds =
          (memberships as List).map((r) => r['group_id'] as String).toList();
      if (groupIds.isEmpty) return const [];

      final trips = await _db
          .from('trip_groups')
          .select('id, trip_name, destination, end_date, based_on_itinerary_id')
          .inFilter('id', groupIds)
          .lt('end_date', today)
          .order('end_date', ascending: false)
          .limit(10);

      final result = <PendingRecap>[];
      for (final t in trips as List) {
        final gid = t['id'] as String;
        if (prefs.getBool('recap_done_$gid') == true) continue;

        final places = await _placesForTrip(
          groupId: gid,
          basedOnItineraryId: t['based_on_itinerary_id'] as String?,
        );
        if (places.isEmpty) continue; // sin paradas no hay recap

        result.add(PendingRecap(
          groupId: gid,
          tripName: t['trip_name'] as String? ?? 'My Trip',
          destination: t['destination'] as String? ?? '',
          places: places,
        ));
        if (result.length >= limit) break;
      }
      return result;
    } catch (e) {
      debugPrint('TripRecapService.pendingRecaps error: $e');
      return const [];
    }
  }

  /// Paradas del viaje: del itinerario clonado (based_on_itinerary_id)
  /// o del itinerario publicado desde el viaje (source_group_id inverso).
  static Future<List<RecapPlace>> _placesForTrip({
    required String groupId,
    String? basedOnItineraryId,
  }) async {
    try {
      String? itineraryId = basedOnItineraryId;
      if (itineraryId == null) {
        // Puede haber tanto un borrador privado (getOrCreateGroupItinerary,
        // is_public=false) como una copia publicada para el mismo grupo;
        // preferimos el borrador, que es el que el grupo rellena día a día.
        final pub = await _db
            .from('user_itineraries')
            .select('id')
            .eq('source_group_id', groupId)
            .eq('is_public', false)
            .order('created_at', ascending: true)
            .limit(1)
            .maybeSingle();
        itineraryId = pub?['id']?.toString();
      }
      if (itineraryId == null) return const [];

      // itinerary_places no tiene itinerary_id directo: hay que pasar
      // primero por itinerary_days (mismo patrón que _refreshTotals).
      final days = await _db
          .from('itinerary_days')
          .select('id')
          .eq('itinerary_id', itineraryId);
      final dayIds = (days as List).map((d) => d['id'] as String).toList();
      if (dayIds.isEmpty) return const [];

      final rows = await _db
          .from('itinerary_places')
          .select('place_name, category')
          .inFilter('day_id', dayIds)
          .limit(20);

      return (rows as List)
          .map((r) => RecapPlace(
                placeName: r['place_name'] as String? ?? '',
                category: r['category'] as String? ?? 'Activities',
              ))
          .where((p) => p.placeName.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('TripRecapService._placesForTrip error: $e');
      return const [];
    }
  }

  static Future<void> markDone(String groupId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('recap_done_$groupId', true);
  }
}

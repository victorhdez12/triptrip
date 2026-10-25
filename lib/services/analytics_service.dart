// lib/services/analytics_service.dart
//
// Esqueleto de medición: los eventos que validan (o tumban) el negocio.
//
//   CORE (salud del producto)
//     • sign_up               — registro completado
//     • trip_created          — viaje creado
//     • itinerary_published   — itinerario publicado al feed
//     • itinerary_cloned      — alguien usó una ruta como base de su viaje
//     • reserve_tapped        — intención de reserva (valida afiliación)
//
//   EMBUDO DE INVITACIONES (K-factor)
//     • invite_shared         — el usuario compartió/copió su invite code
//     • invite_joined         — alguien se unió a un grupo con un código
//
//   K-factor ≈ (invite_joined por usuario activo). Si > 0.5, el grupo
//   es tu motor de crecimiento. Se mide en Firebase Analytics → Funnels
//   (invite_shared → invite_joined) y en retención por cohortes.
//
// Diseño: estáticos, nunca lanzan (un fallo de analítica jamás debe
// romper la app), parámetros mínimos y sin PII (no nombres ni emails).

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

class AnalyticsService {
  static final _fa = FirebaseAnalytics.instance;

  static Future<void> _log(String name, [Map<String, Object>? params]) async {
    try {
      await _fa.logEvent(name: name, parameters: params);
    } catch (e) {
      debugPrint('Analytics($name) error: $e');
    }
  }

  // ── CORE ──────────────────────────────────────────────────
  static Future<void> signUp() => _log('sign_up');

  static Future<void> tripCreated({
    String? groupId,
    required int guests,
    required int totalDays,
  }) =>
      _log('trip_created', {
        'group_id': groupId ?? '',
        'guests': guests,
        'total_days': totalDays,
      });

  static Future<void> itineraryPublished({
    required String itineraryId,
    required bool isPublic,
    required bool fromTrip,
  }) =>
      _log('itinerary_published', {
        'itinerary_id': itineraryId,
        'is_public': isPublic ? 1 : 0,
        'from_trip': fromTrip ? 1 : 0,
      });

  static Future<void> itineraryCloned({required String itineraryId}) =>
      _log('itinerary_cloned', {'itinerary_id': itineraryId});

  static Future<void> reserveTapped({
    required String partner,
    required String category,
  }) =>
      _log('reserve_tapped', {'partner': partner, 'category': category});

  // ── EMBUDO DE INVITACIONES ────────────────────────────────
  static Future<void> inviteShared({required String groupId}) =>
      _log('invite_shared', {'group_id': groupId});

  static Future<void> inviteJoined({required String groupId}) =>
      _log('invite_joined', {'group_id': groupId});
}

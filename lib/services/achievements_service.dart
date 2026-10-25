// lib/services/achievements_service.dart
//
// Gestiona los badges/logros del usuario.
// - El catálogo de achievements vive en código (Achievement.catalog)
// - El estado "desbloqueado" se persiste en la tabla user_achievements
//   SOLO cuando se desbloquea (filas vacías = bloqueados → ahorra espacio)
// - El cálculo de "¿está desbloqueado?" se hace localmente con los stats
//   ya cargados, así no requiere round-trips extra al servidor.

import 'package:supabase_flutter/supabase_flutter.dart';

// ══════════════════════════════════════════════════════════════
// MODELO
// ══════════════════════════════════════════════════════════════

class Achievement {
  final String key;          // 'first_flight', 'explorer_5'...
  final String emoji;
  final String title;
  final String subtitle;
  final int requirement;     // umbral numérico
  final String metric;       // 'onboarding' | 'countries' | 'groups' | 'friends'
  final List<int> gradient;  // colores RGB del badge

  const Achievement({
    required this.key,
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.requirement,
    required this.metric,
    required this.gradient,
  });

  /// Catálogo único de logros. Para añadir uno nuevo basta con
  /// añadir una entrada aquí — no requiere migración de BD.
  static const List<Achievement> catalog = [
    Achievement(
      key: 'first_flight',
      emoji: '✈️',
      title: 'First Flight',
      subtitle: 'Complete onboarding',
      requirement: 1,
      metric: 'onboarding',
      gradient: [0xFF29B6D2, 0xFF1E88B8],
    ),
    Achievement(
      key: 'explorer_5',
      emoji: '🌍',
      title: 'Explorer',
      subtitle: 'Visit 5 countries',
      requirement: 5,
      metric: 'countries',
      gradient: [0xFF66D9A8, 0xFF2A9D7C],
    ),
    Achievement(
      key: 'squad_goals',
      emoji: '👥',
      title: 'Squad Goals',
      subtitle: 'Join a group trip',
      requirement: 1,
      metric: 'groups',
      gradient: [0xFFFFB347, 0xFFFF8C42],
    ),
    Achievement(
      key: 'wanderlust_10',
      emoji: '🗺️',
      title: 'Wanderlust',
      subtitle: 'Visit 10 countries',
      requirement: 10,
      metric: 'countries',
      gradient: [0xFF9B7BFF, 0xFF6B4FE3],
    ),
    Achievement(
      key: 'social_butterfly',
      emoji: '🤝',
      title: 'Social Butterfly',
      subtitle: 'Add 5 trip friends',
      requirement: 5,
      metric: 'friends',
      gradient: [0xFFFF6B9D, 0xFFE91E63],
    ),
    Achievement(
      key: 'globetrotter_25',
      emoji: '🏆',
      title: 'Globetrotter',
      subtitle: 'Visit 25 countries',
      requirement: 25,
      metric: 'countries',
      gradient: [0xFFFFD700, 0xFFFFA500],
    ),
  ];
}

// ══════════════════════════════════════════════════════════════
// SERVICIO
// ══════════════════════════════════════════════════════════════

class AchievementsService {
  static final _db = Supabase.instance.client;

  /// Devuelve la lista de claves ya desbloqueadas para el usuario.
  static Future<Set<String>> getUnlocked(String uid) async {
    try {
      final res = await _db
          .from('user_achievements')
          .select('achievement_key')
          .eq('firebase_uid', uid);
      return (res as List)
          .map((r) => r['achievement_key'] as String)
          .toSet();
    } catch (_) {
      return <String>{};
    }
  }

  /// Llama a esto tras cargar stats — desbloquea los que correspondan
  /// y los persiste. Devuelve los nuevos desbloqueos (para mostrar toast).
  static Future<List<Achievement>> syncUnlocked({
    required String uid,
    required int countries,
    required int groups,
    required int friends,
  }) async {
    final alreadyUnlocked = await getUnlocked(uid);
    final newlyUnlocked = <Achievement>[];

    for (final a in Achievement.catalog) {
      if (alreadyUnlocked.contains(a.key)) continue;
      final met = _evaluate(a, countries: countries, groups: groups, friends: friends);
      if (met) newlyUnlocked.add(a);
    }

    if (newlyUnlocked.isNotEmpty) {
      try {
        await _db.from('user_achievements').insert(
              newlyUnlocked
                  .map((a) => {
                        'firebase_uid': uid,
                        'achievement_key': a.key,
                      })
                  .toList(),
            );
      } catch (_) {
        // Silencioso: el siguiente sync lo reintentará
      }
    }

    return newlyUnlocked;
  }

  /// Evalúa si un achievement está desbloqueado con los stats actuales.
  /// Útil para renderizar la grid sin tocar BD.
  static bool isUnlocked(
    Achievement a, {
    required int countries,
    required int groups,
    required int friends,
  }) {
    return _evaluate(a, countries: countries, groups: groups, friends: friends);
  }

  static bool _evaluate(
    Achievement a, {
    required int countries,
    required int groups,
    required int friends,
  }) {
    switch (a.metric) {
      case 'onboarding': return true; // si el usuario llegó al perfil → completó onboarding
      case 'countries':  return countries >= a.requirement;
      case 'groups':     return groups    >= a.requirement;
      case 'friends':    return friends   >= a.requirement;
      default:           return false;
    }
  }
}

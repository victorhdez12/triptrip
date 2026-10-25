// lib/services/profile_service.dart
//
// Carga todas las stats del perfil en UNA SOLA query RPC.
// Antes: 4 round-trips (groups, friends, countries, points) ≈ 600-1200ms
// Ahora: 1 round-trip                                       ≈ 150-300ms

import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileStats {
  final String displayName;
  final String instagram;
  final String tiktok;
  final String avatarUrl;
  final String bio;
  final int    points;
  final int    groupsCount;
  final int    friendsCount;
  final int    countriesCount;
  final Set<String> unlockedAchievements;

  const ProfileStats({
    required this.displayName,
    required this.instagram,
    required this.tiktok,
    this.avatarUrl = '',
    this.bio = '',
    required this.points,
    required this.groupsCount,
    required this.friendsCount,
    required this.countriesCount,
    required this.unlockedAchievements,
  });

  factory ProfileStats.fromJson(Map<String, dynamic> json) {
    return ProfileStats(
      displayName:    (json['display_name']    as String?) ?? '',
      instagram:      (json['instagram']       as String?) ?? '',
      tiktok:         (json['tiktok']          as String?) ?? '',
      avatarUrl:      (json['avatar_url']      as String?) ?? '',
      bio:            (json['bio']             as String?) ?? '',
      points:         (json['points']          as num?)?.toInt() ?? 0,
      groupsCount:    (json['groups_count']    as num?)?.toInt() ?? 0,
      friendsCount:   (json['friends_count']   as num?)?.toInt() ?? 0,
      countriesCount: (json['countries_count'] as num?)?.toInt() ?? 0,
      unlockedAchievements: ((json['unlocked_achievements'] as List?) ?? const [])
          .map((e) => e as String)
          .toSet(),
    );
  }

  static const empty = ProfileStats(
    displayName: '',
    instagram: '',
    tiktok: '',
    points: 0,
    groupsCount: 0,
    friendsCount: 0,
    countriesCount: 0,
    unlockedAchievements: <String>{},
  );
}

class ProfileService {
  static final _db = Supabase.instance.client;

  /// Llama a la función SQL `get_profile_stats(uid)` y mapea el JSON.
  /// Devuelve [ProfileStats.empty] si algo falla (no rompe la UI).
  static Future<ProfileStats> loadStats(String uid) async {
    try {
      final res = await _db.rpc('get_profile_stats', params: {'uid': uid});
      if (res is Map<String, dynamic>) {
        return ProfileStats.fromJson(res);
      }
      return ProfileStats.empty;
    } catch (_) {
      return ProfileStats.empty;
    }
  }
}
// lib/services/social_service.dart
//
// Follow / unfollow y contadores de seguidores.
// Usa firebase_uid como identificador (igual que el resto del proyecto).

import 'package:supabase_flutter/supabase_flutter.dart';

class SocialService {
  static final _db = Supabase.instance.client;

  // ── Follow / Unfollow ──────────────────────────────────────

  static Future<void> follow(String followerUid, String followingUid) async {
    try {
      await _db.from('user_follows').insert({
        'follower_uid': followerUid,
        'following_uid': followingUid,
      });
    } catch (_) {
      // Ignora UNIQUE violation si ya sigues a esta persona
    }
  }

  static Future<void> unfollow(String followerUid, String followingUid) async {
    await _db
        .from('user_follows')
        .delete()
        .eq('follower_uid', followerUid)
        .eq('following_uid', followingUid);
  }

  static Future<bool> isFollowing(
      String followerUid, String followingUid) async {
    final res = await _db
        .from('user_follows')
        .select('id')
        .eq('follower_uid', followerUid)
        .eq('following_uid', followingUid)
        .maybeSingle();
    return res != null;
  }

  // ── Contadores ─────────────────────────────────────────────

  static Future<Map<String, int>> getFollowCounts(String uid) async {
    final followers = await _db
        .from('user_follows')
        .select('id')
        .eq('following_uid', uid);
    final following = await _db
        .from('user_follows')
        .select('id')
        .eq('follower_uid', uid);
    return {
      'followers': (followers as List).length,
      'following': (following as List).length,
    };
  }

  static Future<List<String>> getFollowingUids(String uid) async {
    final res = await _db
        .from('user_follows')
        .select('following_uid')
        .eq('follower_uid', uid);
    return (res as List)
        .map((r) => r['following_uid'] as String)
        .toList();
  }

  // ── Lista de usuarios (seguidores o seguidos) con sus datos ──
  static Future<List<Map<String, dynamic>>> getFollowList(
    String uid, {
    required bool followers,
  }) async {
    try {
      final col = followers ? 'follower_uid' : 'following_uid';
      final whereCol = followers ? 'following_uid' : 'follower_uid';
      final rel =
          await _db.from('user_follows').select(col).eq(whereCol, uid);
      final uids = (rel as List)
          .map((r) => r[col].toString())
          .where((x) => x.isNotEmpty)
          .toList();
      if (uids.isEmpty) return [];
      final users = await _db
          .from('users')
          .select('firebase_uid, display_name, avatar_url, city')
          .inFilter('firebase_uid', uids);
      return (users as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  // ── Viajeros gemelos: sugerencias por afinidad de países ──
  /// Usuarios con más países visitados en común contigo, excluyendo
  /// a quienes ya sigues. Devuelve hasta [limit] sugerencias.
  static Future<List<TravelerSuggestion>> suggestTravelers(
    String uid, {
    int limit = 5,
  }) async {
    try {
      // 1) Mis países
      final mine = await _db
          .from('user_visited_countries')
          .select('country_code')
          .eq('firebase_uid', uid);
      final myCodes =
          (mine as List).map((r) => r['country_code'] as String).toSet();
      if (myCodes.isEmpty) return const [];

      // 2) Quién más ha visitado esos países
      final rows = await _db
          .from('user_visited_countries')
          .select('firebase_uid, country_code')
          .inFilter('country_code', myCodes.toList())
          .neq('firebase_uid', uid)
          .limit(500);

      final overlap = <String, int>{};
      for (final r in rows as List) {
        final u = r['firebase_uid'] as String;
        overlap[u] = (overlap[u] ?? 0) + 1;
      }
      if (overlap.isEmpty) return const [];

      // 3) Excluir a quienes ya sigo
      final following = (await getFollowingUids(uid)).toSet();
      overlap.removeWhere((u, _) => following.contains(u));
      if (overlap.isEmpty) return const [];

      // 4) Top N + nombres
      final top = overlap.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final topUids = top.take(limit).map((e) => e.key).toList();

      final users = await _db
          .from('users')
          .select('firebase_uid, display_name')
          .inFilter('firebase_uid', topUids);
      final names = <String, String>{
        for (final u in users as List)
          u['firebase_uid'] as String:
              (u['display_name'] as String?)?.isNotEmpty == true
                  ? u['display_name'] as String
                  : 'Traveler',
      };

      return topUids
          .map((u) => TravelerSuggestion(
                uid: u,
                displayName: names[u] ?? 'Traveler',
                countriesInCommon: overlap[u] ?? 0,
              ))
          .toList();
    } catch (_) {
      return const [];
    }
  }
}

class TravelerSuggestion {
  final String uid;
  final String displayName;
  final int countriesInCommon;
  const TravelerSuggestion({
    required this.uid,
    required this.displayName,
    required this.countriesInCommon,
  });
}
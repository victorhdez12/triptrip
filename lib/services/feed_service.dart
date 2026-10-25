// lib/services/feed_service.dart
//
// Feed social del Home. Se apoya en PlaceSocialService para todo lo
// que ya existe (favoritos y comentarios) y solo añade lo nuevo:
// el feed agregado, los likes y los follows.
//
// Auth: Firebase. El identificador es siempre el firebase_uid (text),
// nunca un uuid de Supabase.
//
// La agregación ocurre en Postgres (ver social_feed.sql): cinco amigos
// guardando el mismo sitio llegan como UNA fila con actorCount = 5.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'place_social_service.dart';

/// Se incrementa al publicar/despublicar contenido, para que el feed del
/// dashboard se recargue sin reiniciar la app.
final ValueNotifier<int> feedChanged = ValueNotifier<int>(0);

class FeedService {
  static final _db = Supabase.instance.client;

  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  // ── FEED ────────────────────────────────────────────────────

  static Future<List<FeedItem>> feed({int offset = 0, int limit = 20}) async {
    final uid = _uid;
    if (uid == null) return const [];
    try {
      final rows = await _db.rpc('feed_for_user', params: {
        'p_uid': uid,
        'p_limit': limit,
        'p_offset': offset,
      });
      return (rows as List)
          .map((r) => FeedItem.fromJson(Map<String, dynamic>.from(r as Map)))
          .toList();
    } catch (e) {
      debugPrint('FeedService.feed error: $e');
      return const [];
    }
  }

  // ── LIKES ───────────────────────────────────────────────────
  // Reacción ligera, distinta de favorito (guardar) y de rating
  // (valoración 1-5, que sigue viviendo solo en el detalle).

  static Future<bool> toggleLike(String placeId, bool currentlyLiked) async {
    final uid = _uid;
    if (uid == null) return currentlyLiked;
    try {
      if (currentlyLiked) {
        await _db
            .from('place_likes')
            .delete()
            .eq('firebase_uid', uid)
            .eq('place_id', placeId);
        return false;
      }
      await _db.from('place_likes').insert({
        'firebase_uid': uid,
        'place_id': placeId,
      });
      return true;
    } catch (e) {
      debugPrint('FeedService.toggleLike error: $e');
      return currentlyLiked;
    }
  }

  // ── GUARDAR EN UN VIAJE ─────────────────────────────────────
  // Delega en PlaceSocialService para no duplicar la lógica de
  // favoritos, y añade el viaje destino si lo hay.

  static Future<bool> toggleSave(
    String placeId,
    bool currentlySaved, {
    String? tripId,
  }) async {
    final uid = _uid;
    final saved =
        await PlaceSocialService.toggleFavorite(placeId, currentlySaved);
    if (saved && tripId != null && uid != null) {
      try {
        await _db
            .from('place_favorites')
            .update({'trip_id': tripId})
            .eq('firebase_uid', uid)
            .eq('place_id', placeId);
      } catch (e) {
        debugPrint('FeedService.toggleSave (trip_id) error: $e');
      }
    }
    return saved;
  }

  // ── FOLLOWS ─────────────────────────────────────────────────

  static Future<bool> isFollowing(String otherUid) async {
    final uid = _uid;
    if (uid == null) return false;
    try {
      final row = await _db
          .from('user_follows')
          .select('follower_uid')
          .eq('follower_uid', uid)
          .eq('following_uid', otherUid)
          .maybeSingle();
      return row != null;
    } catch (e) {
      debugPrint('FeedService.isFollowing error: $e');
      return false;
    }
  }

  static Future<bool> toggleFollow(
      String otherUid, bool currentlyFollowing) async {
    final uid = _uid;
    if (uid == null || uid == otherUid) return currentlyFollowing;
    try {
      if (currentlyFollowing) {
        await _db
            .from('user_follows')
            .delete()
            .eq('follower_uid', uid)
            .eq('following_uid', otherUid);
        return false;
      }
      await _db.from('user_follows').insert({
        'follower_uid': uid,
        'following_uid': otherUid,
      });
      return true;
    } catch (e) {
      debugPrint('FeedService.toggleFollow error: $e');
      return currentlyFollowing;
    }
  }

  static Future<int> followingCount() async {
    final uid = _uid;
    if (uid == null) return 0;
    try {
      final rows = await _db
          .from('user_follows')
          .select('following_uid')
          .eq('follower_uid', uid);
      return (rows as List).length;
    } catch (e) {
      debugPrint('FeedService.followingCount error: $e');
      return 0;
    }
  }

  // ── PRÓXIMO VIAJE ───────────────────────────────────────────
  // El esquema real de viajes es trip_groups / trip_group_members
  // (el mismo que usan GroupsScreen y TripDetailScreen), no trips/
  // trip_members. Si falla, devuelve null y el Home muestra el CTA
  // de crear viaje.

  static Future<Map<String, dynamic>?> nextTrip() async {
    final uid = _uid;
    if (uid == null) return null;
    try {
      final rows = await _db
          .from('trip_group_members')
          .select(
              'trip_groups!inner(id, trip_name, destination, start_date, end_date, invite_code)')
          .eq('firebase_uid', uid)
          .gte('trip_groups.end_date', DateTime.now().toIso8601String())
          .order('start_date', referencedTable: 'trip_groups', ascending: true)
          .limit(1);
      if ((rows as List).isEmpty) return null;
      return Map<String, dynamic>.from(rows.first['trip_groups'] as Map);
    } catch (e) {
      debugPrint('FeedService.nextTrip error: $e');
      return null;
    }
  }

  /// Sitios ya guardados en ese viaje: alimenta el contador de la
  /// tarjeta de próximo viaje.
  static Future<int> savedInTrip(String tripId) async {
    try {
      final rows = await _db
          .from('place_favorites')
          .select('place_id')
          .eq('trip_id', tripId);
      return (rows as List).length;
    } catch (e) {
      debugPrint('FeedService.savedInTrip error: $e');
      return 0;
    }
  }

  // ── PERFIL PÚBLICO ──────────────────────────────────────────
  // Posts públicos de un usuario concreto (visitas + itinerarios),
  // para pintar la cuadrícula de PublicProfileScreen. No usa el RPC
  // agregado (ese es para el feed del viewer, no para "sus" posts).

  static Future<List<FeedItem>> getUserPosts(String uid) async {
    try {
      final visits = await _db
          .from('place_visits')
          .select()
          .eq('user_uid', uid)
          .eq('is_public', true)
          .order('created_at', ascending: false)
          .limit(20);

      final itineraries = await _db
          .from('user_itineraries')
          .select()
          .eq('user_uid', uid)
          .eq('is_public', true)
          .order('created_at', ascending: false)
          .limit(10);

      final items = <FeedItem>[
        for (final v in visits as List)
          FeedItem.fromPost(Map<String, dynamic>.from(v as Map), type: 'visit'),
        for (final v in itineraries as List)
          FeedItem.fromPost(Map<String, dynamic>.from(v as Map),
              type: 'itinerary'),
      ]..sort((a, b) => b.lastAt.compareTo(a.lastAt));

      await _attachVisitMedia(items);
      return items;
    } catch (e) {
      debugPrint('FeedService.getUserPosts error: $e');
      return const [];
    }
  }

  // Carga en lote las fotos (post_media) de las visitas y las adjunta
  // como data['media'] = [url,...] → carrusel sin N+1.
  static Future<void> _attachVisitMedia(List<FeedItem> items) async {
    final ids = <String>[];
    for (final it in items) {
      if (it.verb == 'visit') {
        final id = it.data['id']?.toString();
        if (id != null && id.isNotEmpty) ids.add(id);
      }
    }
    if (ids.isEmpty) return;
    try {
      final rows = await _db
          .from('post_media')
          .select('parent_id, url, position')
          .eq('parent_type', 'visit')
          .inFilter('parent_id', ids)
          .order('position', ascending: true);
      final byParent = <String, List<String>>{};
      for (final r in (rows as List)) {
        final pid = r['parent_id'].toString();
        (byParent[pid] ??= <String>[]).add(r['url'] as String);
      }
      for (final it in items) {
        if (it.verb == 'visit') {
          final id = it.data['id']?.toString() ?? '';
          final urls = byParent[id];
          if (urls != null && urls.isNotEmpty) it.data['media'] = urls;
        }
      }
    } catch (e) {
      debugPrint('FeedService._attachVisitMedia error: $e');
    }
  }
}

// ══════════════════════════════════════════════════════════════
// MODELO
// ══════════════════════════════════════════════════════════════

class FeedItem {
  final String groupKey;
  final String verb; // save | like | comment | publish
  final String placeId;
  final String placeName;
  final String location;
  final String category;
  final String countryFlag;
  final List<String> actorNames;
  final int actorCount;

  final int likesCount;
  final int commentsCount;
  final int favoritesCount;
  final bool likedByMe;
  final bool savedByMe;

  final DateTime lastAt;

  /// Fila cruda de origen (place_visits / user_itineraries / feed_for_user).
  /// La usan pantallas como PublicProfileScreen que necesitan campos que
  /// no forman parte del modelo agregado (media, cover_image_url, ...).
  final Map<String, dynamic> data;

  const FeedItem({
    required this.groupKey,
    required this.verb,
    required this.placeId,
    required this.placeName,
    required this.location,
    required this.category,
    required this.countryFlag,
    required this.actorNames,
    required this.actorCount,
    required this.likesCount,
    required this.commentsCount,
    required this.favoritesCount,
    required this.likedByMe,
    required this.savedByMe,
    required this.lastAt,
    this.data = const {},
  });

  factory FeedItem.fromJson(Map<String, dynamic> j) => FeedItem(
        groupKey: j['group_key']?.toString() ?? '',
        verb: j['verb']?.toString() ?? 'save',
        placeId: j['place_id']?.toString() ?? '',
        placeName: j['place_name'] as String? ?? '',
        location: j['location'] as String? ?? '',
        category: j['category'] as String? ?? '',
        countryFlag: j['country_flag'] as String? ?? '📍',
        actorNames: List<String>.from((j['actor_names'] as List?) ?? const []),
        actorCount: (j['actor_count'] as num?)?.toInt() ?? 1,
        likesCount: (j['likes_count'] as num?)?.toInt() ?? 0,
        commentsCount: (j['comments_count'] as num?)?.toInt() ?? 0,
        favoritesCount: (j['favorites_count'] as num?)?.toInt() ?? 0,
        likedByMe: j['liked_by_me'] == true,
        savedByMe: j['saved_by_me'] == true,
        lastAt: DateTime.tryParse(j['last_at']?.toString() ?? '') ??
            DateTime.now(),
        data: j,
      );

  /// Construye un FeedItem a partir de una fila cruda de place_visits o
  /// user_itineraries (perfil público de un usuario), no del feed agregado.
  factory FeedItem.fromPost(Map<String, dynamic> j, {required String type}) =>
      FeedItem(
        groupKey: '$type:${j['id'] ?? ''}',
        verb: type, // 'visit' | 'itinerary'
        placeId: j['place_id']?.toString() ?? '',
        placeName:
            j['place_name'] as String? ?? j['title'] as String? ?? '',
        location: j['location'] as String? ?? '',
        category: j['category'] as String? ?? '',
        countryFlag: j['country_flag'] as String? ?? '📍',
        actorNames: const [],
        actorCount: 1,
        likesCount: 0,
        commentsCount: (j['comments_count'] as num?)?.toInt() ?? 0,
        favoritesCount: 0,
        likedByMe: false,
        savedByMe: false,
        lastAt: DateTime.tryParse(j['created_at']?.toString() ?? '') ??
            DateTime.now(),
        data: j,
      );

  /// "Ana, Diego y Marta lo guardaron" · "Sara y 6 más lo guardaron"
  String get headline {
    if (actorNames.isEmpty) return 'Actividad nueva';

    if (verb == 'publish') return '${actorNames.first} estuvo aquí';
    if (verb == 'comment') return '${actorNames.first} comentó';

    if (actorCount == 1) {
      return verb == 'like'
          ? 'A ${actorNames.first} le gusta esto'
          : '${actorNames.first} lo guardó';
    }

    // Hasta 3 caben todos los nombres; a partir de 4, dos y un contador.
    final String who;
    if (actorCount <= 3 && actorNames.length == actorCount) {
      final visible = actorNames.toList();
      final last = visible.removeLast();
      who = '${visible.join(', ')} y $last';
    } else {
      final visible = actorNames.take(2).toList();
      who = '${visible.join(', ')} y ${actorCount - visible.length} más';
    }

    return verb == 'like' ? 'A $who les gusta esto' : '$who lo guardaron';
  }

  bool get isTrending => actorCount >= 4;
}

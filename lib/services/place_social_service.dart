// lib/services/place_social_service.dart
//
// Capa social para lugares/restaurantes (tabla place_visits):
//   • Favoritos (toggle)         → place_favorites
//   • Ratings 1-5 (upsert)       → place_ratings   (1 por usuario, editable)
//   • Comentarios (add/list/del) → place_comments
//   • Detalle (card + flags del viewer)
//
// Diseño idéntico a ItineraryService:
//   static _db + métodos estáticos + Model.fromJson.
//   Los comentarios denormalizan display_name/avatar_color en la fila.
//   getDetail calcula contadores en vivo → es correcto AUNQUE no haya
//   triggers todavía. Los contadores de place_visits (favorites_count,
//   ratings_count, comments_count, avg_rating) los mantienen los triggers
//   del SQL para que las tarjetas de listado salgan rápidas.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ══════════════════════════════════════════════════════════════
// MODELOS
// ══════════════════════════════════════════════════════════════

class PlaceCard {
  final String id;
  final String userUid;
  final String displayName;
  final String avatarColor;
  final String placeName;
  final String location;
  final String countryFlag;
  final String category;
  final double authorRating; // valoración del propio autor del post
  final String? note;
  final int favoritesCount;
  final int ratingsCount;
  final int commentsCount;
  final double avgRating; // media de valoraciones de OTROS usuarios
  final bool isFavorited;
  final DateTime createdAt;

  const PlaceCard({
    required this.id,
    required this.userUid,
    required this.displayName,
    required this.avatarColor,
    required this.placeName,
    required this.location,
    required this.countryFlag,
    required this.category,
    required this.authorRating,
    this.note,
    required this.favoritesCount,
    required this.ratingsCount,
    required this.commentsCount,
    required this.avgRating,
    required this.isFavorited,
    required this.createdAt,
  });

  factory PlaceCard.fromJson(Map<String, dynamic> j) => PlaceCard(
        id:             j['id']?.toString() ?? '',
        userUid:        j['user_uid'] as String? ?? '',
        displayName:    j['display_name'] as String? ?? 'Traveler',
        avatarColor:    j['avatar_color'] as String? ?? '#29B6D2',
        // 'place_name' en place_visits · 'name' en places (canónico)
        placeName:      j['place_name'] as String? ?? j['name'] as String? ?? '',
        location:       j['location'] as String? ?? '',
        countryFlag:    j['country_flag'] as String? ?? '📍',
        category:       j['category'] as String? ?? '',
        authorRating:   (j['rating']           as num?)?.toDouble() ?? 0,
        note:           j['note'] as String?,
        favoritesCount: (j['favorites_count']  as num?)?.toInt() ?? 0,
        ratingsCount:   (j['ratings_count']    as num?)?.toInt() ?? 0,
        commentsCount:  (j['comments_count']   as num?)?.toInt() ?? 0,
        avgRating:      (j['avg_rating']       as num?)?.toDouble() ?? 0,
        isFavorited:    j['is_favorited'] == true,
        createdAt:      DateTime.tryParse(j['created_at']?.toString() ?? '') ?? DateTime.now(),
      );
}

class PlaceDetail {
  final PlaceCard card;
  final int? viewerRating; // null si el usuario aún no ha votado
  final bool viewerFavorited;

  const PlaceDetail({
    required this.card,
    this.viewerRating,
    required this.viewerFavorited,
  });
}

class PlaceComment {
  final String id;
  final String userUid;
  final String displayName;
  final String avatarColor;
  final String body;
  final DateTime createdAt;

  const PlaceComment({
    required this.id,
    required this.userUid,
    required this.displayName,
    required this.avatarColor,
    required this.body,
    required this.createdAt,
  });

  factory PlaceComment.fromJson(Map<String, dynamic> j) => PlaceComment(
        id:          j['id']?.toString() ?? '',
        userUid:     j['firebase_uid'] as String? ?? '',
        displayName: j['display_name'] as String? ?? 'Traveler',
        avatarColor: j['avatar_color'] as String? ?? '#29B6D2',
        body:        j['body'] as String? ?? '',
        createdAt:   DateTime.tryParse(j['created_at']?.toString() ?? '') ?? DateTime.now(),
      );
}

// ══════════════════════════════════════════════════════════════
// SERVICIO
// ══════════════════════════════════════════════════════════════

class PlaceSocialService {
  static final _db = Supabase.instance.client;

  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  // ── MIS FAVORITOS ─────────────────────────────────────────
  // Catálogo de lugares reales, paginado y por categoría (Explore).
  // Ordena por popularidad (guardados, luego valoraciones). Devuelve mapas
  // crudos con las claves que espera la tarjeta de Explore.
  static Future<List<Map<String, dynamic>>> listCatalog({
    String category = 'All',
    String location = '',
    int offset = 0,
    int limit = 20,
  }) async {
    try {
      var q = _db.from('places').select();
      if (category != 'All' && category.isNotEmpty) {
        q = q.eq('category', category);
      }
      final loc = location.split(',').first.trim();
      if (loc.isNotEmpty) {
        q = q.ilike('location', '%' + loc + '%');
      }
      final res = await q
          .order('favorites_count', ascending: false)
          .order('ratings_count', ascending: false)
          .range(offset, offset + limit - 1);
      return (res as List).map((r) {
        final m = Map<String, dynamic>.from(r as Map);
        m['visitors'] = (m['favorites_count'] as num?)?.toInt() ?? 0;
        return m;
      }).toList();
    } catch (e) {
      debugPrint('listCatalog error: $e');
      return [];
    }
  }

  static Future<List<PlaceCard>> listFavorites() async {
    final uid = _uid;
    if (uid == null) return const [];
    try {
      final favs = await _db
          .from('place_favorites')
          .select('place_id, created_at')
          .eq('firebase_uid', uid)
          .order('created_at', ascending: false);

      final ids = (favs as List).map((r) => r['place_id'] as String).toList();
      if (ids.isEmpty) return const [];

      final places =
          await _db.from('places').select().inFilter('id', ids);

      return (places as List)
          .map((r) => PlaceCard.fromJson(
              {...r as Map<String, dynamic>, 'is_favorited': true}))
          .toList();
    } catch (e) {
      debugPrint('PlaceSocialService.listFavorites error: $e');
      return const [];
    }
  }

  // ── IDs de mis favoritos (para pintar el ❤ en listados) ──
  static Future<Set<String>> listFavoriteIds() async {
    final uid = _uid;
    if (uid == null) return <String>{};
    try {
      final favs = await _db
          .from('place_favorites')
          .select('place_id')
          .eq('firebase_uid', uid);
      return (favs as List).map((r) => r['place_id'] as String).toSet();
    } catch (e) {
      debugPrint('PlaceSocialService.listFavoriteIds error: $e');
      return <String>{};
    }
  }

  // ── DETALLE (sitio canónico + contexto del último visitante) ──
  static Future<PlaceDetail?> getDetail(String placeId) async {
    try {
      final row = await _db
          .from('places')
          .select()
          .eq('id', placeId)
          .maybeSingle();
      if (row == null) return null;

      // Última visita: aporta autor/nota/valoración como contexto humano
      final lastVisit = await _db
          .from('place_visits')
          .select('user_uid, display_name, avatar_color, note, rating, created_at')
          .eq('place_id', placeId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      final uid = _uid;
      bool viewerFav = false;
      int? viewerRating;
      if (uid != null) {
        final fav = await _db
            .from('place_favorites')
            .select('id')
            .eq('firebase_uid', uid)
            .eq('place_id', placeId)
            .maybeSingle();
        viewerFav = fav != null;

        final r = await _db
            .from('place_ratings')
            .select('stars')
            .eq('firebase_uid', uid)
            .eq('place_id', placeId)
            .maybeSingle();
        viewerRating = (r?['stars'] as num?)?.toInt();
      }

      // Los contadores ya viven denormalizados en `places` (triggers).
      final card = PlaceCard.fromJson({
        ...row,
        if (lastVisit != null) ...{
          'user_uid':     lastVisit['user_uid'],
          'display_name': lastVisit['display_name'],
          'avatar_color': lastVisit['avatar_color'],
          'note':         lastVisit['note'],
          'rating':       lastVisit['rating'],
          'created_at':   lastVisit['created_at'],
        },
        'is_favorited': viewerFav,
      });

      return PlaceDetail(
        card: card,
        viewerRating: viewerRating,
        viewerFavorited: viewerFav,
      );
    } catch (e) {
      debugPrint('PlaceSocialService.getDetail error: $e');
      return null;
    }
  }

  // ── FAVORITOS: toggle ─────────────────────────────────────
  static Future<bool> toggleFavorite(
      String placeId, bool currentlyFavorited) async {
    final uid = _uid;
    if (uid == null) return currentlyFavorited;
    try {
      if (currentlyFavorited) {
        await _db
            .from('place_favorites')
            .delete()
            .eq('firebase_uid', uid)
            .eq('place_id', placeId);
        return false;
      } else {
        await _db.from('place_favorites').insert({
          'firebase_uid': uid,
          'place_id': placeId,
        });
        return true;
      }
    } catch (e) {
      debugPrint('PlaceSocialService.toggleFavorite error: $e');
      return currentlyFavorited;
    }
  }

  // ── RATINGS: upsert ───────────────────────────────────────
  /// stars: 1..5. Si ya existía un rating del usuario, lo actualiza.
  static Future<bool> rate(String placeId, int stars) async {
    final uid = _uid;
    if (uid == null) return false;
    if (stars < 1 || stars > 5) return false;
    try {
      await _db.from('place_ratings').upsert({
        'firebase_uid': uid,
        'place_id':     placeId,
        'stars':        stars,
        'updated_at':   DateTime.now().toIso8601String(),
      }, onConflict: 'firebase_uid,place_id');
      return true;
    } catch (e) {
      debugPrint('PlaceSocialService.rate error: $e');
      return false;
    }
  }

  static Future<bool> removeRating(String placeId) async {
    final uid = _uid;
    if (uid == null) return false;
    try {
      await _db
          .from('place_ratings')
          .delete()
          .eq('firebase_uid', uid)
          .eq('place_id', placeId);
      return true;
    } catch (e) {
      debugPrint('PlaceSocialService.removeRating error: $e');
      return false;
    }
  }

  // ── COMMENTS ──────────────────────────────────────────────
  static Future<List<PlaceComment>> listComments(String placeId,
      {int limit = 50}) async {
    try {
      final res = await _db
          .from('place_comments')
          .select()
          .eq('place_id', placeId)
          .order('created_at', ascending: false)
          .limit(limit);
      return (res as List)
          .map((r) => PlaceComment.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('PlaceSocialService.listComments error: $e');
      return const [];
    }
  }

  static Future<PlaceComment?> addComment(
    String placeId,
    String body, {
    required String displayName,
    required String avatarColor,
  }) async {
    final uid = _uid;
    if (uid == null) return null;
    final clean = body.trim();
    if (clean.isEmpty) return null;
    try {
      final res = await _db.from('place_comments').insert({
        'place_id':     placeId,
        'firebase_uid': uid,
        'display_name': displayName,
        'avatar_color': avatarColor,
        'body':         clean,
      }).select().single();
      return PlaceComment.fromJson(res);
    } catch (e) {
      debugPrint('PlaceSocialService.addComment error: $e');
      return null;
    }
  }

  static Future<bool> deleteComment(String commentId) async {
    final uid = _uid;
    if (uid == null) return false;
    try {
      await _db
          .from('place_comments')
          .delete()
          .eq('id', commentId)
          .eq('firebase_uid', uid); // solo el autor lo borra
      return true;
    } catch (e) {
      debugPrint('PlaceSocialService.deleteComment error: $e');
      return false;
    }
  }
}
// lib/services/itinerary_service.dart
//
// Gestiona TODA la lógica de itinerarios sociales:
//   • Listar feed público (sorted: recent/top/trending)
//   • Detalle completo con días + lugares
//   • Publicar itinerario (desde cero o desde un viaje existente)
//   • Favoritos (toggle)
//   • Ratings (upsert, 1 por usuario, editable)
//   • Comentarios (add/list/delete)
//   • Clonar itinerario → crea un trip_group nuevo con atribución
//
// Diseño:
//   • Las queries pesadas (detalle, feed) van vía RPC → 1 round-trip
//   • Las acciones simples (favoritar, comentar) son inserts directos
//   • Los counters se actualizan SOLOS vía triggers SQL — el cliente
//     no tiene que recalcular nada después de un favoritar/comentar

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ══════════════════════════════════════════════════════════════
// MODELOS
// ══════════════════════════════════════════════════════════════

class ItineraryCard {
  final String id;
  final String userUid;
  final String displayName;
  final String avatarColor;
  final String title;
  final String destination;
  final String countryFlag;
  final String? coverImageUrl;
  final int totalDays;
  final int totalPlaces;
  final int favoritesCount;
  final int commentsCount;
  final int clonesCount;
  final int ratingsCount;
  final double avgRating;
  final bool isFavorited;
  final DateTime createdAt;
  final int groupSize;
  final double budgetPerPerson;
  final String currency;

  const ItineraryCard({
    required this.id,
    required this.userUid,
    required this.displayName,
    required this.avatarColor,
    required this.title,
    required this.destination,
    required this.countryFlag,
    this.coverImageUrl,
    required this.totalDays,
    required this.totalPlaces,
    required this.favoritesCount,
    required this.commentsCount,
    required this.clonesCount,
    required this.ratingsCount,
    required this.avgRating,
    required this.isFavorited,
    required this.createdAt,
    this.groupSize = 0,
    this.budgetPerPerson = 0,
    this.currency = '€',
  });

  factory ItineraryCard.fromJson(Map<String, dynamic> j) => ItineraryCard(
        id:             j['id']?.toString() ?? '',
        userUid:        j['user_uid'] as String? ?? '',
        displayName:    j['display_name'] as String? ?? 'Traveler',
        avatarColor:    j['avatar_color'] as String? ?? '#29B6D2',
        title:          j['title'] as String? ?? '',
        destination:    j['destination'] as String? ?? '',
        countryFlag:    j['country_flag'] as String? ?? '📍',
        coverImageUrl:  j['cover_image_url'] as String?,
        totalDays:      (j['total_days']      as num?)?.toInt() ?? 1,
        totalPlaces:    (j['total_places']    as num?)?.toInt() ?? 0,
        favoritesCount: (j['favorites_count'] as num?)?.toInt() ?? 0,
        commentsCount:  (j['comments_count']  as num?)?.toInt() ?? 0,
        clonesCount:    (j['clones_count']    as num?)?.toInt() ?? 0,
        ratingsCount:   (j['ratings_count']   as num?)?.toInt() ?? 0,
        avgRating:      (j['avg_rating']      as num?)?.toDouble() ?? 0,
        isFavorited:    j['is_favorited'] == true,
        groupSize:        (j['group_size']        as num?)?.toInt() ?? 0,
        budgetPerPerson:  (j['budget_per_person']  as num?)?.toDouble() ?? 0,
        currency:         j['currency'] as String? ?? '€',
        createdAt:      DateTime.tryParse(j['created_at']?.toString() ?? '') ?? DateTime.now(),
      );
}

class ItineraryDay {
  final String id;
  final int    dayNumber;
  final String title;
  final String? notes;
  final List<ItineraryPlace> places;

  const ItineraryDay({
    required this.id,
    required this.dayNumber,
    required this.title,
    this.notes,
    required this.places,
  });

  factory ItineraryDay.fromJson(Map<String, dynamic> j) => ItineraryDay(
        id:        j['id']?.toString() ?? '',
        dayNumber: (j['day_number'] as num?)?.toInt() ?? 1,
        title:     j['title'] as String? ?? '',
        notes:     j['notes'] as String?,
        places: ((j['places'] as List?) ?? const [])
            .map((p) => ItineraryPlace.fromJson(p as Map<String, dynamic>))
            .toList(),
      );
}

class ItineraryPlace {
  final String id;
  final int    position;
  final String placeName;
  final String category;
  final String? timeLabel;
  final String? note;

  const ItineraryPlace({
    required this.id,
    required this.position,
    required this.placeName,
    required this.category,
    this.timeLabel,
    this.note,
  });

  factory ItineraryPlace.fromJson(Map<String, dynamic> j) => ItineraryPlace(
        id:        j['id']?.toString() ?? '',
        position:  (j['position'] as num?)?.toInt() ?? 0,
        placeName: j['place_name'] as String? ?? '',
        category:  j['category']   as String? ?? 'Activities',
        timeLabel: j['time_label'] as String?,
        note:      j['note']       as String?,
      );
}

class ItineraryDetail {
  final ItineraryCard card;
  final List<ItineraryDay> days;
  final int? viewerRating;       // null si el usuario aún no ha votado
  final bool viewerFavorited;

  const ItineraryDetail({
    required this.card,
    required this.days,
    this.viewerRating,
    required this.viewerFavorited,
  });
}

class ItineraryComment {
  final String id;
  final String userUid;
  final String displayName;
  final String avatarColor;
  final String body;
  final DateTime createdAt;

  const ItineraryComment({
    required this.id,
    required this.userUid,
    required this.displayName,
    required this.avatarColor,
    required this.body,
    required this.createdAt,
  });

  factory ItineraryComment.fromJson(Map<String, dynamic> j) => ItineraryComment(
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

class ItineraryService {
  static final _db = Supabase.instance.client;

  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  // ── FEED PÚBLICO ──────────────────────────────────────────
  /// sort: 'recent' | 'top' | 'trending'
  static Future<List<ItineraryCard>> listPublic({
    String sort = 'recent',
    int pageSize = 20,
    DateTime? pageAfter,
  }) async {
    try {
      final res = await _db.rpc('list_public_itineraries', params: {
        'viewer_uid': _uid,
        'sort_mode':  sort,
        'page_size':  pageSize,
        'page_after': pageAfter?.toIso8601String(),
      });
      if (res is List) {
        return res
            .map((e) => ItineraryCard.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      return const [];
    } catch (e) {
      debugPrint('listPublic error: $e');
      return const [];
    }
  }

  // ── MIS FAVORITOS ─────────────────────────────────────────
  static Future<List<ItineraryCard>> listFavorites() async {
    final uid = _uid;
    if (uid == null) return const [];
    try {
      final favs = await _db
          .from('itinerary_favorites')
          .select('itinerary_id, created_at')
          .eq('firebase_uid', uid)
          .order('created_at', ascending: false);

      final ids = (favs as List).map((r) => r['itinerary_id'] as String).toList();
      if (ids.isEmpty) return const [];

      final itins = await _db
          .from('user_itineraries')
          .select()
          .inFilter('id', ids);

      return (itins as List)
          .map((r) => ItineraryCard.fromJson({...r as Map<String, dynamic>, 'is_favorited': true}))
          .toList();
    } catch (e) {
      debugPrint('listFavorites error: $e');
      return const [];
    }
  }

  // ── MIS ITINERARIOS (publicados o borradores) ─────────────
  static Future<List<ItineraryCard>> listMine({bool onlyPublic = false}) async {
    final uid = _uid;
    if (uid == null) return const [];
    try {
      var q = _db.from('user_itineraries').select().eq('user_uid', uid);
      if (onlyPublic) q = q.eq('is_public', true);
      final res = await q.order('created_at', ascending: false);
      return (res as List)
          .map((r) => ItineraryCard.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('listMine error: $e');
      return const [];
    }
  }

  // ── ITINERARIOS PÚBLICOS DE OTRO USUARIO (perfil ajeno) ───
  static Future<List<ItineraryCard>> listByUser(String uid) async {
    try {
      final res = await _db
          .from('user_itineraries')
          .select()
          .eq('user_uid', uid)
          .eq('is_public', true)
          .order('created_at', ascending: false);
      return (res as List)
          .map((r) => ItineraryCard.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('listByUser error: $e');
      return const [];
    }
  }

  // ── DETALLE COMPLETO ──────────────────────────────────────
  static Future<ItineraryDetail?> getDetail(String itineraryId) async {
    try {
      final res = await _db.rpc('get_itinerary_detail', params: {
        'itin_id':    itineraryId,
        'viewer_uid': _uid,
      });
      if (res is! Map<String, dynamic>) return null;

      final itin = res['itinerary'] as Map<String, dynamic>?;
      if (itin == null) return null;

      // Aseguramos el flag is_favorited en el card
      itin['is_favorited'] = res['viewer_favorited'] == true;

      final card = ItineraryCard.fromJson(itin);
      final days = ((res['days'] as List?) ?? const [])
          .map((d) => ItineraryDay.fromJson(d as Map<String, dynamic>))
          .toList();

      return ItineraryDetail(
        card: card,
        days: days,
        viewerRating:    (res['viewer_rating'] as num?)?.toInt(),
        viewerFavorited: res['viewer_favorited'] == true,
      );
    } catch (e) {
      debugPrint('getDetail error: $e');
      return null;
    }
  }

  // ── FAVORITOS: toggle ─────────────────────────────────────
  static Future<bool> toggleFavorite(String itineraryId, bool currentlyFavorited) async {
    final uid = _uid;
    if (uid == null) return currentlyFavorited;
    try {
      if (currentlyFavorited) {
        await _db.from('itinerary_favorites')
            .delete()
            .eq('firebase_uid', uid)
            .eq('itinerary_id', itineraryId);
        return false;
      } else {
        await _db.from('itinerary_favorites').insert({
          'firebase_uid': uid,
          'itinerary_id': itineraryId,
        });
        return true;
      }
    } catch (e) {
      debugPrint('toggleFavorite error: $e');
      return currentlyFavorited;
    }
  }

  // ── RATINGS: upsert ───────────────────────────────────────
  /// stars: 1..5. Si ya existía un rating del usuario, lo actualiza.
  static Future<bool> rate(String itineraryId, int stars) async {
    final uid = _uid;
    if (uid == null) return false;
    if (stars < 1 || stars > 5) return false;
    try {
      await _db.from('itinerary_ratings').upsert({
        'firebase_uid': uid,
        'itinerary_id': itineraryId,
        'stars':        stars,
        'updated_at':   DateTime.now().toIso8601String(),
      }, onConflict: 'firebase_uid,itinerary_id');
      return true;
    } catch (e) {
      debugPrint('rate error: $e');
      return false;
    }
  }

  static Future<bool> removeRating(String itineraryId) async {
    final uid = _uid;
    if (uid == null) return false;
    try {
      await _db.from('itinerary_ratings')
          .delete()
          .eq('firebase_uid', uid)
          .eq('itinerary_id', itineraryId);
      return true;
    } catch (e) {
      debugPrint('removeRating error: $e');
      return false;
    }
  }

  // ── COMMENTS ──────────────────────────────────────────────
  static Future<List<ItineraryComment>> listComments(String itineraryId, {int limit = 50}) async {
    try {
      final res = await _db
          .from('itinerary_comments')
          .select()
          .eq('itinerary_id', itineraryId)
          .order('created_at', ascending: false)
          .limit(limit);
      return (res as List)
          .map((r) => ItineraryComment.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('listComments error: $e');
      return const [];
    }
  }

  static Future<ItineraryComment?> addComment(
    String itineraryId,
    String body, {
    required String displayName,
    required String avatarColor,
  }) async {
    final uid = _uid;
    if (uid == null) return null;
    final clean = body.trim();
    if (clean.isEmpty) return null;
    try {
      final res = await _db.from('itinerary_comments').insert({
        'itinerary_id': itineraryId,
        'firebase_uid': uid,
        'display_name': displayName,
        'avatar_color': avatarColor,
        'body':         clean,
      }).select().single();
      return ItineraryComment.fromJson(res);
    } catch (e) {
      debugPrint('addComment error: $e');
      return null;
    }
  }

  static Future<bool> deleteComment(String commentId) async {
    final uid = _uid;
    if (uid == null) return false;
    try {
      await _db.from('itinerary_comments')
          .delete()
          .eq('id', commentId)
          .eq('firebase_uid', uid);  // solo el autor lo borra
      return true;
    } catch (e) {
      debugPrint('deleteComment error: $e');
      return false;
    }
  }

  // ── PUBLICAR un itinerario nuevo (vacío) ──────────────────
  /// Devuelve el id del itinerario creado, o null si falla.
  static Future<String?> publishEmpty({
    required String title,
    required String destination,
    String countryFlag = '📍',
    String? description,
    String? coverImageUrl,
    bool isPublic = true,
    required String displayName,
    required String avatarColor,
  }) async {
    final uid = _uid;
    if (uid == null) return null;
    try {
      final res = await _db.from('user_itineraries').insert({
        'user_uid':         uid,
        'display_name':     displayName,
        'avatar_color':     avatarColor,
        'title':            title.trim(),
        'destination':      destination.trim(),
        'country_flag':     countryFlag,
        'description':      description?.trim(),
        'cover_image_url':  coverImageUrl,
        'is_public':        isPublic,
        'published_at':     isPublic ? DateTime.now().toIso8601String() : null,
      }).select('id').single();
      return res['id']?.toString();
    } catch (e) {
      debugPrint('publishEmpty error: $e');
      return null;
    }
  }

  // ── PUBLICAR a partir de un trip_group existente ──────────
  /// Copia destino, fechas y nombre del trip_group como itinerario.
  /// Si el trip_group tiene structure de días/lugares (futura mejora)
  /// se replica también.
  static Future<String?> publishFromTrip({
    required String tripGroupId,
    required String title,
    String? description,
    bool isPublic = true,
    required String displayName,
    required String avatarColor,
  }) async {
    final uid = _uid;
    if (uid == null) return null;
    try {
      final trip = await _db
          .from('trip_groups')
          .select('destination, total_days, member_count, budget_per_person, currency')
          .eq('id', tripGroupId)
          .single();

      final res = await _db.from('user_itineraries').insert({
        'user_uid':         uid,
        'display_name':     displayName,
        'avatar_color':     avatarColor,
        'title':            title.trim(),
        'destination':      trip['destination'] ?? '',
        'country_flag':     '📍',
        'description':      description?.trim(),
        'total_days':       trip['total_days'] ?? 1,
        'total_places':     0,
        'group_size':        trip['member_count'] ?? 1,
        'budget_per_person': trip['budget_per_person'] ?? 0,
        'currency':          trip['currency'] ?? '€',
        'source_group_id':  tripGroupId,
        'is_public':        isPublic,
        'published_at':     isPublic ? DateTime.now().toIso8601String() : null,
      }).select('id').single();
      return res['id']?.toString();
    } catch (e) {
      debugPrint('publishFromTrip error: $e');
      return null;
    }
  }

  // ── ITINERARIO DE TRABAJO de un trip_group (privado) ──────
  /// Devuelve el itinerario ya vinculado a este grupo, o crea uno
  /// nuevo (no público) para que el grupo pueda ir montando su plan
  /// día a día y sacar luego la ruta de Maps.
  static Future<String?> getOrCreateGroupItinerary({
    required String tripGroupId,
    required String destination,
    required int totalDays,
    required String displayName,
    required String avatarColor,
  }) async {
    final uid = _uid;
    if (uid == null) return null;
    try {
      // NOTA: source_group_id también lo usa publishFromTrip() (itinerario
      // PÚBLICO al pulsar "Publish to feed"). Filtramos is_public=false para
      // no confundir el plan de trabajo privado con esa copia publicada —
      // ambos pueden coexistir para el mismo grupo.
      final existing = await _db
          .from('user_itineraries')
          .select('id')
          .eq('source_group_id', tripGroupId)
          .eq('is_public', false)
          .order('created_at', ascending: true)
          .limit(1);
      if (existing.isNotEmpty) {
        return existing.first['id']?.toString();
      }

      final res = await _db.from('user_itineraries').insert({
        'user_uid':         uid,
        'display_name':     displayName,
        'avatar_color':     avatarColor,
        'title':            'Trip plan',
        'destination':      destination,
        'country_flag':     '📍',
        'total_days':       totalDays,
        'total_places':     0,
        'source_group_id':  tripGroupId,
        'is_public':        false,
      }).select('id').single();
      return res['id']?.toString();
    } catch (e) {
      debugPrint('getOrCreateGroupItinerary error: $e');
      return null;
    }
  }

  // ── DÍAS y LUGARES (editar contenido del itinerario) ──────
  static Future<String?> addDay({
    required String itineraryId,
    required int dayNumber,
    String title = '',
  }) async {
    try {
      final res = await _db.from('itinerary_days').insert({
        'itinerary_id': itineraryId,
        'day_number':   dayNumber,
        'title':        title.trim(),
      }).select('id').single();
      await _refreshTotals(itineraryId);
      return res['id']?.toString();
    } catch (e) {
      debugPrint('addDay error: $e');
      return null;
    }
  }

  static Future<String?> addPlace({
    required String dayId,
    required String itineraryId,
    required int position,
    required String placeName,
    String category = 'Activities',
    String? timeLabel,
    String? note,
  }) async {
    try {
      final res = await _db.from('itinerary_places').insert({
        'day_id':     dayId,
        'position':   position,
        'place_name': placeName.trim(),
        'category':   category,
        'time_label': timeLabel,
        'note':       note,
      }).select('id').single();
      await _refreshTotals(itineraryId);
      return res['id']?.toString();
    } catch (e) {
      debugPrint('addPlace error: $e');
      return null;
    }
  }

  static Future<bool> deletePlace(String placeId, String itineraryId) async {
    try {
      await _db.from('itinerary_places').delete().eq('id', placeId);
      await _refreshTotals(itineraryId);
      return true;
    } catch (e) {
      debugPrint('deletePlace error: $e');
      return false;
    }
  }

  /// Recalcula total_days y total_places del itinerario.
  static Future<void> _refreshTotals(String itineraryId) async {
    try {
      final days = await _db
          .from('itinerary_days')
          .select('id')
          .eq('itinerary_id', itineraryId);
      final dayIds = (days as List).map((d) => d['id'] as String).toList();
      int placesCount = 0;
      if (dayIds.isNotEmpty) {
        final places = await _db
            .from('itinerary_places')
            .select('id')
            .inFilter('day_id', dayIds);
        placesCount = (places as List).length;
      }
      await _db.from('user_itineraries').update({
        'total_days':   dayIds.length,
        'total_places': placesCount,
      }).eq('id', itineraryId);
    } catch (e) {
      debugPrint('_refreshTotals error: $e');
    }
  }

  // ── Total de clones de MIS itinerarios (reconocimiento) ───
  static Future<int> getMyTotalClones() async {
    final uid = _uid;
    if (uid == null) return 0;
    try {
      final rows = await _db
          .from('user_itineraries')
          .select('clones_count')
          .eq('user_uid', uid);
      var total = 0;
      for (final r in rows as List) {
        total += (r['clones_count'] as num?)?.toInt() ?? 0;
      }
      return total;
    } catch (e) {
      debugPrint('getMyTotalClones error: $e');
      return 0;
    }
  }

  // ── Rutas más clonadas (ranking de Explore) ───────────────
  static Future<List<ItineraryCard>> listTopCloned({int limit = 5}) async {
    try {
      final rows = await _db
          .from('user_itineraries')
          .select()
          .eq('is_public', true)
          .gt('clones_count', 0)
          .order('clones_count', ascending: false)
          .limit(limit);
      return (rows as List)
          .map((r) => ItineraryCard.fromJson(
              {...r as Map<String, dynamic>, 'is_favorited': false}))
          .toList();
    } catch (e) {
      debugPrint('listTopCloned error: $e');
      return const [];
    }
  }

  // ── ¿Puede editar? Dueño O miembro del grupo de origen ────
  static Future<bool> canEditItinerary(String itineraryId) async {
    final uid = _uid;
    if (uid == null) return false;
    try {
      final it = await _db
          .from('user_itineraries')
          .select('user_uid, source_group_id')
          .eq('id', itineraryId)
          .maybeSingle();
      if (it == null) return false;
      if (it['user_uid'] == uid) return true; // dueño
      final gid = it['source_group_id'];
      if (gid == null) return false;
      final member = await _db
          .from('trip_group_members')
          .select('id')
          .eq('group_id', gid)
          .eq('firebase_uid', uid)
          .maybeSingle();
      return member != null; // miembro del grupo
    } catch (e) {
      debugPrint('canEditItinerary error: $e');
      return false;
    }
  }

  // ── PUBLICAR / DESPUBLICAR un itinerario existente ────────
  static Future<bool> setItineraryPublic(String itineraryId, bool isPublic) async {
    try {
      await _db.from('user_itineraries').update({
        'is_public':    isPublic,
        'published_at': isPublic ? DateTime.now().toIso8601String() : null,
      }).eq('id', itineraryId);
      return true;
    } catch (e) {
      debugPrint('setItineraryPublic error: $e');
      return false;
    }
  }

  // ── CLONAR itinerario → crear nuevo trip_group ────────────
  /// Crea un trip_group nuevo basado en este itinerario.
  /// El trigger SQL incrementa clones_count automáticamente.
  /// Devuelve (tripGroupId, inviteCode) o null si falla.
  static Future<({String tripGroupId, String inviteCode})?> cloneToTrip({
    required String itineraryId,
    required DateTime startDate,
    DateTime? endDate,
    String? tripName,
    int guests = 0,
    String currency = '€',
    double budget = 0,
  }) async {
    final uid = _uid;
    if (uid == null) return null;
    try {
      // 1) Garantizar que existe el usuario
      final fbUser = FirebaseAuth.instance.currentUser;
      await _db.from('users').upsert({
        'firebase_uid': uid,
        'email':        fbUser?.email ?? '',
        'display_name': fbUser?.displayName ?? fbUser?.email?.split('@').first ?? '',
      }, onConflict: 'firebase_uid');

      // 2) Cargar el itinerario fuente
      final itin = await _db
          .from('user_itineraries')
          .select('title, destination, total_days')
          .eq('id', itineraryId)
          .single();

      final inviteCode = DateTime.now().millisecondsSinceEpoch
          .toRadixString(36).toUpperCase().substring(0, 6);
      final end = endDate ?? startDate.add(Duration(
        days: (((itin['total_days'] as num?)?.toInt() ?? 1) - 1).clamp(0, 365),
      ));
      final days = end.difference(startDate).inDays + 1;

      // 3) Crear el trip_group (el trigger incrementa clones_count solo)
      final group = await _db.from('trip_groups').insert({
        'invite_code':            inviteCode,
        'trip_name':              (tripName ?? itin['title'] ?? 'My Trip').toString().trim(),
        'destination':            itin['destination'] ?? '',
        'start_date':             startDate.toIso8601String().split('T').first,
        'end_date':               end.toIso8601String().split('T').first,
        'total_days':             days,
        'member_count':           guests + 1,
        'budget_per_person':      budget,
        'currency':               currency,
        'created_by':             uid,
        'based_on_itinerary_id':  itineraryId,
      }).select('id').single();

      final tripGroupId = group['id']?.toString() ?? '';

      // 4) Añadir al creador como miembro líder
      await _db.from('trip_group_members').insert({
        'group_id':     tripGroupId,
        'firebase_uid': uid,
        'is_leader':    true,
      });

      return (tripGroupId: tripGroupId, inviteCode: inviteCode);
    } catch (e) {
      debugPrint('cloneToTrip error: $e');
      return null;
    }
  }

  // ── ELIMINAR itinerario propio ────────────────────────────
  static Future<bool> deleteItinerary(String itineraryId) async {
    final uid = _uid;
    if (uid == null) return false;
    try {
      await _db.from('user_itineraries')
          .delete()
          .eq('id', itineraryId)
          .eq('user_uid', uid);  // solo el autor lo borra
      return true;
    } catch (e) {
      debugPrint('deleteItinerary error: $e');
      return false;
    }
  }
}
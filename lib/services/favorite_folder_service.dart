// lib/services/favorite_folder_service.dart
//
// Carpetas de favoritos (muchos-a-muchos), separadas por tipo:
//   kind = 'itinerary' | 'place'
//
// NO toca itinerary_favorites / place_favorites: esas siguen siendo la
// fuente del "es favorito" (heart + contadores por trigger). Las carpetas
// son una capa encima:
//   favorite_folders        → carpetas del usuario (por tipo)
//   favorite_folder_items   → pertenencia item↔carpeta (un item en varias)
//
// Al guardar en >=1 carpeta se garantiza que el item esté en *_favorites.
// Al quitar de todas las carpetas se elimina también de *_favorites.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Se incrementa cada vez que cambian los favoritos o sus carpetas, para que
/// pantallas vivas (p. ej. el perfil dentro del IndexedStack) se refresquen.
final ValueNotifier<int> favouritesChanged = ValueNotifier<int>(0);

class FavoriteFolder {
  final String id;
  final String name;
  final String kind;
  final int itemCount;
  final String? groupId; // != null si está compartida con un grupo de viaje

  const FavoriteFolder({
    required this.id,
    required this.name,
    required this.kind,
    this.itemCount = 0,
    this.groupId,
  });

  bool get isShared => groupId != null;

  factory FavoriteFolder.fromJson(Map<String, dynamic> j, {int itemCount = 0}) =>
      FavoriteFolder(
        id:        j['id']?.toString() ?? '',
        name:      j['name'] as String? ?? '',
        kind:      j['kind'] as String? ?? 'place',
        itemCount: itemCount,
        groupId:   j['group_id']?.toString(),
      );
}

class FavoriteFolderService {
  static final _db = Supabase.instance.client;

  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  static String _favTable(String kind) =>
      kind == 'itinerary' ? 'itinerary_favorites' : 'place_favorites';
  static String _favCol(String kind) =>
      kind == 'itinerary' ? 'itinerary_id' : 'place_id';

  // ── CARPETAS ──────────────────────────────────────────────
  /// Carpetas de un tipo, con su nº de items (calculado en cliente).
  static Future<List<FavoriteFolder>> listFolders(String kind) async {
    final uid = _uid;
    if (uid == null) return const [];
    try {
      // Mis carpetas
      final mine = await _db
          .from('favorite_folders')
          .select()
          .eq('firebase_uid', uid)
          .eq('kind', kind)
          .order('created_at', ascending: true);

      // Carpetas compartidas con grupos donde soy miembro
      final memberships = await _db
          .from('trip_group_members')
          .select('group_id')
          .eq('firebase_uid', uid);
      final myGroupIds =
          (memberships as List).map((r) => r['group_id'] as String).toList();

      List shared = const [];
      if (myGroupIds.isNotEmpty) {
        shared = await _db
            .from('favorite_folders')
            .select()
            .inFilter('group_id', myGroupIds)
            .eq('kind', kind)
            .neq('firebase_uid', uid) // las mías ya están arriba
            .order('created_at', ascending: true);
      }

      final all = [...mine as List, ...shared];
      if (all.isEmpty) return const [];

      // Conteo de items (de TODOS los usuarios: una compartida suma todo)
      final folderIds = all.map((f) => f['id'].toString()).toList();
      final items = await _db
          .from('favorite_folder_items')
          .select('folder_id')
          .inFilter('folder_id', folderIds);

      final counts = <String, int>{};
      for (final r in items as List) {
        final fid = r['folder_id'] as String;
        counts[fid] = (counts[fid] ?? 0) + 1;
      }

      return all
          .map((f) => FavoriteFolder.fromJson(
                f as Map<String, dynamic>,
                itemCount: counts[f['id']?.toString()] ?? 0,
              ))
          .toList();
    } catch (e) {
      debugPrint('FavoriteFolderService.listFolders error: $e');
      return const [];
    }
  }

  static Future<String?> createFolder(String name, String kind) async {
    final uid = _uid;
    final clean = name.trim();
    if (uid == null || clean.isEmpty) return null;
    try {
      final res = await _db
          .from('favorite_folders')
          .insert({'firebase_uid': uid, 'name': clean, 'kind': kind})
          .select('id')
          .single();
      favouritesChanged.value++;
      return res['id']?.toString();
    } catch (e) {
      debugPrint('FavoriteFolderService.createFolder error: $e');
      return null;
    }
  }

  static Future<bool> renameFolder(String folderId, String name) async {
    final uid = _uid;
    final clean = name.trim();
    if (uid == null || clean.isEmpty) return false;
    try {
      await _db
          .from('favorite_folders')
          .update({'name': clean})
          .eq('id', folderId)
          .eq('firebase_uid', uid);
      return true;
    } catch (e) {
      debugPrint('FavoriteFolderService.renameFolder error: $e');
      return false;
    }
  }

  static Future<bool> deleteFolder(String folderId) async {
    final uid = _uid;
    if (uid == null) return false;
    try {
      // Los items (favorite_folder_items) caen por ON DELETE CASCADE.
      await _db
          .from('favorite_folders')
          .delete()
          .eq('id', folderId)
          .eq('firebase_uid', uid);
      return true;
    } catch (e) {
      debugPrint('FavoriteFolderService.deleteFolder error: $e');
      return false;
    }
  }

  // ── PERTENENCIA ───────────────────────────────────────────
  /// IDs de carpeta a las que pertenece un item.
  static Future<Set<String>> foldersForItem(String kind, String itemId) async {
    final uid = _uid;
    if (uid == null) return <String>{};
    try {
      final res = await _db
          .from('favorite_folder_items')
          .select('folder_id')
          .eq('firebase_uid', uid)
          .eq('kind', kind)
          .eq('item_id', itemId);
      return (res as List).map((r) => r['folder_id'] as String).toSet();
    } catch (e) {
      debugPrint('FavoriteFolderService.foldersForItem error: $e');
      return <String>{};
    }
  }

  /// Mapa folderId → set de itemIds (para filtrar listados por carpeta).
  static Future<Map<String, Set<String>>> membershipsByFolder(String kind) async {
    final uid = _uid;
    if (uid == null) return {};
    try {
      final res = await _db
          .from('favorite_folder_items')
          .select('folder_id, item_id')
          .eq('firebase_uid', uid)
          .eq('kind', kind);
      final map = <String, Set<String>>{};
      for (final r in res as List) {
        final fid = r['folder_id'] as String;
        final iid = r['item_id'] as String;
        map.putIfAbsent(fid, () => <String>{}).add(iid);
      }
      return map;
    } catch (e) {
      debugPrint('FavoriteFolderService.membershipsByFolder error: $e');
      return {};
    }
  }

  // ── GUARDAR / QUITAR ──────────────────────────────────────
  /// Reemplaza la pertenencia del item por [folderIds].
  /// Si queda vacío → quita el favorito por completo.
  /// Devuelve true si el item queda como favorito.
  static Future<bool> saveItemToFolders({
    required String kind,
    required String itemId,
    required Set<String> folderIds,
  }) async {
    final uid = _uid;
    if (uid == null) return false;

    if (folderIds.isEmpty) {
      await removeFavorite(kind: kind, itemId: itemId);
      return false;
    }

    try {
      // 1) Garantizar que está en *_favorites (sin duplicar).
      final favTable = _favTable(kind);
      final favCol = _favCol(kind);
      final existing = await _db
          .from(favTable)
          .select('id')
          .eq('firebase_uid', uid)
          .eq(favCol, itemId)
          .maybeSingle();
      if (existing == null) {
        await _db.from(favTable).insert({'firebase_uid': uid, favCol: itemId});
      }

      // 2) Reemplazar pertenencias.
      await _db
          .from('favorite_folder_items')
          .delete()
          .eq('firebase_uid', uid)
          .eq('kind', kind)
          .eq('item_id', itemId);

      final rows = folderIds
          .map((fid) => {
                'folder_id': fid,
                'firebase_uid': uid,
                'kind': kind,
                'item_id': itemId,
              })
          .toList();
      await _db.from('favorite_folder_items').insert(rows);
      favouritesChanged.value++;
      return true;
    } catch (e) {
      debugPrint('FavoriteFolderService.saveItemToFolders error: $e');
      return false;
    }
  }

  static Future<void> removeFavorite({
    required String kind,
    required String itemId,
  }) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await _db
          .from(_favTable(kind))
          .delete()
          .eq('firebase_uid', uid)
          .eq(_favCol(kind), itemId);
      await _db
          .from('favorite_folder_items')
          .delete()
          .eq('firebase_uid', uid)
          .eq('kind', kind)
          .eq('item_id', itemId);
      favouritesChanged.value++;
    } catch (e) {
      debugPrint('FavoriteFolderService.removeFavorite error: $e');
    }
  }

  // ══════════════════════════════════════════════════════════
  // CARPETAS COMPARTIDAS + VOTACIÓN
  // ══════════════════════════════════════════════════════════

  /// Mis grupos de viaje (para el selector de "compartir carpeta").
  static Future<List<({String id, String name})>> myGroups() async {
    final uid = _uid;
    if (uid == null) return const [];
    try {
      final memberships = await _db
          .from('trip_group_members')
          .select('group_id')
          .eq('firebase_uid', uid);
      final ids =
          (memberships as List).map((r) => r['group_id'] as String).toList();
      if (ids.isEmpty) return const [];
      final groups = await _db
          .from('trip_groups')
          .select('id, trip_name')
          .inFilter('id', ids)
          .order('created_at', ascending: false);
      return (groups as List)
          .map((g) => (
                id: g['id'].toString(),
                name: g['trip_name'] as String? ?? 'Trip',
              ))
          .toList();
    } catch (e) {
      debugPrint('FavoriteFolderService.myGroups error: $e');
      return const [];
    }
  }

  /// Comparte (o descomparte con groupId=null) una carpeta con un grupo.
  static Future<bool> shareFolderWithGroup(
      String folderId, String? groupId) async {
    try {
      await _db
          .from('favorite_folders')
          .update({'group_id': groupId}).eq('id', folderId);
      favouritesChanged.value++;
      return true;
    } catch (e) {
      debugPrint('FavoriteFolderService.shareFolderWithGroup error: $e');
      return false;
    }
  }

  /// Contenido de una carpeta con votos. Deduplica items repetidos
  /// (si dos miembros guardaron el mismo sitio) sumando sus votos.
  static Future<List<FolderItemView>> listFolderItems(String folderId) async {
    final uid = _uid;
    try {
      final rows = await _db
          .from('favorite_folder_items')
          .select('id, kind, item_id')
          .eq('folder_id', folderId);
      if ((rows as List).isEmpty) return const [];

      final rowIds = rows.map((r) => r['id'].toString()).toList();
      final votes = await _db
          .from('favorite_folder_votes')
          .select('folder_item_id, firebase_uid')
          .inFilter('folder_item_id', rowIds);

      // Votos por fila
      final votesByRow = <String, Set<String>>{};
      for (final v in votes as List) {
        votesByRow
            .putIfAbsent(v['folder_item_id'] as String, () => <String>{})
            .add(v['firebase_uid'] as String);
      }

      // Dedupe por (kind,item_id): votos = unión de votantes
      final byItem = <String, FolderItemView>{};
      for (final r in rows) {
        final kind = r['kind'] as String;
        final itemId = r['item_id'] as String;
        final rowId = r['id'].toString();
        final voters = votesByRow[rowId] ?? <String>{};
        final key = '$kind:$itemId';
        final prev = byItem[key];
        if (prev == null) {
          byItem[key] = FolderItemView(
            rowId: rowId,
            kind: kind,
            itemId: itemId,
            voters: {...voters},
          );
        } else {
          prev.voters.addAll(voters);
        }
      }

      final list = byItem.values.toList();

      // Hidratar nombres (dos consultas planas, sin JOINs embebidos)
      final placeIds = list
          .where((i) => i.kind == 'place')
          .map((i) => i.itemId)
          .toList();
      final itinIds = list
          .where((i) => i.kind == 'itinerary')
          .map((i) => i.itemId)
          .toList();

      final placeNames = <String, ({String name, String subtitle})>{};
      if (placeIds.isNotEmpty) {
        final places = await _db
            .from('places')
            .select('id, name, location, category')
            .inFilter('id', placeIds);
        for (final p in places as List) {
          placeNames[p['id'].toString()] = (
            name: p['name'] as String? ?? '',
            subtitle: [
              p['category'] as String? ?? '',
              p['location'] as String? ?? ''
            ].where((s) => s.isNotEmpty).join(' · '),
          );
        }
      }
      if (itinIds.isNotEmpty) {
        final itins = await _db
            .from('user_itineraries')
            .select('id, title, destination')
            .inFilter('id', itinIds);
        for (final it in itins as List) {
          placeNames[it['id'].toString()] = (
            name: it['title'] as String? ?? '',
            subtitle: it['destination'] as String? ?? '',
          );
        }
      }

      for (final i in list) {
        final h = placeNames[i.itemId];
        i.name = h?.name ?? '(deleted)';
        i.subtitle = h?.subtitle ?? '';
        i.iVoted = uid != null && i.voters.contains(uid);
      }

      // Más votados primero
      list.sort((a, b) => b.voters.length.compareTo(a.voters.length));
      return list;
    } catch (e) {
      debugPrint('FavoriteFolderService.listFolderItems error: $e');
      return const [];
    }
  }

  /// Vota / quita el voto a un item de carpeta.
  static Future<bool> toggleVote(String rowId, bool currentlyVoted) async {
    final uid = _uid;
    if (uid == null) return currentlyVoted;
    try {
      if (currentlyVoted) {
        await _db
            .from('favorite_folder_votes')
            .delete()
            .eq('folder_item_id', rowId)
            .eq('firebase_uid', uid);
        return false;
      } else {
        await _db.from('favorite_folder_votes').insert({
          'folder_item_id': rowId,
          'firebase_uid': uid,
        });
        return true;
      }
    } catch (e) {
      debugPrint('FavoriteFolderService.toggleVote error: $e');
      return currentlyVoted;
    }
  }
}

/// Vista de un item dentro de una carpeta (con votos agregados).
class FolderItemView {
  final String rowId; // fila representativa (para votar)
  final String kind; // 'itinerary' | 'place'
  final String itemId;
  final Set<String> voters;
  String name = '';
  String subtitle = '';
  bool iVoted = false;

  FolderItemView({
    required this.rowId,
    required this.kind,
    required this.itemId,
    required this.voters,
  });
}

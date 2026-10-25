// lib/services/trip_kit_service.dart
//
// Kit del viaje:
//   • Checklist (tareas) y Packing (maleta) — misma forma, tablas gemelas:
//     título + asignado (miembro del grupo) + hecho.
//   • Photos — links de fotos (WeTransfer/Drive/iCloud...), máx. 20.
//   • Info — punto de encuentro, teléfono del alojamiento, seguro, notas.
//
// Patrón del proyecto: static _db + métodos estáticos + modelos inline.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ══════════════════════════════════════════════════════════════
// MODELOS
// ══════════════════════════════════════════════════════════════

/// Item de checklist o de maleta (estructuralmente idénticos).
class KitItem {
  final String id;
  final String title;
  final String? assigneeUid;
  final String? assigneeName;
  final bool done;

  const KitItem({
    required this.id,
    required this.title,
    this.assigneeUid,
    this.assigneeName,
    required this.done,
  });

  factory KitItem.fromJson(Map<String, dynamic> j) => KitItem(
        id:           j['id'].toString(),
        title:        j['title'] as String? ?? '',
        assigneeUid:  j['assignee_uid'] as String?,
        assigneeName: j['assignee_name'] as String?,
        done:         j['done'] == true,
      );
}

class TripLink {
  final String id;
  final String kind; // 'photos' | 'booking' | 'playlist' | 'other'
  final String title;
  final String url;
  final String addedBy;
  final DateTime createdAt;

  const TripLink({
    required this.id,
    required this.kind,
    required this.title,
    required this.url,
    required this.addedBy,
    required this.createdAt,
  });

  factory TripLink.fromJson(Map<String, dynamic> j) => TripLink(
        id:        j['id'].toString(),
        kind:      j['kind'] as String? ?? 'other',
        title:     j['title'] as String? ?? '',
        url:       j['url'] as String? ?? '',
        addedBy:   j['added_by'] as String? ?? '',
        createdAt: DateTime.tryParse(j['created_at']?.toString() ?? '') ??
            DateTime.now(),
      );
}

class TripInfo {
  final String meetingPoint;
  final String lodgingPhone;
  final String insurance;
  final String notes;

  const TripInfo({
    this.meetingPoint = '',
    this.lodgingPhone = '',
    this.insurance = '',
    this.notes = '',
  });

  factory TripInfo.fromJson(Map<String, dynamic> j) => TripInfo(
        meetingPoint: j['meeting_point'] as String? ?? '',
        lodgingPhone: j['lodging_phone'] as String? ?? '',
        insurance:    j['insurance'] as String? ?? '',
        notes:        j['notes'] as String? ?? '',
      );
}

class GroupMember {
  final String uid;
  final String name;
  const GroupMember({required this.uid, required this.name});
}

// ══════════════════════════════════════════════════════════════
// SERVICIO
// ══════════════════════════════════════════════════════════════

class TripKitService {
  static final _db = Supabase.instance.client;

  static const checklistTable = 'trip_checklist_items';
  static const packingTable   = 'trip_packing_items';
  static const maxLinksPerKind = 20;

  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  // ── CHECKLIST / PACKING (tabla parametrizada) ─────────────
  static Future<List<KitItem>> listItems(String table, String groupId) async {
    try {
      final res = await _db
          .from(table)
          .select()
          .eq('group_id', groupId)
          .order('done', ascending: true)
          .order('created_at', ascending: true);
      return (res as List)
          .map((r) => KitItem.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('TripKitService.listItems($table) error: $e');
      return const [];
    }
  }

  static Future<bool> addItem(String table, String groupId, String title) async {
    final clean = title.trim();
    if (clean.isEmpty) return false;
    try {
      await _db.from(table).insert({'group_id': groupId, 'title': clean});
      return true;
    } catch (e) {
      debugPrint('TripKitService.addItem($table) error: $e');
      return false;
    }
  }

  static Future<bool> toggleDone(String table, String itemId, bool done) async {
    try {
      await _db.from(table).update({'done': done}).eq('id', itemId);
      return true;
    } catch (e) {
      debugPrint('TripKitService.toggleDone($table) error: $e');
      return false;
    }
  }

  static Future<bool> assignItem(
      String table, String itemId, GroupMember? member) async {
    try {
      await _db.from(table).update({
        'assignee_uid': member?.uid,
        'assignee_name': member?.name,
      }).eq('id', itemId);
      return true;
    } catch (e) {
      debugPrint('TripKitService.assignItem($table) error: $e');
      return false;
    }
  }

  static Future<bool> deleteItem(String table, String itemId) async {
    try {
      await _db.from(table).delete().eq('id', itemId);
      return true;
    } catch (e) {
      debugPrint('TripKitService.deleteItem($table) error: $e');
      return false;
    }
  }

  // ── LINKS (fotos, etc.) ───────────────────────────────────
  static Future<List<TripLink>> listLinks(String groupId,
      {String kind = 'photos'}) async {
    try {
      final res = await _db
          .from('trip_links')
          .select()
          .eq('group_id', groupId)
          .eq('kind', kind)
          .order('created_at', ascending: false);
      return (res as List)
          .map((r) => TripLink.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('TripKitService.listLinks error: $e');
      return const [];
    }
  }

  /// Devuelve null si OK, o un mensaje de error (p. ej. límite alcanzado).
  static Future<String?> addLink({
    required String groupId,
    required String title,
    required String url,
    String kind = 'photos',
    String addedBy = '',
  }) async {
    final cleanUrl = url.trim();
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty || cleanUrl.isEmpty) return 'Fill in title and link';
    final uri = Uri.tryParse(cleanUrl);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      return 'Invalid link (must start with http/https)';
    }
    try {
      final existing = await _db
          .from('trip_links')
          .select('id')
          .eq('group_id', groupId)
          .eq('kind', kind);
      if ((existing as List).length >= maxLinksPerKind) {
        return 'Limit of $maxLinksPerKind links reached';
      }
      await _db.from('trip_links').insert({
        'group_id': groupId,
        'kind': kind,
        'title': cleanTitle,
        'url': cleanUrl,
        'added_by': addedBy,
      });
      return null;
    } catch (e) {
      debugPrint('TripKitService.addLink error: $e');
      return 'Could not save link';
    }
  }

  static Future<bool> deleteLink(String linkId) async {
    try {
      await _db.from('trip_links').delete().eq('id', linkId);
      return true;
    } catch (e) {
      debugPrint('TripKitService.deleteLink error: $e');
      return false;
    }
  }

  // ── INFO del viaje ────────────────────────────────────────
  static Future<TripInfo> getInfo(String groupId) async {
    try {
      final res = await _db
          .from('trip_info')
          .select()
          .eq('group_id', groupId)
          .maybeSingle();
      return res == null ? const TripInfo() : TripInfo.fromJson(res);
    } catch (e) {
      debugPrint('TripKitService.getInfo error: $e');
      return const TripInfo();
    }
  }

  static Future<bool> saveInfo(String groupId, TripInfo info) async {
    try {
      await _db.from('trip_info').upsert({
        'group_id':      groupId,
        'meeting_point': info.meetingPoint,
        'lodging_phone': info.lodgingPhone,
        'insurance':     info.insurance,
        'notes':         info.notes,
        'updated_at':    DateTime.now().toIso8601String(),
      });
      return true;
    } catch (e) {
      debugPrint('TripKitService.saveInfo error: $e');
      return false;
    }
  }

  // ── MIEMBROS del grupo (para asignar) ─────────────────────
  static Future<List<GroupMember>> groupMembers(String groupId) async {
    try {
      final rows = await _db
          .from('trip_group_members')
          .select('firebase_uid')
          .eq('group_id', groupId);
      final uids =
          (rows as List).map((r) => r['firebase_uid'] as String).toList();
      if (uids.isEmpty) return const [];
      final users = await _db
          .from('users')
          .select('firebase_uid, display_name')
          .inFilter('firebase_uid', uids);
      return (users as List)
          .map((u) => GroupMember(
                uid: u['firebase_uid'] as String,
                name: (u['display_name'] as String?)?.isNotEmpty == true
                    ? u['display_name'] as String
                    : 'Traveler',
              ))
          .toList();
    } catch (e) {
      debugPrint('TripKitService.groupMembers error: $e');
      return const [];
    }
  }

  /// Mi display_name (para added_by de los links).
  static Future<String> myDisplayName() async {
    final uid = _uid;
    if (uid == null) return 'Traveler';
    try {
      final res = await _db
          .from('users')
          .select('display_name')
          .eq('firebase_uid', uid)
          .maybeSingle();
      final n = res?['display_name'] as String?;
      return (n == null || n.isEmpty) ? 'Traveler' : n;
    } catch (_) {
      return 'Traveler';
    }
  }
}

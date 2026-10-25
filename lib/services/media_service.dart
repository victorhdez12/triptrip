// lib/services/media_service.dart
//
// Fotos: subida de imágenes + galería (post_media).
//
// ─────────────────────────────────────────────────────────────
//  PUNTO DE MIGRACIÓN A R2 (egress 0):
//  Toda la app sube a través de uploadImage() y solo usa la URL que
//  devuelve. Hoy guarda en Supabase Storage (bucket público 'media').
//  Para pasar a Cloudflare R2 sin tocar pantallas: cambia SOLO el cuerpo
//  de uploadImage() por una subida a R2 (vía URL prefirmada de un Worker/
//  Edge Function) y devuelve la URL pública del CDN. Nada más cambia.
// ─────────────────────────────────────────────────────────────

import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MediaItem {
  final String url;
  final String? thumbUrl;
  final int position;

  const MediaItem({required this.url, this.thumbUrl, this.position = 0});

  factory MediaItem.fromJson(Map<String, dynamic> j) => MediaItem(
        url: j['url'] as String? ?? '',
        thumbUrl: j['thumb_url'] as String?,
        position: (j['position'] as num?)?.toInt() ?? 0,
      );
}

class MediaService {
  static final _db = Supabase.instance.client;
  static const _bucket = 'media';

  /// Sube una imagen y devuelve su URL pública (o null si falla).
  /// [pathPrefix] agrupa los archivos, p. ej. 'visits/<uid>'.
  static Future<String?> uploadImage(
    Uint8List bytes, {
    required String pathPrefix,
    String ext = 'jpg',
    String contentType = 'image/jpeg',
  }) async {
    try {
      final path =
          '$pathPrefix/${DateTime.now().millisecondsSinceEpoch}_${bytes.length}.$ext';
      await _db.storage.from(_bucket).uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: contentType, upsert: true),
          );
      return _db.storage.from(_bucket).getPublicUrl(path);
    } catch (e) {
      debugPrint('uploadImage error: $e');
      return null;
    }
  }

  /// Registra una foto en la galería de un post.
  static Future<void> addMedia({
    required String parentType,
    required String parentId,
    required String url,
    required String addedBy,
    String? thumbUrl,
    int position = 0,
  }) async {
    try {
      await _db.from('post_media').insert({
        'parent_type': parentType,
        'parent_id': parentId,
        'url': url,
        if (thumbUrl != null) 'thumb_url': thumbUrl,
        'position': position,
        'added_by': addedBy,
      });
    } catch (e) {
      debugPrint('addMedia error: $e');
    }
  }

  /// TODAS las fotos de un sitio canónico (de todas las visitas públicas).
  /// Para la galería "ver todas" del detalle del lugar.
  static Future<List<String>> listPlaceMedia(String placeId) async {
    if (placeId.isEmpty) return const [];
    try {
      final visits = await _db
          .from('place_visits')
          .select('id')
          .eq('place_id', placeId)
          .eq('is_public', true);
      final ids = (visits as List).map((r) => r['id'].toString()).toList();
      if (ids.isEmpty) return const [];
      final rows = await _db
          .from('post_media')
          .select('url, position')
          .eq('parent_type', 'visit')
          .inFilter('parent_id', ids)
          .order('position', ascending: true);
      return (rows as List).map((r) => r['url'] as String).toList();
    } catch (e) {
      debugPrint('listPlaceMedia error: $e');
      return const [];
    }
  }

  /// Fotos de un post, ordenadas (0 = portada primero).
  static Future<List<MediaItem>> listMedia(
      String parentType, String parentId) async {
    try {
      final res = await _db
          .from('post_media')
          .select()
          .eq('parent_type', parentType)
          .eq('parent_id', parentId)
          .order('position', ascending: true);
      return (res as List)
          .map((r) => MediaItem.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('listMedia error: $e');
      return const [];
    }
  }
}
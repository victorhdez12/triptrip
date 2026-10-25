// lib/widgets/social_actions_bar.dart
//
// Barra de acciones reutilizable: like · comentar · guardar.
// La misma en el feed de Home, en las tarjetas de Explorar y en el
// detalle del sitio, para que la interacción se aprenda una sola vez.
//
// Reparto de responsabilidades:
//   • guardar   → PlaceSocialService.toggleFavorite (+ trip_id)
//   • comentar  → PlaceSocialService.listComments / addComment
//   • like      → FeedService.toggleLike (place_likes)
//
// El rating 1-5 NO está aquí a propósito: tres señales sobre el mismo
// objeto en la misma pantalla se pisan. El rating vive en el detalle.
//
// Todas las acciones son optimistas y revierten si el servidor falla.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/feed_service.dart';
import '../services/place_social_service.dart';

const _kPrimary = Color(0xFF29B6D2);
const _kDark = Color(0xFF1A1A2E);
const _kMuted = Color(0xFF9CA3AF);
const _kLike = Color(0xFFE24B4A);

class SocialActionsBar extends StatefulWidget {
  final String placeId;
  final bool initialLiked;
  final bool initialSaved;
  final int initialLikeCount;
  final int initialCommentCount;

  /// Viaje al que se guarda por defecto (el próximo viaje activo).
  final String? tripId;

  /// Se denormalizan en place_comments, igual que hace el resto de la app.
  final String displayName;
  final String avatarColor;

  final void Function(bool saved)? onSaveChanged;

  const SocialActionsBar({
    super.key,
    required this.placeId,
    this.initialLiked = false,
    this.initialSaved = false,
    this.initialLikeCount = 0,
    this.initialCommentCount = 0,
    this.tripId,
    this.displayName = '',
    this.avatarColor = '#29B6D2',
    this.onSaveChanged,
  });

  @override
  State<SocialActionsBar> createState() => _SocialActionsBarState();
}

class _SocialActionsBarState extends State<SocialActionsBar> {
  late bool _liked = widget.initialLiked;
  late bool _saved = widget.initialSaved;
  late int _likes = widget.initialLikeCount;
  late int _comments = widget.initialCommentCount;
  bool _busy = false;

  String get _authorName => widget.displayName.isNotEmpty
      ? widget.displayName
      : (FirebaseAuth.instance.currentUser?.displayName ?? 'Traveler');

  Future<void> _toggleLike() async {
    if (_busy) return;
    final next = !_liked;
    setState(() {
      _busy = true;
      _liked = next;
      _likes += next ? 1 : -1;
    });
    final result = await FeedService.toggleLike(widget.placeId, !next);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result != next) {
        _liked = result;
        _likes += next ? -1 : 1;
      }
    });
  }

  Future<void> _toggleSave() async {
    if (_busy) return;
    final next = !_saved;
    setState(() {
      _busy = true;
      _saved = next;
    });
    final result = await FeedService.toggleSave(
      widget.placeId,
      !next,
      tripId: widget.tripId,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _saved = result;
    });
    if (result == next) widget.onSaveChanged?.call(result);
    if (result && next && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.tripId != null
              ? 'Guardado en tu viaje'
              : 'Guardado en favoritos'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _openComments() async {
    await CommentsSheet.show(
      context,
      placeId: widget.placeId,
      displayName: _authorName,
      avatarColor: widget.avatarColor,
      onAdded: () {
        if (mounted) setState(() => _comments++);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _Action(
          icon: _liked ? Icons.favorite : Icons.favorite_border,
          label: _likes > 0 ? '$_likes' : 'Me gusta',
          color: _liked ? _kLike : _kMuted,
          onTap: _toggleLike,
        ),
        const SizedBox(width: 18),
        _Action(
          icon: Icons.mode_comment_outlined,
          label: _comments > 0 ? '$_comments' : 'Comentar',
          color: _kMuted,
          onTap: _openComments,
        ),
        const Spacer(),
        // Guardar es la única acción con etiqueta completa siempre:
        // es la que convierte el consumo en planificación.
        GestureDetector(
          onTap: _toggleSave,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: _saved ? _kPrimary : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _saved ? _kPrimary : _kPrimary.withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_saved ? Icons.bookmark : Icons.bookmark_border,
                    size: 15, color: _saved ? Colors.white : _kPrimary),
                const SizedBox(width: 5),
                Text(
                  _saved ? 'Guardado' : 'Guardar',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _saved ? Colors.white : _kPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Action extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _Action({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// COMENTARIOS
// ══════════════════════════════════════════════════════════════

class CommentsSheet extends StatefulWidget {
  final String placeId;
  final String displayName;
  final String avatarColor;
  final VoidCallback? onAdded;

  const CommentsSheet({
    super.key,
    required this.placeId,
    required this.displayName,
    required this.avatarColor,
    this.onAdded,
  });

  /// Avisa con onAdded en cada comentario publicado, para que el
  /// contador de la tarjeta suba aunque se cierre arrastrando.
  static Future<void> show(
    BuildContext context, {
    required String placeId,
    required String displayName,
    required String avatarColor,
    VoidCallback? onAdded,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CommentsSheet(
        placeId: placeId,
        displayName: displayName,
        avatarColor: avatarColor,
        onAdded: onAdded,
      ),
    );
  }

  @override
  State<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<CommentsSheet> {
  final _ctrl = TextEditingController();
  final _rows = <PlaceComment>[];
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await PlaceSocialService.listComments(widget.placeId);
    if (!mounted) return;
    setState(() {
      _rows
        ..clear()
        ..addAll(rows);
      _loading = false;
    });
  }

  Future<void> _send() async {
    final body = _ctrl.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    final added = await PlaceSocialService.addComment(
      widget.placeId,
      body,
      displayName: widget.displayName,
      avatarColor: widget.avatarColor,
    );
    if (!mounted) return;
    if (added != null) {
      _ctrl.clear();
      widget.onAdded?.call();
      setState(() => _rows.insert(0, added));
    }
    setState(() => _sending = false);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE5E7EB),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text('Comentarios',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: _kDark)),
            ),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: _kPrimary))
                  : _rows.isEmpty
                      ? const Center(
                          child: Text('Sé el primero en comentar',
                              style:
                                  TextStyle(fontSize: 14, color: _kMuted)))
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _rows.length,
                          itemBuilder: (_, i) => _CommentTile(_rows[i]),
                        ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _ctrl,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        decoration: InputDecoration(
                          hintText: 'Escribe un comentario',
                          hintStyle: const TextStyle(
                              fontSize: 14, color: Color(0xFFBBBBBB)),
                          filled: true,
                          fillColor: const Color(0xFFF5F5F5),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(22),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _send,
                      child: Container(
                        width: 42,
                        height: 42,
                        decoration: const BoxDecoration(
                            color: _kPrimary, shape: BoxShape.circle),
                        child: _sending
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.arrow_upward,
                                color: Colors.white, size: 20),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  final PlaceComment c;
  const _CommentTile(this.c);

  Color get _color {
    final hex = c.avatarColor.replaceFirst('#', '');
    final value = int.tryParse(hex, radix: 16);
    return value == null ? _kPrimary : Color(0xFF000000 | value);
  }

  @override
  Widget build(BuildContext context) {
    final name = c.displayName.isEmpty ? 'Traveler' : c.displayName;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: _color.withValues(alpha: 0.14),
            child: Text(
              name.substring(0, 1).toUpperCase(),
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: _color),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _kDark)),
                const SizedBox(height: 2),
                Text(c.body,
                    style: const TextStyle(
                        fontSize: 13, height: 1.4, color: Color(0xFF4B5563))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

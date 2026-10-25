// lib/screens/place_comments_screen.dart
//
// Lista de comentarios de un lugar/restaurante + input para añadir uno.
// Permite borrar los comentarios propios. Calcado de
// itinerary_comments_screen.dart pero usando PlaceSocialService.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/place_social_service.dart';
import '../widgets/common_widgets.dart';

class PlaceCommentsScreen extends StatefulWidget {
  final String placeId;
  const PlaceCommentsScreen({super.key, required this.placeId});

  @override
  State<PlaceCommentsScreen> createState() => _PlaceCommentsScreenState();
}

class _PlaceCommentsScreenState extends State<PlaceCommentsScreen> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  List<PlaceComment> _comments = [];
  bool _loading = true;
  bool _sending = false;

  String _myName = 'You';
  String _myColor = '#29B6D2';

  @override
  void initState() {
    super.initState();
    _load();
    _loadMyProfile();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadMyProfile() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final res = await Supabase.instance.client
          .from('users')
          .select('display_name, avatar_color')
          .eq('firebase_uid', uid)
          .maybeSingle();
      if (res != null && mounted) {
        setState(() {
          _myName = (res['display_name'] as String?)?.isNotEmpty == true
              ? res['display_name'] as String
              : 'You';
          _myColor = res['avatar_color'] as String? ?? '#29B6D2';
        });
      }
    } catch (_) {}
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await PlaceSocialService.listComments(widget.placeId);
    if (!mounted) return;
    setState(() {
      _comments = list;
      _loading = false;
    });
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);

    final newComment = await PlaceSocialService.addComment(
      widget.placeId,
      text,
      displayName: _myName,
      avatarColor: _myColor,
    );

    if (!mounted) return;
    setState(() => _sending = false);

    if (newComment != null) {
      setState(() {
        _comments = [newComment, ..._comments];
        _ctrl.clear();
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Could not send comment'),
            backgroundColor: Colors.redAccent),
      );
    }
  }

  Future<void> _delete(PlaceComment c) async {
    final ok = await PlaceSocialService.deleteComment(c.id);
    if (ok && mounted) {
      setState(() => _comments.removeWhere((x) => x.id == c.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF1A1A2E)),
        title: const Text('Comments',
          style: TextStyle(
            color: Color(0xFF1A1A2E),
            fontWeight: FontWeight.w800,
            fontSize: 17,
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: kPrimary))
                : _comments.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Text('💬', style: TextStyle(fontSize: 56)),
                              SizedBox(height: 8),
                              Text('Be the first to comment',
                                style: TextStyle(
                                  fontSize: 15,
                                  color: Color(0xFF6B7280),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                        itemCount: _comments.length,
                        itemBuilder: (_, i) {
                          final c = _comments[i];
                          final isMine = c.userUid == myUid;
                          return _CommentTile(
                            comment: c,
                            isMine: isMine,
                            onDelete: isMine ? () => _delete(c) : null,
                          );
                        },
                      ),
          ),
          // Input
          SafeArea(
            top: false,
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Color(0xFFEEF0F4))),
              ),
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
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
                        hintText: 'Add a comment...',
                        filled: true,
                        fillColor: const Color(0xFFF5F5F5),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5, color: kPrimary),
                          )
                        : const Icon(Icons.send_rounded, color: kPrimary),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// COMMENT TILE
// ══════════════════════════════════════════════════════════════

class _CommentTile extends StatelessWidget {
  final PlaceComment comment;
  final bool isMine;
  final VoidCallback? onDelete;

  const _CommentTile({
    required this.comment,
    required this.isMine,
    this.onDelete,
  });

  static Color _hex(String h) {
    final c = h.replaceAll('#', '');
    return Color(int.parse('FF$c', radix: 16));
  }

  static String _rel(DateTime dt) {
    final d = DateTime.now().difference(dt);
    if (d.inDays > 0)    return '${d.inDays}d';
    if (d.inHours > 0)   return '${d.inHours}h';
    if (d.inMinutes > 0) return '${d.inMinutes}m';
    return 'now';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: _hex(comment.avatarColor),
            child: Text(
              comment.displayName.isNotEmpty
                  ? comment.displayName[0].toUpperCase()
                  : 'T',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFEEF0F4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(comment.displayName,
                          style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700,
                            color: Color(0xFF1A1A2E),
                          ),
                        ),
                      ),
                      Text(_rel(comment.createdAt),
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFF9CA3AF)),
                      ),
                      if (isMine && onDelete != null) ...[
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: onDelete,
                          child: const Icon(Icons.delete_outline,
                              size: 16, color: Color(0xFF9CA3AF)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(comment.body,
                    style: const TextStyle(
                        fontSize: 14, color: Color(0xFF374151), height: 1.35),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

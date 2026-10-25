// ══════════════════════════════════════════════════════════════
// FOLLOW LIST SCREEN
// Lista de seguidores o seguidos de un usuario. Cada fila abre su
// perfil público. Datos: SocialService.getFollowList(uid, followers).
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../l10n.dart';
import '../services/social_service.dart';
import '../widgets/common_widgets.dart';
import 'public_profile_screen.dart';

class FollowListScreen extends StatefulWidget {
  final String uid;
  final bool followers; // true = seguidores, false = seguidos
  final String title;

  const FollowListScreen({
    super.key,
    required this.uid,
    required this.followers,
    this.title = '',
  });

  @override
  State<FollowListScreen> createState() => _FollowListScreenState();
}

class _FollowListScreenState extends State<FollowListScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _users = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list =
        await SocialService.getFollowList(widget.uid, followers: widget.followers);
    if (!mounted) return;
    setState(() {
      _users = list;
      _loading = false;
    });
  }

  void _openProfile(Map<String, dynamic> u) {
    final uid = u['firebase_uid']?.toString() ?? '';
    if (uid.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PublicProfileScreen(
          uid: uid,
          displayName: u['display_name'] as String? ?? '',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.title.isNotEmpty
        ? widget.title
        : (widget.followers
            ? tr('Followers', 'Seguidores')
            : tr('Following', 'Siguiendo'));
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: const Color(0xFF1A1A2E),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kPrimary))
          : _users.isEmpty
              ? Center(
                  child: Text(
                    widget.followers
                        ? tr('No followers yet.', 'Aún no tiene seguidores.')
                        : tr('Not following anyone yet.',
                            'Aún no sigue a nadie.'),
                    style: const TextStyle(color: Color(0xFF9CA3AF)),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _users.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, color: Color(0xFFEEF0F4)),
                  itemBuilder: (_, i) => _tile(_users[i]),
                ),
    );
  }

  Widget _tile(Map<String, dynamic> u) {
    final name = u['display_name'] as String? ?? 'Traveler';
    final city = u['city'] as String? ?? '';
    final avatarUrl = u['avatar_url'] as String? ?? '';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'T';
    return ListTile(
      onTap: () => _openProfile(u),
      leading: CircleAvatar(
        radius: 22,
        backgroundColor: kPrimary,
        backgroundImage: avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
        child: avatarUrl.isNotEmpty
            ? null
            : Text(initial,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700)),
      ),
      title: Text(name,
          style: const TextStyle(
              fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E))),
      subtitle: city.isNotEmpty
          ? Text(city,
              style: const TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)))
          : null,
      trailing: const Icon(Icons.chevron_right, color: Color(0xFF9CA3AF)),
    );
  }
}
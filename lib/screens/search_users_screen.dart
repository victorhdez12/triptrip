// lib/screens/search_users_screen.dart
//
// Buscador de usuarios para seguirlos / dejar de seguirlos.

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/social_service.dart';
import 'public_profile_screen.dart';

const _kPrimary = Color(0xFF29B6D2);
const _kDark = Color(0xFF1A1A2E);

class SearchUsersScreen extends StatefulWidget {
  const SearchUsersScreen({super.key});

  @override
  State<SearchUsersScreen> createState() => _SearchUsersScreenState();
}

class _SearchUsersScreenState extends State<SearchUsersScreen> {
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  Set<String> _followingSet = {};
  final Set<String> _pendingToggles = {};
  bool _loading = false;
  Timer? _debounce;

  String get _myUid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _loadFollowing();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadFollowing() async {
    try {
      final uids = await SocialService.getFollowingUids(_myUid);
      if (mounted) setState(() => _followingSet = uids.toSet());
    } catch (e) {
      debugPrint('Error loading following: $e');
    }
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      setState(() => _results = []);
      return;
    }
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => _search(query.trim()),
    );
  }

  Future<void> _search(String query) async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final res = await Supabase.instance.client
          .from('users')
          .select('firebase_uid, display_name, city, country_code, avatar_url')
          .ilike('display_name', '%$query%')
          .neq('firebase_uid', _myUid)
          .limit(25);
      if (mounted) {
        setState(() {
          _results = (res as List)
              .map((r) => Map<String, dynamic>.from(r))
              .toList();
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Search error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleFollow(String uid) async {
    if (_pendingToggles.contains(uid)) return;
    final isFollowing = _followingSet.contains(uid);

    setState(() {
      _pendingToggles.add(uid);
      if (isFollowing) {
        _followingSet.remove(uid);
      } else {
        _followingSet.add(uid);
      }
    });

    try {
      if (isFollowing) {
        await SocialService.unfollow(_myUid, uid);
      } else {
        await SocialService.follow(_myUid, uid);
      }
    } catch (e) {
      // Revert on error
      if (mounted) {
        setState(() {
          if (isFollowing) {
            _followingSet.add(uid);
          } else {
            _followingSet.remove(uid);
          }
        });
      }
    } finally {
      if (mounted) setState(() => _pendingToggles.remove(uid));
    }
  }

  Color _colorForName(String name) {
    const colors = [
      Color(0xFF29B6D2),
      Color(0xFFFF7B54),
      Color(0xFF7C3AED),
      Color(0xFF10B981),
      Color(0xFFEC4899),
      Color(0xFFF59E0B),
    ];
    final hash = name.codeUnits.fold(0, (p, e) => p + e);
    return colors[hash % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _kDark),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Find people',
          style: TextStyle(
              fontSize: 17, fontWeight: FontWeight.w700, color: _kDark),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // ── Search bar ────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE5E7EB)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: TextField(
                controller: _searchCtrl,
                autofocus: true,
                onChanged: _onSearchChanged,
                decoration: const InputDecoration(
                  hintText: 'Search by name...',
                  hintStyle:
                      TextStyle(color: Color(0xFFBBBBBB), fontSize: 14),
                  border: InputBorder.none,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  prefixIcon: Icon(Icons.search,
                      color: Color(0xFF9CA3AF), size: 20),
                ),
              ),
            ),
          ),

          // ── Results ───────────────────────────────────────
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(
                        color: _kPrimary, strokeWidth: 2.5),
                  )
                : _results.isEmpty
                    ? _buildEmptyState()
                    : ListView.separated(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _results.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 8),
                        itemBuilder: (_, i) =>
                            _buildUserCard(_results[i]),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserCard(Map<String, dynamic> user) {
    final uid = user['firebase_uid'] as String;
    final name = user['display_name'] as String? ?? 'Traveler';
    final avatarUrl = user['avatar_url'] as String? ?? '';
    final city = user['city'] as String? ?? '';
    final country = user['country_code'] as String? ?? '';
    final isFollowing = _followingSet.contains(uid);
    final isPending = _pendingToggles.contains(uid);
    final initial =
        name.isNotEmpty ? name[0].toUpperCase() : 'T';

    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Avatar
          CircleAvatar(
            radius: 22,
            backgroundColor: _colorForName(name),
            backgroundImage:
                avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
            child: avatarUrl.isNotEmpty
                ? null
                : Text(initial,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 12),
          // Name + location (toca para abrir el perfil)
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      PublicProfileScreen(uid: uid, displayName: name),
                ),
              ),
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: _kDark)),
                if (city.isNotEmpty || country.isNotEmpty)
                  Text(
                    [city, country]
                        .where((s) => s.isNotEmpty)
                        .join(', '),
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF9CA3AF)),
                  ),
              ],
            ),
            ),
          ),
          const SizedBox(width: 8),
          // Follow button
          GestureDetector(
            onTap: isPending ? null : () => _toggleFollow(uid),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isFollowing ? Colors.white : _kPrimary,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isFollowing
                      ? const Color(0xFFE5E7EB)
                      : _kPrimary,
                ),
              ),
              child: isPending
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: _kPrimary),
                    )
                  : Text(
                      isFollowing ? 'Following' : 'Follow',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isFollowing
                            ? const Color(0xFF6B7280)
                            : Colors.white,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final hasQuery = _searchCtrl.text.isNotEmpty;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(hasQuery ? '🔍' : '👤',
              style: const TextStyle(fontSize: 52)),
          const SizedBox(height: 16),
          Text(
            hasQuery ? 'No users found' : 'Search for travelers',
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF9CA3AF)),
          ),
          const SizedBox(height: 6),
          Text(
            hasQuery
                ? 'Try a different name'
                : 'Type a name to find people',
            style: const TextStyle(
                fontSize: 13, color: Color(0xFFBBBBBB)),
          ),
        ],
      ),
    );
  }
}
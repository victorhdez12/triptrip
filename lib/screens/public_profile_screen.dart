// ══════════════════════════════════════════════════════════════
// PUBLIC PROFILE SCREEN
// Perfil de OTRO viajero: cabecera (avatar, nombre, redes, stats),
// sus itinerarios públicos, sus lugares (posts con fotos) y los
// países que ha visitado. Es una pantalla apilada (tiene Scaffold).
//
// Fuentes de datos (todas tolerantes a fallos):
//   · ProfileService.loadStats(uid)
//   · ItineraryService.listByUser(uid)
//   · FeedService.getUserPosts(uid)
//   · VisitedCountriesService().getVisitedCountries(uid)
// ══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../l10n.dart';
import '../services/feed_service.dart';
import '../services/social_service.dart';
import '../services/itinerary_service.dart';
import '../services/profile_service.dart';
import '../services/visited_countries_service.dart';
import '../widgets/common_widgets.dart';
import 'itinerary_detail_screen.dart';
import 'place_detail_screen.dart';
import 'follow_list_screen.dart';

class PublicProfileScreen extends StatefulWidget {
  final String uid;
  final String displayName; // para pintar la cabecera al instante
  final String avatarColor; // hex tipo '#29B6D2'

  const PublicProfileScreen({
    super.key,
    required this.uid,
    this.displayName = '',
    this.avatarColor = '#29B6D2',
  });

  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen> {
  // ── variables ────────────────────────────────────────────
  bool _loading = true;
  ProfileStats _stats = ProfileStats.empty;
  List<ItineraryCard> _itineraries = const [];
  List<FeedItem> _posts = const [];
  List<VisitedCountry> _countries = const [];
  int _followers = 0;
  int _following = 0;
  bool _isFollowing = false;
  String get _currentUid => FirebaseAuth.instance.currentUser?.uid ?? '';

  // ── ciclo de vida ────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _load();
  }

  // ── lógica privada ───────────────────────────────────────
  Future<void> _load() async {
    final uid = widget.uid;
    // Cuatro cargas en paralelo; cada servicio devuelve vacío si falla.
    final results = await Future.wait([
      ProfileService.loadStats(uid),
      ItineraryService.listByUser(uid),
      FeedService.getUserPosts(uid),
      VisitedCountriesService().getVisitedCountries(uid),
    ]);
    if (!mounted) return;
    setState(() {
      _stats = results[0] as ProfileStats;
      _itineraries = results[1] as List<ItineraryCard>;
      _posts = results[2] as List<FeedItem>;
      _countries = results[3] as List<VisitedCountry>;
      _loading = false;
    });
    final counts = await SocialService.getFollowCounts(uid);
    final isFol = (_currentUid.isNotEmpty && _currentUid != uid)
        ? await SocialService.isFollowing(_currentUid, uid)
        : false;
    if (!mounted) return;
    setState(() {
      _followers = counts['followers'] ?? 0;
      _following = counts['following'] ?? 0;
      _isFollowing = isFol;
    });
  }

  Color _hexToColor(String hex) {
    var h = hex.replaceAll('#', '').trim();
    if (h.length == 6) h = 'FF$h';
    return Color(int.tryParse(h, radix: 16) ?? 0xFF29B6D2);
  }

  // Convierte un código ISO de 2 letras (ES, FR…) en emoji de bandera.
  String _flagEmoji(String code) {
    final c = code.trim().toUpperCase();
    if (c.length != 2) return '🏳️';
    const base = 0x1F1E6; // 'A' regional indicator
    final a = base + (c.codeUnitAt(0) - 65);
    final b = base + (c.codeUnitAt(1) - 65);
    return String.fromCharCode(a) + String.fromCharCode(b);
  }

  void _openItinerary(ItineraryCard it) {
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => ItineraryDetailScreen(itineraryId: it.id)),
    );
  }

  void _openPlace(FeedItem post) {
    final placeId = post.data['place_id']?.toString() ?? '';
    if (placeId.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PlaceDetailScreen(placeId: placeId)),
    );
  }

  // ── build ────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final name =
        _stats.displayName.isNotEmpty ? _stats.displayName : widget.displayName;
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: const Color(0xFF1A1A2E),
        title: Text(
          name.isEmpty ? tr('Profile', 'Perfil') : name,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kPrimary))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                children: [
                  _buildHeader(name),
                  if (_itineraries.isNotEmpty) _buildItineraries(),
                  if (_posts.isNotEmpty) _buildPosts(),
                  if (_countries.isNotEmpty) _buildCountries(),
                  if (_itineraries.isEmpty &&
                      _posts.isEmpty &&
                      _countries.isEmpty)
                    _buildEmpty(),
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  // ── cabecera ─────────────────────────────────────────────
  Widget _buildHeader(String name) {
    final color = _hexToColor(widget.avatarColor);
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final socials = <String>[
      if (_stats.instagram.isNotEmpty) '📷 @${_stats.instagram}',
      if (_stats.tiktok.isNotEmpty) '🎵 @${_stats.tiktok}',
    ];
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
      child: Column(
        children: [
          CircleAvatar(
            radius: 38,
            backgroundColor: color,
            backgroundImage: _stats.avatarUrl.isNotEmpty
                ? NetworkImage(_stats.avatarUrl)
                : null,
            child: _stats.avatarUrl.isNotEmpty
                ? null
                : Text(
                    initial,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.w800),
                  ),
          ),
          const SizedBox(height: 10),
          Text(
            name.isEmpty ? 'Traveler' : name,
            style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1A1A2E)),
          ),
          if (_stats.bio.isNotEmpty) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                _stats.bio,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 14, height: 1.35, color: Color(0xFF4B5563)),
              ),
            ),
          ],
          if (socials.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              socials.join('     '),
              style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _stat('$_followers', tr('Followers', 'Seguidores'),
                  onTap: () => _openFollowList(true)),
              _stat('$_following', tr('Following', 'Siguiendo'),
                  onTap: () => _openFollowList(false)),
              _stat('${_stats.countriesCount}', tr('Countries', 'Países')),
            ],
          ),
          if (_currentUid.isNotEmpty && _currentUid != widget.uid) ...[
            const SizedBox(height: 14),
            _buildFollowButton(),
          ],
        ],
      ),
    );
  }

  Widget _stat(String value, String label, {VoidCallback? onTap}) {
    final col = Column(
      children: [
        Text(value,
            style: const TextStyle(
                fontSize: 20, fontWeight: FontWeight.w800, color: kPrimary)),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
      ],
    );
    if (onTap == null) return col;
    return GestureDetector(
        behavior: HitTestBehavior.opaque, onTap: onTap, child: col);
  }

  Widget _buildFollowButton() {
    return GestureDetector(
      onTap: _toggleFollow,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 10),
        decoration: BoxDecoration(
          color: _isFollowing ? Colors.white : kPrimary,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: kPrimary, width: 1.5),
        ),
        child: Text(
          _isFollowing ? tr('Following', 'Siguiendo') : tr('Follow', 'Seguir'),
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: _isFollowing ? kPrimary : Colors.white,
          ),
        ),
      ),
    );
  }

  Future<void> _toggleFollow() async {
    if (_currentUid.isEmpty) return;
    final was = _isFollowing;
    setState(() {
      _isFollowing = !was;
      _followers += was ? -1 : 1;
    });
    if (was) {
      await SocialService.unfollow(_currentUid, widget.uid);
    } else {
      await SocialService.follow(_currentUid, widget.uid);
    }
  }

  void _openFollowList(bool followers) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FollowListScreen(uid: widget.uid, followers: followers),
      ),
    );
  }

  Widget _sectionTitle(String s) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
        child: Text(s,
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1A1A2E))),
      );

  // ── itinerarios públicos ─────────────────────────────────
  Widget _buildItineraries() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(tr('Itineraries', 'Itinerarios')),
        ..._itineraries.map((it) => Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: GestureDetector(
                onTap: () => _openItinerary(it),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFEEF0F4)),
                  ),
                  child: Row(
                    children: [
                      Text(it.countryFlag,
                          style: const TextStyle(fontSize: 26)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              it.title.isEmpty ? it.destination : it.title,
                              style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF1A1A2E)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${it.destination} · ${it.totalDays} ${tr('days', 'días')} · ${it.totalPlaces} ${tr('places', 'lugares')}',
                              style: const TextStyle(
                                  fontSize: 12, color: Color(0xFF6B7280)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: Color(0xFF9CA3AF)),
                    ],
                  ),
                ),
              ),
            )),
      ],
    );
  }

  // ── lugares (posts con foto, rejilla) ────────────────────
  Widget _buildPosts() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(tr('Places', 'Lugares')),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            children: _posts.map(_buildPostTile).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildPostTile(FeedItem post) {
    final d = post.data;
    final media = (d['media'] as List?)?.cast<String>() ?? const <String>[];
    final cover =
        media.isNotEmpty ? media.first : (d['cover_image_url'] as String?);
    final name = d['place_name'] as String? ?? '';
    return GestureDetector(
      onTap: () => _openPlace(post),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: (cover != null && cover.isNotEmpty)
            ? Image.network(
                cover,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _tilePlaceholder(name),
                loadingBuilder: (ctx, child, progress) =>
                    progress == null ? child : _tilePlaceholder(name),
              )
            : _tilePlaceholder(name),
      ),
    );
  }

  Widget _tilePlaceholder(String name) => Container(
        color: const Color(0xFFEEF1F5),
        padding: const EdgeInsets.all(6),
        alignment: Alignment.center,
        child: Text(
          name,
          maxLines: 3,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF6B7280)),
        ),
      );

  // ── países visitados (chips con bandera) ─────────────────
  Widget _buildCountries() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('${tr('Countries', 'Países')} (${_countries.length})'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _countries.map((c) {
              final label = c.nameEs ?? c.nameEn ?? c.countryCode;
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0xFFEEF0F4)),
                ),
                child: Text(
                  '${_flagEmoji(c.countryCode)}  $label',
                  style: const TextStyle(
                      fontSize: 13, color: Color(0xFF1A1A2E)),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildEmpty() => Padding(
        padding: const EdgeInsets.all(40),
        child: Center(
          child: Text(
            tr('No public activity yet.', 'Aún no hay actividad pública.'),
            style: const TextStyle(color: Color(0xFF9CA3AF)),
          ),
        ),
      );
}
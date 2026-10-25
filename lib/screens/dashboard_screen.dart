// lib/screens/dashboard_screen.dart
//
// Pestaña Home. Responde a una sola pregunta: "¿qué pasa con mi viaje
// y con mi gente?". El descubrimiento abierto vive en Explorar.
//
//   1. Próximo viaje: cuenta atrás + cuántos sitios lleva guardados
//   2. Feed del grafo conocido, agregado por objeto:
//      cinco amigos guardando el mismo sitio = una tarjeta, no cinco
//   3. Sin viaje y sin feed: invitaciones a actuar, nunca pantalla vacía

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/feed_service.dart';
import '../widgets/social_actions_bar.dart';
import 'plan_trip_screen.dart';
import 'place_detail_screen.dart';
import 'search_users_screen.dart';

const _kPrimary = Color(0xFF29B6D2);
const _kDark = Color(0xFF1A1A2E);
const _kMuted = Color(0xFF9CA3AF);

const _kCatGradients = <String, List<Color>>{
  'Restaurants': [Color(0xFFFF7B54), Color(0xFFDB4437)],
  'Activities': [Color(0xFF29B6D2), Color(0xFF0284C7)],
  'Museums': [Color(0xFF7C3AED), Color(0xFF5B21B6)],
  'Nature': [Color(0xFF10B981), Color(0xFF047857)],
  'Shopping': [Color(0xFFEC4899), Color(0xFFBE185D)],
  'Nightlife': [Color(0xFF334155), Color(0xFF0F172A)],
};

const _kCatEmoji = <String, String>{
  'Restaurants': '🍽️',
  'Activities': '🎯',
  'Museums': '🏛️',
  'Nature': '🌿',
  'Shopping': '🛍️',
  'Nightlife': '🌙',
};

// ══════════════════════════════════════════════════════════════
// DASHBOARD SCREEN
// ══════════════════════════════════════════════════════════════

class DashboardScreen extends StatefulWidget {
  final VoidCallback onGoToProfile;

  const DashboardScreen({super.key, required this.onGoToProfile});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic>? _trip;
  int _savedInTrip = 0;

  final _feed = <FeedItem>[];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _offset = 0;
  static const _pageSize = 20;

  final _scroll = ScrollController();

  String get _displayName =>
      FirebaseAuth.instance.currentUser?.displayName ?? 'Traveler';

  String? get _tripId => _trip?['id']?.toString();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _loadAll();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 400 &&
        _hasMore &&
        !_loadingMore &&
        !_loading) {
      _loadFeed();
    }
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _feed.clear();
      _offset = 0;
      _hasMore = true;
    });

    final trip = await FeedService.nextTrip();
    final saved =
        trip == null ? 0 : await FeedService.savedInTrip(trip['id'].toString());

    if (!mounted) return;
    setState(() {
      _trip = trip;
      _savedInTrip = saved;
    });

    await _loadFeed(first: true);
  }

  Future<void> _loadFeed({bool first = false}) async {
    if (!first) setState(() => _loadingMore = true);
    final rows = await FeedService.feed(offset: _offset, limit: _pageSize);
    if (!mounted) return;
    setState(() {
      _feed.addAll(rows);
      _offset += rows.length;
      _hasMore = rows.length == _pageSize;
      _loading = false;
      _loadingMore = false;
    });
  }

  // ── Build ───────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: RefreshIndicator(
        color: _kPrimary,
        onRefresh: _loadAll,
        child: CustomScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _buildHeader()),
            SliverToBoxAdapter(
              child: _trip == null ? _buildNoTripCard() : _buildTripCard(),
            ),
            SliverToBoxAdapter(child: _sectionHeader('De tu gente')),
            if (_loading)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 60),
                  child: Center(
                      child: CircularProgressIndicator(color: _kPrimary)),
                ),
              )
            else if (_feed.isEmpty)
              SliverToBoxAdapter(child: _buildEmptyFeed())
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => _FeedCard(
                      item: _feed[i],
                      tripId: _tripId,
                      displayName: _displayName,
                      onOpen: () => _openPlace(_feed[i]),
                    ),
                    childCount: _feed.length,
                  ),
                ),
              ),
            if (_loadingMore)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                      child: CircularProgressIndicator(color: _kPrimary)),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 48)),
          ],
        ),
      ),
    );
  }

  void _openPlace(FeedItem item) {
    if (item.placeId.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => PlaceDetailScreen(placeId: item.placeId)),
    );
  }

  // ── Header ──────────────────────────────────────────────────

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('TripTrip',
                    style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: _kDark)),
                SizedBox(height: 3),
                Text('Lo que se mueve en tu círculo',
                    style: TextStyle(fontSize: 14, color: _kMuted)),
              ],
            ),
          ),
          GestureDetector(
            onTap: widget.onGoToProfile,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child:
                  const Icon(Icons.person_outline, size: 21, color: _kPrimary),
            ),
          ),
        ],
      ),
    );
  }

  // ── Próximo viaje ───────────────────────────────────────────

  Widget _buildTripCard() {
    final trip = _trip!;
    final start = DateTime.tryParse(trip['start_date']?.toString() ?? '');
    final days = start?.difference(DateTime.now()).inDays;
    final destination = trip['destination'] as String? ?? '';
    final title = (trip['trip_name'] as String?)?.isNotEmpty == true
        ? trip['trip_name'] as String
        : (destination.isNotEmpty ? destination : 'Tu viaje');
    final inviteCode = trip['invite_code'] as String? ?? '';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [_kPrimary, Color(0xFF0284C7)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: _kPrimary.withValues(alpha: 0.28),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        days == null
                            ? 'Tu próximo viaje'
                            : days <= 0
                                ? 'En marcha'
                                : days == 1
                                    ? 'Mañana'
                                    : 'En $days días',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withValues(alpha: 0.85)),
                      ),
                      const SizedBox(height: 4),
                      Text(title,
                          style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: Colors.white)),
                    ],
                  ),
                ),
                if (inviteCode.isNotEmpty)
                  GestureDetector(
                    onTap: () =>
                        _showTripShareSheet(destination, inviteCode),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.ios_share_rounded,
                          size: 18, color: Colors.white),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _pill(
                  _savedInTrip == 0
                      ? 'Sin sitios todavía'
                      : _savedInTrip == 1
                          ? '1 sitio guardado'
                          : '$_savedInTrip sitios guardados',
                  Icons.bookmark_border,
                ),
                const SizedBox(width: 8),
                if (_savedInTrip == 0) _pill('Añade el primero', Icons.add),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Compartir viaje (WhatsApp / Copiar / Email) ──────────────

  void _showTripShareSheet(String destination, String inviteCode) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFDDDDDD),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            const Text('Invitar a viajeros',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text('Comparte este código con tus compañeros de viaje',
                style: TextStyle(fontSize: 13, color: Color(0xFF999999))),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 18),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F4FF),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: Text(inviteCode,
                    style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w900,
                        color: _kDark,
                        letterSpacing: 10)),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _ShareOptionButton(
                    icon: '📱',
                    label: 'WhatsApp',
                    color: const Color(0xFF25D366),
                    onTap: () =>
                        _shareTripViaWhatsApp(destination, inviteCode),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ShareOptionButton(
                    icon: '📋',
                    label: 'Copiar',
                    color: _kPrimary,
                    onTap: () {
                      Navigator.pop(context);
                      Clipboard.setData(ClipboardData(
                          text:
                              'Únete a mi viaje a $destination! Código: $inviteCode'));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Enlace copiado al portapapeles'),
                            backgroundColor: _kPrimary),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ShareOptionButton(
                    icon: '✉️',
                    label: 'Email',
                    color: const Color(0xFFE8533A),
                    onTap: () => _shareTripViaEmail(destination, inviteCode),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _shareTripViaWhatsApp(String destination, String code) async {
    final message = 'Únete a mi viaje a $destination! Código: $code';
    final uri = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(message)}');
    Navigator.pop(context);
    final launched =
        await launchUrl(uri, mode: LaunchMode.externalApplication)
            .catchError((_) => false);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No se pudo abrir WhatsApp. ¿Está instalado?')));
    }
  }

  Future<void> _shareTripViaEmail(String destination, String code) async {
    final subject = 'Únete a mi viaje a $destination';
    final body =
        'Únete a mi viaje a $destination!\n\nCódigo de invitación: $code';
    final uri = Uri(
      scheme: 'mailto',
      query:
          'subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(body)}',
    );
    Navigator.pop(context);
    final launched =
        await launchUrl(uri, mode: LaunchMode.externalApplication)
            .catchError((_) => false);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo abrir la app de correo.')));
    }
  }

  Widget _pill(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white)),
        ],
      ),
    );
  }

  Widget _buildNoTripCard() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
      child: GestureDetector(
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const PlanTripScreen())),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _kPrimary.withValues(alpha: 0.3)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _kPrimary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.add, color: _kPrimary, size: 22),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Crea tu próximo viaje',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: _kDark)),
                    SizedBox(height: 2),
                    Text('Lo que guardes tendrá dónde aterrizar',
                        style: TextStyle(fontSize: 12.5, color: _kMuted)),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios,
                  size: 13, color: Color(0xFFD1D5DB)),
            ],
          ),
        ),
      ),
    );
  }

  // ── Varios ──────────────────────────────────────────────────

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 10),
      child: Text(title,
          style: const TextStyle(
              fontSize: 18, fontWeight: FontWeight.w700, color: _kDark)),
    );
  }

  Widget _buildEmptyFeed() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 30, 40, 60),
      child: Column(
        children: [
          Icon(Icons.groups_outlined, size: 60, color: Colors.grey.shade300),
          const SizedBox(height: 14),
          const Text('Aquí verás lo que guardan y visitan tus amigos',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6B7280))),
          const SizedBox(height: 6),
          const Text('Sigue a algunos viajeros para empezar',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: _kMuted)),
          const SizedBox(height: 18),
          GestureDetector(
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SearchUsersScreen())),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
              decoration: BoxDecoration(
                color: _kPrimary,
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Text('Buscar viajeros',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// TARJETA DE FEED
// ══════════════════════════════════════════════════════════════

class _FeedCard extends StatelessWidget {
  final FeedItem item;
  final String? tripId;
  final String displayName;
  final VoidCallback onOpen;

  const _FeedCard({
    required this.item,
    required this.tripId,
    required this.displayName,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final colors =
        _kCatGradients[item.category] ?? [_kPrimary, const Color(0xFF006D8F)];
    final emoji = _kCatEmoji[item.category] ?? item.countryFlag;
    final avatars = item.actorNames.length.clamp(0, 3);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Quién ─────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 0),
            child: Row(
              children: [
                SizedBox(
                  width: avatars == 0 ? 0 : 28.0 + (avatars - 1) * 15.0,
                  height: 28,
                  child: Stack(
                    children: [
                      for (var i = 0; i < avatars; i++)
                        Positioned(
                          left: i * 15.0,
                          child: _Avatar(name: item.actorNames[i]),
                        ),
                    ],
                  ),
                ),
                if (avatars > 0) const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item.headline,
                    style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF4B5563)),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (item.isTrending)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _kPrimary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text('Tendencia',
                        style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: _kPrimary)),
                  ),
              ],
            ),
          ),

          // ── Qué ───────────────────────────────────────────
          GestureDetector(
            onTap: onOpen,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: colors,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                        child:
                            Text(emoji, style: const TextStyle(fontSize: 22))),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.placeName,
                            style: const TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w700,
                                color: _kDark),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                        if (item.location.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(item.location,
                              style: const TextStyle(
                                  fontSize: 12.5, color: _kMuted),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Acciones ──────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: SocialActionsBar(
              key: ValueKey('feed-${item.placeId}'),
              placeId: item.placeId,
              initialLiked: item.likedByMe,
              initialSaved: item.savedByMe,
              initialLikeCount: item.likesCount,
              initialCommentCount: item.commentsCount,
              tripId: tripId,
              displayName: displayName,
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// SHARE OPTION BUTTON (WhatsApp / Copiar / Email)
// ══════════════════════════════════════════════════════════════

class _ShareOptionButton extends StatelessWidget {
  final String icon, label;
  final Color color;
  final VoidCallback onTap;
  const _ShareOptionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12)),
          child: Column(
            children: [
              Text(icon, style: const TextStyle(fontSize: 24)),
              const SizedBox(height: 4),
              Text(label,
                  style: TextStyle(
                      fontSize: 12, color: color, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );
}

// ══════════════════════════════════════════════════════════════
// AVATAR
// ══════════════════════════════════════════════════════════════

class _Avatar extends StatelessWidget {
  final String name;
  const _Avatar({required this.name});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: _kPrimary.withValues(alpha: 0.14),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: Center(
        child: Text(
          name.isEmpty ? '?' : name.substring(0, 1).toUpperCase(),
          style: const TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, color: _kPrimary),
        ),
      ),
    );
  }
}

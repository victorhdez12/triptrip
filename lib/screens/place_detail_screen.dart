// lib/screens/place_detail_screen.dart
//
// Detalle público de un lugar/restaurante (tabla place_visits):
//   • Hero con flag + nombre + ubicación + categoría
//   • Autor + stats (★ media, ❤ favoritos, 💬 comentarios)
//   • Nota del autor + su valoración
//   • Acciones del viewer: ❤ favoritar, ★ ratear (1-5), 💬 comentar
//
// Calcado de itinerary_detail_screen.dart (sin días ni clonar a viaje,
// que no aplican a un lugar suelto).

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../services/affiliate_service.dart';
import '../services/media_service.dart';
import '../services/place_social_service.dart';
import '../widgets/common_widgets.dart';
import '../widgets/folder_picker_sheet.dart';
import 'place_comments_screen.dart';

class PlaceDetailScreen extends StatefulWidget {
  final String placeId;
  const PlaceDetailScreen({super.key, required this.placeId});

  @override
  State<PlaceDetailScreen> createState() => _PlaceDetailScreenState();
}

class _PlaceDetailScreenState extends State<PlaceDetailScreen> {
  PlaceDetail? _detail;
  bool _loading = true;
  List<String> _photos = const [];

  static const _catGradients = <String, List<Color>>{
    'Restaurants': [Color(0xFFFF7B54), Color(0xFFE5533B)],
    'Activities':  [kPrimary, Color(0xFF006D8F)],
    'Museums':     [Color(0xFF7C3AED), Color(0xFF4C1D95)],
    'Nature':      [Color(0xFF10B981), Color(0xFF047857)],
    'Shopping':    [Color(0xFFEC4899), Color(0xFFBE185D)],
    'Nightlife':   [Color(0xFF334155), Color(0xFF0F172A)],
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final d = await PlaceSocialService.getDetail(widget.placeId);
    final ph = await MediaService.listPlaceMedia(widget.placeId);
    if (!mounted) return;
    setState(() {
      _detail = d;
      _photos = ph;
      _loading = false;
    });
  }

  void _show(String msg, [Color color = kPrimary]) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  // ── ACCIONES ────────────────────────────────────────────────
  Future<void> _toggleFavorite() async {
    final d = _detail;
    if (d == null) return;
    final fav = await showFolderPicker(context, kind: 'place', itemId: d.card.id);
    if (fav == null || !mounted) return;
    _load(); // refresca flag + contador
  }

  Future<void> _rate(int stars) async {
    final d = _detail;
    if (d == null) return;
    final ok = await PlaceSocialService.rate(d.card.id, stars);
    if (!mounted) return;
    if (ok) {
      _show('Rating saved ⭐');
      _load();
    } else {
      _show('Could not save rating', Colors.redAccent);
    }
  }

  Future<void> _openComments() async {
    final d = _detail;
    if (d == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlaceCommentsScreen(placeId: d.card.id),
      ),
    );
    _load(); // refresca counter
  }

  // ── UI ──────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: kBackground,
        body: Center(child: CircularProgressIndicator(color: kPrimary)),
      );
    }
    final d = _detail;
    if (d == null) {
      return Scaffold(
        backgroundColor: kBackground,
        appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
        body: const Center(child: Text('Place not found')),
      );
    }
    final c = d.card;
    final gradient = _catGradients[c.category] ?? const [kPrimary, Color(0xFF006D8F)];

    return Scaffold(
      backgroundColor: kBackground,
      body: CustomScrollView(
        slivers: [
          // ── HEADER hero ─────────────────────────────────────
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            backgroundColor: gradient.first,
            iconTheme: const IconThemeData(color: Colors.white),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: gradient,
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 50, 20, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(c.countryFlag, style: const TextStyle(fontSize: 32)),
                        const SizedBox(height: 6),
                        Text(c.placeName,
                          style: const TextStyle(
                            fontSize: 26, fontWeight: FontWeight.w900,
                            color: Colors.white, letterSpacing: -0.5,
                          ),
                          maxLines: 2, overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          c.category.isEmpty ? c.location : '${c.category} · ${c.location}',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white.withOpacity(0.92),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            actions: [
              IconButton(
                icon: Icon(
                  d.viewerFavorited ? Icons.favorite : Icons.favorite_border,
                  color: Colors.white,
                ),
                onPressed: _toggleFavorite,
              ),
            ],
          ),

          // ── AUTOR + STATS ───────────────────────────────────
          SliverToBoxAdapter(
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: _hexToColor(c.avatarColor),
                        child: Text(
                          c.displayName.isNotEmpty
                              ? c.displayName[0].toUpperCase()
                              : 'T',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(c.displayName,
                              style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w700,
                                color: Color(0xFF1A1A2E),
                              ),
                            ),
                            Text(_relTime(c.createdAt),
                              style: const TextStyle(
                                fontSize: 12, color: Color(0xFF9CA3AF),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 16, runSpacing: 6,
                    children: [
                      _statChip('⭐', '${c.avgRating.toStringAsFixed(1)} (${c.ratingsCount})'),
                      _statChip('❤️', '${c.favoritesCount}'),
                      _statChip('💬', '${c.commentsCount}'),
                      if (c.authorRating > 0)
                        _statChip('👤', c.authorRating.toStringAsFixed(1)),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // ── GALERÍA del sitio (todas las fotos de la comunidad) ─
          if (_photos.isNotEmpty)
            SliverToBoxAdapter(
              child: Container(
                color: Colors.white,
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.fromLTRB(20, 14, 0, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 20, bottom: 10),
                      child: Text('Photos (${_photos.length})',
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1A1A2E))),
                    ),
                    SizedBox(
                      height: 130,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _photos.length,
                        itemBuilder: (_, i) => Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: CachedNetworkImage(
                              imageUrl: _photos[i],
                              width: 130, height: 130, fit: BoxFit.cover,
                              placeholder: (_, __) => Container(
                                  width: 130, height: 130,
                                  color: const Color(0xFFF3F4F6)),
                              errorWidget: (_, __, ___) => Container(
                                  width: 130, height: 130,
                                  color: const Color(0xFFF3F4F6)),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ── NOTA del autor ──────────────────────────────────
          if ((c.note ?? '').isNotEmpty)
            SliverToBoxAdapter(
              child: Container(
                color: Colors.white,
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('"',
                      style: TextStyle(
                        fontSize: 22, color: kPrimary,
                        fontWeight: FontWeight.w700, height: 0.9,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(c.note!,
                        style: const TextStyle(
                          fontSize: 14, color: Color(0xFF374151), height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ── RATING (tap stars) ──────────────────────────────
          SliverToBoxAdapter(
            child: Container(
              color: Colors.white,
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
              child: Row(
                children: [
                  const Text('Your rating',
                    style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                  const Spacer(),
                  for (int i = 1; i <= 5; i++)
                    GestureDetector(
                      onTap: () => _rate(i),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Icon(
                          (d.viewerRating ?? 0) >= i
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded,
                          color: (d.viewerRating ?? 0) >= i
                              ? const Color(0xFFFFB400)
                              : const Color(0xFFD1D5DB),
                          size: 30,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // ── RESERVAR (afiliación; solo si hay partner) ──────
          SliverToBoxAdapter(
            child: Builder(builder: (_) {
              final link = AffiliateService.linkFor(
                placeName: c.placeName,
                location: c.location,
                category: c.category,
              );
              if (link == null) return const SizedBox.shrink();
              return Container(
                color: Colors.white,
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => AffiliateService.open(link, category: c.category),
                    icon: const Icon(Icons.open_in_new,
                        size: 18, color: kPrimary),
                    label: Text('Reserve on ${link.partner}',
                        style: const TextStyle(
                            color: kPrimary, fontWeight: FontWeight.w700)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      side: const BorderSide(color: kPrimary, width: 1.5),
                    ),
                  ),
                ),
              );
            }),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),

      // ── BOTTOM ACTIONS ──────────────────────────────────────
      bottomNavigationBar: SafeArea(
        child: Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _openComments,
                  icon: const Icon(Icons.chat_bubble_outline, color: kPrimary),
                  label: const Text('Comments',
                    style: TextStyle(color: kPrimary, fontWeight: FontWeight.w700),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    side: const BorderSide(color: kPrimary, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: _toggleFavorite,
                  icon: Icon(
                    d.viewerFavorited ? Icons.favorite : Icons.favorite_border,
                    color: Colors.white,
                  ),
                  label: Text(
                    d.viewerFavorited ? 'Saved' : 'Save to favourites',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w800),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: d.viewerFavorited ? kOrange : kPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statChip(String emoji, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 14)),
        const SizedBox(width: 4),
        Text(label,
          style: const TextStyle(
            fontSize: 13, color: Color(0xFF374151), fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  static Color _hexToColor(String hex) {
    final cleaned = hex.replaceAll('#', '');
    return Color(int.parse('FF$cleaned', radix: 16));
  }

  static String _relTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inDays > 365) return '${(diff.inDays / 365).floor()}y ago';
    if (diff.inDays > 30)  return '${(diff.inDays / 30).floor()}mo ago';
    if (diff.inDays > 0)   return '${diff.inDays}d ago';
    if (diff.inHours > 0)  return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'just now';
  }
}
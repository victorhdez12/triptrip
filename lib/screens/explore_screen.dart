// lib/screens/explore_screen.dart

import 'package:flutter/material.dart';

import '../services/place_social_service.dart';
import 'search_users_screen.dart';
import 'place_detail_screen.dart';

const _kPrimary = Color(0xFF29B6D2);
const _kDark = Color(0xFF1A1A2E);

// Gradientes por categoría (usados en place cards y trip cards)
const _kCatGradients = <String, List<Color>>{
  'Restaurants': [Color(0xFFFF7B54), Color(0xFFDB4437)],
  'Activities':  [Color(0xFF29B6D2), Color(0xFF0284C7)],
  'Museums':     [Color(0xFF7C3AED), Color(0xFF5B21B6)],
  'Nature':      [Color(0xFF10B981), Color(0xFF047857)],
  'Shopping':    [Color(0xFFEC4899), Color(0xFFBE185D)],
  'Nightlife':   [Color(0xFF334155), Color(0xFF0F172A)],
};

// ══════════════════════════════════════════════════════════════
// EXPLORE SCREEN
// ══════════════════════════════════════════════════════════════

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  String _activeFilter = 'All';

  // ── Explore real + scroll infinito ───────────────────────
  final _places = <Map<String, dynamic>>[];
  bool _loading = true;
  bool _loadingMore = false;
  int _offset = 0;
  bool _hasMore = true;
  final ScrollController _scroll = ScrollController();
  static const _pageSize = 20;
  // Incrementado en cada reset; descarta respuestas de filtros ya obsoletos
  // (p. ej. tap rápido en 'Restaurants' → 'Museums' antes de que responda
  // la primera petición).
  int _requestGen = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _loadPlaces(reset: true);
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 400 &&
        _hasMore &&
        !_loadingMore &&
        !_loading) {
      _loadPlaces();
    }
  }

  Future<void> _loadPlaces({bool reset = false}) async {
    if (reset) {
      _requestGen++;
      setState(() {
        _loading = true;
        _places.clear();
        _offset = 0;
        _hasMore = true;
      });
    } else {
      setState(() => _loadingMore = true);
    }
    final gen = _requestGen;
    final rows = await PlaceSocialService.listCatalog(
        category: _activeFilter, offset: _offset, limit: _pageSize);
    if (!mounted || gen != _requestGen) return; // filtro cambiado entretanto
    setState(() {
      _places.addAll(rows);
      _offset += rows.length;
      _hasMore = rows.length == _pageSize;
      _loading = false;
      _loadingMore = false;
    });
  }

  List<Map<String, dynamic>> get _visiblePlaces {
    final q = _searchCtrl.text.toLowerCase();
    if (q.isEmpty) return _places;
    return _places
        .where((p) =>
            (p['name'] as String? ?? '').toLowerCase().contains(q) ||
            (p['location'] as String? ?? '').toLowerCase().contains(q))
        .toList();
  }

  void _openPlace(Map<String, dynamic> p) {
    final id = p['id']?.toString() ?? '';
    if (id.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PlaceDetailScreen(placeId: id)),
    );
  }
  final _searchCtrl = TextEditingController();

  final _filters = <Map<String, String>>[
    {'label': 'All',         'emoji': '🌍'},
    {'label': 'Restaurants', 'emoji': '🍽️'},
    {'label': 'Activities',  'emoji': '🎯'},
    {'label': 'Museums',     'emoji': '🏛️'},
    {'label': 'Nature',      'emoji': '🌿'},
    {'label': 'Shopping',    'emoji': '🛍️'},
    {'label': 'Nightlife',   'emoji': '🌙'},
  ];

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final places = _visiblePlaces;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: CustomScrollView(
        controller: _scroll,
        slivers: [
          SliverToBoxAdapter(child: _buildHeader()),
          SliverToBoxAdapter(child: _buildFindPeopleButton()),
          SliverToBoxAdapter(child: _buildFilters()),
          SliverToBoxAdapter(
            child: _sectionHeader(
              _activeFilter == 'All' ? 'Popular Places' : 'Popular $_activeFilter',
            ),
          ),
          if (_loading)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 60),
                child: Center(
                    child: CircularProgressIndicator(color: _kPrimary)),
              ),
            )
          else if (places.isEmpty)
            SliverToBoxAdapter(child: _buildEmptyState())
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverGrid(
                delegate: SliverChildBuilderDelegate(
                  (_, i) => GestureDetector(
                    onTap: () => _openPlace(places[i]),
                    child: _buildPlaceCard(places[i]),
                  ),
                  childCount: places.length,
                ),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.78,
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
    );
  }

  // ── Header ─────────────────────────────────────────────────

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Explore',
              style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: _kDark)),
          const SizedBox(height: 3),
          const Text('Discover where travelers have been',
              style: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF))),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'Search destinations, cities...',
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
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  // ── Find people button ─────────────────────────────────────

  Widget _buildFindPeopleButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => const SearchUsersScreen()),
        ),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border:
                Border.all(color: _kPrimary.withValues(alpha: 0.3)),
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
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: _kPrimary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                    child: Text('👤',
                        style: TextStyle(fontSize: 15))),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Find travelers to follow',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: _kDark)),
                    Text('See their trips in your feed',
                        style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF9CA3AF))),
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

  // ── Filters ────────────────────────────────────────────────

  Widget _buildFilters() {
    return SizedBox(
      height: 50,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _filters.length,
        itemBuilder: (_, i) {
          final f = _filters[i];
          final label = f['label']!;
          final isActive = label == _activeFilter;
          return GestureDetector(
            onTap: () {
              setState(() => _activeFilter = label);
              _loadPlaces(reset: true);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 8, top: 6, bottom: 6),
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: isActive ? _kPrimary : Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(f['emoji']!,
                      style: const TextStyle(fontSize: 13)),
                  const SizedBox(width: 5),
                  Text(label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isActive
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: isActive
                            ? Colors.white
                            : const Color(0xFF6B7280),
                      )),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      child: Text(title,
          style: const TextStyle(
              fontSize: 18, fontWeight: FontWeight.w700, color: _kDark)),
    );
  }

  // ── Place card (sin imágenes, gradient por categoría) ───────

  Widget _buildPlaceCard(Map<String, dynamic> place) {
    final category = place['category'] as String;
    final catColors =
        _kCatGradients[category] ?? [_kPrimary, const Color(0xFF006D8F)];
    final emoji = _categoryEmoji(category);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Category gradient cover ───────────────────────
          Expanded(
            child: ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Gradient bg
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: catColors,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                  ),
                  // Decorative circle
                  Positioned(
                    top: -15, right: -15,
                    child: Container(
                      width: 70, height: 70,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
                  ),
                  // Emoji + place name
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(emoji,
                            style: const TextStyle(fontSize: 30)),
                        const Spacer(),
                        Text(
                          place['name'] as String,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // ── Info row ─────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  place['location'] as String,
                  style: const TextStyle(
                      fontSize: 11, color: Color(0xFF9CA3AF)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.bookmark_border,
                      size: 12, color: Color(0xFF9CA3AF)),
                  const SizedBox(width: 3),
                  Text('${place['visitors']} guardados',
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF6B7280))),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 60),
      child: Column(
        children: [
          Icon(Icons.explore_off_outlined,
              size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            'No results for "$_activeFilter"',
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF9CA3AF)),
          ),
          const SizedBox(height: 8),
          const Text(
            'Try a different filter or search another destination',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Color(0xFFBBBBBB)),
          ),
        ],
      ),
    );
  }

  String _categoryEmoji(String category) {
    const map = {
      'Restaurants': '🍽️',
      'Activities':  '🎯',
      'Museums':     '🏛️',
      'Nature':      '🌿',
      'Shopping':    '🛍️',
      'Nightlife':   '🌙',
    };
    return map[category] ?? '📍';
  }
}
// lib/screens/itineraries_screen.dart
//
// Pantalla hub de itinerarios. Tabs:
//   • Explore (públicos, ordenables por recent/top/trending)
//   • Favorites
//   • Mine

import 'package:flutter/material.dart';

import '../services/itinerary_service.dart';
import '../widgets/common_widgets.dart';
import 'itinerary_detail_screen.dart';
import 'publish_itinerary_screen.dart';

class ItinerariesScreen extends StatefulWidget {
  const ItinerariesScreen({super.key});

  @override
  State<ItinerariesScreen> createState() => _ItinerariesScreenState();
}

class _ItinerariesScreenState extends State<ItinerariesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  List<ItineraryCard> _explore = [];
  List<ItineraryCard> _favs    = [];
  List<ItineraryCard> _mine    = [];
  List<ItineraryCard> _topCloned = [];
  bool _loading = true;
  String _sort = 'recent';   // 'recent' | 'top' | 'trending'

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      ItineraryService.listPublic(sort: _sort),
      ItineraryService.listFavorites(),
      ItineraryService.listMine(),
      ItineraryService.listTopCloned(),
    ]);
    if (!mounted) return;
    setState(() {
      _explore = results[0];
      _favs    = results[1];
      _mine    = results[2];
      _topCloned = results[3];
      _loading = false;
    });
  }

  Future<void> _changeSort(String mode) async {
    setState(() => _sort = mode);
    final list = await ItineraryService.listPublic(sort: mode);
    if (!mounted) return;
    setState(() => _explore = list);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('Itineraries',
          style: TextStyle(
            color: Color(0xFF1A1A2E),
            fontWeight: FontWeight.w800,
            fontSize: 20,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline, color: kPrimary),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PublishItineraryScreen()),
              );
              _loadAll();
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          labelColor: kPrimary,
          unselectedLabelColor: const Color(0xFF9CA3AF),
          indicatorColor: kPrimary,
          indicatorWeight: 3,
          labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          tabs: const [
            Tab(text: 'EXPLORE'),
            Tab(text: 'FAVORITES'),
            Tab(text: 'MINE'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kPrimary))
          : TabBarView(
              controller: _tabs,
              children: [
                _buildExplore(),
                _buildList(_favs, emptyText: 'No favorites yet. Tap ❤ on any itinerary.'),
                _buildList(_mine, emptyText: 'You have not published yet. Tap + above.'),
              ],
            ),
    );
  }

  Widget _buildExplore() {
    return RefreshIndicator(
      color: kPrimary,
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        children: [
          // 🏆 Rutas más clonadas (prueba social)
          if (_topCloned.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 8),
              child: Text('🏆 Top routes',
                style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w800,
                  color: Color(0xFF1A1A2E),
                ),
              ),
            ),
            SizedBox(
              height: 96,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _topCloned.length,
                itemBuilder: (_, i) {
                  final c = _topCloned[i];
                  return GestureDetector(
                    onTap: () => _open(c.id),
                    child: Container(
                      width: 190,
                      margin: const EdgeInsets.only(right: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFEEF0F4)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${c.countryFlag} ${c.title}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700,
                              color: Color(0xFF1A1A2E),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(c.destination,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 11, color: Color(0xFF9CA3AF)),
                          ),
                          const Spacer(),
                          Text('🔁 ${c.clonesCount} travelers used it',
                            style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w600,
                              color: kPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 14),
          ],
          Row(
            children: [
              _sortChip('Recent',   'recent'),
              const SizedBox(width: 8),
              _sortChip('Top',      'top'),
              const SizedBox(width: 8),
              _sortChip('Trending', 'trending'),
            ],
          ),
          const SizedBox(height: 12),
          if (_explore.isEmpty)
            _empty('No public itineraries yet. Be the first to publish one!')
          else
            ..._explore.map((c) => _ItineraryListCard(
              card: c,
              onTap: () => _open(c.id),
              onFav: () => _toggleFav(c, listSource: _explore),
            )),
        ],
      ),
    );
  }

  Widget _buildList(List<ItineraryCard> list, {required String emptyText}) {
    if (list.isEmpty) {
      return Center(child: _empty(emptyText));
    }
    return RefreshIndicator(
      color: kPrimary,
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        children: list.map((c) => _ItineraryListCard(
          card: c,
          onTap: () => _open(c.id),
          onFav: () => _toggleFav(c, listSource: list),
        )).toList(),
      ),
    );
  }

  Widget _sortChip(String label, String mode) {
    final active = _sort == mode;
    return GestureDetector(
      onTap: () => _changeSort(mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active ? kPrimary : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: active ? kPrimary : const Color(0xFFE5E7EB)),
        ),
        child: Text(label,
          style: TextStyle(
            color: active ? Colors.white : const Color(0xFF374151),
            fontSize: 13, fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _empty(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
        child: Column(
          children: [
            const Text('🗺️', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 10),
            Text(text, textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14, color: Color(0xFF6B7280), fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );

  Future<void> _open(String id) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ItineraryDetailScreen(itineraryId: id)),
    );
    _loadAll();
  }

  Future<void> _toggleFav(ItineraryCard c, {required List<ItineraryCard> listSource}) async {
    final newState = await ItineraryService.toggleFavorite(c.id, c.isFavorited);
    if (!mounted) return;
    setState(() {
      final idx = listSource.indexWhere((x) => x.id == c.id);
      if (idx >= 0) {
        listSource[idx] = ItineraryCard(
          id: c.id, userUid: c.userUid, displayName: c.displayName,
          avatarColor: c.avatarColor, title: c.title, destination: c.destination,
          countryFlag: c.countryFlag, coverImageUrl: c.coverImageUrl,
          totalDays: c.totalDays, totalPlaces: c.totalPlaces,
          favoritesCount: c.favoritesCount + (newState ? 1 : -1),
          commentsCount: c.commentsCount, clonesCount: c.clonesCount,
          ratingsCount: c.ratingsCount, avgRating: c.avgRating,
          isFavorited: newState, createdAt: c.createdAt,
          groupSize: c.groupSize, budgetPerPerson: c.budgetPerPerson,
          currency: c.currency,
        );
      }
    });
  }
}

// ══════════════════════════════════════════════════════════════
// CARD
// ══════════════════════════════════════════════════════════════

class _ItineraryListCard extends StatelessWidget {
  final ItineraryCard card;
  final VoidCallback onTap;
  final VoidCallback onFav;

  const _ItineraryListCard({
    required this.card,
    required this.onTap,
    required this.onFav,
  });

  static Color _hex(String h) {
    final c = h.replaceAll('#', '');
    return Color(int.parse('FF$c', radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFEEF0F4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: autor
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 14, backgroundColor: _hex(card.avatarColor),
                    child: Text(
                      card.displayName.isNotEmpty
                          ? card.displayName[0].toUpperCase()
                          : 'T',
                      style: const TextStyle(
                        color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(card.displayName,
                      style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700,
                        color: Color(0xFF1A1A2E),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  GestureDetector(
                    onTap: onFav,
                    child: Icon(
                      card.isFavorited ? Icons.favorite : Icons.favorite_border,
                      color: card.isFavorited ? const Color(0xFFEC4899) : const Color(0xFF9CA3AF),
                      size: 22,
                    ),
                  ),
                ],
              ),
            ),
            // Body
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text(card.countryFlag, style: const TextStyle(fontSize: 18)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(card.title,
                        style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800,
                          color: Color(0xFF1A1A2E), letterSpacing: -0.2,
                        ),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ]),
                  const SizedBox(height: 2),
                  Text(card.destination,
                    style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 12, runSpacing: 4,
                    children: [
                      _stat('⭐', '${card.avgRating.toStringAsFixed(1)}'),
                      _stat('❤️', '${card.favoritesCount}'),
                      _stat('💬', '${card.commentsCount}'),
                      _stat('🔁', '${card.clonesCount}'),
                      _stat('📅', '${card.totalDays}d'),
                      if (card.groupSize > 0) _stat('👥', '${card.groupSize}'),
                      if (card.budgetPerPerson > 0)
                        _stat('💰', '${card.currency}${card.budgetPerPerson.toStringAsFixed(0)}/p'),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String e, String v) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(e, style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 3),
          Text(v,
            style: const TextStyle(
              fontSize: 12, color: Color(0xFF374151), fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
}

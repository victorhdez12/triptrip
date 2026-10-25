// lib/screens/trip_recap_screen.dart
//
// Recap post-viaje: valora en un toque las paradas de tu viaje terminado.
// Cada valoración genera un place_visit PÚBLICO → alimenta el feed.
// Al terminar ofrece compartir la Trip Card (story).

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/feed_service.dart';
import '../services/trip_recap_service.dart';
import '../widgets/common_widgets.dart';
import '../widgets/place_categories.dart';
import '../widgets/shareable_trip_card.dart';

class TripRecapScreen extends StatefulWidget {
  final PendingRecap recap;
  const TripRecapScreen({super.key, required this.recap});

  @override
  State<TripRecapScreen> createState() => _TripRecapScreenState();
}

class _TripRecapScreenState extends State<TripRecapScreen> {
  late final List<int> _stars; // 0 = sin valorar (se omite)
  bool _saving = false;

  String _myName = 'Traveler';
  String _myColor = '#29B6D2';

  @override
  void initState() {
    super.initState();
    _stars = List<int>.filled(widget.recap.places.length, 0);
    _loadMyProfile();
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
              : 'Traveler';
          _myColor = res['avatar_color'] as String? ?? '#29B6D2';
        });
      }
    } catch (_) {}
  }

  int get _ratedCount => _stars.where((s) => s > 0).length;

  Future<void> _submit() async {
    if (_saving) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _saving = true);

    var published = 0;
    for (var i = 0; i < widget.recap.places.length; i++) {
      final stars = _stars[i];
      if (stars == 0) continue; // omitida
      final p = widget.recap.places[i];
      try {
        await FeedService.addPlaceVisit(
          uid: uid,
          displayName: _myName,
          avatarColor: _myColor,
          placeName: p.placeName,
          location: widget.recap.destination,
          countryFlag: '📍',
          category: p.category,
          rating: stars.toDouble(),
        );
        published++;
      } catch (_) {}
    }

    await TripRecapService.markDone(widget.recap.groupId);
    if (published > 0) feedChanged.value++;

    if (!mounted) return;
    setState(() => _saving = false);

    // Ofrecer la Trip Card antes de salir
    await showTripCardShareSheet(
      context,
      tripName: widget.recap.tripName,
      destination: widget.recap.destination,
      totalDays: _tripDaysFallback(),
      placesCount: widget.recap.places.length,
    );

    if (mounted) Navigator.pop(context, true);
  }

  // No tenemos los días aquí; aproximamos por nº de paradas (mín. 1).
  int _tripDaysFallback() =>
      widget.recap.places.isEmpty ? 1 : (widget.recap.places.length / 3).ceil().clamp(1, 30);

  Future<void> _skip() async {
    await TripRecapService.markDone(widget.recap.groupId);
    if (mounted) Navigator.pop(context, false);
  }

  void _setStars(int i, int s) {
    HapticFeedback.selectionClick();
    setState(() => _stars[i] = _stars[i] == s ? 0 : s);
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.recap;
    final total = r.places.length;
    return Scaffold(
      backgroundColor: kBackground,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 168,
            pinned: true,
            backgroundColor: kOrange,
            iconTheme: const IconThemeData(color: Colors.white),
            actions: [
              TextButton(
                onPressed: _skip,
                child: const Text('Skip',
                    style: TextStyle(
                        color: Colors.white70, fontWeight: FontWeight.w600)),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [kOrange, Color(0xFFE05E0F)],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 48, 20, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        const Text('🌟', style: TextStyle(fontSize: 30)),
                        const SizedBox(height: 6),
                        Text('How was ${r.destination}?',
                          style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w900,
                            color: Colors.white, letterSpacing: -0.5,
                          ),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text('"${r.tripName}" · $_ratedCount of $total rated',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withOpacity(0.9),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Text(
                'Rate each place in one tap. Every rating is shared to the feed to help other travelers.',
                style: const TextStyle(
                    fontSize: 13, color: Color(0xFF6B7280), height: 1.4),
              ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
            sliver: SliverList.builder(
              itemCount: total,
              itemBuilder: (_, i) => _PlaceRatingCard(
                place: r.places[i],
                stars: _stars[i],
                onRate: (s) => _setStars(i, s),
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 90)),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _saving ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimary,
                disabledBackgroundColor: kPrimary.withOpacity(0.5),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: _saving
                  ? const SizedBox(
                      width: 22, height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: Colors.white),
                    )
                  : Text(
                      _ratedCount == 0
                          ? 'Done'
                          : 'Share $_ratedCount ${_ratedCount == 1 ? 'rating' : 'ratings'}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w800)),
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// TARJETA DE PARADA — misma taxonomía de categorías que el resto
// de la app (placeCategory: emoji + color por categoría).
// ══════════════════════════════════════════════════════════════

class _PlaceRatingCard extends StatelessWidget {
  final RecapPlace place;
  final int stars;
  final ValueChanged<int> onRate;
  const _PlaceRatingCard({
    required this.place,
    required this.stars,
    required this.onRate,
  });

  @override
  Widget build(BuildContext context) {
    final cat = placeCategory(place.category);
    final rated = stars > 0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: rated ? const Color(0xFFFFB400).withOpacity(0.4) : const Color(0xFFEEF0F4),
          width: rated ? 1.5 : 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: cat.color.withOpacity(0.12), shape: BoxShape.circle),
            child: Center(child: Text(cat.emoji, style: const TextStyle(fontSize: 17))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(place.placeName,
                        style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700,
                          color: Color(0xFF1A1A2E),
                        ),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (!rated)
                      const Text('skipped',
                          style: TextStyle(
                              fontSize: 11, color: Color(0xFFD1D5DB))),
                  ],
                ),
                Text(cat.label,
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600, color: cat.color)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (int s = 1; s <= 5; s++)
                      GestureDetector(
                        onTap: () => onRate(s),
                        child: Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Icon(
                            stars >= s
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                            size: 28,
                            color: stars >= s
                                ? const Color(0xFFFFB400)
                                : const Color(0xFFD1D5DB),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

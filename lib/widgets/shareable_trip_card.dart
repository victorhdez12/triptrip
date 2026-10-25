// lib/widgets/shareable_trip_card.dart
//
// "Trip Card" compartible (Instagram Stories / share nativo) al cerrar
// un viaje. Reutiliza BadgeShareHelper (captura RepaintBoundary + share)
// de shareable_badge_card.dart.

import 'package:flutter/material.dart';

import 'common_widgets.dart';
import 'shareable_badge_card.dart';

/// Abre el bottom sheet con la preview de la trip card y el botón de share.
Future<void> showTripCardShareSheet(
  BuildContext context, {
  required String tripName,
  required String destination,
  required int totalDays,
  required int placesCount,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => _TripCardSheet(
      tripName: tripName,
      destination: destination,
      totalDays: totalDays,
      placesCount: placesCount,
    ),
  );
}

class _TripCardSheet extends StatefulWidget {
  final String tripName;
  final String destination;
  final int totalDays;
  final int placesCount;
  const _TripCardSheet({
    required this.tripName,
    required this.destination,
    required this.totalDays,
    required this.placesCount,
  });

  @override
  State<_TripCardSheet> createState() => _TripCardSheetState();
}

class _TripCardSheetState extends State<_TripCardSheet> {
  final _boundaryKey = GlobalKey();
  bool _sharing = false;

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      // Espera un frame para garantizar que el RepaintBoundary esté pintado
      await Future.delayed(const Duration(milliseconds: 50));
      final path = await BadgeShareHelper.captureWidget(_boundaryKey);
      await BadgeShareHelper.shareToInstagram(
        imagePath: path,
        bgTop: kPrimary,
        bgBottom: const Color(0xFF006D8F),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Could not share'),
              backgroundColor: Colors.redAccent),
        );
      }
    }
    if (mounted) setState(() => _sharing = false);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE5E7EB),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),
            const Text('Share your trip',
              style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w800,
                color: Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 14),
            RepaintBoundary(
              key: _boundaryKey,
              child: TripStoryCard(
                tripName: widget.tripName,
                destination: widget.destination,
                totalDays: widget.totalDays,
                placesCount: widget.placesCount,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _sharing ? null : _share,
                icon: _sharing
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: Colors.white),
                      )
                    : const Icon(Icons.ios_share, color: Colors.white),
                label: const Text('Share',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w800)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// TRIP STORY CARD (formato vertical tipo story)
// ══════════════════════════════════════════════════════════════

class TripStoryCard extends StatelessWidget {
  final String tripName;
  final String destination;
  final int totalDays;
  final int placesCount;

  const TripStoryCard({
    super.key,
    required this.tripName,
    required this.destination,
    required this.totalDays,
    required this.placesCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 270,
      height: 480,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [kPrimary, Color(0xFF006D8F)],
        ),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('✈️', style: TextStyle(fontSize: 40)),
          const Spacer(),
          Text(tripName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 26, fontWeight: FontWeight.w900,
              color: Colors.white, letterSpacing: -0.5, height: 1.1,
            ),
          ),
          const SizedBox(height: 6),
          Text(destination,
            style: TextStyle(
              fontSize: 15, fontWeight: FontWeight.w600,
              color: Colors.white.withOpacity(0.92),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _stat('$totalDays', totalDays == 1 ? 'day' : 'days'),
              const SizedBox(width: 22),
              _stat('$placesCount', placesCount == 1 ? 'place' : 'places'),
            ],
          ),
          const Spacer(),
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text('TripTrip',
                  style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(String value, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value,
          style: const TextStyle(
            fontSize: 30, fontWeight: FontWeight.w900, color: Colors.white,
          ),
        ),
        Text(label,
          style: TextStyle(
            fontSize: 13, color: Colors.white.withOpacity(0.85),
          ),
        ),
      ],
    );
  }
}

// lib/widgets/shareable_badge_card.dart
//
// Badge compartible en Instagram Stories. Combina dos responsabilidades:
//
//   1. Render compacto (la celda de la grid en UserProfileScreen).
//   2. Render "story" (1080x1920) que se captura y se comparte.
//
// Diseño: gradiente diagonal con el color del achievement, brillo radial
// arriba a la izquierda, emoji XL centrado, borde dorado si está unlocked.
// El render shareable añade marca TripTrip + nombre del usuario + ubicación.

import 'dart:ui' as ui;
import 'dart:typed_data';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:social_share/social_share.dart';
import 'package:share_plus/share_plus.dart';

import '../services/achievements_service.dart';
import 'common_widgets.dart';

// ══════════════════════════════════════════════════════════════
// BADGE GRID CELL — celda compacta usada en el grid del perfil
// ══════════════════════════════════════════════════════════════

class BadgeGridCell extends StatelessWidget {
  final Achievement achievement;
  final bool unlocked;
  final VoidCallback onTap;

  const BadgeGridCell({
    super.key,
    required this.achievement,
    required this.unlocked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c1 = Color(achievement.gradient[0]);
    final c2 = Color(achievement.gradient[1]);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          gradient: unlocked
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [c1, c2],
                )
              : const LinearGradient(
                  colors: [Color(0xFFF9FAFB), Color(0xFFEEF0F4)],
                ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: unlocked ? Colors.white.withOpacity(0.4) : const Color(0xFFE5E7EB),
            width: 1.5,
          ),
          boxShadow: unlocked
              ? [
                  BoxShadow(
                    color: c1.withOpacity(0.35),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [],
        ),
        child: Stack(
          children: [
            // Brillo radial decorativo
            if (unlocked)
              Positioned(
                top: -20,
                left: -20,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        Colors.white.withOpacity(0.35),
                        Colors.white.withOpacity(0.0),
                      ],
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        unlocked ? achievement.emoji : '🔒',
                        style: const TextStyle(fontSize: 26),
                      ),
                      const Spacer(),
                      if (unlocked)
                        const Icon(Icons.ios_share,
                            size: 16, color: Colors.white),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    achievement.title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: unlocked ? Colors.white : const Color(0xFF9CA3AF),
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    achievement.subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: unlocked
                          ? Colors.white.withOpacity(0.85)
                          : const Color(0xFF9CA3AF),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// SHAREABLE STORY CARD — render 1080x1920 para Instagram
// ══════════════════════════════════════════════════════════════

class ShareableStoryCard extends StatelessWidget {
  final Achievement achievement;
  final String displayName;
  final String location;       // opcional ("Madrid, Spain")

  const ShareableStoryCard({
    super.key,
    required this.achievement,
    required this.displayName,
    this.location = '',
  });

  @override
  Widget build(BuildContext context) {
    final c1 = Color(achievement.gradient[0]);
    final c2 = Color(achievement.gradient[1]);

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 1080,
        height: 1920,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [c1, c2],
          ),
        ),
        child: Stack(
          children: [
            // Blob decorativo top-right
            Positioned(
              top: -200,
              right: -200,
              child: Container(
                width: 600,
                height: 600,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Colors.white.withOpacity(0.18),
                      Colors.white.withOpacity(0.0),
                    ],
                  ),
                ),
              ),
            ),
            // Blob decorativo bottom-left
            Positioned(
              bottom: -200,
              left: -200,
              child: Container(
                width: 700,
                height: 700,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Colors.white.withOpacity(0.12),
                      Colors.white.withOpacity(0.0),
                    ],
                  ),
                ),
              ),
            ),

            // Contenido principal
            Padding(
              padding: const EdgeInsets.all(80),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Top: logo + brand
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: const Icon(
                          Icons.flight_takeoff_rounded,
                          color: kPrimary,
                          size: 36,
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Text(
                        'TripTrip',
                        style: TextStyle(
                          fontSize: 42,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -1,
                        ),
                      ),
                    ],
                  ),

                  const Spacer(),

                  // Badge giant
                  Container(
                    width: 360,
                    height: 360,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.18),
                          blurRadius: 40,
                          offset: const Offset(0, 20),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        achievement.emoji,
                        style: const TextStyle(fontSize: 200),
                      ),
                    ),
                  ),

                  const SizedBox(height: 60),

                  // Tag "UNLOCKED"
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.25),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                          color: Colors.white.withOpacity(0.5), width: 2),
                    ),
                    child: const Text(
                      'UNLOCKED',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 4,
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Título
                  Text(
                    achievement.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 86,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: -2,
                      height: 1.05,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    achievement.subtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withOpacity(0.92),
                    ),
                  ),

                  const Spacer(),

                  // Footer: usuario
                  if (displayName.isNotEmpty)
                    Text(
                      '@$displayName',
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  if (location.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      location,
                      style: TextStyle(
                        fontSize: 26,
                        color: Colors.white.withOpacity(0.85),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Text(
                    'triptrip.app',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withOpacity(0.9),
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// HELPER: capturar + compartir
// ══════════════════════════════════════════════════════════════

class BadgeShareHelper {
  /// Captura un widget como PNG y lo guarda en disco temporal.
  /// Devuelve la ruta del archivo PNG.
  static Future<String> captureWidget(GlobalKey boundaryKey) async {
    final boundary = boundaryKey.currentContext!.findRenderObject()
        as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = byteData!.buffer.asUint8List();

    final tmpDir = await getTemporaryDirectory();
    final filePath =
        '${tmpDir.path}/triptrip_badge_${DateTime.now().millisecondsSinceEpoch}.png';
    final file = File(filePath);
    await file.writeAsBytes(bytes);
    return filePath;
  }

  /// Comparte un PNG directamente a Instagram Stories si está instalado;
  /// si no, abre el share sheet nativo (fallback).
  static Future<void> shareToInstagram({
    required String imagePath,
    required Color bgTop,
    required Color bgBottom,
  }) async {
    try {
      await SocialShare.shareInstagramStory(
        appId: 'YOUR_FB_APP_ID', // opcional para IG, requerido para FB story
        imagePath: imagePath,
        backgroundTopColor: '#${bgTop.value.toRadixString(16).substring(2)}',
        backgroundBottomColor: '#${bgBottom.value.toRadixString(16).substring(2)}',
        attributionURL: 'https://triptrip.app',
      );
    } catch (_) {
      // Fallback: share sheet nativo
      await Share.shareXFiles(
        [XFile(imagePath)],
        text: 'Just unlocked a new badge on TripTrip! ✈️',
      );
    }
  }
}

// ══════════════════════════════════════════════════════════════
// BOTTOM SHEET: preview + acciones (share / save)
// ══════════════════════════════════════════════════════════════

class BadgeShareSheet extends StatefulWidget {
  final Achievement achievement;
  final String displayName;
  final String location;

  const BadgeShareSheet({
    super.key,
    required this.achievement,
    required this.displayName,
    this.location = '',
  });

  static Future<void> show(
    BuildContext context, {
    required Achievement achievement,
    required String displayName,
    String location = '',
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BadgeShareSheet(
        achievement: achievement,
        displayName: displayName,
        location: location,
      ),
    );
  }

  @override
  State<BadgeShareSheet> createState() => _BadgeShareSheetState();
}

class _BadgeShareSheetState extends State<BadgeShareSheet> {
  final _boundaryKey = GlobalKey();
  bool _sharing = false;

  @override
  Widget build(BuildContext context) {
    final a = widget.achievement;
    final c1 = Color(a.gradient[0]);
    final c2 = Color(a.gradient[1]);

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SingleChildScrollView(
          controller: controller,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            child: Column(
              children: [
                // Handle
                Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE5E7EB),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),

                // Preview (escalado del story card)
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: AspectRatio(
                    aspectRatio: 9 / 16,
                    child: FittedBox(
                      fit: BoxFit.cover,
                      child: RepaintBoundary(
                        key: _boundaryKey,
                        child: ShareableStoryCard(
                          achievement: a,
                          displayName: widget.displayName,
                          location: widget.location,
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Botón compartir IG
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: _sharing ? null : _handleShareInstagram,
                    icon: _sharing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : const Icon(Icons.camera_alt_outlined,
                            color: Colors.white),
                    label: Text(
                      _sharing ? 'Preparing...' : 'Share to Instagram Story',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700),
                    ),
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      padding: EdgeInsets.zero,
                      elevation: 0,
                    ).copyWith(
                      backgroundColor: WidgetStateProperty.all(c1),
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // Botón share sheet nativo
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: OutlinedButton.icon(
                    onPressed: _sharing ? null : _handleShareGeneric,
                    icon: const Icon(Icons.ios_share, color: kPrimary),
                    label: const Text(
                      'More options',
                      style: TextStyle(
                          color: kPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w700),
                    ),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      side: const BorderSide(color: kPrimary, width: 1.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleShareInstagram() async {
    setState(() => _sharing = true);
    try {
      // Espera un frame para garantizar que RepaintBoundary esté pintado
      await Future.delayed(const Duration(milliseconds: 50));
      final path = await BadgeShareHelper.captureWidget(_boundaryKey);
      final a = widget.achievement;
      await BadgeShareHelper.shareToInstagram(
        imagePath: path,
        bgTop: Color(a.gradient[0]),
        bgBottom: Color(a.gradient[1]),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not share: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _handleShareGeneric() async {
    setState(() => _sharing = true);
    try {
      await Future.delayed(const Duration(milliseconds: 50));
      final path = await BadgeShareHelper.captureWidget(_boundaryKey);
      await Share.shareXFiles(
        [XFile(path)],
        text:
            'Just unlocked "${widget.achievement.title}" on TripTrip! ✈️ triptrip.app',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not share: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }
}

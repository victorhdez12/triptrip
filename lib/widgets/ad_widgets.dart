// lib/widgets/ad_widgets.dart
//
// Widgets de anuncios reutilizables:
//   • BannerAdBox   — banner adaptativo estándar (320x50 aprox.)
//   • NativeFeedAd  — tarjeta de anuncio para el feed (mediumRectangle
//                     300x250 envuelto en una card con el mismo estilo que
//                     las tarjetas del feed + etiqueta "Sponsored").
//
// Ambos:
//   • Devuelven SizedBox.shrink() si AdService.adsAvailable == false
//     (web, desktop, sin consentimiento GDPR, o SDK no inicializado)
//     → el layout no deja huecos y Chrome dev sigue funcionando.
//   • Registran la impresión en Supabase vía AdService.logImpression.

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../services/ad_service.dart';

// ══════════════════════════════════════════════════════════════
// BANNER ESTÁNDAR
// ══════════════════════════════════════════════════════════════

class BannerAdBox extends StatefulWidget {
  /// Identificador del lugar donde se muestra (para ad_impressions).
  final String placement;
  const BannerAdBox({super.key, required this.placement});

  @override
  State<BannerAdBox> createState() => _BannerAdBoxState();
}

class _BannerAdBoxState extends State<BannerAdBox> {
  BannerAd? _ad;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadAd();
  }

  void _loadAd() {
    if (!AdService.adsAvailable) return;
    _ad = BannerAd(
      adUnitId: AdService.bannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (!mounted) return;
          setState(() => _loaded = true);
          AdService.logImpression(
              adType: 'banner', placement: widget.placement);
        },
        onAdFailedToLoad: (ad, err) {
          debugPrint('BannerAdBox failed: ${err.message}');
          ad.dispose();
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (!_loaded || ad == null) return const SizedBox.shrink();
    return Center(
      child: SizedBox(
        width: ad.size.width.toDouble(),
        height: ad.size.height.toDouble(),
        child: AdWidget(ad: ad),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// ANUNCIO DE FEED (cada ~5 tarjetas)
// ══════════════════════════════════════════════════════════════

class NativeFeedAd extends StatefulWidget {
  /// Identificador del lugar donde se muestra (para ad_impressions).
  final String placement;
  const NativeFeedAd({super.key, required this.placement});

  @override
  State<NativeFeedAd> createState() => _NativeFeedAdState();
}

class _NativeFeedAdState extends State<NativeFeedAd>
    with AutomaticKeepAliveClientMixin {
  BannerAd? _ad;
  bool _loaded = false;

  // Mantiene el anuncio vivo al hacer scroll (evita recargas al volver).
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadAd();
  }

  void _loadAd() {
    if (!AdService.adsAvailable) return;
    _ad = BannerAd(
      adUnitId: AdService.feedAdUnitId,
      size: AdSize.mediumRectangle, // 300x250 — formato tipo tarjeta
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (!mounted) return;
          setState(() => _loaded = true);
          AdService.logImpression(
              adType: 'native_feed', placement: widget.placement);
        },
        onAdFailedToLoad: (ad, err) {
          debugPrint('NativeFeedAd failed: ${err.message}');
          ad.dispose();
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // requerido por AutomaticKeepAliveClientMixin
    final ad = _ad;
    if (!_loaded || ad == null) return const SizedBox.shrink();

    // Card con el mismo lenguaje visual que las tarjetas del feed
    // (blanco, radio 16, borde 0xFFEEF0F4) + etiqueta de transparencia.
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEEF0F4)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
            child: Row(
              children: [
                const Icon(Icons.campaign_outlined,
                    size: 15, color: Color(0xFF9CA3AF)),
                const SizedBox(width: 6),
                Text('Sponsored',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF9CA3AF).withValues(alpha: 0.9),
                    )),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SizedBox(
              width: ad.size.width.toDouble(),
              height: ad.size.height.toDouble(),
              child: AdWidget(ad: ad),
            ),
          ),
        ],
      ),
    );
  }
}

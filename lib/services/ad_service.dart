// lib/services/ad_service.dart
//
// AdMob centralizado (patrón estático, como el resto de servicios):
//   • init()          — consentimiento GDPR/UMP + inicialización del SDK.
//   • adsAvailable    — true solo si hay consentimiento y el SDK arrancó.
//   • bannerAdUnitId / feedAdUnitId — IDs por plataforma (TEST por ahora).
//   • logImpression() — registra cada impresión en Supabase (ad_impressions)
//                       para el futuro dashboard interno (get_ad_impression_stats).
//
// Compatibilidad Chrome dev:
//   google_mobile_ads NO funciona en web → todo es no-op si kIsWeb.
//   Se usa kIsWeb / defaultTargetPlatform (NUNCA dart:io Platform).
//
// GDPR/UMP (obligatorio en España/UE):
//   Antes de pedir anuncios se muestra el formulario de consentimiento de
//   Google (User Messaging Platform). Si el usuario no consiente y la región
//   lo exige, adsAvailable queda en false y no se carga ningún anuncio.
//
// IMPORTANTE antes de producción:
//   1. Sustituir los ad unit IDs de TEST por los reales de la cuenta AdMob.
//   2. Sustituir el APPLICATION_ID de test en AndroidManifest.xml e Info.plist.
//   3. Ejecutar supabase/ads_setup.sql en Supabase (tabla ad_impressions + RPC).

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdService {
  static final _db = Supabase.instance.client;

  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  static bool _initStarted = false;
  static bool _adsAvailable = false;

  /// true solo si: plataforma móvil + consentimiento OK + SDK inicializado.
  static bool get adsAvailable => _adsAvailable;

  /// Solo Android/iOS reales — en web y desktop todo queda apagado.
  static bool get _isMobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  // ── IDs de bloque de anuncio (TEST de Google — reemplazar) ─
  static String get bannerAdUnitId =>
      defaultTargetPlatform == TargetPlatform.iOS
          ? 'ca-app-pub-3940256099942544/2934735716' // iOS banner TEST
          : 'ca-app-pub-3940256099942544/6300978111'; // Android banner TEST

  /// El anuncio del feed usa formato mediumRectangle (300x250) con el
  /// mismo bloque de banner — no requiere factories nativas por plataforma.
  static String get feedAdUnitId => bannerAdUnitId;

  // ── INIT: consentimiento UMP + SDK ────────────────────────
  /// Llamar una vez al arrancar (no bloquear el primer frame: sin await
  /// en main). Idempotente: llamadas repetidas no hacen nada.
  static Future<void> init() async {
    if (_initStarted || !_isMobile) return;
    _initStarted = true;
    try {
      // 1) Consentimiento GDPR/UMP — Google decide si hace falta formulario
      //    según la región del dispositivo (UE/España → sí).
      final consentDone = Completer<void>();
      ConsentInformation.instance.requestConsentInfoUpdate(
        ConsentRequestParameters(),
        () {
          // Muestra el formulario SOLO si es obligatorio y aún no se aceptó.
          ConsentForm.loadAndShowConsentFormIfRequired((formError) {
            if (formError != null) {
              debugPrint('UMP form error: ${formError.message}');
            }
            if (!consentDone.isCompleted) consentDone.complete();
          });
        },
        (updateError) {
          debugPrint('UMP update error: ${updateError.message}');
          if (!consentDone.isCompleted) consentDone.complete();
        },
      );
      await consentDone.future;

      // 2) ¿Podemos pedir anuncios con el consentimiento actual?
      final canRequest = await ConsentInformation.instance.canRequestAds();
      if (!canRequest) {
        debugPrint('AdService: sin consentimiento — anuncios desactivados');
        return;
      }

      // 3) Inicializar el SDK de Mobile Ads.
      await MobileAds.instance.initialize();
      _adsAvailable = true;
      debugPrint('AdService: inicializado con consentimiento');
    } catch (e) {
      debugPrint('AdService.init error: $e');
    }
  }

  /// Vuelve a mostrar el formulario de privacidad (para un botón en Ajustes,
  /// requisito GDPR: el usuario debe poder cambiar su elección).
  static Future<void> showPrivacyOptions() async {
    if (!_isMobile) return;
    try {
      ConsentForm.showPrivacyOptionsForm((formError) {
        if (formError != null) {
          debugPrint('UMP privacy options error: ${formError.message}');
        }
      });
    } catch (e) {
      debugPrint('showPrivacyOptions error: $e');
    }
  }

  // ── IMPRESIONES → Supabase ────────────────────────────────
  /// Registra una impresión para el dashboard interno.
  /// adType: 'banner' | 'native_feed' · placement: p.ej. 'dashboard_feed'.
  /// Fire-and-forget: nunca rompe la UI si falla.
  static Future<void> logImpression({
    required String adType,
    required String placement,
  }) async {
    final uid = _uid;
    try {
      await _db.from('ad_impressions').insert({
        'firebase_uid': uid,
        'ad_type':      adType,
        'placement':    placement,
        'platform':     defaultTargetPlatform.name,
      });
    } catch (e) {
      debugPrint('logImpression error: $e');
    }
  }
}

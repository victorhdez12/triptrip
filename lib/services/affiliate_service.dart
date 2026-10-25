// lib/services/affiliate_service.dart
//
// Links de reserva con afiliación, limpios para el usuario:
//   • Solo aparece el botón si la categoría tiene partner.
//   • El botón muestra el nombre del partner (transparencia).
//   • Un único punto donde cambiar los IDs de afiliado.
//
// Sustituye los IDs placeholder por los tuyos al darte de alta en
// cada programa (GetYourGuide Partner, Booking Affiliate, TheFork).

import 'package:url_launcher/url_launcher.dart';

import 'analytics_service.dart';

class AffiliateLink {
  final String partner; // nombre visible (transparencia)
  final Uri url;
  const AffiliateLink({required this.partner, required this.url});
}

class AffiliateService {
  // ── IDs de afiliado (reemplazar por los reales) ───────────
  static const _gygPartnerId = 'TRIPTRIP';   // GetYourGuide partner_id
  static const _bookingAid   = '000000';     // Booking.com aid
  static const _civitatisAid = '000000';     // Civitatis aid

  /// Devuelve el link de reserva para un sitio, o null si su categoría
  /// no tiene partner (en ese caso NO se muestra botón: UX limpia).
  static AffiliateLink? linkFor({
    required String placeName,
    required String location,
    required String category,
  }) {
    final q = Uri.encodeComponent(
        location.isEmpty ? placeName : '$placeName $location');

    switch (category) {
      case 'Restaurants':
        return AffiliateLink(
          partner: 'TheFork',
          url: Uri.parse('https://www.thefork.com/search/?text=$q'),
        );
      case 'Activities':
      case 'Museums':
      case 'Nature':
      case 'Nightlife':
        // TARJETA = elemento concreto → búsqueda por nombre.
        // GetYourGuide cae directo en ESA actividad/museo. Civitatis no
        // permite enlazar a un producto por nombre sin su API (Nivel B).
        return AffiliateLink(
          partner: 'GetYourGuide',
          url: Uri.parse(
              'https://www.getyourguide.com/s/?q=$q&partner_id=$_gygPartnerId'),
        );
      case 'Hotel':
      case 'Hotels':
      case 'Stay':
        return AffiliateLink(
          partner: 'Booking',
          url: Uri.parse(
              'https://www.booking.com/searchresults.html?ss=$q&aid=$_bookingAid'),
        );
      default:
        return null; // Shopping y otros: sin botón
    }
  }

  /// Link de búsqueda de hoteles (Booking) prefijado con destino y viajeros.
  static AffiliateLink hotelsLink(String destination, {int guests = 2}) {
    final ss = Uri.encodeComponent(destination);
    final adults = guests > 0 ? guests : 2;
    return AffiliateLink(
      partner: 'Booking',
      url: Uri.parse(
          'https://www.booking.com/searchresults.html?ss=$ss&group_adults=$adults&aid=$_bookingAid'),
    );
  }

  /// Abre hoteles en el navegador in-app (registra la intención).
  static Future<void> openHotels(
      {required String destination, int guests = 2}) async {
    await open(hotelsLink(destination, guests: guests), category: 'Hotels');
  }

  /// Link a TODAS las actividades de una ciudad (Civitatis) — itinerario.
  static AffiliateLink activitiesCityLink(String destination) {
    final city = _civitatisSlug(destination);
    if (city.isNotEmpty) {
      return AffiliateLink(
        partner: 'Civitatis',
        url: Uri.parse(
            'https://www.civitatis.com/es/$city/?aid=$_civitatisAid'),
      );
    }
    final q = Uri.encodeComponent(destination);
    return AffiliateLink(
      partner: 'GetYourGuide',
      url: Uri.parse(
          'https://www.getyourguide.com/s/?q=$q&partner_id=$_gygPartnerId'),
    );
  }

  /// Abre todas las actividades de la ciudad en el navegador in-app.
  static Future<void> openActivities(String destination) async {
    await open(activitiesCityLink(destination), category: 'Activities');
  }

  // Deriva el slug de ciudad de Civitatis desde "Ciudad, País".
  static String _civitatisSlug(String location) {
    if (location.trim().isEmpty) return '';
    var city = location.split(',').first.trim().toLowerCase();
    const fromA = 'áàäâãéèëêíìïîóòöôõúùüûñç';
    const toA   = 'aaaaaeeeeiiiiooooouuuunc';
    final sb = StringBuffer();
    for (final ch in city.split('')) {
      final idx = fromA.indexOf(ch);
      sb.write(idx >= 0 ? toA[idx] : ch);
    }
    city = sb.toString().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    city = city.replaceAll(RegExp(r'^-+|-+$'), '');
    return city;
  }

  /// Abre el link en el navegador in-app (y registra la intención).
  static Future<void> open(AffiliateLink link, {String category = ''}) async {
    AnalyticsService.reserveTapped(partner: link.partner, category: category);
    await launchUrl(link.url, mode: LaunchMode.inAppBrowserView);
  }

  /// Abre cualquier URL externa (sin tracking de afiliación).
  /// Lo usan los links del Kit (fotos WeTransfer, etc.).
  static Future<void> openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
  }

  // ── ESSENTIALS (bloque de Overview) ───────────────────────
  // eSIM, seguro… afiliación de alta conversión en viajes.
  // Sustituye los parámetros placeholder por tus IDs reales al darte
  // de alta en cada programa (Airalo Partners, Heymondo afiliados).
  static final List<EssentialItem> essentials = [
    EssentialItem(
      emoji: '📶',
      title: 'eSIM with data',
      subtitle: 'Internet abroad in 2 min',
      link: AffiliateLink(
        partner: 'Airalo',
        url: Uri.parse('https://www.airalo.com/?ref=TRIPTRIP'),
      ),
    ),
    EssentialItem(
      emoji: '🛡️',
      title: 'Travel insurance',
      subtitle: 'Medical + cancellation cover',
      link: AffiliateLink(
        partner: 'Heymondo',
        url: Uri.parse('https://heymondo.com/?utm_source=TRIPTRIP'),
      ),
    ),
  ];
}

class EssentialItem {
  final String emoji;
  final String title;
  final String subtitle;
  final AffiliateLink link;
  const EssentialItem({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.link,
  });
}
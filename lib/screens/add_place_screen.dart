// lib/screens/add_place_screen.dart
//
// Formulario para compartir un lugar visitado en el feed.
// Devuelve true al pop si se creó correctamente (para refrescar el feed).

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n.dart';
import '../services/feed_service.dart';
import '../services/media_service.dart';
import '../services/places_catalog_service.dart';
import 'pick_location_map_screen.dart';

const _kPrimary = Color(0xFF29B6D2);
const _kDark = Color(0xFF1A1A2E);

class AddPlaceScreen extends StatefulWidget {
  const AddPlaceScreen({super.key});

  @override
  State<AddPlaceScreen> createState() => _AddPlaceScreenState();
}

class _AddPlaceScreenState extends State<AddPlaceScreen> {
  final _placeCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  String _selectedCategory = 'Activities';
  double _rating = 4.0;
  bool _isPublic = true;
  bool _loading = false;
  bool _locating = false;
  String _selectedFlag = '📍';
  final List<Uint8List> _photos = [];

  // ── Sitio canónico (anti-duplicados) ───────────────────────
  Timer? _debounce;
  List<PlaceSuggestion> _suggestions = const [];
  bool _searching = false;
  PlaceSuggestion? _picked;   // sugerencia OSM elegida
  double? _pinLat, _pinLng;   // pin manual en mapa

  final _categories = <Map<String, String>>[
    {'label': 'Restaurants', 'emoji': '🍽️'},
    {'label': 'Activities', 'emoji': '🎯'},
    {'label': 'Museums', 'emoji': '🏛️'},
    {'label': 'Nature', 'emoji': '🌿'},
    {'label': 'Shopping', 'emoji': '🛍️'},
    {'label': 'Nightlife', 'emoji': '🌙'},
  ];

  final _flags = [
    '🇪🇸', '🇬🇧', '🇩🇪', '🇫🇷', '🇮🇹', '🇵🇹',
    '🇯🇵', '🇺🇸', '🇧🇷', '🇲🇽', '🇨🇿', '🇳🇱',
    '📍',
  ];

  @override
  void dispose() {
    _debounce?.cancel();
    _placeCtrl.dispose();
    _locationCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhotos() async {
    try {
      final picked = await ImagePicker().pickMultiImage(imageQuality: 90);
      if (picked.isEmpty) return;
      for (final x in picked) {
        if (_photos.length >= 3) break;
        var bytes = await x.readAsBytes();
        if (!kIsWeb) {
          bytes = await FlutterImageCompress.compressWithList(
            bytes, minWidth: 1080, minHeight: 1080, quality: 72);
        }
        _photos.add(bytes);
      }
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('pickPhotos error: $e');
    }
  }

  void _removePhoto(int i) => setState(() => _photos.removeAt(i));

  // ── Autocomplete (Nominatim, debounce 600ms — máx 1 req/s) ──
  void _onPlaceChanged(String value) {
    _picked = null; // si edita el texto, deja de ser la sugerencia elegida
    _debounce?.cancel();
    if (value.trim().length < 3) {
      setState(() => _suggestions = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 600), () async {
      setState(() => _searching = true);
      final results = await PlacesCatalogService.search(value);
      if (!mounted) return;
      setState(() {
        _suggestions = results;
        _searching = false;
      });
    });
  }

  void _pickSuggestion(PlaceSuggestion s) {
    setState(() {
      _picked = s;
      _placeCtrl.text = s.name;
      if (s.location.isNotEmpty) _locationCtrl.text = s.location;
      _suggestions = const [];
      _pinLat = null;
      _pinLng = null;
    });
  }

  Future<void> _pickOnMap() async {
    final picked = await Navigator.push<PickedLocation>(
      context,
      MaterialPageRoute(builder: (_) => const PickLocationMapScreen()),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _pinLat = picked.lat;
      _pinLng = picked.lng;
      _picked = null; // pin manual anula la sugerencia OSM
      if (picked.locationText.isNotEmpty) {
        _locationCtrl.text = picked.locationText;
      } else {
        _locationCtrl.text =
            '${picked.lat.toStringAsFixed(4)}, ${picked.lng.toStringAsFixed(4)}';
      }
    });
  }

  Future<void> _submit() async {
    final place = _placeCtrl.text.trim();
    final location = _locationCtrl.text.trim();
    if (place.isEmpty || location.isEmpty) {
      _snack(tr('Fill in place name and location', 'Rellena el nombre y la ubicación'), Colors.redAccent);
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _loading = true);
    try {
      final profile = await Supabase.instance.client
          .from('users')
          .select('display_name')
          .eq('firebase_uid', user.uid)
          .maybeSingle();
      final displayName =
          profile?['display_name'] as String? ?? user.displayName ?? 'Traveler';

      // Resolver el sitio canónico ANTES de publicar (cero duplicados):
      //  • sugerencia OSM elegida → dedupe por osm id
      //  • pin en mapa / texto manual → dedupe por nombre+ubicación
      final canonicalId = await PlacesCatalogService.upsertCanonical(
        osmKey: _picked?.osmKey,
        name: place,
        location: location,
        countryFlag: _selectedFlag,
        category: _selectedCategory,
        lat: _picked?.lat ?? _pinLat,
        lng: _picked?.lng ?? _pinLng,
      );

      final urls = <String>[];
      for (final bytes in _photos) {
        final url = await MediaService.uploadImage(bytes,
            pathPrefix: 'visits/${user.uid}');
        if (url != null) urls.add(url);
      }

      final visitId = await FeedService.addPlaceVisit(
        uid: user.uid,
        displayName: displayName,
        avatarColor: '#29B6D2',
        placeName: place,
        location: location,
        countryFlag: _selectedFlag,
        category: _selectedCategory,
        rating: _rating,
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        coverUrl: urls.isNotEmpty ? urls.first : null,
        isPublic: _isPublic,
        placeId: canonicalId,
      );

      if (visitId != null) {
        for (var i = 0; i < urls.length; i++) {
          await MediaService.addMedia(
            parentType: 'visit', parentId: visitId,
            url: urls[i], addedBy: user.uid, position: i);
        }
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      debugPrint('AddPlace error: $e');
      if (mounted) {
        setState(() => _loading = false);
        _snack(tr('Error sharing place. Try again.', 'Error al compartir. Inténtalo de nuevo.'), Colors.redAccent);
      }
    }
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  Future<void> _detectLocation() async {
    setState(() => _locating = true);
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _snack(tr('Location permission denied', 'Permiso de ubicación denegado'), Colors.redAccent);
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 10),
        ),
      );

      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?lat=${position.latitude}&lon=${position.longitude}'
        '&format=json&accept-language=en',
      );
      final response = await http.get(
        url,
        headers: {'User-Agent': 'TripTrip/1.0'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final address = data['address'] as Map<String, dynamic>?;
        if (address != null) {
          final city = address['city'] as String? ??
              address['town'] as String? ??
              address['village'] as String? ??
              address['county'] as String? ??
              '';
          final country = address['country'] as String? ?? '';
          final text = city.isNotEmpty && country.isNotEmpty
              ? '$city, $country'
              : city.isNotEmpty
                  ? city
                  : country;
          if (text.isNotEmpty) _locationCtrl.text = text;
        }
      }
    } catch (e) {
      debugPrint('Location error: $e');
      _snack(tr('Could not detect location', 'No se pudo detectar la ubicación'), Colors.redAccent);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.close, color: _kDark),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          tr('Share a place', 'Compartir un lugar'),
          style: const TextStyle(
              fontSize: 17, fontWeight: FontWeight.w700, color: _kDark),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label(tr('Place name *', 'Nombre del lugar *')),
            _placeNameField(),
            const SizedBox(height: 16),
            _label(tr('Location *', 'Ubicación *')),
            _locationField(),
            const SizedBox(height: 16),
            _label(tr('Country flag', 'Bandera del país')),
            _buildFlagPicker(),
            const SizedBox(height: 16),
            _label(tr('Category', 'Categoría')),
            _buildCategoryPicker(),
            const SizedBox(height: 16),
            _label(tr('Your rating', 'Tu valoración')),
            _buildRatingPicker(),
            const SizedBox(height: 16),
            _label(tr('Note (optional)', 'Nota (opcional)')),
            _textField(
              _noteCtrl,
              'What made it special? Any tip?',
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            _label(tr('Photos (optional)', 'Fotos (opcional)')),
            _buildPhotoPicker(),
            const SizedBox(height: 16),
            _buildVisibilityToggle(),
            const SizedBox(height: 32),
            _buildSubmitButton(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // ── Helpers de UI ──────────────────────────────────────────

  // Campo de nombre con autocomplete (Nominatim) y dedupe canónico.
  Widget _placeNameField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _picked != null ? _kPrimary : const Color(0xFFE5E7EB),
              width: _picked != null ? 1.5 : 1,
            ),
          ),
          child: TextField(
            controller: _placeCtrl,
            onChanged: _onPlaceChanged,
            decoration: InputDecoration(
              hintText: 'e.g. Sagrada Família',
              hintStyle:
                  const TextStyle(color: Color(0xFFBBBBBB), fontSize: 14),
              border: InputBorder.none,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              suffixIcon: _searching
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(
                            color: _kPrimary, strokeWidth: 2),
                      ),
                    )
                  : _picked != null
                      ? const Icon(Icons.verified,
                          color: _kPrimary, size: 20)
                      : null,
            ),
          ),
        ),
        if (_suggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Column(
              children: _suggestions
                  .map((s) => ListTile(
                        dense: true,
                        leading: const Icon(Icons.place_outlined,
                            color: _kPrimary, size: 20),
                        title: Text(s.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600)),
                        subtitle: s.location.isEmpty
                            ? null
                            : Text(s.location,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12)),
                        onTap: () => _pickSuggestion(s),
                      ))
                  .toList(),
            ),
          ),
        if (_picked != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              tr('Matched to the community place — ratings will add up',
                  'Vinculado al sitio de la comunidad — las valoraciones se suman'),
              style: const TextStyle(fontSize: 11, color: _kPrimary),
            ),
          ),
        if (_pinLat != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              '📌 ${_pinLat!.toStringAsFixed(4)}, ${_pinLng!.toStringAsFixed(4)}',
              style:
                  const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
            ),
          ),
      ],
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF6B7280))),
      );

  Widget _textField(TextEditingController ctrl, String hint,
      {int maxLines = 1}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: TextField(
        controller: ctrl,
        maxLines: maxLines,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle:
              const TextStyle(color: Color(0xFFBBBBBB), fontSize: 14),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }

  Widget _locationField() {
    return Column(
      children: [
        _textField(_locationCtrl, 'e.g. Barcelona, Spain'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _locationActionBtn()),
            const SizedBox(width: 8),
            // Pin manual en mapa (sitios remotos sin índice)
            GestureDetector(
              onTap: _pickOnMap,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: _pinLat != null
                      ? _kPrimary.withValues(alpha: 0.08)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color:
                          _pinLat != null ? _kPrimary : const Color(0xFFE5E7EB),
                      width: 1.5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.pin_drop_outlined,
                        size: 16,
                        color: _pinLat != null
                            ? _kPrimary
                            : const Color(0xFF6B7280)),
                    const SizedBox(width: 6),
                    Text(tr('Pin', 'Pin'),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _pinLat != null
                              ? _kPrimary
                              : const Color(0xFF6B7280),
                        )),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _locationActionBtn() {
    return GestureDetector(
          onTap: _locating ? null : _detectLocation,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: _locating
                  ? const Color(0xFFF3F4F6)
                  : _kPrimary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _locating ? const Color(0xFFE5E7EB) : _kPrimary,
                width: 1.5,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_locating)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        color: _kPrimary, strokeWidth: 2),
                  )
                else
                  const Icon(Icons.my_location, color: _kPrimary, size: 16),
                const SizedBox(width: 8),
                Text(
                  _locating ? tr('Detecting your location…', 'Detectando tu ubicación…') : tr('Use my current location', 'Usar mi ubicación actual'),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _locating
                        ? const Color(0xFF9CA3AF)
                        : _kPrimary,
                  ),
                ),
              ],
            ),
          ),
        );
  }

  Widget _buildFlagPicker() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _flags.map((flag) {
        final isSelected = flag == _selectedFlag;
        return GestureDetector(
          onTap: () => setState(() => _selectedFlag = flag),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: isSelected
                  ? _kPrimary.withValues(alpha: 0.12)
                  : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? _kPrimary : const Color(0xFFE5E7EB),
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Center(
              child: Text(flag, style: const TextStyle(fontSize: 22)),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildCategoryPicker() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _categories.map((c) {
        final label = c['label']!;
        final isSelected = label == _selectedCategory;
        return GestureDetector(
          onTap: () => setState(() => _selectedCategory = label),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected ? _kPrimary : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? _kPrimary : const Color(0xFFE5E7EB),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(c['emoji']!, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 6),
                Text(label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? Colors.white
                          : const Color(0xFF374151),
                    )),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildRatingPicker() {
    return Row(
      children: List.generate(5, (i) {
        final starValue = (i + 1).toDouble();
        return GestureDetector(
          onTap: () => setState(() => _rating = starValue),
          child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Icon(
              _rating >= starValue ? Icons.star : Icons.star_border,
              color: const Color(0xFFFBBF24),
              size: 34,
            ),
          ),
        );
      }),
    );
  }

  Widget _buildVisibilityToggle() {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          const Icon(Icons.public, color: Color(0xFF6B7280), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('Public', 'Público'),
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _kDark)),
                Text(tr('Visible to everyone', 'Visible para todos'),
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF9CA3AF))),
              ],
            ),
          ),
          Switch(
            value: _isPublic,
            onChanged: (v) => setState(() => _isPublic = v),
            activeThumbColor: _kPrimary,
            activeTrackColor: _kPrimary.withValues(alpha: 0.4),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoPicker() {
    return Row(
      children: [
        ..._photos.asMap().entries.map((e) {
          return Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(e.value,
                      width: 72, height: 72, fit: BoxFit.cover),
                ),
                Positioned(
                  top: -6, right: -6,
                  child: GestureDetector(
                    onTap: () => _removePhoto(e.key),
                    child: Container(
                      decoration: const BoxDecoration(
                          color: Colors.black54, shape: BoxShape.circle),
                      padding: const EdgeInsets.all(2),
                      child: const Icon(Icons.close,
                          size: 14, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
        if (_photos.length < 3)
          GestureDetector(
            onTap: _pickPhotos,
            child: Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: const Icon(Icons.add_a_photo_outlined,
                  color: Color(0xFF9CA3AF)),
            ),
          ),
      ],
    );
  }

  Widget _buildSubmitButton() {
    return GestureDetector(
      onTap: _loading ? null : _submit,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 56,
        decoration: BoxDecoration(
          color: _loading
              ? _kPrimary.withValues(alpha: 0.6)
              : _kPrimary,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: _kPrimary.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Center(
          child: _loading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2.5),
                )
              : Text(tr('Share place', 'Compartir lugar'),
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white)),
        ),
      ),
    );
  }
}
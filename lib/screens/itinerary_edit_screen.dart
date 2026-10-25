// lib/screens/itinerary_edit_screen.dart
//
// Editor de CONTENIDO de un itinerario (solo el dueño):
//   • Añadir días
//   • Añadir paradas a un día → desde FAVORITOS o escribiéndolas a mano
//   • Publicar / despublicar en el feed (toggle público)
//
// Comparte solo la "parte pura" del itinerario (días + paradas); los datos
// personales del viaje (fechas, presupuesto, miembros) no viven aquí.
//
// Persiste vía ItineraryService.addDay / addPlace / setItineraryPublic.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/itinerary_service.dart';
import '../services/feed_service.dart';
import '../services/place_social_service.dart';
import '../services/affiliate_service.dart';
import '../widgets/common_widgets.dart';

class ItineraryEditScreen extends StatefulWidget {
  final String itineraryId;
  const ItineraryEditScreen({super.key, required this.itineraryId});

  @override
  State<ItineraryEditScreen> createState() => _ItineraryEditScreenState();
}

class _ItineraryEditScreenState extends State<ItineraryEditScreen> {
  ItineraryDetail? _detail;
  bool _loading = true;
  bool _public = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = await ItineraryService.getDetail(widget.itineraryId);
    bool pub = true;
    try {
      final row = await Supabase.instance.client
          .from('user_itineraries')
          .select('is_public')
          .eq('id', widget.itineraryId)
          .maybeSingle();
      pub = (row?['is_public'] as bool?) ?? true;
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _detail = d;
      _public = pub;
      _loading = false;
    });
  }

  void _show(String msg, [Color color = kPrimary]) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  // ── Público ───────────────────────────────────────────────
  Future<void> _togglePublic(bool v) async {
    setState(() => _public = v);
    final ok = await ItineraryService.setItineraryPublic(widget.itineraryId, v);
    if (!ok) {
      setState(() => _public = !v); // revertir
      _show('Could not update visibility', Colors.redAccent);
    } else {
      feedChanged.value++; // el feed del dashboard reflejará el cambio
    }
  }

  // ── Días ──────────────────────────────────────────────────
  Future<void> _addDay() async {
    final d = _detail;
    if (d == null || _busy) return;
    setState(() => _busy = true);
    final next = d.days.isEmpty ? 1 : d.days.last.dayNumber + 1;
    final id = await ItineraryService.addDay(
      itineraryId: widget.itineraryId,
      dayNumber: next,
      title: 'Day $next',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (id == null) {
      _show('Could not add day', Colors.redAccent);
      return;
    }
    _load();
  }

  // ── Paradas ───────────────────────────────────────────────
  Future<void> _addPlaceFlow(ItineraryDay day) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE5E7EB),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.favorite, color: kOrange),
              title: const Text('From favourites',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Pick a saved place or restaurant'),
              onTap: () => Navigator.pop(context, 'fav'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined, color: kPrimary),
              title: const Text('Type manually',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              onTap: () => Navigator.pop(context, 'manual'),
            ),
            ListTile(
              leading: const Icon(Icons.house_rounded, color: kTeal),
              title: const Text('Add hotel',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Your stay for this day · Booking link'),
              onTap: () => Navigator.pop(context, 'hotel'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (choice == 'fav') {
      await _addFromFavourites(day);
    } else if (choice == 'manual') {
      await _addManual(day);
    } else if (choice == 'hotel') {
      await _addHotel(day);
    }
  }

  Future<void> _addFromFavourites(ItineraryDay day) async {
    final favs = await PlaceSocialService.listFavorites();
    if (!mounted) return;

    final picked = await showModalBottomSheet<PlaceCard>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.6,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E7EB),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Your saved places',
                    style: TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                ),
              ),
              if (favs.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28, horizontal: 20),
                  child: Text(
                    'No saved places yet. Save some from the feed first.',
                    style: TextStyle(color: Color(0xFF9CA3AF)),
                  ),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: favs.length,
                    itemBuilder: (_, i) {
                      final p = favs[i];
                      return ListTile(
                        leading: Text(p.countryFlag,
                            style: const TextStyle(fontSize: 24)),
                        title: Text(p.placeName,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          p.category.isEmpty
                              ? p.location
                              : '${p.category} · ${p.location}',
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => Navigator.pop(context, p),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );

    if (picked == null || !mounted) return;
    await _insertPlace(
      day,
      placeName: picked.placeName,
      category: picked.category.isEmpty ? 'Activities' : picked.category,
      note: picked.note,
    );
  }

  Future<void> _addManual(ItineraryDay day) async {
    final nameCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add place'),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Place name'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Add')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) return;
    await _insertPlace(day, placeName: name, category: 'Activities');
  }

  // ── Hotel: parada de alojamiento (sin hora, "perenne") ────
  // El hotel es igual que cualquier parada (mismo addPlace, misma tabla,
  // reseñable en el recap) pero con category 'Hotel', sin time_label y
  // renderizado con icono de casa + kTeal. Su fila lleva link de Booking
  // (AffiliateService.linkFor ya cubre 'Hotel').
  Future<void> _addHotel(ItineraryDay day) async {
    final nameCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.house_rounded, color: kTeal),
            SizedBox(width: 8),
            Text('Add hotel'),
          ],
        ),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Hotel name'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Add')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) return;
    await _insertPlace(day, placeName: name, category: 'Hotel');
  }

  Future<void> _insertPlace(
    ItineraryDay day, {
    required String placeName,
    required String category,
    String? note,
  }) async {
    final id = await ItineraryService.addPlace(
      dayId: day.id,
      itineraryId: widget.itineraryId,
      position: day.places.length,
      placeName: placeName,
      category: category,
      note: note,
    );
    if (!mounted) return;
    if (id == null) {
      _show('Could not add place', Colors.redAccent);
      return;
    }
    _load();
  }

  // ── UI ────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF1A1A2E)),
        title: const Text('Edit itinerary',
          style: TextStyle(
            color: Color(0xFF1A1A2E),
            fontWeight: FontWeight.w800,
            fontSize: 17,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done',
                style: TextStyle(
                    color: kPrimary, fontWeight: FontWeight.w800, fontSize: 15)),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kPrimary))
          : _detail == null
              ? const Center(child: Text('Itinerary not found'))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                  children: [
                    _buildPublicToggle(),
                    const SizedBox(height: 16),
                    _buildSuggestions(_detail!.card.destination),
                    const SizedBox(height: 16),
                    ..._detail!.days.map(_buildDayBlock),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _addDay,
                      icon: const Icon(Icons.add, color: kPrimary),
                      label: const Text('Add day',
                          style: TextStyle(
                              color: kPrimary, fontWeight: FontWeight.w700)),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        side: const BorderSide(color: kPrimary, width: 1.5),
                      ),
                    ),
                  ],
                ),
    );
  }

  // ── Sugerencias: hoteles (afiliado) y actividades (catálogo real) ──
  Widget _buildSuggestions(String city) {
    final label = city.isEmpty ? '' : ' en $city';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 2),
          child: Text('🏨 Hoteles$label',
              style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: Color(0xFF1A1A2E))),
        ),
        SizedBox(
          height: 96,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _searchCard('🔎', 'Buscar hoteles', 'Booking · sin salir', () {
                AffiliateService.openHotels(
                    destination: city, guests: _detail!.card.groupSize);
              }),
              _searchCard('🏨', 'Añadir mi hotel', 'Como parada del día',
                  () async {
                final day = await _pickDay();
                if (day != null && mounted) await _addHotel(day);
              }),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 2),
          child: Text('🎟️ Actividades$label',
              style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: Color(0xFF1A1A2E))),
        ),
        SizedBox(
          height: 124,
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: PlaceSocialService.listCatalog(location: city, limit: 12),
            builder: (_, snap) {
              final items = snap.data ?? const <Map<String, dynamic>>[];
              return ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _searchCard('🔎', 'Buscar más', 'Civitatis · sin salir',
                      () => AffiliateService.openActivities(city)),
                  ...items.map(_suggCard),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _searchCard(
      String emoji, String title, String sub, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 150,
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [kPrimary, Color(0xFF006D8F)]),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 22)),
            const Spacer(),
            Text(title,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14)),
            Text(sub,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9), fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _suggCard(Map<String, dynamic> p) {
    final name = p['name'] as String? ?? '';
    final cat = p['category'] as String? ?? 'Activities';
    final flag = p['country_flag'] as String? ?? '📍';
    return GestureDetector(
      onTap: () => _addSuggestion(p),
      child: Container(
        width: 150,
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
            Text(flag, style: const TextStyle(fontSize: 20)),
            const SizedBox(height: 6),
            Text(name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: Color(0xFF1A1A2E))),
            const Spacer(),
            Row(children: [
              Expanded(
                child: Text(cat,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF9CA3AF))),
              ),
              const Icon(Icons.add_circle, color: kPrimary, size: 20),
            ]),
          ],
        ),
      ),
    );
  }

  Future<void> _addSuggestion(Map<String, dynamic> p) async {
    final day = await _pickDay();
    if (day == null) return;
    await _insertPlace(day,
        placeName: p['name'] as String? ?? '',
        category: p['category'] as String? ?? 'Activities');
  }

  Future<ItineraryDay?> _pickDay() async {
    final days = _detail!.days;
    if (days.isEmpty) return null;
    if (days.length == 1) return days.first;
    return showModalBottomSheet<ItineraryDay>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('¿A qué día?',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            ),
            ...days.map((d) => ListTile(
                  leading: const Icon(Icons.event, color: kPrimary),
                  title: Text(
                      d.title.isEmpty ? 'Día ${d.dayNumber}' : d.title),
                  onTap: () => Navigator.pop(context, d),
                )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildPublicToggle() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEEF0F4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.public, color: kPrimary, size: 20),
          const SizedBox(width: 10),
          const Expanded(
            child: Text('Public in feed',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          Switch(
            value: _public,
            activeColor: kPrimary,
            onChanged: _togglePublic,
          ),
        ],
      ),
    );
  }

  Widget _buildDayBlock(ItineraryDay day) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEEF0F4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            day.title.isEmpty ? 'Day ${day.dayNumber}' : day.title,
            style: const TextStyle(
              fontSize: 15, fontWeight: FontWeight.w800,
              color: Color(0xFF1A1A2E),
            ),
          ),
          const SizedBox(height: 8),
          if (day.places.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text('No places yet.',
                  style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF))),
            )
          else
            // Hoteles primero (parada "perenne" del día), luego el resto.
            ...([
              ...day.places.where((p) => p.category == 'Hotel'),
              ...day.places.where((p) => p.category != 'Hotel'),
            ].map((p) {
              final isHotel = p.category == 'Hotel';
              return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      Icon(isHotel ? Icons.house_rounded : Icons.place,
                          size: 16, color: isHotel ? kTeal : kOrange),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(p.placeName,
                          style: TextStyle(
                            fontSize: 14,
                            color: isHotel
                                ? kTeal
                                : const Color(0xFF374151),
                            fontWeight:
                                isHotel ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                      ),
                      Text(p.category,
                          style: const TextStyle(
                              fontSize: 11, color: Color(0xFF9CA3AF))),
                    ],
                  ),
                );
            })),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () => _addPlaceFlow(day),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(Icons.add_circle_outline, size: 18, color: kPrimary),
                  SizedBox(width: 6),
                  Text('Add place',
                      style: TextStyle(
                          color: kPrimary, fontWeight: FontWeight.w700, fontSize: 13)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
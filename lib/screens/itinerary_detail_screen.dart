// lib/screens/itinerary_detail_screen.dart
//
// Detalle público de un itinerario:
//   • Hero con cover + título + autor + stats (★, ❤, 💬, 🔁)
//   • Lista de días desplegables con sus lugares
//   • Acciones: ★ ratear, ❤ favoritar, 💬 comentar, 🔁 usar como trip
//   • Sheet inferior de comentarios

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/affiliate_service.dart';
import '../services/maps_export_service.dart';
import '../services/analytics_service.dart';
import '../services/itinerary_service.dart';
import '../widgets/common_widgets.dart';
import '../widgets/folder_picker_sheet.dart';
import '../widgets/place_categories.dart';
import 'itinerary_comments_screen.dart';
import 'itinerary_edit_screen.dart';
import 'plan_trip_screen.dart';
import 'trip_detail_screen.dart';

class ItineraryDetailScreen extends StatefulWidget {
  final String itineraryId;
  const ItineraryDetailScreen({super.key, required this.itineraryId});

  @override
  State<ItineraryDetailScreen> createState() => _ItineraryDetailScreenState();
}

class _ItineraryDetailScreenState extends State<ItineraryDetailScreen> {
  ItineraryDetail? _detail;
  bool _loading = true;
  bool _cloning = false;

  // Agregados publicados (anónimos): tamaño del grupo y presupuesto/persona.
  int _groupSize = 0;
  double _budgetPerPerson = 0;
  String _currency = '€';

  // Puede editar: el dueño O cualquier miembro del grupo de origen.
  bool _canEdit = false;

  Future<void> _openEditor() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ItineraryEditScreen(itineraryId: widget.itineraryId),
      ),
    );
    _load(); // refresca días/lugares al volver
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final d = await ItineraryService.getDetail(widget.itineraryId);
    // Agregados (no vienen en el RPC de getDetail). Tolerante a columnas
    // inexistentes: si fallan, quedan a 0 y no se muestran.
    int groupSize = 0;
    double budget = 0;
    String currency = '€';
    try {
      final row = await Supabase.instance.client
          .from('user_itineraries')
          .select('group_size, budget_per_person, currency')
          .eq('id', widget.itineraryId)
          .maybeSingle();
      if (row != null) {
        groupSize = (row['group_size'] as num?)?.toInt() ?? 0;
        budget = (row['budget_per_person'] as num?)?.toDouble() ?? 0;
        currency = row['currency'] as String? ?? '€';
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _detail = d;
      _groupSize = groupSize;
      _budgetPerPerson = budget;
      _currency = currency;
      _loading = false;
    });
    // ¿Puede editar este usuario? (dueño o miembro del grupo)
    final canEdit = await ItineraryService.canEditItinerary(widget.itineraryId);
    if (mounted) setState(() => _canEdit = canEdit);
  }

  void _show(String msg, [Color color = kPrimary]) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  // ── ACCIONES ────────────────────────────────────────────────
  Future<void> _toggleFavorite() async {
    final d = _detail;
    if (d == null) return;
    final fav = await showFolderPicker(
      context,
      kind: 'itinerary',
      itemId: d.card.id,
      suggestedFolderName: d.card.title,
    );
    if (fav == null || !mounted) return;
    _load(); // refresca flag + contador desde el servidor
  }

  Future<void> _rate(int stars) async {
    final d = _detail;
    if (d == null) return;
    final ok = await ItineraryService.rate(d.card.id, stars);
    if (!mounted) return;
    if (ok) {
      _show('Rating saved ⭐');
      _load(); // recargamos para refrescar avg + count
    } else {
      _show('Could not save rating', Colors.redAccent);
    }
  }

  Future<void> _openComments() async {
    final d = _detail;
    if (d == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ItineraryCommentsScreen(itineraryId: d.card.id),
      ),
    );
    _load(); // refresca counter
  }

  Future<void> _cloneToTrip() async {
    final d = _detail;
    if (d == null || _cloning) return;

    // Pedir solo los inputs que faltan: fechas, invitados, presupuesto, nombre.
    final cfg = await showModalBottomSheet<_CloneConfig>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => _CloneTripSheet(
        defaultName: d.card.title,
        totalDays: d.card.totalDays,
      ),
    );
    if (cfg == null || !mounted) return;

    setState(() => _cloning = true);
    final result = await ItineraryService.cloneToTrip(
      itineraryId: d.card.id,
      startDate: cfg.startDate,
      endDate: cfg.endDate,
      tripName: cfg.name,
      guests: cfg.guests,
      budget: cfg.budget,
    );
    if (!mounted) return;
    setState(() => _cloning = false);

    if (result == null) {
      _show('Could not create trip', Colors.redAccent);
      return;
    }

    AnalyticsService.itineraryCloned(itineraryId: d.card.id);

    final end = cfg.endDate ??
        cfg.startDate.add(Duration(days: (d.card.totalDays - 1).clamp(0, 365)));
    final days = end.difference(cfg.startDate).inDays + 1;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => TripDetailScreen(
          destination: d.card.destination,
          tripName: cfg.name.isEmpty ? d.card.title : cfg.name,
          startDate: cfg.startDate,
          endDate: end,
          guests: cfg.guests,
          totalDays: days,
          budgetPerPerson: cfg.budget,
          currency: '€',
          groupId: result.tripGroupId,
          inviteCode: result.inviteCode,
        ),
      ),
    );
  }

  // ── UI ──────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: kBackground,
        body: Center(child: CircularProgressIndicator(color: kPrimary)),
      );
    }
    final d = _detail;
    if (d == null) {
      return Scaffold(
        backgroundColor: kBackground,
        appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
        body: const Center(child: Text('Itinerary not found')),
      );
    }
    final c = d.card;

    return Scaffold(
      backgroundColor: kBackground,
      body: CustomScrollView(
        slivers: [
          // ── HEADER hero ─────────────────────────────────────
          SliverAppBar(
            expandedHeight: 240,
            pinned: true,
            backgroundColor: kPrimary,
            iconTheme: const IconThemeData(color: Colors.white),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: [kPrimary, Color(0xFF006D8F)],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 50, 20, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(c.countryFlag, style: const TextStyle(fontSize: 32)),
                        const SizedBox(height: 6),
                        Text(c.title,
                          style: const TextStyle(
                            fontSize: 26, fontWeight: FontWeight.w900,
                            color: Colors.white, letterSpacing: -0.5,
                          ),
                          maxLines: 2, overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(c.destination,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white.withOpacity(0.92),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            actions: [
              if (_canEdit)
                IconButton(
                  icon: const Icon(Icons.edit_outlined, color: Colors.white),
                  onPressed: _openEditor,
                ),
              IconButton(
                icon: Icon(
                  d.viewerFavorited ? Icons.favorite : Icons.favorite_border,
                  color: Colors.white,
                ),
                onPressed: _toggleFavorite,
              ),
            ],
          ),

          // ── AUTOR + STATS ───────────────────────────────────
          SliverToBoxAdapter(
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: _hexToColor(c.avatarColor),
                        child: Text(
                          c.displayName.isNotEmpty ? c.displayName[0].toUpperCase() : 'T',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(c.displayName,
                              style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w700,
                                color: Color(0xFF1A1A2E),
                              ),
                            ),
                            Text(_relTime(c.createdAt),
                              style: const TextStyle(
                                fontSize: 12, color: Color(0xFF9CA3AF),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 16, runSpacing: 6,
                    children: [
                      _statChip('⭐', '${c.avgRating.toStringAsFixed(1)} (${c.ratingsCount})'),
                      _statChip('❤️', '${c.favoritesCount}'),
                      _statChip('💬', '${c.commentsCount}'),
                      _statChip('🔁', '${c.clonesCount}'),
                      _statChip('📅', '${c.totalDays}d · ${c.totalPlaces}p'),
                      if (_groupSize > 0) _statChip('👥', '$_groupSize'),
                      if (_budgetPerPerson > 0)
                        _statChip('💰',
                            '$_currency${_budgetPerPerson.toStringAsFixed(0)}/p'),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // ── RATING (tap stars) ──────────────────────────────
          SliverToBoxAdapter(
            child: Container(
              color: Colors.white,
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
              child: Row(
                children: [
                  const Text('Your rating',
                    style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                  const Spacer(),
                  for (int i = 1; i <= 5; i++)
                    GestureDetector(
                      onTap: () => _rate(i),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Icon(
                          (d.viewerRating ?? 0) >= i
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded,
                          color: (d.viewerRating ?? 0) >= i
                              ? const Color(0xFFFFB400)
                              : const Color(0xFFD1D5DB),
                          size: 30,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // ── DAYS ────────────────────────────────────────────
          if (d.days.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 32, 20, 32),
                child: Center(
                  child: Text(
                    'This itinerary has no days yet.',
                    style: TextStyle(color: const Color(0xFF6B7280)),
                  ),
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => _DayCard(day: d.days[i], destination: d.card.destination),
                childCount: d.days.length,
              ),
            ),

          // ── ACTIVIDADES Y MUSEOS (Civitatis ciudad, navegador in-app) ─
          SliverToBoxAdapter(
            child: Container(
              color: Colors.white,
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Actividades y museos en ${c.destination}',
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1A1A2E))),
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: () =>
                        AffiliateService.openActivities(c.destination),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: [kOrange, Color(0xFFEA580C)]),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          const Text('🎟️', style: TextStyle(fontSize: 26)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Ver actividades y entradas',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14)),
                                Text('Tours y museos · sin salir de la app',
                                    style: TextStyle(
                                        color: Colors.white
                                            .withValues(alpha: 0.9),
                                        fontSize: 12)),
                              ],
                            ),
                          ),
                          const Icon(Icons.arrow_forward_ios,
                              color: Colors.white, size: 16),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text('Civitatis · enlace de afiliado',
                      style: TextStyle(
                          fontSize: 11, color: Color(0xFF9CA3AF))),
                ],
              ),
            ),
          ),

          // ── DÓNDE DORMIR (afiliación Booking, navegador in-app) ─
          SliverToBoxAdapter(
            child: Container(
              color: Colors.white,
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Dónde dormir en ${c.destination}',
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1A1A2E))),
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: () => AffiliateService.openHotels(
                        destination: c.destination, guests: c.groupSize),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: [kPrimary, Color(0xFF006D8F)]),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          const Text('🏨', style: TextStyle(fontSize: 26)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Ver hoteles disponibles',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14)),
                                Text('Sin salir de la app',
                                    style: TextStyle(
                                        color: Colors.white
                                            .withValues(alpha: 0.9),
                                        fontSize: 12)),
                              ],
                            ),
                          ),
                          const Icon(Icons.arrow_forward_ios,
                              color: Colors.white, size: 16),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text('Booking.com · enlace de afiliado',
                      style: TextStyle(
                          fontSize: 11, color: Color(0xFF9CA3AF))),
                ],
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),

      // ── BOTTOM ACTIONS ──────────────────────────────────────
      bottomNavigationBar: SafeArea(
        child: Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _openComments,
                  icon: const Icon(Icons.chat_bubble_outline, color: kPrimary),
                  label: const Text('Comments',
                    style: TextStyle(color: kPrimary, fontWeight: FontWeight.w700),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    side: const BorderSide(color: kPrimary, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: _cloning ? null : _cloneToTrip,
                  icon: _cloning
                    ? const SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                    : const Icon(Icons.flight_takeoff_rounded, color: Colors.white),
                  label: Text(_cloning ? 'Creating...' : 'Use this itinerary',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statChip(String emoji, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 14)),
        const SizedBox(width: 4),
        Text(label,
          style: const TextStyle(
            fontSize: 13, color: Color(0xFF374151), fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  static Color _hexToColor(String hex) {
    final cleaned = hex.replaceAll('#', '');
    return Color(int.parse('FF$cleaned', radix: 16));
  }

  static String _relTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inDays > 365) return '${(diff.inDays / 365).floor()}y ago';
    if (diff.inDays > 30)  return '${(diff.inDays / 30).floor()}mo ago';
    if (diff.inDays > 0)   return '${diff.inDays}d ago';
    if (diff.inHours > 0)  return '${diff.inHours}h ago';
    if (diff.inMinutes > 0)return '${diff.inMinutes}m ago';
    return 'just now';
  }
}

// ══════════════════════════════════════════════════════════════
// DAY CARD
// ══════════════════════════════════════════════════════════════

class _DayCard extends StatelessWidget {
  final ItineraryDay day;
  final String destination;
  const _DayCard({required this.day, this.destination = ''});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEEF0F4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: kPrimary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text('Day ${day.dayNumber}',
                    style: const TextStyle(
                      color: kPrimary, fontSize: 12, fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(day.title.isEmpty ? 'Day ${day.dayNumber}' : day.title,
                    style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1A2E),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          if (day.places.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Text('No places added yet.',
                style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
              ),
            )
          else
            ...day.places.map((p) {
              final c = placeCategory(p.category).color;
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(width: 4, height: 38,
                      decoration: BoxDecoration(
                        color: c, borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.placeName,
                            style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700,
                              color: Color(0xFF1A1A2E),
                            ),
                          ),
                          Text(
                            [p.timeLabel, p.category].whereType<String>().join(' · '),
                            style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                          ),
                        ],
                      ),
                    ),
                    // Reserva (afiliación) — discreto, solo si hay partner
                    Builder(builder: (_) {
                      final link = AffiliateService.linkFor(
                        placeName: p.placeName,
                        location: destination,
                        category: p.category,
                      );
                      if (link == null) return const SizedBox.shrink();
                      return GestureDetector(
                        onTap: () => AffiliateService.open(link, category: p.category),
                        behavior: HitTestBehavior.opaque,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 8, top: 2),
                          child: Column(
                            children: const [
                              Icon(Icons.open_in_new,
                                  size: 16, color: kPrimary),
                              SizedBox(height: 2),
                              Text('Reserve',
                                  style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      color: kPrimary)),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              );
            }),
          // ── RUTA DEL DÍA EN GOOGLE MAPS ──────────────────────
          if (day.places.length >= 2)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: GestureDetector(
                onTap: () => MapsExportService.openDayRoute(
                    day.places, destination: destination),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: kPrimary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.map_outlined, size: 18, color: kPrimary),
                      SizedBox(width: 8),
                      Text('Ver ruta del día en Maps',
                          style: TextStyle(
                              color: kPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 13)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
// ══════════════════════════════════════════════════════════════
// CLONE SHEET — pide fechas / invitados / presupuesto / nombre
// ══════════════════════════════════════════════════════════════

class _CloneConfig {
  final DateTime startDate;
  final DateTime? endDate;
  final int guests;
  final double budget;
  final String name;

  const _CloneConfig({
    required this.startDate,
    this.endDate,
    required this.guests,
    required this.budget,
    required this.name,
  });
}

class _CloneTripSheet extends StatefulWidget {
  final String defaultName;
  final int totalDays;
  const _CloneTripSheet({required this.defaultName, required this.totalDays});

  @override
  State<_CloneTripSheet> createState() => _CloneTripSheetState();
}

class _CloneTripSheetState extends State<_CloneTripSheet> {
  late final TextEditingController _nameCtrl;
  final _budgetCtrl = TextEditingController();
  DateTime? _start;
  DateTime? _end;
  int _guests = 0;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.defaultName);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _budgetCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickStart() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _start ?? DateTime.now().add(const Duration(days: 14)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
      helpText: 'Start date',
    );
    if (picked != null) {
      setState(() {
        _start = picked;
        // Si la fecha fin queda antes del inicio, la reseteamos.
        if (_end != null && _end!.isBefore(picked)) _end = null;
      });
    }
  }

  Future<void> _pickEnd() async {
    final base = _start ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _end ?? base.add(Duration(days: (widget.totalDays - 1).clamp(0, 365))),
      firstDate: base,
      lastDate: base.add(const Duration(days: 365 * 2)),
      helpText: 'End date (optional)',
    );
    if (picked != null) setState(() => _end = picked);
  }

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  void _submit() {
    if (_start == null) return;
    final budget = double.tryParse(_budgetCtrl.text.replaceAll(',', '.')) ?? 0;
    Navigator.pop(
      context,
      _CloneConfig(
        startDate: _start!,
        endDate: _end,
        guests: _guests,
        budget: budget,
        name: _nameCtrl.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE5E7EB),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text('Create a trip from this itinerary',
                style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w800,
                  color: Color(0xFF1A1A2E),
                ),
              ),
              const SizedBox(height: 16),

              _fieldLabel('Trip name'),
              TextField(
                controller: _nameCtrl,
                decoration: _dec('My trip'),
              ),
              const SizedBox(height: 14),

              Row(
                children: [
                  Expanded(child: _dateBtn('Start', _start, _pickStart)),
                  const SizedBox(width: 10),
                  Expanded(child: _dateBtn('End (opt.)', _end, _pickEnd)),
                ],
              ),
              const SizedBox(height: 14),

              _fieldLabel('Guests'),
              Row(
                children: [
                  _roundBtn(Icons.remove,
                      () => setState(() => _guests = (_guests - 1).clamp(0, 50))),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text('$_guests',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                  _roundBtn(Icons.add,
                      () => setState(() => _guests = (_guests + 1).clamp(0, 50))),
                ],
              ),
              const SizedBox(height: 14),

              _fieldLabel('Budget per person (€)'),
              TextField(
                controller: _budgetCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: _dec('0'),
              ),
              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _start == null ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimary,
                    disabledBackgroundColor: const Color(0xFFB7E5EE),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: const Text('Create trip',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fieldLabel(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 0, 0, 6),
        child: Text(t,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF374151))),
      );

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: const Color(0xFFF5F5F5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      );

  Widget _dateBtn(String label, DateTime? value, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today, size: 16, color: kPrimary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value == null ? label : _fmt(value),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: value == null
                      ? const Color(0xFF9CA3AF)
                      : const Color(0xFF1A1A2E),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _roundBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38, height: 38,
        decoration: BoxDecoration(
          color: const Color(0xFFF0F0F0),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 18, color: const Color(0xFF1A1A2E)),
      ),
    );
  }
}
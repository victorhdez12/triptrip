import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/analytics_service.dart';
import '../services/itinerary_service.dart';
import '../services/maps_export_service.dart';
import '../widgets/common_widgets.dart';
import '../widgets/place_categories.dart';
import '../widgets/shareable_trip_card.dart';
import '../widgets/trip_kit_sections.dart';
import 'publish_itinerary_screen.dart';

class TripDetailScreen extends StatefulWidget {
  final String destination;
  final String tripName;
  final DateTime startDate;
  final DateTime endDate;
  final int guests;
  final int totalDays;
  final double budgetPerPerson;
  final String currency;
  final String? groupId;
  final String? inviteCode;

  const TripDetailScreen({
    super.key,
    required this.destination,
    required this.tripName,
    required this.startDate,
    required this.endDate,
    required this.guests,
    required this.totalDays,
    required this.budgetPerPerson,
    required this.currency,
    this.groupId,
    this.inviteCode,
  });

  @override
  State<TripDetailScreen> createState() => _TripDetailScreenState();
}

class _TripDetailScreenState extends State<TripDetailScreen> {
  int _selectedTab = 0; // 0=Overview, 1=Itinerary, 2=Members, 3=Expenses
  bool _isTripOwner = false; // solo el creador puede publicar

  // Código de invitación generado (simulado — en producción viene de Firebase)
  late String _inviteCode;

  // Lista de miembros (simulado)
  final List<_Member> _members = [
    _Member(name: 'Tú', initials: 'TU', color: const Color(0xFF29B6D2), isLeader: true),
  ];

  // ── Itinerario de trabajo del grupo (persistido en Supabase) ──
  String? _itineraryId;
  ItineraryDetail? _itinDetail;
  bool _itinLoading = false;
  int _selectedDay = 0;

  @override
  void initState() {
    super.initState();
    _inviteCode = widget.inviteCode ?? _generateCode();
    _checkTripOwner();
    if (widget.groupId != null) _loadItinerary();
  }

  // Carga (o crea si no existe aún) el itinerario privado del grupo,
  // y se asegura de tener un día por cada día del viaje.
  Future<void> _loadItinerary() async {
    final gid = widget.groupId;
    if (gid == null) return;
    setState(() => _itinLoading = true);
    final user = FirebaseAuth.instance.currentUser;
    final id = await ItineraryService.getOrCreateGroupItinerary(
      tripGroupId: gid,
      destination: widget.destination,
      totalDays: widget.totalDays,
      displayName: user?.displayName ?? user?.email?.split('@').first ?? 'Traveler',
      avatarColor: '#29B6D2',
    );
    if (id == null) {
      if (mounted) setState(() => _itinLoading = false);
      return;
    }
    var detail = await ItineraryService.getDetail(id);
    final existingDays = detail?.days.length ?? 0;
    if (existingDays < widget.totalDays) {
      for (int i = existingDays + 1; i <= widget.totalDays; i++) {
        final date = widget.startDate.add(Duration(days: i - 1));
        await ItineraryService.addDay(itineraryId: id, dayNumber: i, title: _formatDate(date));
      }
      detail = await ItineraryService.getDetail(id);
    }
    if (!mounted) return;
    setState(() {
      _itineraryId = id;
      _itinDetail = detail;
      _itinLoading = false;
    });
  }

  // Recarga solo el detalle (tras añadir un lugar), sin repetir la
  // creación/relleno de días.
  Future<void> _refreshItinerary() async {
    final id = _itineraryId;
    if (id == null) return;
    final d = await ItineraryService.getDetail(id);
    if (!mounted) return;
    setState(() => _itinDetail = d);
  }

  List<ItineraryDay> get _sortedDays {
    final days = List<ItineraryDay>.from(_itinDetail?.days ?? const []);
    days.sort((a, b) => a.dayNumber.compareTo(b.dayNumber));
    return days;
  }

  // Solo el creador del viaje (trip_groups.created_by) puede publicar.
  Future<void> _checkTripOwner() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final gid = widget.groupId;
    if (uid == null || gid == null) return;
    try {
      final row = await Supabase.instance.client
          .from('trip_groups')
          .select('created_by')
          .eq('id', gid)
          .maybeSingle();
      if (mounted && row != null && row['created_by'] == uid) {
        setState(() => _isTripOwner = true);
      }
    } catch (_) {}
  }

  String _generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final now = DateTime.now().millisecondsSinceEpoch;
    String code = '';
    int n = now;
    for (int i = 0; i < 6; i++) {
      code += chars[n % chars.length];
      n ~/= chars.length;
    }
    return code;
  }

  String _formatDate(DateTime d) {
    final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[d.month - 1]} ${d.day.toString().padLeft(2,'0')}';
  }

  double get _totalBudget => widget.budgetPerPerson * (widget.guests + 1);
  double get _budgetPerDay => _totalBudget / widget.totalDays;

  // Sale del viaje directo a HOME (raíz del stack).
  void _goHome() {
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  // Publica el itinerario del viaje en el feed público.
  // Comparte solo la parte del itinerario + agregados (nº personas, budget),
  // nunca datos de los miembros.
  void _publishTrip() {
    if (widget.groupId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Save the trip first')),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PublishItineraryScreen(
          sourceTripGroupId: widget.groupId,
          prefillTitle: widget.tripName,
          prefillDestination: widget.destination,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          _buildHeroHeader(),
          _buildTabBar(),
          Expanded(child: _buildTabContent()),
        ],
      ),
      bottomNavigationBar: _selectedTab == 1 && widget.groupId != null
          ? _buildAddPlanBtn()
          : null,
    );
  }

  // ── Hero con imagen de destino ────────────────────────────────────────────
  Widget _buildHeroHeader() {
    return Stack(
      children: [
        // Imagen placeholder (reemplaza con Image.network o Image.asset)
        Container(
          height: 220,
          width: double.infinity,
          color: const Color(0xFF1A1A2E),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('🌍', style: TextStyle(fontSize: 52)),
                Text(widget.destination,
                  style: const TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ),
        // Overlay gradiente
        Container(
          height: 220,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black.withOpacity(0.3), Colors.black.withOpacity(0.6)],
            ),
          ),
        ),
        // Botones top
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
                    child: const Icon(Icons.chevron_left, color: Colors.white),
                  ),
                ),
                Row(
                  children: [
                    GestureDetector(
                      onTap: _showShareSheet,
                      child: Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
                        child: const Icon(Icons.ios_share, color: Colors.white, size: 18),
                      ),
                    ),
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: _goHome,
                      child: Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
                        child: const Icon(Icons.check, color: Colors.white, size: 20),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        // Info overlay en el fondo del hero
        Positioned(
          bottom: 16, left: 20, right: 20,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.tripName,
                style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('${_formatDate(widget.startDate)} – ${_formatDate(widget.endDate)}  ·  ${widget.totalDays} días',
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ],
          ),
        ),
      ],
    );
  }

  // ── Tabs ──────────────────────────────────────────────────────────────────
  Widget _buildTabBar() {
    final tabs = ['Overview', 'Itinerary', 'Members', 'Expenses', 'Photos', 'Checklist', 'Info'];
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: List.generate(tabs.length, (i) {
            final active = _selectedTab == i;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => setState(() => _selectedTab = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(
                    color: active ? const Color(0xFF1A1A2E) : const Color(0xFFF0F0F0),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Text(tabs[i], style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600,
                    color: active ? Colors.white : const Color(0xFF888888),
                  )),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildTabContent() {
    switch (_selectedTab) {
      case 0: return _buildOverviewTab();
      case 1: return _buildItineraryTab();
      case 2: return _buildMembersTab();
      case 3: return _buildExpensesTab();
      case 4: return _buildKitTab((gid) => PhotosSection(groupId: gid));
      case 5: return _buildKitTab((gid) => ChecklistSection(groupId: gid));
      case 6: return _buildKitTab((gid) => InfoSection(groupId: gid));
      default: return const SizedBox();
    }
  }

  // Las pestañas del Kit necesitan el viaje guardado (groupId).
  Widget _buildKitTab(Widget Function(String gid) builder) {
    final gid = widget.groupId;
    if (gid == null) {
      return const Center(
        child: Text('Save the trip first',
            style: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF))),
      );
    }
    return builder(gid);
  }

  // ── TAB 0: OVERVIEW ───────────────────────────────────────────────────────
  Widget _buildOverviewTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Trip info cards
          Row(
            children: [
              _InfoCard(icon: '📅', label: 'Duration', value: '${widget.totalDays} days'),
              const SizedBox(width: 12),
              _InfoCard(icon: '👥', label: 'Travelers', value: '${widget.guests + 1} people'),
              const SizedBox(width: 12),
              _InfoCard(icon: '📍', label: 'Destination', value: widget.destination.split(',').first),
            ],
          ),
          const SizedBox(height: 20),

          // Budget section
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FF),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE8E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Text('💰', style: TextStyle(fontSize: 18)),
                    SizedBox(width: 8),
                    Text('Budget Overview', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))),
                  ],
                ),
                const SizedBox(height: 12),
                _BudgetRow(label: 'Total trip (flights, hotels, etc.)', value: '${widget.currency}${widget.budgetPerPerson.toStringAsFixed(0)}'),
                _BudgetRow(label: 'Total group', value: '${widget.currency}${_totalBudget.toStringAsFixed(0)}'),
                _BudgetRow(label: 'Per day', value: '${widget.currency}${_budgetPerDay.toStringAsFixed(0)}/day'),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Travel partners
          const Text('Your Travel Partners', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))),
          const SizedBox(height: 12),
          _buildMembersRow(),
          const SizedBox(height: 20),

          // Essentials (afiliación) — visible sin abrumar
          const EssentialsCard(),
          const SizedBox(height: 16),

          // Check itinerary button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: () => setState(() => _selectedTab = 1),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6B4EFF),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: const Text('Check your Trip Plan',
                  style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: 12),
          // Trip Card compartible (story) — para todos los miembros
          Center(
            child: TextButton.icon(
              onPressed: () => showTripCardShareSheet(
                context,
                tripName: widget.tripName,
                destination: widget.destination,
                totalDays: widget.totalDays,
                placesCount: 0,
              ),
              icon: const Icon(Icons.auto_awesome,
                  size: 18, color: Color(0xFF6B4EFF)),
              label: const Text('Share trip card',
                  style: TextStyle(
                      color: Color(0xFF6B4EFF),
                      fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 4),
          // Publicar el itinerario del viaje — SOLO el owner del viaje.
          if (_isTripOwner)
            SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton.icon(
                onPressed: _publishTrip,
                icon: const Icon(Icons.public, color: Color(0xFF29B6D2)),
                label: const Text('Publish to feed',
                    style: TextStyle(
                        color: Color(0xFF29B6D2),
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  side: const BorderSide(color: Color(0xFF29B6D2), width: 1.5),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMembersRow() {
    return Row(
      children: [
        ..._members.map((m) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: _MemberAvatar(member: m, size: 48),
        )),
        GestureDetector(
          onTap: _showShareSheet,
          child: Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF6B4EFF), width: 2),
            ),
            child: const Icon(Icons.add, color: Color(0xFF6B4EFF), size: 22),
          ),
        ),
      ],
    );
  }

  Widget _buildInviteCodeCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A1A2E), Color(0xFF29B6D2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Invite your travel partners',
            style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('Share this code so they can join your trip',
            style: TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(_inviteCode,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 8,
                      )),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: _inviteCode));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Código copiado'), backgroundColor: Color(0xFF29B6D2)));
                },
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.copy, color: Colors.white, size: 20),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _showShareSheet,
              icon: const Icon(Icons.share, size: 16),
              label: const Text('Share via WhatsApp / Link'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF1A1A2E),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTricountCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF86EFAC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Text('🧾', style: TextStyle(fontSize: 20)),
              SizedBox(width: 8),
              Text('Tricount Integration', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF15803D))),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Gestiona los gastos compartidos del grupo con Tricount.',
            style: TextStyle(fontSize: 12, color: Color(0xFF16A34A)),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _openTricount(),
                  icon: const Icon(Icons.receipt_long, size: 16),
                  label: const Text('Abrir Tricount'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _createTricountGroup(),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Crear grupo'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF16A34A),
                    side: const BorderSide(color: Color(0xFF16A34A)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── TAB 1: ITINERARY ──────────────────────────────────────────────────────
  Widget _buildItineraryTab() {
    if (widget.groupId == null) {
      return const Center(
        child: Text('Save the trip first',
            style: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF))),
      );
    }
    if (_itinLoading || _itinDetail == null) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF6B4EFF)));
    }
    final days = _sortedDays;
    return Column(
      children: [
        _buildMonthLabel(),
        _buildDaySelector(days),
        Expanded(child: _buildActivitiesList(days)),
      ],
    );
  }

  Widget _buildMonthLabel() {
    final months = ['January','February','March','April','May','June','July','August','September','October','November','December'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Align(alignment: Alignment.centerLeft,
        child: Text('${months[widget.startDate.month - 1]} ${widget.startDate.year}',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E)))),
    );
  }

  Widget _buildDaySelector(List<ItineraryDay> days) {
    final weekdays = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    return SizedBox(
      height: 72,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: days.length,
        itemBuilder: (ctx, i) {
          final date = widget.startDate.add(Duration(days: i));
          final active = _selectedDay == i;
          return GestureDetector(
            onTap: () => setState(() => _selectedDay = i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 10, top: 4, bottom: 4),
              width: 52,
              decoration: BoxDecoration(
                color: active ? const Color(0xFFE8533A) : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(weekdays[(date.weekday - 1) % 7],
                    style: TextStyle(fontSize: 11, color: active ? Colors.white70 : const Color(0xFF999999))),
                  const SizedBox(height: 2),
                  Text('${date.day}'.padLeft(2, '0'),
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold,
                      color: active ? Colors.white : const Color(0xFF1A1A2E))),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildActivitiesList(List<ItineraryDay> days) {
    if (_selectedDay >= days.length) return const SizedBox();
    final places = List<ItineraryPlace>.from(days[_selectedDay].places)
      ..sort((a, b) => a.position.compareTo(b.position));
    return Column(
      children: [
        Expanded(
          child: places.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_circle_outline, size: 56, color: Color(0xFFDDDDDD)),
                      SizedBox(height: 14),
                      Text('No plans yet for this day', style: TextStyle(fontSize: 15, color: Color(0xFF999999))),
                      SizedBox(height: 6),
                      Text('Tap "Add New Plan" below', style: TextStyle(fontSize: 12, color: Color(0xFFBBBBBB))),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  itemCount: places.length,
                  itemBuilder: (ctx, i) => _ActivityCard(
                    place: places[i],
                    onDelete: () => _deletePlace(places[i]),
                  ),
                ),
        ),
        if (places.length >= 2)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: GestureDetector(
              onTap: () => MapsExportService.openDayRoute(places, destination: widget.destination),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: kPrimary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.map_outlined, size: 18, color: kPrimary),
                    SizedBox(width: 8),
                    Text('View day route in Maps',
                      style: TextStyle(color: kPrimary, fontWeight: FontWeight.w700, fontSize: 13)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _deletePlace(ItineraryPlace place) async {
    final itinId = _itineraryId;
    if (itinId == null) return;
    HapticFeedback.lightImpact();
    final ok = await ItineraryService.deletePlace(place.id, itinId);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not remove plan'), backgroundColor: Colors.redAccent));
      return;
    }
    await _refreshItinerary();
  }

  Widget _buildAddPlanBtn() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: SizedBox(
        width: double.infinity, height: 52,
        child: ElevatedButton(
          onPressed: _itineraryId == null ? null : _showAddActivity,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1A1A2E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 0,
          ),
          child: const Text('Add New Plan', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }

  static String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<TimeOfDay?> _pickTime(BuildContext ctx, TimeOfDay? initial) {
    return showTimePicker(
      context: ctx,
      initialTime: initial ?? TimeOfDay.now(),
      builder: (c, child) => MediaQuery(
        data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
  }

  void _showAddActivity() {
    final nameCtrl = TextEditingController();
    String cat = 'Activities';
    TimeOfDay? start;
    TimeOfDay? end;
    bool saving = false;
    final dayLabel = _sortedDays.length > _selectedDay
        ? (_sortedDays[_selectedDay].title.isEmpty
            ? 'Day ${_sortedDays[_selectedDay].dayNumber}'
            : _sortedDays[_selectedDay].title)
        : '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setM) => Padding(
          padding: EdgeInsets.only(left: 24, right: 24, top: 24, bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(color: const Color(0xFFE5E7EB), borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const Text('Add New Plan', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF1A1A2E))),
              if (dayLabel.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(dayLabel, style: const TextStyle(fontSize: 13, color: Color(0xFF9CA3AF))),
              ],
              const SizedBox(height: 18),
              _SheetField(ctrl: nameCtrl, hint: 'Place or activity name'),
              const SizedBox(height: 16),
              const Text('Category', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF6B7280))),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8, runSpacing: 8,
                children: kPlaceCategories.map((c) {
                  final selected = c.label == cat;
                  return GestureDetector(
                    onTap: () => setM(() => cat = c.label),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: selected ? c.color.withOpacity(0.12) : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: selected ? c.color : const Color(0xFFE5E7EB), width: selected ? 1.5 : 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(c.emoji, style: const TextStyle(fontSize: 14)),
                          const SizedBox(width: 6),
                          Text(c.label, style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600,
                            color: selected ? c.color : const Color(0xFF374151),
                          )),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              const Text('Time (optional)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF6B7280))),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: _TimeField(
                  label: 'Start', value: start,
                  onTap: () async {
                    final picked = await _pickTime(ctx, start);
                    if (picked != null) setM(() => start = picked);
                  },
                )),
                const SizedBox(width: 12),
                Expanded(child: _TimeField(
                  label: 'End', value: end,
                  onTap: () async {
                    final picked = await _pickTime(ctx, end ?? start);
                    if (picked != null) setM(() => end = picked);
                  },
                )),
              ]),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity, height: 50,
                child: ElevatedButton(
                  onPressed: saving ? null : () async {
                    final name = nameCtrl.text.trim();
                    final itinId = _itineraryId;
                    if (name.isEmpty || itinId == null || _selectedDay >= _sortedDays.length) return;
                    setM(() => saving = true);
                    final day = _sortedDays[_selectedDay];
                    final timeLabel = start == null && end == null
                        ? null
                        : [
                            if (start != null) _fmtTime(start!),
                            if (end != null) _fmtTime(end!),
                          ].join(' - ');
                    final id = await ItineraryService.addPlace(
                      dayId: day.id,
                      itineraryId: itinId,
                      position: day.places.length,
                      placeName: name,
                      category: cat,
                      timeLabel: timeLabel,
                    );
                    if (id == null) {
                      setM(() => saving = false);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Could not add plan'), backgroundColor: Colors.redAccent));
                      return;
                    }
                    Navigator.pop(ctx);
                    HapticFeedback.lightImpact();
                    await _refreshItinerary();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A1A2E),
                    disabledBackgroundColor: const Color(0xFF1A1A2E).withOpacity(0.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: saving
                      ? const SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                      : const Text('Add', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── TAB 2: MEMBERS ────────────────────────────────────────────────────────
  Widget _buildMembersTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Travel Partners', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))),
          const SizedBox(height: 4),
          Text('${_members.length} of ${widget.guests + 1} joined',
            style: const TextStyle(fontSize: 13, color: Color(0xFF999999))),
          const SizedBox(height: 16),
          // Members list
          ..._members.map((m) => _MemberListTile(member: m)),
          // Pending slots
          ...List.generate(
            (widget.guests + 1 - _members.length).clamp(0, 99),
            (i) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F8F8),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFEEEEEE), style: BorderStyle.solid),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFFDDDDDD), width: 1.5),
                    ),
                    child: const Icon(Icons.person_add_outlined, color: Color(0xFFCCCCCC), size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Text('Waiting for member...', style: TextStyle(color: Color(0xFFBBBBBB), fontSize: 14)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _showShareSheet,
              icon: const Icon(Icons.person_add_alt_1, size: 18),
              label: const Text('Invite Travel Partners'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A1A2E),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── TAB 3: EXPENSES ───────────────────────────────────────────────────────
  Widget _buildExpensesTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Budget summary
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Budget Summary', style: TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 8),
                Text('${widget.currency}${_totalBudget.toStringAsFixed(0)}',
                  style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
                Text('Total for ${widget.guests + 1} people · ${widget.totalDays} days',
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _BudgetChip(label: 'Per person', value: '${widget.currency}${widget.budgetPerPerson.toStringAsFixed(0)}'),
                    const SizedBox(width: 12),
                    _BudgetChip(label: 'Per day', value: '${widget.currency}${_budgetPerDay.toStringAsFixed(0)}'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _buildTricountCard(),
          const SizedBox(height: 20),
          const Text('Expenses', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(color: const Color(0xFFF8F8F8), borderRadius: BorderRadius.circular(14)),
            child: const Center(
              child: Column(
                children: [
                  Icon(Icons.receipt_long_outlined, size: 40, color: Color(0xFFDDDDDD)),
                  SizedBox(height: 10),
                  Text('No expenses yet', style: TextStyle(color: Color(0xFF999999))),
                  SizedBox(height: 4),
                  Text('Add expenses from Tricount', style: TextStyle(fontSize: 12, color: Color(0xFFBBBBBB))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Share Sheet ───────────────────────────────────────────────────────────
  void _showShareSheet() {
    if (widget.groupId != null) {
      AnalyticsService.inviteShared(groupId: widget.groupId!);
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: const Color(0xFFDDDDDD), borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            const Text('Invite Travel Partners', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text('Share this code with your travel partners', style: TextStyle(fontSize: 13, color: Color(0xFF999999))),
            const SizedBox(height: 20),
            // Code display
            Container(
              padding: const EdgeInsets.symmetric(vertical: 18),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F4FF),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: Text(_inviteCode,
                  style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: Color(0xFF1A1A2E), letterSpacing: 10)),
              ),
            ),
            const SizedBox(height: 16),
            // Share options
            Row(
              children: [
                Expanded(child: _ShareOption(
                  icon: '📱',
                  label: 'WhatsApp',
                  color: const Color(0xFF25D366),
                  onTap: () => _shareViaWhatsApp(context),
                )),
                const SizedBox(width: 12),
                Expanded(child: _ShareOption(
                  icon: '📋',
                  label: 'Copiar',
                  color: const Color(0xFF29B6D2),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: 'Únete a mi viaje a ${widget.destination}! Código: $_inviteCode'));
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Enlace copiado al portapapeles'), backgroundColor: Color(0xFF29B6D2)));
                  },
                )),
                const SizedBox(width: 12),
                Expanded(child: _ShareOption(
                  icon: '✉️',
                  label: 'Email',
                  color: const Color(0xFFE8533A),
                  onTap: () => _shareViaEmail(context),
                )),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity, height: 50,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A1A2E),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: const Text('Done', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _shareViaWhatsApp(BuildContext sheetContext) async {
    final message = 'Únete a mi viaje a ${widget.destination}! Código: $_inviteCode';
    final uri = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(message)}');
    Navigator.pop(sheetContext);
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo abrir WhatsApp. ¿Está instalado?')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo abrir WhatsApp. ¿Está instalado?')));
      }
    }
  }

  Future<void> _shareViaEmail(BuildContext sheetContext) async {
    final subject = 'Únete a mi viaje a ${widget.destination}';
    final body = 'Únete a mi viaje a ${widget.destination}!\n\nCódigo de invitación: $_inviteCode';
    final uri = Uri(
      scheme: 'mailto',
      query: 'subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(body)}',
    );
    Navigator.pop(sheetContext);
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo abrir la app de correo.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo abrir la app de correo.')));
      }
    }
  }

  // ── Tricount ──────────────────────────────────────────────────────────────
  void _openTricount() {
    // En producción: url_launcher → https://tricount.com
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Tricount'),
        content: const Text('Instala la app Tricount o ve a tricount.com para gestionar los gastos del grupo.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
        ],
      ),
    );
  }

  void _createTricountGroup() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Crear grupo en Tricount'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Nombre sugerido: ${widget.tripName}'),
            const SizedBox(height: 8),
            Text('Miembros: ${widget.guests + 1}'),
            const SizedBox(height: 8),
            Text('Presupuesto total: ${widget.currency}${_totalBudget.toStringAsFixed(0)}'),
            const SizedBox(height: 12),
            const Text('Abre Tricount y crea un grupo con estos datos.', style: TextStyle(color: Color(0xFF999999), fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
          ElevatedButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: widget.tripName));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Nombre copiado'), backgroundColor: Color(0xFF16A34A)));
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF16A34A)),
            child: const Text('Copiar nombre', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

// ─── Data models ──────────────────────────────────────────────────────────────

class _Member {
  final String name, initials;
  final Color color;
  final bool isLeader;
  _Member({required this.name, required this.initials, required this.color, this.isLeader = false});
}

// ─── Small widgets ────────────────────────────────────────────────────────────

class _InfoCard extends StatelessWidget {
  final String icon, label, value;
  const _InfoCard({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFFF8F8F8), borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          Text(icon, style: const TextStyle(fontSize: 20)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E)), textAlign: TextAlign.center),
          Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF999999))),
        ],
      ),
    ),
  );
}

class _BudgetRow extends StatelessWidget {
  final String label, value;
  const _BudgetRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF666666))),
        Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))),
      ],
    ),
  );
}

class _BudgetChip extends StatelessWidget {
  final String label, value;
  const _BudgetChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10)),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
      ],
    ),
  );
}

class _MemberAvatar extends StatelessWidget {
  final _Member member;
  final double size;
  const _MemberAvatar({required this.member, this.size = 44});

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Container(
        width: size, height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: member.color),
        child: Center(child: Text(member.initials,
          style: TextStyle(color: Colors.white, fontSize: size * 0.3, fontWeight: FontWeight.bold))),
      ),
      if (member.isLeader)
        Positioned(
          right: 0, bottom: 0,
          child: Container(
            width: 16, height: 16,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFFFC107)),
            child: const Icon(Icons.star, size: 10, color: Colors.white),
          ),
        ),
    ],
  );
}

class _MemberListTile extends StatelessWidget {
  final _Member member;
  const _MemberListTile({required this.member});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)]),
    child: Row(
      children: [
        _MemberAvatar(member: member),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Text(member.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))),
                if (member.isLeader) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: const Color(0xFFFFF3CD), borderRadius: BorderRadius.circular(6)),
                    child: const Text('Leader', style: TextStyle(fontSize: 10, color: Color(0xFF856404), fontWeight: FontWeight.w600)),
                  ),
                ],
              ]),
              const Text('Joined', style: TextStyle(fontSize: 12, color: Color(0xFF999999))),
            ],
          ),
        ),
        const Icon(Icons.check_circle, color: Color(0xFF29B6D2), size: 20),
      ],
    ),
  );
}

class _ShareOption extends StatelessWidget {
  final String icon, label;
  final Color color;
  final VoidCallback onTap;
  const _ShareOption({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          Text(icon, style: const TextStyle(fontSize: 24)),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    ),
  );
}

// Misma taxonomía/colores que el itinerario publicado (placeCategory) para
// que una parada se vea igual aquí y en ItineraryDetailScreen._DayCard.
class _ActivityCard extends StatelessWidget {
  final ItineraryPlace place;
  final VoidCallback onDelete;
  const _ActivityCard({required this.place, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final cat = placeCategory(place.category);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEEF0F4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(color: cat.color.withOpacity(0.12), shape: BoxShape.circle),
            child: Center(child: Text(cat.emoji, style: const TextStyle(fontSize: 19))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(place.placeName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: cat.color.withOpacity(0.1), borderRadius: BorderRadius.circular(999)),
                      child: Text(cat.label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cat.color)),
                    ),
                    if (place.timeLabel != null && place.timeLabel!.isNotEmpty)
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.schedule, size: 12, color: Color(0xFF9CA3AF)),
                        const SizedBox(width: 3),
                        Text(place.timeLabel!, style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280), fontWeight: FontWeight.w500)),
                      ]),
                  ],
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onDelete,
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.close, size: 18, color: Color(0xFFD1D5DB)),
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetField extends StatelessWidget {
  final TextEditingController ctrl;
  final String hint;
  const _SheetField({required this.ctrl, required this.hint});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE8E8E8)), borderRadius: BorderRadius.circular(12)),
    child: TextField(
      controller: ctrl,
      decoration: InputDecoration(
        hintText: hint, hintStyle: const TextStyle(color: Color(0xFFBBBBBB), fontSize: 14),
        border: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    ),
  );
}

// Selector de hora táctil (formato 24h) para el sheet de "Add New Plan" —
// evita errores de tecleo frente a un campo de texto libre.
class _TimeField extends StatelessWidget {
  final String label;
  final TimeOfDay? value;
  final VoidCallback onTap;
  const _TimeField({required this.label, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final text = value == null
        ? label
        : '${value!.hour.toString().padLeft(2, '0')}:${value!.minute.toString().padLeft(2, '0')}';
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: value == null ? const Color(0xFFE8E8E8) : kPrimary),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.schedule, size: 16, color: value == null ? const Color(0xFF9CA3AF) : kPrimary),
            const SizedBox(width: 8),
            Text(text, style: TextStyle(
              fontSize: 14, fontWeight: FontWeight.w600,
              color: value == null ? const Color(0xFFBBBBBB) : const Color(0xFF1A1A2E),
            )),
          ],
        ),
      ),
    );
  }
}
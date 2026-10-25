// lib/screens/groups_screen.dart
//
// MEJORA UX #1: Barra de progreso del viaje + "X days to go" en cada card

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/common_widgets.dart';
import 'trip_detail_screen.dart';

// ══════════════════════════════════════════════════════════════
// MODELO
// ══════════════════════════════════════════════════════════════

class _TripGroup {
  final String id;
  final String inviteCode;
  final String tripName;
  final String destination;
  final DateTime? startDate;
  final DateTime? endDate;
  final int totalDays;
  final int memberCount;
  final String status;
  final List<_GroupMember> members;
  final String? coverImageUrl;
  final double? budgetPerPerson;
  final String currency;

  const _TripGroup({
    required this.id,
    required this.inviteCode,
    required this.tripName,
    required this.destination,
    this.startDate,
    this.endDate,
    required this.totalDays,
    required this.memberCount,
    required this.status,
    required this.members,
    this.coverImageUrl,
    this.budgetPerPerson,
    this.currency = 'USD',
  });

  factory _TripGroup.fromMap(
      Map<String, dynamic> map, List<_GroupMember> members) {
    final start = map['start_date'] != null
        ? DateTime.tryParse(map['start_date'] as String)
        : null;
    final end = map['end_date'] != null
        ? DateTime.tryParse(map['end_date'] as String)
        : null;

    final now = DateTime.now();
    String status = 'upcoming';
    if (start != null && end != null) {
      if (now.isAfter(end)) status = 'past';
      else if (now.isAfter(start)) status = 'ongoing';
    }

    return _TripGroup(
      id: map['id']?.toString() ?? '',
      inviteCode: map['invite_code'] as String? ?? '',
      tripName: map['trip_name'] as String? ?? 'My Trip',
      destination: map['destination'] as String? ?? '',
      startDate: start,
      endDate: end,
      totalDays: (map['total_days'] as num?)?.toInt() ?? 1,
      memberCount: (map['member_count'] as num?)?.toInt() ?? members.length,
      status: status,
      members: members,
      coverImageUrl: map['cover_image_url'] as String?,
      budgetPerPerson: (map['budget_per_person'] as num?)?.toDouble(),
      currency: map['currency'] as String? ?? 'USD',
    );
  }

  // ── Progreso del viaje (0.0 a 1.0) ──────────────────────
  double get tripProgress {
    if (startDate == null || endDate == null) return 0;
    final now = DateTime.now();
    if (now.isBefore(startDate!)) return 0;
    if (now.isAfter(endDate!)) return 1;
    final total = endDate!.difference(startDate!).inMinutes;
    final elapsed = now.difference(startDate!).inMinutes;
    return (elapsed / total).clamp(0.0, 1.0);
  }

  int get daysUntilStart {
    if (startDate == null) return 0;
    return startDate!.difference(DateTime.now()).inDays;
  }
}

class _GroupMember {
  final String firebaseUid;
  final String displayName;
  final String? avatarUrl;
  final bool isLeader;

  const _GroupMember({
    required this.firebaseUid,
    required this.displayName,
    this.avatarUrl,
    this.isLeader = false,
  });

  factory _GroupMember.fromMap(Map<String, dynamic> map) {
    return _GroupMember(
      firebaseUid: map['firebase_uid'] as String? ?? '',
      displayName: map['display_name'] as String? ?? 'Traveler',
      avatarUrl: map['avatar_url'] as String?,
      isLeader: map['is_leader'] as bool? ?? false,
    );
  }
}

// ══════════════════════════════════════════════════════════════
// GROUPS SCREEN
// ══════════════════════════════════════════════════════════════

class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key});

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen>
    with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  late TabController _tabController;

  List<_TripGroup> _upcomingGroups = [];
  List<_TripGroup> _ongoingGroups = [];
  List<_TripGroup> _pastGroups = [];
  bool _loading = true;
  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadGroups();
    // Refresco automático: sin botón manual, la lista se mantiene al día
    // sola mientras la pantalla está abierta (p.ej. si alguien se une
    // al grupo desde otro dispositivo).
    _autoRefreshTimer = Timer.periodic(
        const Duration(seconds: 30), (_) => _loadGroups(silent: true));
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadGroups({bool silent = false}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    try {
      // 1) Memberships del usuario actual
      final memberships = await _supabase
          .from('trip_group_members')
          .select('group_id, is_leader')
          .eq('firebase_uid', uid);

      if ((memberships as List).isEmpty) {
        if (mounted) {
          setState(() {
            _upcomingGroups = [];
            _ongoingGroups  = [];
            _pastGroups     = [];
            _loading = false;
          });
        }
        return;
      }

      final groupIds =
          memberships.map((r) => r['group_id'] as String).toList();

      // 2) Datos de los grupos
      final groupsData = await _supabase
          .from('trip_groups')
          .select()
          .inFilter('id', groupIds)
          .order('start_date', ascending: true);

      // 3) Miembros — query plana SIN JOIN embedded
      //    (más robusto que '... users(display_name, avatar_url)')
      final allMembersData = await _supabase
          .from('trip_group_members')
          .select('group_id, firebase_uid, is_leader')
          .inFilter('group_id', groupIds);

      // 4) Datos de usuarios (en una sola query para todos los miembros)
      final allUids = (allMembersData as List)
          .map((m) => m['firebase_uid'] as String)
          .toSet()
          .toList();

      final usersData = allUids.isEmpty
          ? <dynamic>[]
          : await _supabase
              .from('users')
              .select('firebase_uid, display_name, avatar_url')
              .inFilter('firebase_uid', allUids);

      final usersByUid = <String, Map<String, dynamic>>{
        for (final u in (usersData as List))
          (u['firebase_uid'] as String): u as Map<String, dynamic>,
      };

      // 5) Mapeo final
      final membersByGroup = <String, List<_GroupMember>>{};
      for (final m in allMembersData) {
        final gid  = m['group_id']     as String? ?? '';
        final muid = m['firebase_uid'] as String? ?? '';
        final u    = usersByUid[muid] ?? const <String, dynamic>{};
        membersByGroup.putIfAbsent(gid, () => []).add(_GroupMember(
              firebaseUid: muid,
              displayName: (u['display_name'] as String?)?.isNotEmpty == true
                  ? u['display_name'] as String
                  : 'Traveler',
              avatarUrl:   u['avatar_url'] as String?,
              isLeader:    m['is_leader']  as bool? ?? false,
            ));
      }

      final List<_TripGroup> allGroups = [];
      for (final groupMap in (groupsData as List)) {
        final gid     = groupMap['id']?.toString() ?? '';
        final members = (membersByGroup[gid] ?? []).take(5).toList();
        allGroups.add(_TripGroup.fromMap(groupMap, members));
      }

      if (mounted) {
        setState(() {
          _upcomingGroups =
              allGroups.where((g) => g.status == 'upcoming').toList();
          _ongoingGroups =
              allGroups.where((g) => g.status == 'ongoing').toList();
          _pastGroups =
              allGroups.where((g) => g.status == 'past').toList();
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading groups: $e');
      if (mounted) {
        // En refrescos automáticos silenciosos no interrumpimos con un
        // snackbar de error: se reintentará solo en el próximo tick.
        if (!silent) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not load groups: $e'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        setState(() => _loading = false);
      }
    }
  }

  void _show(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  void _copyCode(String code) {
    Clipboard.setData(ClipboardData(text: code));
    _show('Code $code copied!', kPrimary);
  }

  Future<void> _shareInviteViaWhatsApp(_TripGroup group) async {
    final message =
        'Únete a mi viaje a ${group.destination}! Código: ${group.inviteCode}';
    final uri = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(message)}');
    Navigator.pop(context);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication)
        .catchError((_) => false);
    if (!launched && mounted) {
      _show('No se pudo abrir WhatsApp. ¿Está instalado?', Colors.redAccent);
    }
  }

  Future<void> _shareInviteViaEmail(_TripGroup group) async {
    final subject = 'Únete a mi viaje a ${group.destination}';
    final body =
        'Únete a mi viaje a ${group.destination}!\n\nCódigo de invitación: ${group.inviteCode}';
    final uri = Uri(
      scheme: 'mailto',
      query: 'subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(body)}',
    );
    Navigator.pop(context);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication)
        .catchError((_) => false);
    if (!launched && mounted) {
      _show('No se pudo abrir la app de correo.', Colors.redAccent);
    }
  }

  void _showInviteShareSheet(_TripGroup group) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFDDDDDD),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            const Text('Invite Travel Partners',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(
              'Share this code with your travel partners',
              style: const TextStyle(fontSize: 13, color: Color(0xFF999999)),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 18),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F4FF),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: Text(group.inviteCode,
                    style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF1A1A2E),
                        letterSpacing: 10)),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _ShareOptionButton(
                    icon: '📱',
                    label: 'WhatsApp',
                    color: const Color(0xFF25D366),
                    onTap: () => _shareInviteViaWhatsApp(group),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ShareOptionButton(
                    icon: '📋',
                    label: 'Copiar',
                    color: kPrimary,
                    onTap: () {
                      Navigator.pop(context);
                      _copyCode(group.inviteCode);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ShareOptionButton(
                    icon: '✉️',
                    label: 'Email',
                    color: const Color(0xFFE8533A),
                    onTap: () => _shareInviteViaEmail(group),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '—';
    const months = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    return '${months[date.month - 1]} ${date.day}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(),
        _buildTabBar(),
        Expanded(child: _buildTabContent()),
      ],
    );
  }

  Widget _buildHeader() {
    return const Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('My Groups',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1A1A2E),
                letterSpacing: -0.5,
              )),
          SizedBox(height: 2),
          Text('Your travel squads',
              style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF))),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: const Color(0xFFEEEEEE),
          borderRadius: BorderRadius.circular(14),
        ),
        child: TabBar(
          controller: _tabController,
          indicator: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(11),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          indicatorSize: TabBarIndicatorSize.tab,
          labelColor: const Color(0xFF1A1A2E),
          unselectedLabelColor: const Color(0xFF9CA3AF),
          labelStyle: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w700),
          unselectedLabelStyle: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w500),
          dividerColor: Colors.transparent,
          tabs: [
            Tab(text: 'Upcoming${_upcomingGroups.isNotEmpty ? ' (${_upcomingGroups.length})' : ''}'),
            Tab(text: 'Now${_ongoingGroups.isNotEmpty ? ' (${_ongoingGroups.length})' : ''}'),
            Tab(text: 'Past${_pastGroups.isNotEmpty ? ' (${_pastGroups.length})' : ''}'),
          ],
        ),
      ),
    );
  }

  Widget _buildTabContent() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(
              color: kPrimary, strokeWidth: 2.5));
    }
    return TabBarView(
      controller: _tabController,
      children: [
        _buildGroupsList(_upcomingGroups, 'upcoming'),
        _buildGroupsList(_ongoingGroups, 'ongoing'),
        _buildGroupsList(_pastGroups, 'past'),
      ],
    );
  }

  Widget _buildGroupsList(List<_TripGroup> groups, String type) {
    if (groups.isEmpty) return _EmptyGroupsState(type: type);
    return RefreshIndicator(
      color: kPrimary,
      onRefresh: _loadGroups,
      child: ListView.separated(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        itemCount: groups.length,
        separatorBuilder: (_, __) => const SizedBox(height: 14),
        itemBuilder: (context, index) => _GroupCard(
          group: groups[index],
          onShare: _showInviteShareSheet,
          onTap: () => _openGroup(groups[index]),
          formatDate: _formatDate,
        ),
      ),
    );
  }

  void _openGroup(_TripGroup group) {
    if (group.startDate == null || group.endDate == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TripDetailScreen(
          destination: group.destination,
          tripName: group.tripName,
          startDate: group.startDate!,
          endDate: group.endDate!,
          guests: group.memberCount - 1,
          totalDays: group.totalDays,
          budgetPerPerson: group.budgetPerPerson ?? 0,
          currency: group.currency,
          groupId: group.id,
          inviteCode: group.inviteCode,
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// GROUP CARD — con barra de progreso y días restantes
// ══════════════════════════════════════════════════════════════

class _GroupCard extends StatelessWidget {
  final _TripGroup group;
  final void Function(_TripGroup) onShare;
  final VoidCallback onTap;
  final String Function(DateTime?) formatDate;

  const _GroupCard({
    required this.group,
    required this.onShare,
    required this.onTap,
    required this.formatDate,
  });

  Color get _statusColor {
    switch (group.status) {
      case 'ongoing': return const Color(0xFF16A34A);
      case 'past':    return const Color(0xFF9CA3AF);
      default:        return kPrimary;
    }
  }

  String get _statusLabel {
    switch (group.status) {
      case 'ongoing': return 'Ongoing ✈️';
      case 'past':    return 'Completed';
      default:
        final days = group.daysUntilStart;
        if (days <= 0) return 'Starting soon!';
        if (days == 1) return 'Tomorrow!';
        return 'In $days days';
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            _buildBanner(),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Nombre + badge
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(group.tripName,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF1A1A2E),
                                )),
                            const SizedBox(height: 2),
                            Text(group.destination,
                                style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF6B7280))),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _statusColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(_statusLabel,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _statusColor,
                            )),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // ── BARRA DE PROGRESO (solo upcoming/ongoing) ──
                  if (group.status != 'past') _buildProgressRow(),

                  const SizedBox(height: 12),

                  // Fechas + días
                  Row(
                    children: [
                      _InfoPill(
                        icon: Icons.calendar_today_outlined,
                        label: group.startDate != null &&
                                group.endDate != null
                            ? '${formatDate(group.startDate)} – ${formatDate(group.endDate)}'
                            : 'No dates yet',
                      ),
                      const SizedBox(width: 8),
                      _InfoPill(
                        icon: Icons.wb_sunny_outlined,
                        label: '${group.totalDays}d',
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Avatares + código
                  Row(
                    children: [
                      _MemberAvatarStack(members: group.members),
                      const SizedBox(width: 8),
                      Text(
                        '${group.memberCount} member${group.memberCount != 1 ? 's' : ''}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6B7280),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const Spacer(),
                      if (group.inviteCode.isNotEmpty)
                        GestureDetector(
                          onTap: () => onShare(group),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF3F4F6),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                Text(group.inviteCode,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF1A1A2E),
                                      letterSpacing: 1.5,
                                    )),
                                const SizedBox(width: 4),
                                const Icon(Icons.ios_share_rounded,
                                    size: 12,
                                    color: Color(0xFF9CA3AF)),
                              ],
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
      ),
    );
  }

  // ── Barra de progreso del viaje ──────────────────────────
  Widget _buildProgressRow() {
    if (group.status == 'upcoming') {
      // Sin progreso — muestra días restantes como bar vacía con label
      final days = group.daysUntilStart;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                days <= 0
                    ? 'Starting soon!'
                    : days == 1
                        ? '1 day to go 🎒'
                        : '$days days to go 🎒',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF374151),
                ),
              ),
              Text('0%',
                  style: TextStyle(
                      fontSize: 11, color: Colors.grey.shade400)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: 0,
              minHeight: 5,
              backgroundColor: const Color(0xFFE5E7EB),
              valueColor:
                  const AlwaysStoppedAnimation<Color>(kPrimary),
            ),
          ),
        ],
      );
    }

    // Ongoing — muestra progreso real
    final pct = (group.tripProgress * 100).toInt();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Trip in progress 🌍',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF16A34A),
              ),
            ),
            Text('$pct%',
                style: const TextStyle(
                    fontSize: 11, color: Color(0xFF16A34A),
                    fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: group.tripProgress,
            minHeight: 5,
            backgroundColor: const Color(0xFFDCFCE7),
            valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFF16A34A)),
          ),
        ),
      ],
    );
  }

  Widget _buildBanner() {
    return ClipRRect(
      borderRadius:
          const BorderRadius.vertical(top: Radius.circular(20)),
      child: SizedBox(
        height: 100,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            group.coverImageUrl != null
                ? Image.network(group.coverImageUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _bannerFallback())
                : _bannerFallback(),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF1A1A2E).withOpacity(0.5),
                    kPrimary.withOpacity(0.4),
                  ],
                ),
              ),
            ),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('✈️', style: TextStyle(fontSize: 28)),
                  const SizedBox(height: 4),
                  Text(
                    group.destination.isNotEmpty
                        ? group.destination
                        : 'Unknown Destination',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      shadows: [
                        Shadow(color: Colors.black45, blurRadius: 6)
                      ],
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

  Widget _bannerFallback() {
    final hue =
        (group.destination.hashCode % 360).abs().toDouble();
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            HSLColor.fromAHSL(1, hue, 0.5, 0.35).toColor(),
            HSLColor.fromAHSL(1, (hue + 40) % 360, 0.6, 0.25)
                .toColor(),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// MEMBER AVATAR STACK
// ══════════════════════════════════════════════════════════════

class _MemberAvatarStack extends StatelessWidget {
  final List<_GroupMember> members;

  const _MemberAvatarStack({required this.members});

  static const _colors = [
    Color(0xFF29B6D2), Color(0xFFF97316), Color(0xFF8B5CF6),
    Color(0xFF16A34A), Color(0xFFEC4899),
  ];

  @override
  Widget build(BuildContext context) {
    final display = members.take(4).toList();
    return SizedBox(
      width: display.length * 20.0 + 24,
      height: 28,
      child: Stack(
        children: List.generate(display.length, (i) {
          final m = display[i];
          return Positioned(
            left: i * 20.0,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                color: _colors[i % _colors.length],
              ),
              child: ClipOval(
                child: m.avatarUrl != null && m.avatarUrl!.isNotEmpty
                    ? Image.network(m.avatarUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            _initials(m.displayName,
                                _colors[i % _colors.length]))
                    : _initials(
                        m.displayName, _colors[i % _colors.length]),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _initials(String name, Color color) {
    final parts = name.trim().split(' ');
    final initials = parts.length >= 2
        ? '${parts[0][0]}${parts[1][0]}'
        : name.isNotEmpty
            ? name[0]
            : '?';
    return Container(
      color: color,
      child: Center(
        child: Text(initials.toUpperCase(),
            style: const TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.w700)),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// INFO PILL
// ══════════════════════════════════════════════════════════════

class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: const Color(0xFF6B7280)),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Color(0xFF374151),
              )),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// SHARE OPTION BUTTON (WhatsApp / Copiar / Email)
// ══════════════════════════════════════════════════════════════

class _ShareOptionButton extends StatelessWidget {
  final String icon, label;
  final Color color;
  final VoidCallback onTap;
  const _ShareOptionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12)),
          child: Column(
            children: [
              Text(icon, style: const TextStyle(fontSize: 24)),
              const SizedBox(height: 4),
              Text(label,
                  style: TextStyle(
                      fontSize: 12, color: color, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );
}

// ══════════════════════════════════════════════════════════════
// EMPTY STATE
// ══════════════════════════════════════════════════════════════

class _EmptyGroupsState extends StatelessWidget {
  final String type;

  const _EmptyGroupsState({required this.type});

  @override
  Widget build(BuildContext context) {
    final config = _emptyConfig(type);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(config['emoji']!,
                style: const TextStyle(fontSize: 56)),
            const SizedBox(height: 16),
            Text(config['title']!,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1A2E),
                ),
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(config['subtitle']!,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF9CA3AF),
                  height: 1.5,
                ),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Map<String, String> _emptyConfig(String type) {
    switch (type) {
      case 'ongoing':
        return {
          'emoji': '🏖️',
          'title': 'No active trips',
          'subtitle': 'You\'re not on any trip right now.\nEnjoy the calm!',
        };
      case 'past':
        return {
          'emoji': '📸',
          'title': 'No past trips yet',
          'subtitle': 'Your completed adventures\nwill show up here.',
        };
      default:
        return {
          'emoji': '✈️',
          'title': 'No upcoming trips',
          'subtitle':
              'Tap + to plan your next trip\nor join one with a group code.',
        };
    }
  }
}
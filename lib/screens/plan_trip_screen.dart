import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/analytics_service.dart';
import 'trip_detail_screen.dart';

class PlanTripScreen extends StatefulWidget {
  const PlanTripScreen({super.key});

  @override
  State<PlanTripScreen> createState() => _PlanTripScreenState();
}

class _PlanTripScreenState extends State<PlanTripScreen> {
  final _destinationCtrl = TextEditingController();
  final _tripNameCtrl    = TextEditingController();
  final _budgetCtrl      = TextEditingController();
  DateTime? _startDate;
  DateTime? _endDate;
  int _guests = 0;
  String _currency = '€';

  bool _saving = false;

  final List<Map<String, String>> _suggestions = [
    {'city': 'Paris',         'country': 'France'},
    {'city': 'Rome',          'country': 'Italy'},
    {'city': 'Tokyo',         'country': 'Japan'},
    {'city': 'New York',      'country': 'United States'},
    {'city': 'Barcelona',     'country': 'Spain'},
    {'city': 'Lisbon',        'country': 'Portugal'},
    {'city': 'Amsterdam',     'country': 'Netherlands'},
    {'city': 'Dubai',         'country': 'UAE'},
    {'city': 'London',        'country': 'United Kingdom'},
    {'city': 'Bangkok',       'country': 'Thailand'},
  ];

  List<Map<String, String>> _filtered = [];
  bool _showSuggestions = false;

  @override
  void initState() {
    super.initState();
    _destinationCtrl.addListener(_onDestChanged);
  }

  @override
  void dispose() {
    _destinationCtrl.dispose();
    _tripNameCtrl.dispose();
    _budgetCtrl.dispose();
    super.dispose();
  }

  void _onDestChanged() {
    final q = _destinationCtrl.text.toLowerCase();
    if (q.isEmpty) {
      setState(() { _showSuggestions = false; _filtered = []; });
      return;
    }
    setState(() {
      _filtered = _suggestions
          .where((s) =>
              s['city']!.toLowerCase().contains(q) ||
              s['country']!.toLowerCase().contains(q))
          .toList();
      _showSuggestions = _filtered.isNotEmpty;
    });
  }

  String get _formattedDates {
    if (_startDate == null) return '';
    final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final days   = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'];
    final s = '${days[_startDate!.weekday % 7]}, ${_startDate!.day} ${months[_startDate!.month - 1]}';
    if (_endDate == null) return s;
    final e = '${days[_endDate!.weekday % 7]}, ${_endDate!.day} ${months[_endDate!.month - 1]}';
    return '$s to $e';
  }

  Future<void> _pickDates() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _CalendarPicker(
        initialStart: _startDate,
        initialEnd: _endDate,
        onConfirm: (s, e) {
          setState(() { _startDate = s; _endDate = e; });
          Navigator.pop(context);
        },
      ),
    );
  }

  // ── NUEVO: garantiza que el usuario existe en public.users
  //    antes de cualquier insert que dependa de su FK.
  Future<bool> _ensureUserExists(String uid) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      await Supabase.instance.client.from('users').upsert(
        {
          'firebase_uid': uid,
          'email':        user?.email ?? '',
          'display_name': user?.displayName ?? user?.email?.split('@').first ?? '',
        },
        onConflict: 'firebase_uid',
        ignoreDuplicates: false,
      );
      return true;
    } catch (e) {
      debugPrint('Error ensuring user exists: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not sync user profile: $e'),
              backgroundColor: Colors.redAccent),
        );
      }
      return false;
    }
  }

  Future<void> _submit() async {
    if (_destinationCtrl.text.isEmpty) { _show('Please enter a destination'); return; }
    if (_startDate == null)            { _show('Please select dates');         return; }
    if (_tripNameCtrl.text.isEmpty)    { _show('Please enter a trip name');    return; }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _show('You must be logged in to create a trip');
      return;
    }

    final days = _endDate != null
        ? _endDate!.difference(_startDate!).inDays + 1
        : 1;
    final budget = double.tryParse(_budgetCtrl.text) ?? 0;

    setState(() => _saving = true);

    // 1) Garantiza que existe la fila en users (necesario para la FK)
    final userOk = await _ensureUserExists(uid);
    if (!userOk) {
      setState(() => _saving = false);
      return;
    }

    final inviteCode = _generateInviteCode();
    String? groupId;

    // 2) Inserta el trip_group
    try {
      final res = await Supabase.instance.client
          .from('trip_groups')
          .insert({
            'invite_code':       inviteCode,
            'trip_name':         _tripNameCtrl.text.trim(),
            'destination':       _destinationCtrl.text.trim(),
            'start_date':        _startDate!.toIso8601String().split('T').first,
            'end_date':          (_endDate ?? _startDate!).toIso8601String().split('T').first,
            'total_days':        days,
            'budget_per_person': budget,
            'currency':          _currency,
            'member_count':      _guests + 1,
            'created_by':        uid,
          })
          .select('id')
          .single();

      groupId = res['id']?.toString();
    } catch (e) {
      debugPrint('Error inserting trip_group: $e');
      _show('Could not save trip: $e');
      setState(() => _saving = false);
      return;
    }

    // 3) Añade al creador como miembro líder
    if (groupId != null) {
      try {
        await Supabase.instance.client.from('trip_group_members').insert({
          'group_id':     groupId,
          'firebase_uid': uid,
          'is_leader':    true,
        });
      } catch (e) {
        debugPrint('Error inserting trip_group_member: $e');
        _show('Trip saved, but could not add you as member: $e');
        // No abortamos — el trip está creado
      }
    }

    AnalyticsService.tripCreated(
      groupId: groupId,
      guests: _guests,
      totalDays: days,
    );

    if (!mounted) return;
    setState(() => _saving = false);

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => TripDetailScreen(
          destination:     _destinationCtrl.text,
          tripName:        _tripNameCtrl.text,
          startDate:       _startDate!,
          endDate:         _endDate ?? _startDate!,
          guests:          _guests,
          totalDays:       days,
          budgetPerPerson: budget,
          currency:        _currency,
          groupId:         groupId,
          inviteCode:      inviteCode,
        ),
      ),
    );
  }

  String _generateInviteCode() {
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

  void _show(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.redAccent));
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () { FocusScope.of(context).unfocus(); setState(() => _showSuggestions = false); },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 38, height: 38,
                        decoration: BoxDecoration(color: const Color(0xFFF0F0F0), borderRadius: BorderRadius.circular(12)),
                        child: const Icon(Icons.chevron_left, color: Colors.black87),
                      ),
                    ),
                    const Expanded(child: Center(child: Text('Plan a new trip', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)))),
                    const SizedBox(width: 38),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 16),
                      Center(
                        child: Container(
                          width: 72, height: 72,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0F4FF),
                            shape: BoxShape.circle,
                            boxShadow: [BoxShadow(color: const Color(0xFF29B6D2).withOpacity(0.15), blurRadius: 20)],
                          ),
                          child: const Center(child: Text('✈️', style: TextStyle(fontSize: 36))),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Center(
                        child: Text("Let's Start Planning\nA New Trip",
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Color(0xFF1A1A2E), height: 1.25)),
                      ),
                      const SizedBox(height: 28),

                      // Where to
                      const _Label('Where to?'),
                      const SizedBox(height: 8),
                      _buildDestField(),
                      if (_showSuggestions) _buildSuggestions(),
                      const SizedBox(height: 18),

                      // Trip Date
                      const _Label('Trip Date'),
                      const SizedBox(height: 8),
                      _TripField(icon: Icons.calendar_month_outlined, hint: 'set date', value: _formattedDates, onTap: _pickDates),
                      const SizedBox(height: 18),

                      // Guests
                      const _Label('Add guest list'),
                      const SizedBox(height: 8),
                      _GuestCounter(
                        value: _guests,
                        onDecrement: () { if (_guests > 0) setState(() => _guests--); },
                        onIncrement: () => setState(() => _guests++),
                      ),
                      const SizedBox(height: 18),

                      // Budget per person
                      const _Label('Budget per person'),
                      const SizedBox(height: 8),
                      _buildBudgetField(),
                      const SizedBox(height: 18),

                      // Trip Name
                      const _Label('Trip Name'),
                      const SizedBox(height: 8),
                      _buildTextField(_tripNameCtrl, 'type name'),
                      const SizedBox(height: 32),

                      // Submit
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: _saving ? null : _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1A1A2E),
                            disabledBackgroundColor:
                                const Color(0xFF1A1A2E).withOpacity(0.5),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                            elevation: 0,
                          ),
                          child: _saving
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2.5),
                                )
                              : const Text("Let's Start Planning",
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600)),
                        ),
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDestField() {
    return Container(
      decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE8E8E8)), borderRadius: BorderRadius.circular(14)),
      child: TextField(
        controller: _destinationCtrl,
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.location_on_outlined, color: Color(0xFF999999), size: 20),
          hintText: 'type location',
          hintStyle: TextStyle(color: Color(0xFFBBBBBB)),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 16),
        ),
      ),
    );
  }

  Widget _buildBudgetField() {
    return Container(
      decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE8E8E8)), borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          // Currency selector
          GestureDetector(
            onTap: () => _showCurrencyPicker(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
              decoration: const BoxDecoration(
                border: Border(right: BorderSide(color: Color(0xFFE8E8E8))),
              ),
              child: Text(_currency, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E))),
            ),
          ),
          Expanded(
            child: TextField(
              controller: _budgetCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                hintText: '0.00 per person',
                hintStyle: TextStyle(color: Color(0xFFBBBBBB)),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showCurrencyPicker() {
    final currencies = ['€', '\$', '£', '¥', 'CHF', 'kr'];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Select Currency', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: currencies.map((c) => GestureDetector(
                onTap: () { setState(() => _currency = c); Navigator.pop(context); },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: _currency == c ? const Color(0xFF1A1A2E) : const Color(0xFFF0F0F0),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(c, style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600,
                    color: _currency == c ? Colors.white : const Color(0xFF1A1A2E),
                  )),
                ),
              )).toList(),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController ctrl, String hint) {
    return Container(
      decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE8E8E8)), borderRadius: BorderRadius.circular(14)),
      child: TextField(
        controller: ctrl,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Color(0xFFBBBBBB)),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
    );
  }

  Widget _buildSuggestions() {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 16, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Text('Where To?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))),
          ),
          ..._filtered.map((s) => InkWell(
            onTap: () {
              _destinationCtrl.text = '${s['city']}, ${s['country']}';
              setState(() => _showSuggestions = false);
              FocusScope.of(context).unfocus();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFFE8E8E8))),
                    child: const Icon(Icons.search, size: 14, color: Color(0xFF999999)),
                  ),
                  const SizedBox(width: 12),
                  RichText(text: TextSpan(
                    style: const TextStyle(fontSize: 14, color: Colors.black87),
                    children: [
                      TextSpan(text: '${s['city']}, '),
                      TextSpan(text: s['country'], style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  )),
                ],
              ),
            ),
          )),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ─── Shared sub-widgets ───────────────────────────────────────────────────────

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E)));
}

class _TripField extends StatelessWidget {
  final IconData icon; final String hint, value; final VoidCallback onTap;
  const _TripField({required this.icon, required this.hint, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE8E8E8)), borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        Icon(icon, color: const Color(0xFF999999), size: 20),
        const SizedBox(width: 12),
        Text(value.isEmpty ? hint : value,
          style: TextStyle(fontSize: 14, color: value.isEmpty ? const Color(0xFFBBBBBB) : const Color(0xFF1A1A2E))),
      ]),
    ),
  );
}

class _GuestCounter extends StatelessWidget {
  final int value; final VoidCallback onDecrement, onIncrement;
  const _GuestCounter({required this.value, required this.onDecrement, required this.onIncrement});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE8E8E8)), borderRadius: BorderRadius.circular(14)),
    child: Row(children: [
      _CircleBtn(icon: Icons.remove, onTap: onDecrement),
      const SizedBox(width: 16),
      Text(value.toString().padLeft(2, '0'),
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E))),
      const SizedBox(width: 16),
      _CircleBtn(icon: Icons.add, onTap: onIncrement),
    ]),
  );
}

class _CircleBtn extends StatelessWidget {
  final IconData icon; final VoidCallback onTap;
  const _CircleBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 34, height: 34,
      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFFE8E8E8))),
      child: Icon(icon, size: 16, color: const Color(0xFF1A1A2E)),
    ),
  );
}

// ─── Calendar Picker ─────────────────────────────────────────────────────────

class _CalendarPicker extends StatefulWidget {
  final DateTime? initialStart, initialEnd;
  final void Function(DateTime, DateTime?) onConfirm;
  const _CalendarPicker({this.initialStart, this.initialEnd, required this.onConfirm});

  @override
  State<_CalendarPicker> createState() => _CalendarPickerState();
}

class _CalendarPickerState extends State<_CalendarPicker> {
  late DateTime _month;
  DateTime? _start, _end;

  @override
  void initState() {
    super.initState();
    _start = widget.initialStart;
    _end   = widget.initialEnd;
    _month = DateTime.now();
  }

  bool _isSame(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
  bool _inRange(DateTime d) => _start != null && _end != null && d.isAfter(_start!) && d.isBefore(_end!);

  void _onTap(DateTime d) {
    setState(() {
      if (_start == null || (_start != null && _end != null)) { _start = d; _end = null; }
      else if (d.isBefore(_start!)) { _end = _start; _start = d; }
      else { _end = d; }
    });
  }

  @override
  Widget build(BuildContext context) {
    final months = ['January','February','March','April','May','June','July','August','September','October','November','December'];
    final first = DateTime(_month.year, _month.month, 1);
    final startWd = first.weekday % 7;
    final daysInM = DateTime(_month.year, _month.month + 1, 0).day;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text("When's Your Trips?", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF1A1A2E))),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _MonthBtn(icon: Icons.chevron_left,  onTap: () => setState(() => _month = DateTime(_month.year, _month.month - 1))),
              Text('${months[_month.month - 1]}, ${_month.year}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              _MonthBtn(icon: Icons.chevron_right, onTap: () => setState(() => _month = DateTime(_month.year, _month.month + 1))),
            ],
          ),
          const SizedBox(height: 16),
          Row(children: ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'].map((d) => Expanded(
            child: Center(child: Text(d, style: const TextStyle(fontSize: 12, color: Color(0xFF999999), fontWeight: FontWeight.w500)))
          )).toList()),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, childAspectRatio: 1),
            itemCount: startWd + daysInM,
            itemBuilder: (ctx, i) {
              if (i < startWd) return const SizedBox();
              final day = DateTime(_month.year, _month.month, i - startWd + 1);
              final isS = _start != null && _isSame(day, _start!);
              final isE = _end   != null && _isSame(day, _end!);
              final inR = _inRange(day);
              return GestureDetector(
                onTap: () => _onTap(day),
                child: Container(
                  margin: const EdgeInsets.all(1),
                  decoration: BoxDecoration(
                    color: (isS || isE) ? const Color(0xFFE8533A) : inR ? const Color(0xFFFFECE8) : Colors.transparent,
                    shape: (isS || isE) ? BoxShape.circle : BoxShape.rectangle,
                    borderRadius: inR ? BorderRadius.circular(4) : null,
                  ),
                  child: Center(child: Text('${day.day}', style: TextStyle(
                    fontSize: 13,
                    fontWeight: (isS || isE) ? FontWeight.bold : FontWeight.normal,
                    color: (isS || isE) ? Colors.white : inR ? const Color(0xFFE8533A) : const Color(0xFF1A1A2E),
                  ))),
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity, height: 52,
            child: ElevatedButton(
              onPressed: _start == null ? null : () => widget.onConfirm(_start!, _end),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A1A2E),
                disabledBackgroundColor: const Color(0xFFCCCCCC),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: const Text('Confirm', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthBtn extends StatelessWidget {
  final IconData icon; final VoidCallback onTap;
  const _MonthBtn({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 36, height: 36,
      decoration: const BoxDecoration(color: Color(0xFFF0F0F0), shape: BoxShape.circle),
      child: Icon(icon, size: 18, color: const Color(0xFF1A1A2E)),
    ),
  );
}
// lib/widgets/trip_kit_sections.dart
//
// Secciones del Kit del viaje (pestañas de trip_detail):
//   • PhotosSection    — links de fotos (WeTransfer/Drive...), máx. 20
//   • ChecklistSection — sub-tabs Tasks | Packing (quién lleva qué)
//   • InfoSection      — info práctica/emergencia del viaje
//   • EssentialsCard   — bloque compacto de afiliación para Overview
//
// Cada sección es autónoma: recibe groupId y carga lo suyo.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../services/affiliate_service.dart';
import '../services/trip_kit_service.dart';
import 'common_widgets.dart';

const _kDark = Color(0xFF1A1A2E);
const _kGrey = Color(0xFF9CA3AF);

// ══════════════════════════════════════════════════════════════
// PHOTOS — links de fotos compartidas
// ══════════════════════════════════════════════════════════════

class PhotosSection extends StatefulWidget {
  final String groupId;
  const PhotosSection({super.key, required this.groupId});

  @override
  State<PhotosSection> createState() => _PhotosSectionState();
}

class _PhotosSectionState extends State<PhotosSection> {
  List<TripLink> _links = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final links = await TripKitService.listLinks(widget.groupId);
    if (!mounted) return;
    setState(() {
      _links = links;
      _loading = false;
    });
  }

  Future<void> _addLinkDialog() async {
    final titleCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add photos link'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              autofocus: true,
              decoration:
                  const InputDecoration(hintText: 'e.g. Day 1 — Marta'),
            ),
            TextField(
              controller: urlCtrl,
              decoration:
                  const InputDecoration(hintText: 'https://we.tl/...'),
            ),
          ],
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

    final name = await TripKitService.myDisplayName();
    final error = await TripKitService.addLink(
      groupId: widget.groupId,
      title: titleCtrl.text,
      url: urlCtrl.text,
      addedBy: name,
    );
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: Colors.redAccent),
      );
    } else {
      _load();
    }
  }

  void _copy(TripLink l) {
    Clipboard.setData(ClipboardData(text: l.url));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Link copied 📋'), backgroundColor: kPrimary),
    );
  }

  String _rel(DateTime dt) {
    final d = DateTime.now().difference(dt).inDays;
    if (d == 0) return 'today';
    if (d == 1) return '1d ago';
    return '${d}d ago';
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('Trip photos',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _kDark)),
            ),
            Text('${_links.length}/${TripKitService.maxLinksPerKind}',
                style: const TextStyle(fontSize: 12, color: _kGrey)),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Upload your photos to WeTransfer (or Drive/iCloud) and paste the link here so everyone has them. WeTransfer links expire in ~7 days.',
          style: TextStyle(fontSize: 12, color: _kGrey, height: 1.4),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => AffiliateService.openUrl(
                    'https://wetransfer.com/'),
                icon: const Icon(Icons.cloud_upload_outlined,
                    size: 18, color: kPrimary),
                label: const Text('Open WeTransfer',
                    style: TextStyle(
                        color: kPrimary, fontWeight: FontWeight.w700)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: kPrimary, width: 1.5),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            ElevatedButton.icon(
              onPressed: _addLinkDialog,
              icon: const Icon(Icons.add, size: 18, color: Colors.white),
              label: const Text('Add link',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimary,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child:
                Center(child: CircularProgressIndicator(color: kPrimary)),
          )
        else if (_links.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Center(
              child: Text('📸  No photo links yet',
                  style: TextStyle(fontSize: 14, color: _kGrey)),
            ),
          )
        else
          ..._links.map((l) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFEEF0F4)),
                ),
                child: Row(
                  children: [
                    const Text('📸', style: TextStyle(fontSize: 22)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: _kDark)),
                          Text('${l.addedBy} · ${_rel(l.createdAt)}',
                              style: const TextStyle(
                                  fontSize: 12, color: _kGrey)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy,
                          size: 18, color: Color(0xFF6B7280)),
                      onPressed: () => _copy(l),
                    ),
                    IconButton(
                      icon: const Icon(Icons.open_in_new,
                          size: 18, color: kPrimary),
                      onPressed: () => AffiliateService.openUrl(l.url),
                    ),
                  ],
                ),
              )),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════
// CHECKLIST — sub-tabs Tasks | Packing
// ══════════════════════════════════════════════════════════════

class ChecklistSection extends StatefulWidget {
  final String groupId;
  const ChecklistSection({super.key, required this.groupId});

  @override
  State<ChecklistSection> createState() => _ChecklistSectionState();
}

class _ChecklistSectionState extends State<ChecklistSection> {
  int _subTab = 0; // 0 = Tasks · 1 = Packing
  List<KitItem> _tasks = [];
  List<KitItem> _packing = [];
  List<GroupMember> _members = [];
  bool _loading = true;

  String get _table =>
      _subTab == 0 ? TripKitService.checklistTable : TripKitService.packingTable;
  List<KitItem> get _items => _subTab == 0 ? _tasks : _packing;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      TripKitService.listItems(TripKitService.checklistTable, widget.groupId),
      TripKitService.listItems(TripKitService.packingTable, widget.groupId),
      TripKitService.groupMembers(widget.groupId),
    ]);
    if (!mounted) return;
    setState(() {
      _tasks = results[0] as List<KitItem>;
      _packing = results[1] as List<KitItem>;
      _members = results[2] as List<GroupMember>;
      _loading = false;
    });
  }

  Future<void> _addItem() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(_subTab == 0 ? 'Add task' : 'Add item to pack'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
              hintText: _subTab == 0 ? 'e.g. Book museum tickets' : 'e.g. Speaker'),
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
    final added =
        await TripKitService.addItem(_table, widget.groupId, ctrl.text);
    if (added) _load();
  }

  Future<void> _assign(KitItem item) async {
    final picked = await showModalBottomSheet<GroupMember?>(
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
            const SizedBox(height: 14),
            const Text('Assign to',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w800, color: _kDark)),
            const SizedBox(height: 6),
            ..._members.map((m) => ListTile(
                  leading: CircleAvatar(
                    radius: 14,
                    backgroundColor: kPrimary,
                    child: Text(m.name[0].toUpperCase(),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                  ),
                  title: Text(m.name),
                  onTap: () => Navigator.pop(context, m),
                )),
            ListTile(
              leading: const Icon(Icons.person_off_outlined, color: _kGrey),
              title: const Text('Unassigned'),
              onTap: () => Navigator.pop(context, null),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    // null puede ser "Unassigned" o cierre del sheet; ambos son seguros.
    await TripKitService.assignItem(_table, item.id, picked);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: kPrimary));
    }
    final doneCount = _items.where((i) => i.done).length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
      children: [
        // Sub-tabs
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: const Color(0xFFF0F0F0),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              _seg('✅ Tasks', 0),
              _seg('🎒 Packing', 1),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: Text('$doneCount/${_items.length} done',
                  style: const TextStyle(fontSize: 12, color: _kGrey)),
            ),
            TextButton.icon(
              onPressed: _addItem,
              icon: const Icon(Icons.add, size: 18, color: kPrimary),
              label: const Text('Add',
                  style: TextStyle(
                      color: kPrimary, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        if (_items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: Center(
              child: Text(
                _subTab == 0
                    ? '✅  No tasks yet — add the first one'
                    : '🎒  Decide who brings what',
                style: const TextStyle(fontSize: 14, color: _kGrey),
              ),
            ),
          )
        else
          ..._items.map((i) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFEEF0F4)),
                ),
                child: Row(
                  children: [
                    Checkbox(
                      value: i.done,
                      activeColor: kPrimary,
                      onChanged: (v) async {
                        await TripKitService.toggleDone(
                            _table, i.id, v ?? false);
                        _load();
                      },
                    ),
                    Expanded(
                      child: Text(
                        i.title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: i.done ? _kGrey : _kDark,
                          decoration:
                              i.done ? TextDecoration.lineThrough : null,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => _assign(i),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: i.assigneeName == null
                              ? const Color(0xFFF0F0F0)
                              : kPrimary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          i.assigneeName ?? 'Assign',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: i.assigneeName == null
                                ? _kGrey
                                : kPrimary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: () async {
                        await TripKitService.deleteItem(_table, i.id);
                        _load();
                      },
                      child: const Icon(Icons.close,
                          size: 16, color: Color(0xFFD1D5DB)),
                    ),
                  ],
                ),
              )),
      ],
    );
  }

  Widget _seg(String label, int index) {
    final selected = _subTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _subTab = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? kPrimary : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : _kGrey,
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// INFO — práctica / emergencia
// ══════════════════════════════════════════════════════════════

class InfoSection extends StatefulWidget {
  final String groupId;
  const InfoSection({super.key, required this.groupId});

  @override
  State<InfoSection> createState() => _InfoSectionState();
}

class _InfoSectionState extends State<InfoSection> {
  final _meetingCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _insuranceCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _meetingCtrl.dispose();
    _phoneCtrl.dispose();
    _insuranceCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final info = await TripKitService.getInfo(widget.groupId);
    if (!mounted) return;
    setState(() {
      _meetingCtrl.text = info.meetingPoint;
      _phoneCtrl.text = info.lodgingPhone;
      _insuranceCtrl.text = info.insurance;
      _notesCtrl.text = info.notes;
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final ok = await TripKitService.saveInfo(
      widget.groupId,
      TripInfo(
        meetingPoint: _meetingCtrl.text.trim(),
        lodgingPhone: _phoneCtrl.text.trim(),
        insurance: _insuranceCtrl.text.trim(),
        notes: _notesCtrl.text.trim(),
      ),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'Info saved ✓' : 'Could not save'),
      backgroundColor: ok ? kPrimary : Colors.redAccent,
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: kPrimary));
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
      children: [
        const Text(
          'Practical info everyone should have at hand.',
          style: TextStyle(fontSize: 12, color: _kGrey),
        ),
        const SizedBox(height: 14),
        _field('📍 Meeting point', _meetingCtrl, 'e.g. Hotel lobby, Plaça Catalunya'),
        _field('📞 Lodging phone', _phoneCtrl, '+34 ...'),
        _field('🛡️ Insurance / policy', _insuranceCtrl, 'Company + policy number'),
        _field('📝 Notes', _notesCtrl, 'Anything else…', maxLines: 4),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _saving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimary,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: _saving
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: Colors.white))
                : const Text('Save',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w800)),
          ),
        ),
      ],
    );
  }

  Widget _field(String label, TextEditingController ctrl, String hint,
      {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: _kDark)),
          const SizedBox(height: 6),
          TextField(
            controller: ctrl,
            maxLines: maxLines,
            decoration: InputDecoration(
              hintText: hint,
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
              ),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// ESSENTIALS — bloque compacto de afiliación para el Overview
// ══════════════════════════════════════════════════════════════

class EssentialsCard extends StatelessWidget {
  const EssentialsCard({super.key});

  @override
  Widget build(BuildContext context) {
    final items = AffiliateService.essentials;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEEF0F4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Travel essentials',
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.bold, color: _kDark)),
          const SizedBox(height: 10),
          ...items.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GestureDetector(
                  onTap: () => AffiliateService.open(e.link,
                      category: 'essentials'),
                  child: Row(
                    children: [
                      Text(e.emoji, style: const TextStyle(fontSize: 20)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(e.title,
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: _kDark)),
                            Text('${e.subtitle} · ${e.link.partner}',
                                style: const TextStyle(
                                    fontSize: 11, color: _kGrey)),
                          ],
                        ),
                      ),
                      const Icon(Icons.open_in_new,
                          size: 15, color: kPrimary),
                    ],
                  ),
                ),
              )),
        ],
      ),
    );
  }
}

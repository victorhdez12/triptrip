// lib/screens/publish_itinerary_screen.dart
//
// Permite al usuario publicar un itinerario.
// Dos modos:
//   • Desde cero (sin trip de origen)
//   • Desde un viaje existente (pasa tripGroupId al constructor)
//
// Después de publicar, navega al detalle del nuevo itinerario.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/itinerary_service.dart';
import '../services/analytics_service.dart';
import '../services/feed_service.dart';
import '../widgets/common_widgets.dart';
import 'itinerary_edit_screen.dart';

class PublishItineraryScreen extends StatefulWidget {
  /// Si se pasa, publica a partir del trip_group existente.
  final String? sourceTripGroupId;
  /// Datos prefill cuando se viene desde un trip.
  final String? prefillTitle;
  final String? prefillDestination;
  final String? prefillCountryFlag;

  const PublishItineraryScreen({
    super.key,
    this.sourceTripGroupId,
    this.prefillTitle,
    this.prefillDestination,
    this.prefillCountryFlag,
  });

  @override
  State<PublishItineraryScreen> createState() => _PublishItineraryScreenState();
}

class _PublishItineraryScreenState extends State<PublishItineraryScreen> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _destCtrl;
  late final TextEditingController _flagCtrl;
  final _descCtrl = TextEditingController();

  bool _public = true;
  bool _saving = false;

  String _myName = '';
  String _myColor = '#29B6D2';

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.prefillTitle ?? '');
    _destCtrl  = TextEditingController(text: widget.prefillDestination ?? '');
    _flagCtrl  = TextEditingController(text: widget.prefillCountryFlag ?? '📍');
    _loadMyProfile();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _destCtrl.dispose();
    _flagCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMyProfile() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final res = await Supabase.instance.client
          .from('users')
          .select('display_name, avatar_color')
          .eq('firebase_uid', uid)
          .maybeSingle();
      if (res != null && mounted) {
        setState(() {
          _myName  = (res['display_name'] as String?) ?? '';
          _myColor = (res['avatar_color'] as String?) ?? '#29B6D2';
        });
      }
    } catch (_) {}
  }

  Future<void> _publish() async {
    if (_titleCtrl.text.trim().isEmpty) {
      _show('Please enter a title');
      return;
    }
    if (_destCtrl.text.trim().isEmpty) {
      _show('Please enter a destination');
      return;
    }

    setState(() => _saving = true);

    String? newId;
    if (widget.sourceTripGroupId != null) {
      newId = await ItineraryService.publishFromTrip(
        tripGroupId: widget.sourceTripGroupId!,
        title:       _titleCtrl.text,
        description: _descCtrl.text,
        isPublic:    _public,
        displayName: _myName,
        avatarColor: _myColor,
      );
    } else {
      newId = await ItineraryService.publishEmpty(
        title:        _titleCtrl.text,
        destination:  _destCtrl.text,
        countryFlag:  _flagCtrl.text,
        description:  _descCtrl.text,
        isPublic:     _public,
        displayName:  _myName,
        avatarColor:  _myColor,
      );
    }

    if (!mounted) return;
    setState(() => _saving = false);

    if (newId == null) {
      _show('Could not publish itinerary', Colors.redAccent);
      return;
    }

    if (_public) feedChanged.value++; // refresca el feed del dashboard
    AnalyticsService.itineraryPublished(
      itineraryId: newId!,
      isPublic: _public,
      fromTrip: widget.sourceTripGroupId != null,
    );

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => ItineraryEditScreen(itineraryId: newId!)),
    );
  }

  void _show(String msg, [Color color = kPrimary]) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fromTrip = widget.sourceTripGroupId != null;
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF1A1A2E)),
        title: Text(fromTrip ? 'Publish trip' : 'New itinerary',
          style: const TextStyle(
            color: Color(0xFF1A1A2E),
            fontWeight: FontWeight.w800,
            fontSize: 17,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          _label('Title'),
          _textField(_titleCtrl, hint: 'A weekend in Lisbon...'),
          const SizedBox(height: 16),

          _label('Destination'),
          _textField(_destCtrl, hint: 'Lisbon, Portugal'),
          const SizedBox(height: 16),

          _label('Country flag'),
          _textField(_flagCtrl, hint: '🇵🇹'),
          const SizedBox(height: 16),

          _label('Description (optional)'),
          _textField(_descCtrl, hint: 'What makes this trip special?', maxLines: 4),
          const SizedBox(height: 20),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Public', style: TextStyle(fontWeight: FontWeight.w700)),
                      Text('Visible in explore and to your followers',
                        style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _public,
                  activeColor: kPrimary,
                  onChanged: (v) => setState(() => _public = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _saving ? null : _publish,
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: _saving
                  ? const SizedBox(
                      width: 22, height: 22,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                    )
                  : Text(_public ? 'Publish' : 'Save as draft',
                      style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 0, 0, 6),
        child: Text(t,
          style: const TextStyle(
            fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF374151),
          ),
        ),
      );

  Widget _textField(TextEditingController c, {String? hint, int maxLines = 1}) {
    return TextField(
      controller: c,
      maxLines: maxLines,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFEEF0F4)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFEEF0F4)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: kPrimary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }
}

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'interests_screen.dart';

class ChooseLocationScreen extends StatefulWidget {
  const ChooseLocationScreen({super.key});

  @override
  State<ChooseLocationScreen> createState() => _ChooseLocationScreenState();
}

class _ChooseLocationScreenState extends State<ChooseLocationScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  bool _loadingLocation = false;
  String _detectedCity    = '';
  String _detectedRegion  = '';
  String _detectedCountry = '';
  bool _locationSaved     = false; // true cuando hay ubicación guardada
  int _selectedIndex      = -1;

  final List<Map<String, String>> _locations = [
    {'name': 'Madrid',    'sub': 'Comunidad de Madrid, España',  'km': '0.5 KM'},
    {'name': 'Barcelona', 'sub': 'Cataluña, España',             'km': '6.2 KM'},
    {'name': 'Valencia',  'sub': 'Comunidad Valenciana, España', 'km': '3.1 KM'},
    {'name': 'Sevilla',   'sub': 'Andalucía, España',            'km': '9.8 KM'},
    {'name': 'Bilbao',    'sub': 'País Vasco, España',           'km': '12.4 KM'},
  ];

  List<Map<String, String>> get _filtered {
    final q = _searchCtrl.text.toLowerCase();
    if (q.isEmpty) return _locations;
    return _locations
        .where((l) =>
            l['name']!.toLowerCase().contains(q) ||
            l['sub']!.toLowerCase().contains(q))
        .toList();
  }

  Future<void> _detectLocation() async {
    setState(() => _loadingLocation = true);
    try {
      final response = await http
          .get(Uri.parse('http://ip-api.com/json/?fields=city,regionName,country'))
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _detectedCity    = data['city']       ?? '';
          _detectedRegion  = data['regionName'] ?? '';
          _detectedCountry = data['country']    ?? '';
          _locationSaved   = true;
        });
      }
    } catch (_) {
      setState(() {
        _detectedCity  = 'Ubicación no disponible';
        _locationSaved = true;
      });
    }
    setState(() => _loadingLocation = false);
  }

  void _goNext() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const InterestsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ───────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.maybePop(context),
                    child: Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F0F0),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.chevron_left, color: Colors.black87),
                    ),
                  ),
                  const Expanded(
                    child: Center(
                      child: Text('Choose location',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
                    ),
                  ),
                  const SizedBox(width: 36),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),

                    // ── Detectar ubicación ───────────────────────────────
                    GestureDetector(
                      onTap: _loadingLocation ? null : _detectLocation,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: _locationSaved
                              ? const Color(0xFFE8F5E9)
                              : const Color(0xFFF0F9FF),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: _locationSaved
                                ? const Color(0xFF4CAF50)
                                : const Color(0xFF29B6D2),
                          ),
                        ),
                        child: Row(
                          children: [
                            _loadingLocation
                                ? const SizedBox(
                                    width: 20, height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Color(0xFF29B6D2)),
                                  )
                                : Icon(
                                    _locationSaved
                                        ? Icons.check_circle
                                        : Icons.my_location,
                                    color: _locationSaved
                                        ? const Color(0xFF4CAF50)
                                        : const Color(0xFF29B6D2),
                                    size: 20,
                                  ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _loadingLocation
                                  ? const Text('Detectando ubicación...',
                                      style: TextStyle(color: Color(0xFF29B6D2), fontWeight: FontWeight.w500))
                                  : _locationSaved
                                      ? Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(_detectedCity,
                                                style: const TextStyle(
                                                    color: Color(0xFF2E7D32),
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 14)),
                                            if (_detectedRegion.isNotEmpty)
                                              Text('$_detectedRegion, $_detectedCountry',
                                                  style: const TextStyle(
                                                      color: Color(0xFF388E3C),
                                                      fontSize: 12)),
                                          ],
                                        )
                                      : const Text('Usar mi ubicación actual',
                                          style: TextStyle(
                                              color: Color(0xFF29B6D2),
                                              fontWeight: FontWeight.w600)),
                            ),
                            if (_locationSaved)
                              TextButton(
                                onPressed: () => setState(() {
                                  _locationSaved = false;
                                  _detectedCity  = '';
                                }),
                                child: const Text('Cambiar',
                                    style: TextStyle(color: Color(0xFF29B6D2), fontSize: 12)),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Buscador ─────────────────────────────────────────
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F5F5),
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: TextField(
                        controller: _searchCtrl,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          hintText: 'Search location',
                          hintStyle: TextStyle(color: Color(0xFFBBBBBB)),
                          border: InputBorder.none,
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                          suffixIcon: Icon(Icons.search, color: Color(0xFF555555)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ── Lista de ubicaciones ──────────────────────────────
                    const Text('Popular location',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87)),
                    const SizedBox(height: 8),
                    ..._filtered.map((loc) {
                      final i = _locations.indexOf(loc);
                      final isSelected = _selectedIndex == i;
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedIndex = i;
                            _locationSaved = true;
                            _detectedCity    = loc['name']!;
                            _detectedRegion  = loc['sub']!;
                            _detectedCountry = '';
                          });
                        },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 4),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Row(
                              children: [
                                Icon(Icons.location_on_outlined,
                                    color: isSelected
                                        ? const Color(0xFF29B6D2)
                                        : const Color(0xFF29B6D2),
                                    size: 26),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(loc['name']!,
                                          style: TextStyle(
                                              fontWeight: isSelected
                                                  ? FontWeight.bold
                                                  : FontWeight.w500,
                                              color: Colors.black87)),
                                      Text(loc['sub']!,
                                          style: const TextStyle(
                                              fontSize: 12, color: Color(0xFF999999))),
                                    ],
                                  ),
                                ),
                                Text(loc['km']!,
                                    style: const TextStyle(
                                        fontSize: 12, color: Colors.black45)),
                                if (isSelected) ...[
                                  const SizedBox(width: 8),
                                  const Icon(Icons.check_circle,
                                      color: Color(0xFF29B6D2), size: 18),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 100), // espacio para el botón fijo
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      // ── Botón siguiente — solo aparece cuando hay ubicación guardada ──
      bottomNavigationBar: _locationSaved
          ? Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _goNext,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF29B6D2),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  child: const Text('Next →',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600)),
                ),
              ),
            )
          : null,
    );
  }
}
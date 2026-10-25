// lib/screens/onboarding_flow_screen.dart
//
// Flujo de onboarding para nuevos usuarios: 3 pasos en un PageView fluido.
// Paso 1 → Idioma
// Paso 2 → Ubicación
// Paso 3 → Intereses
//
// Al completarse guarda 'onboarding_done_<uid>' en SharedPreferences
// y navega a HomeScreen eliminando el stack.

import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_locale.dart';
import '../widgets/common_widgets.dart';
import 'home_screen.dart';

// ══════════════════════════════════════════════════════════════
// ONBOARDING FLOW SCREEN (contenedor PageView)
// ══════════════════════════════════════════════════════════════

class OnboardingFlowScreen extends StatefulWidget {
  const OnboardingFlowScreen({super.key});

  @override
  State<OnboardingFlowScreen> createState() => _OnboardingFlowScreenState();
}

class _OnboardingFlowScreenState extends State<OnboardingFlowScreen> {
  final _pageController = PageController();
  int _currentPage = 0;

  // Datos acumulados del onboarding
  String _selectedLangCode = 'en';
  String _selectedCity = '';
  String _selectedCountryCode = '';
  final Set<String> _selectedInterests = {};

  void _nextPage() {
    if (_currentPage < 2) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _completeOnboarding() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      // Guardar en Supabase
      await Supabase.instance.client.from('users').upsert({
        'firebase_uid': uid,
        'language_code': _selectedLangCode,
        'country_code': _selectedCountryCode,
        'city': _selectedCity,
        'interests': _selectedInterests.toList(),
      });

      // Guardar intereses en tabla separada si tienes user_interests
      if (_selectedInterests.isNotEmpty) {
        final interestRows = _selectedInterests
            .map((tag) => {'firebase_uid': uid, 'interest_tag': tag})
            .toList();
        await Supabase.instance.client
            .from('user_interests')
            .upsert(interestRows);
      }
    } catch (e) {
      debugPrint('Error saving onboarding data: $e');
      // Continuamos igualmente — no bloqueamos al usuario
    }

    // Marcar onboarding como completado localmente
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done_$uid', true);

    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (route) => false,
      );
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      body: SafeArea(
        child: Column(
          children: [
            // ── Barra de progreso ──────────────────────────
            _buildProgressBar(),

            // ── Páginas ────────────────────────────────────
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() => _currentPage = i),
                children: [
                  _LanguageStep(
                    selectedCode: _selectedLangCode,
                    onSelected: (code) {
                      setState(() => _selectedLangCode = code);
                    },
                    onNext: _nextPage,
                  ),
                  _LocationStep(
                    onSelected: (city, countryCode) {
                      setState(() {
                        _selectedCity = city;
                        _selectedCountryCode = countryCode;
                      });
                    },
                    onNext: _nextPage,
                  ),
                  _InterestsStep(
                    selectedInterests: _selectedInterests,
                    onToggle: (tag) {
                      setState(() {
                        if (_selectedInterests.contains(tag)) {
                          _selectedInterests.remove(tag);
                        } else {
                          _selectedInterests.add(tag);
                        }
                      });
                    },
                    onComplete: _completeOnboarding,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Row(
        children: List.generate(3, (i) {
          final isActive = i <= _currentPage;
          return Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: EdgeInsets.only(right: i < 2 ? 8 : 0),
              height: 4,
              decoration: BoxDecoration(
                color: isActive ? kPrimary : const Color(0xFFE5E7EB),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// PASO 1 — IDIOMA
// ══════════════════════════════════════════════════════════════

class _LanguageStep extends StatefulWidget {
  final String selectedCode;
  final void Function(String code) onSelected;
  final VoidCallback onNext;

  const _LanguageStep({
    required this.selectedCode,
    required this.onSelected,
    required this.onNext,
  });

  @override
  State<_LanguageStep> createState() => _LanguageStepState();
}

class _LanguageStepState extends State<_LanguageStep> {
  final _searchCtrl = TextEditingController();
  late String _selectedCode;

  final List<Map<String, String>> _languages = [
    {'code': 'en', 'name': 'English', 'flag': '🇬🇧'},
    {'code': 'es', 'name': 'Español', 'flag': '🇪🇸'},
  ];

  List<Map<String, String>> get _filtered {
    final q = _searchCtrl.text.toLowerCase();
    if (q.isEmpty) return _languages;
    return _languages
        .where((l) => l['name']!.toLowerCase().contains(q))
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _selectedCode = widget.selectedCode;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 28),
          const Text(
            'Select your\nlanguage',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1A1A2E),
              height: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Choose the language for your experience',
            style: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF)),
          ),
          const SizedBox(height: 20),

          // Buscador
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'Search language...',
                hintStyle:
                    TextStyle(color: Color(0xFFBBBBBB), fontSize: 14),
                border: InputBorder.none,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                prefixIcon:
                    Icon(Icons.search, color: Color(0xFF9CA3AF), size: 20),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Lista
          Expanded(
            child: ListView.separated(
              physics: const BouncingScrollPhysics(),
              itemCount: _filtered.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (ctx, i) {
                final lang = _filtered[i];
                final isSelected = _selectedCode == lang['code'];
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () {
                    final code = lang['code']!;
                    setState(() => _selectedCode = code);
                    appLocale.value = Locale(code);
                    SharedPreferences.getInstance()
                        .then((p) => p.setString('app_locale', code));
                    widget.onSelected(code);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? kPrimary.withValues(alpha: 0.08)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected
                            ? kPrimary
                            : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(lang['flag']!,
                            style: const TextStyle(fontSize: 24)),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            lang['name']!,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: isSelected
                                  ? kPrimary
                                  : const Color(0xFF1A1A2E),
                            ),
                          ),
                        ),
                        if (isSelected)
                          const Icon(Icons.check_circle,
                              color: kPrimary, size: 20),
                      ],
                    ),
                  ),
                  ),
                  );
              },
            ),
          ),

          const SizedBox(height: 12),
          AppButton(label: 'Continue →', onPressed: widget.onNext),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// PASO 2 — UBICACIÓN
// ══════════════════════════════════════════════════════════════

class _LocationStep extends StatefulWidget {
  final void Function(String city, String countryCode) onSelected;
  final VoidCallback onNext;

  const _LocationStep({
    required this.onSelected,
    required this.onNext,
  });

  @override
  State<_LocationStep> createState() => _LocationStepState();
}

class _LocationStepState extends State<_LocationStep> {
  final _searchCtrl = TextEditingController();
  bool _detecting = false;
  bool _detectError = false;
  String _detectedCity = '';
  String _detectedCountry = '';
  String _detectedCountryCode = '';
  bool _locationSaved = false;

  final List<Map<String, String>> _popular = [
    {'name': 'Madrid',    'sub': 'Spain',          'code': 'ES', 'emoji': '🇪🇸'},
    {'name': 'London',    'sub': 'United Kingdom', 'code': 'GB', 'emoji': '🇬🇧'},
    {'name': 'Paris',     'sub': 'France',         'code': 'FR', 'emoji': '🇫🇷'},
    {'name': 'New York',  'sub': 'United States',  'code': 'US', 'emoji': '🇺🇸'},
    {'name': 'Tokyo',     'sub': 'Japan',          'code': 'JP', 'emoji': '🇯🇵'},
    {'name': 'Barcelona', 'sub': 'Spain',          'code': 'ES', 'emoji': '🇪🇸'},
    {'name': 'Berlin',    'sub': 'Germany',        'code': 'DE', 'emoji': '🇩🇪'},
    {'name': 'Amsterdam', 'sub': 'Netherlands',    'code': 'NL', 'emoji': '🇳🇱'},
    {'name': 'Dubai',     'sub': 'UAE',            'code': 'AE', 'emoji': '🇦🇪'},
    {'name': 'Sydney',    'sub': 'Australia',      'code': 'AU', 'emoji': '🇦🇺'},
    {'name': 'Rome',      'sub': 'Italy',          'code': 'IT', 'emoji': '🇮🇹'},
    {'name': 'Lisbon',    'sub': 'Portugal',       'code': 'PT', 'emoji': '🇵🇹'},
    {'name': 'Singapore', 'sub': 'Singapore',      'code': 'SG', 'emoji': '🇸🇬'},
    {'name': 'Toronto',   'sub': 'Canada',         'code': 'CA', 'emoji': '🇨🇦'},
    {'name': 'Mexico City','sub': 'Mexico',        'code': 'MX', 'emoji': '🇲🇽'},
  ];

  List<Map<String, String>> get _filtered {
    final q = _searchCtrl.text.toLowerCase().trim();
    if (q.isEmpty) return _popular;
    return _popular
        .where((l) =>
            l['name']!.toLowerCase().contains(q) ||
            l['sub']!.toLowerCase().contains(q))
        .toList();
  }

  @override
  void initState() {
    super.initState();
    // Auto-detectar ubicación al cargar el paso
    _detectLocation();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _detectLocation() async {
    setState(() {
      _detecting = true;
      _detectError = false;
      _locationSaved = false;
      _detectedCity = '';
      _detectedCountry = '';
      _detectedCountryCode = '';
    });

    try {
      // HTTPS endpoint (funciona en iOS y Android sin configuración extra)
      final res = await http
          .get(Uri.parse('https://ipapi.co/json/'))
          .timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final city    = data['city']         as String? ?? '';
        final country = data['country_name'] as String? ?? '';
        final code    = data['country_code'] as String? ?? '';

        if (city.isNotEmpty && code.isNotEmpty) {
          if (mounted) {
            setState(() {
              _detectedCity        = city;
              _detectedCountry     = country;
              _detectedCountryCode = code;
              _locationSaved       = true;
            });
            widget.onSelected(city, code);
          }
        } else {
          if (mounted) setState(() => _detectError = true);
        }
      } else {
        if (mounted) setState(() => _detectError = true);
      }
    } catch (_) {
      if (mounted) setState(() => _detectError = true);
    }

    if (mounted) setState(() => _detecting = false);
  }

  void _resetLocation() {
    setState(() {
      _locationSaved       = false;
      _detectError         = false;
      _detectedCity        = '';
      _detectedCountry     = '';
      _detectedCountryCode = '';
    });
  }

  void _selectCity(String name, String country, String code) {
    setState(() {
      _locationSaved       = true;
      _detectedCity        = name;
      _detectedCountry     = country;
      _detectedCountryCode = code;
    });
    widget.onSelected(name, code);
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchCtrl.text.trim();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 28),
          const Text(
            'Where are\nyou based?',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1A1A2E),
              height: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            "We'll show you local destinations and content",
            style: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF)),
          ),
          const SizedBox(height: 20),

          // ── Tile de detección automática ─────────────────
          GestureDetector(
            onTap: (_detecting || _locationSaved) ? null : _detectLocation,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: _locationSaved
                    ? const Color(0xFFECFDF5)
                    : _detectError
                        ? const Color(0xFFFEF2F2)
                        : kPrimary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _locationSaved
                      ? const Color(0xFF16A34A)
                      : _detectError
                          ? const Color(0xFFEF4444)
                          : kPrimary,
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  if (_detecting)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: kPrimary),
                    )
                  else
                    Icon(
                      _locationSaved
                          ? Icons.check_circle
                          : _detectError
                              ? Icons.location_off_outlined
                              : Icons.my_location,
                      color: _locationSaved
                          ? const Color(0xFF16A34A)
                          : _detectError
                              ? const Color(0xFFEF4444)
                              : kPrimary,
                      size: 20,
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _detecting
                        ? const Text(
                            'Detecting your location…',
                            style: TextStyle(
                                color: kPrimary,
                                fontWeight: FontWeight.w600,
                                fontSize: 14),
                          )
                        : _locationSaved
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _detectedCity,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      color: Color(0xFF15803D),
                                    ),
                                  ),
                                  if (_detectedCountry.isNotEmpty)
                                    Text(
                                      _detectedCountry,
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF16A34A)),
                                    ),
                                ],
                              )
                            : Text(
                                _detectError
                                    ? 'Could not detect — tap to retry'
                                    : 'Use my current location',
                                style: TextStyle(
                                  color: _detectError
                                      ? const Color(0xFFEF4444)
                                      : kPrimary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                  ),
                  if (_locationSaved)
                    GestureDetector(
                      onTap: _resetLocation,
                      child: const Text(
                        'Change',
                        style: TextStyle(
                            color: kPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600),
                      ),
                    )
                  else if (_detectError)
                    GestureDetector(
                      onTap: _detectLocation,
                      child: const Text(
                        'Retry',
                        style: TextStyle(
                            color: Color(0xFFEF4444),
                            fontSize: 12,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Buscador ─────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'Search or type any city…',
                hintStyle:
                    TextStyle(color: Color(0xFFBBBBBB), fontSize: 14),
                border: InputBorder.none,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                prefixIcon: Icon(Icons.search,
                    color: Color(0xFF9CA3AF), size: 20),
              ),
            ),
          ),
          const SizedBox(height: 12),

          Text(
            query.isEmpty ? 'Popular cities' : 'Results',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF6B7280),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),

          // ── Lista ────────────────────────────────────────
          Expanded(
            child: ListView(
              physics: const BouncingScrollPhysics(),
              children: [
                // Opción ciudad personalizada (cuando no hay coincidencias)
                if (query.length >= 2 && _filtered.isEmpty)
                  _buildCustomCityTile(query),

                // Lista de ciudades populares o filtradas
                ..._filtered.asMap().entries.map((entry) {
                  final loc = entry.value;
                  final isSelected = _locationSaved &&
                      _detectedCity == loc['name'] &&
                      _detectedCountryCode == loc['code'];
                  return Column(
                    children: [
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => _selectCity(
                              loc['name']!, loc['sub']!, loc['code']!),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Row(
                              children: [
                                Text(loc['emoji']!,
                                    style: const TextStyle(fontSize: 22)),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        loc['name']!,
                                        style: TextStyle(
                                          fontWeight: isSelected
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                          color: isSelected
                                              ? kPrimary
                                              : const Color(0xFF1A1A2E),
                                          fontSize: 14,
                                        ),
                                      ),
                                      Text(
                                        loc['sub']!,
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: Color(0xFF9CA3AF)),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isSelected)
                                  const Icon(Icons.check_circle,
                                      color: kPrimary, size: 18),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const Divider(height: 1, color: Color(0xFFF3F4F6)),
                    ],
                  );
                }),
              ],
            ),
          ),

          const SizedBox(height: 12),
          AppButton(
            label: _locationSaved ? 'Continue →' : 'Skip for now',
            onPressed: widget.onNext,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildCustomCityTile(String query) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _selectCity(query, '', ''),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: kPrimary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.add_location_outlined,
                    size: 18, color: kPrimary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Use "$query"',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: kPrimary,
                        fontSize: 14,
                      ),
                    ),
                    const Text(
                      'Add as your city manually',
                      style:
                          TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios,
                  size: 12, color: Color(0xFFD1D5DB)),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// PASO 3 — INTERESES
// ══════════════════════════════════════════════════════════════

class _InterestsStep extends StatelessWidget {
  final Set<String> selectedInterests;
  final void Function(String tag) onToggle;
  final VoidCallback onComplete;

  const _InterestsStep({
    required this.selectedInterests,
    required this.onToggle,
    required this.onComplete,
  });

  static const _interests = [
    {'tag': 'nature',    'label': 'Nature',    'emoji': '🏕️', 'color': '0xFF4A7C59'},
    {'tag': 'urban',     'label': 'Urban',     'emoji': '🏙️', 'color': '0xFF1A1A2E'},
    {'tag': 'beach',     'label': 'Beach',     'emoji': '🏖️', 'color': '0xFF0077B6'},
    {'tag': 'mountains', 'label': 'Mountains', 'emoji': '⛰️', 'color': '0xFF6B4226'},
    {'tag': 'food',      'label': 'Food',      'emoji': '🍜', 'color': '0xFFB45309'},
    {'tag': 'wildlife',  'label': 'Wildlife',  'emoji': '🦁', 'color': '0xFF1B4332'},
    {'tag': 'culture',   'label': 'Culture',   'emoji': '🏛️', 'color': '0xFF3A0CA3'},
    {'tag': 'resort',    'label': 'Resort',    'emoji': '🏨', 'color': '0xFF9D174D'},
    {'tag': 'adventure', 'label': 'Adventure', 'emoji': '🧗', 'color': '0xFF1D4ED8'},
  ];

  @override
  Widget build(BuildContext context) {
    final canContinue = selectedInterests.length >= 3;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 28),
          const Text(
            'What do you\nlove most?',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1A1A2E),
              height: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Text(
                'Select at least 3 interests',
                style: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF)),
              ),
              const Spacer(),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: canContinue
                      ? kPrimary.withValues(alpha: 0.1)
                      : const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${selectedInterests.length}/3+',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: canContinue
                        ? kPrimary
                        : const Color(0xFF9CA3AF),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Grid
          Expanded(
            child: GridView.builder(
              physics: const BouncingScrollPhysics(),
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 0.9,
              ),
              itemCount: _interests.length,
              itemBuilder: (ctx, i) {
                final item = _interests[i];
                final tag = item['tag']!;
                final isSelected = selectedInterests.contains(tag);
                final color = Color(int.parse(item['color']!));

                return GestureDetector(
                  onTap: () => onToggle(tag),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      color: isSelected ? color : color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected
                            ? color
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(item['emoji']!,
                            style: const TextStyle(fontSize: 32)),
                        const SizedBox(height: 6),
                        Text(
                          item['label']!,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: isSelected
                                ? Colors.white
                                : color,
                          ),
                        ),
                        if (isSelected) ...[
                          const SizedBox(height: 4),
                          const Icon(Icons.check,
                              size: 14, color: Colors.white),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 12),
          AppButton(
            label: canContinue
                ? 'Let\'s go! ✈️'
                : 'Select ${3 - selectedInterests.length} more',
            color: canContinue ? kPrimary : const Color(0xFFD1D5DB),
            onPressed: canContinue ? onComplete : () {},
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
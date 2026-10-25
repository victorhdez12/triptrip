// lib/widgets/settings_sheet.dart
//
// Bottom sheet de ajustes accesible desde el botón ⚙️ del perfil.
// Permite cambiar idioma, ubicación e intereses sin repetir el onboarding.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_locale.dart';
import '../l10n.dart';
import 'common_widgets.dart';

// ══════════════════════════════════════════════════════════════
// ENTRY POINT — llamar desde UserProfileScreen
// ══════════════════════════════════════════════════════════════

Future<void> showSettingsSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _SettingsSheet(),
  );
}

// ══════════════════════════════════════════════════════════════
// SETTINGS SHEET
// ══════════════════════════════════════════════════════════════

class _SettingsSheet extends StatefulWidget {
  const _SettingsSheet();

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  final _supabase = Supabase.instance.client;

  String _langCode = 'en';
  String _langName = 'English';
  String _langFlag = '🇬🇧';
  String _city = '';
  String _countryCode = '';
  Set<String> _interests = {};
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentSettings();
  }

  Future<void> _loadCurrentSettings() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _loading = false);
      return;
    }

    try {
      final profile = await _supabase
          .from('users')
          .select('language_code, city, country_code')
          .eq('firebase_uid', uid)
          .maybeSingle();

      final interestsData = await _supabase
          .from('user_interests')
          .select('interest_tag')
          .eq('firebase_uid', uid);

      if (mounted && profile != null) {
        final code = profile['language_code'] as String? ?? 'en';
        final langInfo = _languages.firstWhere(
          (l) => l['code'] == code,
          orElse: () => _languages[0],
        );

        setState(() {
          _langCode = code;
          _langName = langInfo['name']!;
          _langFlag = langInfo['flag']!;
          _city = profile['city'] as String? ?? '';
          _countryCode = profile['country_code'] as String? ?? '';
          _interests = ((interestsData as List)
                  .map((r) => r['interest_tag'] as String)
                  .toSet());
          _loading = false;
        });
      } else {
        if (mounted) setState(() => _loading = false);
      }
    } catch (e) {
      debugPrint('Error loading settings: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveSettings() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _saving = true);

    try {
      // update (not upsert) — the row always exists after onboarding
      await _supabase.from('users').update({
        'language_code': _langCode,
        'city': _city,
        'country_code': _countryCode,
      }).eq('firebase_uid', uid);

      // Replace interests
      await _supabase
          .from('user_interests')
          .delete()
          .eq('firebase_uid', uid);

      if (_interests.isNotEmpty) {
        await _supabase.from('user_interests').insert(
          _interests
              .map((tag) => {'firebase_uid': uid, 'interest_tag': tag})
              .toList(),
        );
      }

      // Apply locale change immediately across the whole app
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('app_locale', _langCode);
      appLocale.value = Locale(_langCode);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tr('Settings saved ✓', 'Ajustes guardados ✓')),
            backgroundColor: kPrimary,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error saving settings: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving settings: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }

    if (mounted) setState(() => _saving = false);
  }

  Future<void> _signOut() async {
    Navigator.pop(context);
    await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + bottomPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFE5E7EB),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          // Título
          Row(
            children: [
              Text(
                tr('Settings', 'Ajustes'),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1A1A2E),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: CircularProgressIndicator(
                  color: kPrimary, strokeWidth: 2.5),
            )
          else ...[
            // ── Idioma ──────────────────────────────────────
            _SettingsTile(
              icon: Icons.language_rounded,
              title: tr('Language', 'Idioma'),
              value: '$_langFlag  $_langName',
              onTap: () => _showLanguagePicker(context),
            ),
            const SizedBox(height: 10),

            // ── Ubicación ────────────────────────────────────
            _SettingsTile(
              icon: Icons.location_on_outlined,
              title: tr('Home city', 'Ciudad base'),
              value: _city.isNotEmpty ? _city : 'Not set',
              onTap: () => _showLocationPicker(context),
            ),
            const SizedBox(height: 10),

            // ── Intereses ────────────────────────────────────
            _SettingsTile(
              icon: Icons.favorite_outline_rounded,
              title: tr('Interests', 'Intereses'),
              value: _interests.isEmpty
                  ? tr('None selected', 'Ninguno seleccionado')
                  : '${_interests.length} ${tr('selected', 'seleccionados')}',
              onTap: () => _showInterestsPicker(context),
            ),
            const SizedBox(height: 24),

            // Guardar
            AppButton(
              label: _saving ? tr('Saving...', 'Guardando...') : tr('Save changes', 'Guardar cambios'),
              onPressed: _saving ? () {} : _saveSettings,
            ),
            const SizedBox(height: 12),

            // Sign out
            GestureDetector(
              onTap: _signOut,
              child: Container(
                width: double.infinity,
                height: 52,
                decoration: BoxDecoration(
                  color: const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: Text(
                    tr('Sign out', 'Cerrar sesión'),
                    style: const TextStyle(
                      color: Color(0xFFDC2626),
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Pickers ──────────────────────────────────────────────

  Future<void> _showLanguagePicker(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LanguagePickerSheet(
        selectedCode: _langCode,
        onSelected: (code, name, flag) {
          setState(() {
            _langCode = code;
            _langName = name;
            _langFlag = flag;
          });
        },
      ),
    );
  }

  Future<void> _showLocationPicker(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LocationPickerSheet(
        currentCity: _city,
        onSelected: (city, code) {
          setState(() {
            _city = city;
            _countryCode = code;
          });
        },
      ),
    );
  }

  Future<void> _showInterestsPicker(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _InterestsPickerSheet(
        selected: Set.from(_interests),
        onChanged: (updated) {
          setState(() => _interests = updated);
        },
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// SETTINGS TILE
// ══════════════════════════════════════════════════════════════

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: kPrimary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: kPrimary, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF9CA3AF),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                color: Color(0xFF9CA3AF), size: 20),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// LANGUAGE PICKER SHEET
// ══════════════════════════════════════════════════════════════

class _LanguagePickerSheet extends StatefulWidget {
  final String selectedCode;
  final void Function(String code, String name, String flag) onSelected;

  const _LanguagePickerSheet(
      {required this.selectedCode, required this.onSelected});

  @override
  State<_LanguagePickerSheet> createState() =>
      _LanguagePickerSheetState();
}

class _LanguagePickerSheetState extends State<_LanguagePickerSheet> {
  final _searchCtrl = TextEditingController();
  late String _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.selectedCode;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Map<String, String>> get _filtered {
    final q = _searchCtrl.text.toLowerCase();
    if (q.isEmpty) return _languages;
    return _languages
        .where((l) => l['name']!.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: const Color(0xFFE5E7EB),
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          const Text('Language',
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'Search...',
                border: InputBorder.none,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                prefixIcon: Icon(Icons.search,
                    color: Color(0xFF9CA3AF), size: 18),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.separated(
              physics: const BouncingScrollPhysics(),
              itemCount: _filtered.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, color: Color(0xFFF3F4F6)),
              itemBuilder: (ctx, i) {
                final lang = _filtered[i];
                final isSelected = _selected == lang['code'];
                return GestureDetector(
                  onTap: () {
                    setState(() => _selected = lang['code']!);
                    widget.onSelected(
                        lang['code']!, lang['name']!, lang['flag']!);
                    Navigator.pop(context);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      children: [
                        Text(lang['flag']!,
                            style: const TextStyle(fontSize: 22)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(lang['name']!,
                              style: TextStyle(
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: isSelected
                                    ? kPrimary
                                    : const Color(0xFF1A1A2E),
                              )),
                        ),
                        if (isSelected)
                          const Icon(Icons.check_circle,
                              color: kPrimary, size: 18),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// LOCATION PICKER SHEET
// ══════════════════════════════════════════════════════════════

class _LocationPickerSheet extends StatefulWidget {
  final String currentCity;
  final void Function(String city, String countryCode) onSelected;

  const _LocationPickerSheet(
      {required this.currentCity, required this.onSelected});

  @override
  State<_LocationPickerSheet> createState() =>
      _LocationPickerSheetState();
}

class _LocationPickerSheetState extends State<_LocationPickerSheet> {
  final _searchCtrl = TextEditingController();

  static const _popular = [
    {'name': 'Madrid',    'sub': 'Spain',         'code': 'ES', 'emoji': '🇪🇸'},
    {'name': 'London',    'sub': 'UK',             'code': 'GB', 'emoji': '🇬🇧'},
    {'name': 'Paris',     'sub': 'France',         'code': 'FR', 'emoji': '🇫🇷'},
    {'name': 'New York',  'sub': 'United States',  'code': 'US', 'emoji': '🇺🇸'},
    {'name': 'Tokyo',     'sub': 'Japan',          'code': 'JP', 'emoji': '🇯🇵'},
    {'name': 'Barcelona', 'sub': 'Spain',          'code': 'ES', 'emoji': '🇪🇸'},
    {'name': 'Berlin',    'sub': 'Germany',        'code': 'DE', 'emoji': '🇩🇪'},
    {'name': 'Amsterdam', 'sub': 'Netherlands',    'code': 'NL', 'emoji': '🇳🇱'},
    {'name': 'Dubai',     'sub': 'UAE',            'code': 'AE', 'emoji': '🇦🇪'},
    {'name': 'Sydney',    'sub': 'Australia',      'code': 'AU', 'emoji': '🇦🇺'},
  ];

  List<Map<String, String>> get _filtered {
    final q = _searchCtrl.text.toLowerCase();
    if (q.isEmpty) return _popular;
    return _popular
        .where((l) =>
            l['name']!.toLowerCase().contains(q) ||
            l['sub']!.toLowerCase().contains(q))
        .toList();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.65,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: const Color(0xFFE5E7EB),
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          const Text('Home city',
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'Search city...',
                border: InputBorder.none,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                prefixIcon: Icon(Icons.search,
                    color: Color(0xFF9CA3AF), size: 18),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.separated(
              physics: const BouncingScrollPhysics(),
              itemCount: _filtered.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, color: Color(0xFFF3F4F6)),
              itemBuilder: (ctx, i) {
                final loc = _filtered[i];
                final isCurrent =
                    widget.currentCity == loc['name'];
                return GestureDetector(
                  onTap: () {
                    widget.onSelected(loc['name']!, loc['code']!);
                    Navigator.pop(context);
                  },
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
                              Text(loc['name']!,
                                  style: TextStyle(
                                    fontWeight: isCurrent
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: isCurrent
                                        ? kPrimary
                                        : const Color(0xFF1A1A2E),
                                  )),
                              Text(loc['sub']!,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF9CA3AF))),
                            ],
                          ),
                        ),
                        if (isCurrent)
                          const Icon(Icons.check_circle,
                              color: kPrimary, size: 18),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// INTERESTS PICKER SHEET
// ══════════════════════════════════════════════════════════════

class _InterestsPickerSheet extends StatefulWidget {
  final Set<String> selected;
  final void Function(Set<String>) onChanged;

  const _InterestsPickerSheet(
      {required this.selected, required this.onChanged});

  @override
  State<_InterestsPickerSheet> createState() =>
      _InterestsPickerSheetState();
}

class _InterestsPickerSheetState
    extends State<_InterestsPickerSheet> {
  late Set<String> _selected;

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
  void initState() {
    super.initState();
    _selected = Set.from(widget.selected);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: const Color(0xFFE5E7EB),
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          const Text('Interests',
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            '${_selected.length} selected',
            style: const TextStyle(
                fontSize: 13, color: Color(0xFF9CA3AF)),
          ),
          const SizedBox(height: 16),
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
                final isSelected = _selected.contains(tag);
                final color =
                    Color(int.parse(item['color']!));

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      if (isSelected) {
                        _selected.remove(tag);
                      } else {
                        _selected.add(tag);
                      }
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? color
                          : color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected
                            ? color
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment:
                          MainAxisAlignment.center,
                      children: [
                        Text(item['emoji']!,
                            style:
                                const TextStyle(fontSize: 28)),
                        const SizedBox(height: 4),
                        Text(
                          item['label']!,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isSelected
                                ? Colors.white
                                : color,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          AppButton(
            label: 'Done',
            onPressed: () {
              widget.onChanged(_selected);
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// LANGUAGES LIST (compartida)
// ══════════════════════════════════════════════════════════════

const List<Map<String, String>> _languages = [
  {'code': 'en', 'name': 'English', 'flag': '🇬🇧'},
  {'code': 'es', 'name': 'Español', 'flag': '🇪🇸'},
];
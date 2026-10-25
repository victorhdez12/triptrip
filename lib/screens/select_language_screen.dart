import 'package:flutter/material.dart';
import '../widgets/common_widgets.dart';
import 'choose_location_screen.dart';

// Gestor de idioma global sencillo
class AppLanguage {
  static String currentCode = 'es';
  static String currentName = 'Español';
  static String currentFlag = '🇪🇸';
}

class SelectLanguageScreen extends StatefulWidget {
  const SelectLanguageScreen({super.key});

  @override
  State<SelectLanguageScreen> createState() => _SelectLanguageScreenState();
}

class _SelectLanguageScreenState extends State<SelectLanguageScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  String? _selectedCode = AppLanguage.currentCode;

  final List<Map<String, String>> _languages = [
    {'code': 'en', 'name': 'English',   'flag': '🇬🇧'},
    {'code': 'es', 'name': 'Español',   'flag': '🇪🇸'},
    {'code': 'fr', 'name': 'Français',  'flag': '🇫🇷'},
    {'code': 'de', 'name': 'Deutsch',   'flag': '🇩🇪'},
    {'code': 'it', 'name': 'Italiano',  'flag': '🇮🇹'},
    {'code': 'pt', 'name': 'Português', 'flag': '🇵🇹'},
    {'code': 'ru', 'name': 'Русский',   'flag': '🇷🇺'},
    {'code': 'zh', 'name': '中文',       'flag': '🇨🇳'},
    {'code': 'ja', 'name': '日本語',     'flag': '🇯🇵'},
    {'code': 'ko', 'name': '한국어',     'flag': '🇰🇷'},
    {'code': 'ar', 'name': 'العربية',   'flag': '🇸🇦'},
    {'code': 'hi', 'name': 'हिन्दी',    'flag': '🇮🇳'},
  ];

  List<Map<String, String>> get _filtered {
    final q = _searchCtrl.text.toLowerCase();
    if (q.isEmpty) return _languages;
    return _languages.where((l) => l['name']!.toLowerCase().contains(q)).toList();
  }

  Map<String, String> get _selectedLang =>
      _languages.firstWhere((l) => l['code'] == _selectedCode,
          orElse: () => _languages[1]);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const BackBtn(),
              const SizedBox(height: 28),
              const Center(
                child: Text('Select your language',
                    style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87)),
              ),
              const SizedBox(height: 8),
              const Center(
                child: Text(
                  'Elige el idioma de la aplicación',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Color(0xFF999999)),
                ),
              ),
              const SizedBox(height: 20),
              // Buscador
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: const Color(0xFFDDDDDD)),
                ),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: 'Buscar idioma...',
                    hintStyle: TextStyle(color: Color(0xFFBBBBBB)),
                    border: InputBorder.none,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    suffixIcon: Icon(Icons.search, color: Color(0xFF555555)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  itemCount: _filtered.length,
                  itemBuilder: (ctx, i) {
                    final lang = _filtered[i];
                    final isSelected = _selectedCode == lang['code'];
                    return GestureDetector(
                      onTap: () => setState(() => _selectedCode = lang['code']),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        margin: const EdgeInsets.symmetric(vertical: 3),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? kPrimary.withOpacity(0.08)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color:
                                isSelected ? kPrimary : Colors.transparent,
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
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: isSelected
                                      ? kPrimary
                                      : Colors.black87,
                                ),
                              ),
                            ),
                            if (isSelected)
                              const Icon(Icons.check_circle,
                                  color: kPrimary, size: 20),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              // Banner idioma seleccionado
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Center(
                  child: Text(
                    '${_selectedLang['flag']}  ${_selectedLang['name']} seleccionado',
                    style: const TextStyle(
                        color: kPrimary, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              AppButton(
                label: 'Confirmar',
                onPressed: () {
                  // Guardar idioma seleccionado globalmente
                  AppLanguage.currentCode = _selectedLang['code']!;
                  AppLanguage.currentName = _selectedLang['name']!;
                  AppLanguage.currentFlag = _selectedLang['flag']!;

                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const ChooseLocationScreen()),
                  );
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
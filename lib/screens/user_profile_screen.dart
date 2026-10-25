// lib/screens/user_profile_screen.dart

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/achievements_service.dart';
import '../services/country_flags.dart';
import '../services/favorite_folder_service.dart';
import '../services/itinerary_service.dart';
import '../services/media_service.dart';
import '../l10n.dart';
import '../services/place_social_service.dart';
import '../services/profile_service.dart';
import '../services/visited_countries_service.dart';
import '../widgets/common_widgets.dart';
import '../widgets/folder_picker_sheet.dart';
import '../widgets/settings_sheet.dart';
import '../widgets/shareable_badge_card.dart';
import 'itinerary_detail_screen.dart';
import 'folder_detail_screen.dart';
import 'place_detail_screen.dart';

// ══════════════════════════════════════════════════════════════
// USER PROFILE SCREEN
// ══════════════════════════════════════════════════════════════

class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({super.key});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  // ── Estado ──────────────────────────────────────────────
  int _selectedTabIndex = 0;
  final List<String> _tabs = ['STATS', 'ACHIEVEMENTS', 'FAVOURITES'];

  bool _mapLoading = true;
  List<VisitedCountry> _visitedCountries = []; // detalle (nombres) para chips
  Set<String> _visitedCountryCodes = {};

  String _displayName = '';
  String _instagram = '';
  String _tiktok = '';
  String _avatarUrl = '';
  String _bio = '';
  bool _uploadingAvatar = false;
  int _groupsCount = 0;
  int _friendsCount = 0;
  int _points = 0;
  Set<String> _unlockedAchievements = const <String>{};

  // ── Estado FAVOURITES ────────────────────────────────────
  int _favSubTab = 0; // 0 = Itineraries · 1 = Places
  bool _favLoading = true;
  List<ItineraryCard> _favItineraries = const [];
  List<PlaceCard> _favPlaces = const [];
  List<FavoriteFolder> _itinFolders = const [];
  List<FavoriteFolder> _placeFolders = const [];
  Map<String, Set<String>> _itinMembers = const {}; // folderId → itemIds
  Map<String, Set<String>> _placeMembers = const {};
  String? _selItinFolder; // null = All
  String? _selPlaceFolder;

  final _supabase = Supabase.instance.client;

  // ── Cache keys ───────────────────────────────────────────
  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';
  String get _cacheKey => 'profile_cache_$_uid';

  // ── Lifecycle ────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _displayName =
        FirebaseAuth.instance.currentUser?.displayName ?? 'Traveler';
    _loadFromCacheThenNetwork();
    _loadUserStats();
    _initMapData(); // secuencial: países visitados → polígonos GeoJSON
    _loadFavourites(); // itinerarios + lugares guardados
    favouritesChanged.addListener(_onFavouritesChanged);
  }

  @override
  void dispose() {
    favouritesChanged.removeListener(_onFavouritesChanged);
    super.dispose();
  }

  // Recarga favoritos cuando cambian en cualquier pantalla (el perfil vive
  // en el IndexedStack, así que su initState no vuelve a ejecutarse).
  void _onFavouritesChanged() {
    if (mounted) _loadFavourites();
  }

  // ── Lógica privada ───────────────────────────────────────

  void _show(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  Future<void> _loadFromCacheThenNetwork() async {
    await _loadFromCache();
    await _loadUserData();
  }

  Future<void> _loadFromCache() async {
    if (_uid.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null) return;

      final data = jsonDecode(raw) as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _displayName = data['display_name'] as String? ?? _displayName;
          _instagram   = data['instagram']    as String? ?? '';
          _tiktok      = data['tiktok']       as String? ?? '';
          _avatarUrl   = data['avatar_url']   as String? ?? '';
          _bio         = data['bio']          as String? ?? '';
        });
      }
    } catch (e) {
      debugPrint('Cache read error: $e');
    }
  }

  Future<void> _saveToCache(Map<String, dynamic> data) async {
    if (_uid.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(data));
    } catch (e) {
      debugPrint('Cache write error: $e');
    }
  }

  Future<void> _loadUserData() async {
    if (_uid.isEmpty) return;

    // 1 sola RPC → 4x menos round-trips que antes
    final stats = await ProfileService.loadStats(_uid);

    if (!mounted) return;

    final name = stats.displayName.isNotEmpty ? stats.displayName : _displayName;
    setState(() {
      _displayName            = name;
      _instagram              = stats.instagram;
      _tiktok                 = stats.tiktok;
      _avatarUrl              = stats.avatarUrl;
      _bio                    = stats.bio;
      _points                 = stats.points;
      _groupsCount            = stats.groupsCount;
      _friendsCount           = stats.friendsCount;
      _unlockedAchievements   = stats.unlockedAchievements;
    });

    await _saveToCache({
      'display_name': name,
      'instagram':    stats.instagram,
      'tiktok':       stats.tiktok,
      'avatar_url':   stats.avatarUrl,
      'bio':          stats.bio,
    });

    // Sincroniza achievements (desbloquea los que correspondan).
    // Países: consulta directa en vez de _visitedCountryCodes, que se
    // rellena en paralelo vía _initMapData() y puede no estar listo aún.
    final countryCodes =
        await VisitedCountriesService().getVisitedCountryCodes(_uid);
    final newly = await AchievementsService.syncUnlocked(
      uid: _uid,
      countries: countryCodes.length,
      groups: _groupsCount,
      friends: _friendsCount,
    );
    if (newly.isNotEmpty && mounted) {
      setState(() {
        _unlockedAchievements = {
          ..._unlockedAchievements,
          ...newly.map((a) => a.key),
        };
      });
      _show('🎉 New badge unlocked: ${newly.first.title}', kPrimary);
    }
  }

  Future<void> _saveField(String field, String value) async {
    if (_uid.isEmpty) return;

    try {
      await _supabase.from('users').upsert({
        'firebase_uid': _uid,
        field: value,
      }, onConflict: 'firebase_uid');

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      final data = raw != null
          ? Map<String, dynamic>.from(jsonDecode(raw) as Map)
          : <String, dynamic>{};
      data[field] = value;
      await prefs.setString(_cacheKey, jsonEncode(data));
    } catch (e) {
      _show('Error saving $field', Colors.redAccent);
    }
  }

  // ── Stats: cargados ya por _loadUserData (RPC). Mantenemos método
  //   vacío para compatibilidad si se le llama explícitamente desde fuera.
  Future<void> _loadUserStats() async {
    // No-op: las stats vienen ya en _loadUserData() a través de ProfileService.
  }

  // ── Mapa secuencial ──────────────────────────────────────
  Future<void> _initMapData() async {
    await _loadVisitedCountries();
    if (mounted) setState(() => _mapLoading = false);
  }

  Future<void> _reloadMap() async {
    if (!mounted) return;
    setState(() => _mapLoading = true);
    await _loadVisitedCountries();
    if (mounted) setState(() => _mapLoading = false);
  }

  Future<void> _loadVisitedCountries() async {
    if (_uid.isEmpty) return;
    final service = VisitedCountriesService();
    final codes = await service.getVisitedCountryCodes(_uid);
    final detail = await service.getVisitedCountries(_uid);
    if (mounted) {
      setState(() {
        _visitedCountryCodes = codes;
        _visitedCountries = detail;
      });
    }
  }


  // ── Botones del mapa ─────────────────────────────────────
  Future<void> _showAddCountrySheet() async {
    final service = VisitedCountriesService();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) {
        List<CountryRef> results = [];
        bool searching = false;
        final searchCtrl = TextEditingController();

        return StatefulBuilder(
          builder: (ctx, setSheet) {
            return Padding(
              padding: EdgeInsets.only(
                top: 16,
                left: 20,
                right: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE5E7EB),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Add visited country',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: searchCtrl,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'Search country...',
                      prefixIcon: const Icon(
                        Icons.search,
                        color: Color(0xFF9CA3AF),
                      ),
                      filled: true,
                      fillColor: const Color(0xFFF3F4F6),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (q) async {
                      if (q.trim().length < 2) {
                        setSheet(() {
                          results = [];
                          searching = false;
                        });
                        return;
                      }
                      setSheet(() => searching = true);
                      try {
                        final found =
                            await service.searchCountries(q.trim());
                        setSheet(() {
                          results  = found;
                          searching = false;
                        });
                      } catch (_) {
                        setSheet(() => searching = false);
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  if (searching)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: CircularProgressIndicator(
                          color: kPrimary, strokeWidth: 2.5),
                    )
                  else if (results.isNotEmpty)
                    SizedBox(
                      height: 260,
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: results.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final c = results[i];
                          final isVisited =
                              _visitedCountryCodes.contains(c.code);
                          return ListTile(
                            title: Text(c.nameEn,
                                style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600)),
                            subtitle: Text(c.continent,
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF9CA3AF))),
                            trailing: isVisited
                                ? const Icon(Icons.check_circle,
                                    color: kPrimary, size: 20)
                                : Icon(Icons.add_circle_outline,
                                    color: Colors.grey.shade400,
                                    size: 20),
                            onTap: isVisited
                                ? null
                                : () async {
                                    try {
                                      await service.addCountry(
                                        firebaseUid: _uid,
                                        countryCode: c.code,
                                      );
                                      if (mounted) {
                                        setState(() => _visitedCountryCodes
                                            .add(c.code));
                                        _reloadMap();
                                        _show('${c.nameEn} added to your map!',
                                            kPrimary);
                                      }
                                      setSheet(() {});
                                    } catch (e) {
                                      _show('Error adding country',
                                          Colors.redAccent);
                                    }
                                  },
                          );
                        },
                      ),
                    )
                  else if (searchCtrl.text.length >= 2)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text('No countries found',
                          style:
                              TextStyle(color: Color(0xFF9CA3AF))),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _shareMap() {
    Clipboard.setData(ClipboardData(
      text:
          "I've visited ${_visitedCountryCodes.length} ${_visitedCountryCodes.length == 1 ? 'country' : 'countries'} on TripTrip! ✈️🌍",
    ));
    _show('Stats copied to clipboard!', kPrimary);
  }

  String _formatNum(int n) =>
      n >= 1000
          ? '${(n / 1000).toStringAsFixed(1).replaceAll('.0', '')}K'
          : n.toString();

  // ── Edit dialogs ─────────────────────────────────────────
  Future<void> _editDisplayName() async {
    final controller = TextEditingController(text: _displayName);
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit name'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Your name'),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      try {
        await FirebaseAuth.instance.currentUser?.updateDisplayName(result);
        await _saveField('display_name', result);
        if (mounted) setState(() => _displayName = result);
      } on FirebaseAuthException catch (e) {
        _show(e.message ?? 'Error updating name', Colors.redAccent);
      }
    }
  }

  Future<void> _editHandle(String platform, String current) async {
    final controller = TextEditingController(text: current);
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Edit $platform'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: '@username'),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null) {
      final field = platform.toLowerCase();
      setState(() {
        if (field == 'instagram') _instagram = result;
        if (field == 'tiktok')    _tiktok    = result;
      });
      await _saveField(field, result);
    }
  }

  // ── Build ────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          children: [
            const SizedBox(height: 16),
            _buildHeader(),
            const SizedBox(height: 16),
            _buildAvatar(),
            const SizedBox(height: 14),
            _buildNameRow(),
            const SizedBox(height: 8),
            _buildSocialHandles(),
            const SizedBox(height: 10),
            _buildBio(),
            const SizedBox(height: 20),
            _buildTabBar(),
            const SizedBox(height: 20),
            _buildTabContent(),
          ],
        ),
      ),
    );
  }

  // ── Header con botón ⚙️ ──────────────────────────────────
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          GestureDetector(
            onTap: () => showSettingsSheet(context),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(Icons.settings,
                  color: Color(0xFF6B7280), size: 22),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar() {
    final url = _avatarUrl.isNotEmpty
        ? _avatarUrl
        : (FirebaseAuth.instance.currentUser?.photoURL ?? '');
    return GestureDetector(
      onTap: _uploadingAvatar ? null : _pickAndUploadAvatar,
      child: Stack(
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFE0E0E0), width: 3),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipOval(
              child: url.isNotEmpty
                  ? Image.network(
                      url,
                      width: 100,
                      height: 100,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _avatarFallback(),
                    )
                  : _avatarFallback(),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: kPrimary,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: _uploadingAvatar
                  ? const Padding(
                      padding: EdgeInsets.all(7),
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.camera_alt,
                      size: 15, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  // Selecciona una foto, la comprime (solo móvil) y la sube a Storage.
  Future<void> _pickAndUploadAvatar() async {
    final x = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (x == null) return;
    setState(() => _uploadingAvatar = true);
    try {
      var bytes = await x.readAsBytes();
      if (!kIsWeb) {
        bytes = await FlutterImageCompress.compressWithList(
            bytes, minWidth: 600, minHeight: 600, quality: 80);
      }
      final url =
          await MediaService.uploadImage(bytes, pathPrefix: 'avatars');
      if (url == null) {
        _show('Error al subir la foto', Colors.redAccent);
        return;
      }
      await _saveField('avatar_url', url);
      if (mounted) setState(() => _avatarUrl = url);
    } catch (e) {
      _show('Error al subir la foto', Colors.redAccent);
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  // Biografía estilo Instagram (toca para editar).
  Widget _buildBio() {
    return GestureDetector(
      onTap: _editBio,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Text(
          _bio.isEmpty ? tr('Add a bio', 'Añade una biografía') : _bio,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            height: 1.35,
            color: _bio.isEmpty
                ? const Color(0xFFB0B6BE)
                : const Color(0xFF4B5563),
            fontStyle: _bio.isEmpty ? FontStyle.italic : FontStyle.normal,
          ),
        ),
      ),
    );
  }

  Future<void> _editBio() async {
    final ctrl = TextEditingController(text: _bio);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Bio', 'Biografía')),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          maxLength: 150,
          decoration: InputDecoration(
            hintText: tr('e.g. Backpacker · 32 countries · coffee',
                'Ej. Mochilera · 32 países · café ☕'),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(tr('Cancel', 'Cancelar'))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: Text(tr('Save', 'Guardar'))),
        ],
      ),
    );
    if (result == null) return;
    setState(() => _bio = result);
    await _saveField('bio', result);
  }

  Widget _avatarFallback() => Container(
        color: kPrimary.withOpacity(0.2),
        child: const Icon(Icons.person, size: 50, color: kPrimary),
      );

  Widget _buildNameRow() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _displayName,
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1A1A2E),
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _editDisplayName,
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: kPrimary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.edit, size: 15, color: kPrimary),
          ),
        ),
      ],
    );
  }

  Widget _buildSocialHandles() {
    return Column(
      children: [
        GestureDetector(
          onTap: () => _editHandle('Instagram', _instagram),
          child: Text(
            'Instagram: ${_instagram.isEmpty ? 'tap to add' : '@$_instagram'}',
            style: const TextStyle(fontSize: 14, color: Color(0xFF9CA3AF)),
          ),
        ),
        const SizedBox(height: 2),
        GestureDetector(
          onTap: () => _editHandle('TikTok', _tiktok),
          child: Text(
            'TikTok: ${_tiktok.isEmpty ? 'tap to add' : '@$_tiktok'}',
            style: const TextStyle(fontSize: 14, color: Color(0xFF9CA3AF)),
          ),
        ),
      ],
    );
  }

  Widget _buildTabBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Row(
        children: List.generate(_tabs.length, (index) {
          final isSelected = _selectedTabIndex == index;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedTabIndex = index),
              child: Container(
                padding: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: isSelected ? kPrimary : Colors.transparent,
                      width: 2.5,
                    ),
                  ),
                ),
                child: Text(
                  _tabs[index],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight:
                        isSelected ? FontWeight.w700 : FontWeight.w500,
                    color:
                        isSelected ? kPrimary : const Color(0xFF9CA3AF),
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ── Contenido condicional por tab ────────────────────────
  Widget _buildTabContent() {
    switch (_selectedTabIndex) {
      case 1:
        return Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: _buildAchievementsTab(),
        );
      case 2:
        return _buildFavouritesTab();
      default:
        return Column(
          children: [
            _buildStatsGrid(),
            const SizedBox(height: 28),
            _buildMapSection(),
            const SizedBox(height: 24),
          ],
        );
    }
  }

  // ── STATS tab ────────────────────────────────────────────
  Widget _buildStatsGrid() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                  child: _StatCard(
                      icon: _groupsIcon(),
                      value: '$_groupsCount',
                      label: 'Groups')),
              const SizedBox(width: 14),
              Expanded(
                  child: _StatCard(
                      icon: _pointsIcon(),
                      value: _formatNum(_points),
                      label: 'Points')),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                  child: _StatCard(
                      icon: _friendsIcon(),
                      value: '$_friendsCount',
                      label: 'Trip Friends')),
              const SizedBox(width: 14),
              Expanded(
                  child: _StatCard(
                      icon: _countriesIcon(),
                      value: '${_visitedCountryCodes.length}',
                      label: 'Countries\nVisited')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _groupsIcon() => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.group, color: Colors.blue.shade400, size: 18),
          Icon(Icons.group, color: Colors.green.shade400, size: 18),
          Icon(Icons.group, color: Colors.orange.shade400, size: 18),
        ],
      );

  Widget _pointsIcon() => Container(
        width: 32,
        height: 32,
        decoration: const BoxDecoration(
          color: Color(0xFFFFF3E0),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.emoji_events,
            color: Color(0xFFFFB300), size: 20),
      );

  Widget _friendsIcon() => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.person, color: Colors.red.shade400, size: 20),
          Icon(Icons.person, color: Colors.amber.shade600, size: 20),
          Icon(Icons.person, color: Colors.pink.shade300, size: 20),
        ],
      );

  Widget _countriesIcon() => Stack(
        alignment: Alignment.center,
        children: [
          Icon(Icons.public, color: Colors.green.shade400, size: 30),
          Positioned(
            top: 4,
            right: 2,
            child:
                Icon(Icons.location_on, color: Colors.red.shade400, size: 12),
          ),
          Positioned(
            bottom: 6,
            left: 4,
            child: Icon(Icons.location_on,
                color: Colors.blue.shade400, size: 10),
          ),
        ],
      );

  // ── ACHIEVEMENTS tab ─────────────────────────────────────
  Widget _buildAchievementsTab() {
    final catalog = Achievement.catalog;
    final countries = _visitedCountryCodes.length;

    // Estado "unlocked": (1) persistido en BD o (2) cumple condición ahora.
    bool isUnlocked(Achievement a) {
      if (_unlockedAchievements.contains(a.key)) return true;
      return AchievementsService.isUnlocked(
        a,
        countries: countries,
        groups: _groupsCount,
        friends: _friendsCount,
      );
    }

    final unlockedCount = catalog.where(isUnlocked).length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Achievements',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A2E),
                  )),
              Text('$unlockedCount / ${catalog.length}',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: kPrimary)),
            ],
          ),
          const SizedBox(height: 14),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.4,
            ),
            itemCount: catalog.length,
            itemBuilder: (_, i) {
              final a = catalog[i];
              final unlocked = isUnlocked(a);
              return BadgeGridCell(
                achievement: a,
                unlocked: unlocked,
                onTap: () {
                  if (!unlocked) {
                    _show('Keep exploring to unlock!', kPrimary);
                    return;
                  }
                  BadgeShareSheet.show(
                    context,
                    achievement: a,
                    displayName: _displayName,
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  // ── FAVOURITES tab ───────────────────────────────────────

  Future<void> _loadFavourites() async {
    final itins = await ItineraryService.listFavorites();
    final places = await PlaceSocialService.listFavorites();
    final itinFolders = await FavoriteFolderService.listFolders('itinerary');
    final placeFolders = await FavoriteFolderService.listFolders('place');
    final itinMembers = await FavoriteFolderService.membershipsByFolder('itinerary');
    final placeMembers = await FavoriteFolderService.membershipsByFolder('place');
    if (!mounted) return;
    setState(() {
      _favItineraries = itins;
      _favPlaces = places;
      _itinFolders = itinFolders;
      _placeFolders = placeFolders;
      _itinMembers = itinMembers;
      _placeMembers = placeMembers;
      // Si la carpeta seleccionada ya no existe, volver a "All".
      if (_selItinFolder != null &&
          !itinFolders.any((f) => f.id == _selItinFolder)) {
        _selItinFolder = null;
      }
      if (_selPlaceFolder != null &&
          !placeFolders.any((f) => f.id == _selPlaceFolder)) {
        _selPlaceFolder = null;
      }
      _favLoading = false;
    });
  }

  Future<void> _openPlace(PlaceCard p) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PlaceDetailScreen(placeId: p.id)),
    );
    _loadFavourites(); // refresca por si quitó el favorito
  }

  Future<void> _unfavPlace(PlaceCard p) async {
    // El ❤ abre el selector para editar carpetas o quitar el favorito.
    final fav = await showFolderPicker(context, kind: 'place', itemId: p.id);
    if (fav == null) return;
    _loadFavourites();
  }

  Widget _buildFavouritesTab() {
    if (_favLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CircularProgressIndicator(color: kPrimary)),
      );
    }

    final showingItineraries = _favSubTab == 0;

    // Filtrado por carpeta seleccionada (null = All).
    final selFolder = showingItineraries ? _selItinFolder : _selPlaceFolder;
    final members = showingItineraries ? _itinMembers : _placeMembers;
    final allowed = selFolder == null ? null : (members[selFolder] ?? <String>{});

    final itins = allowed == null
        ? _favItineraries
        : _favItineraries.where((c) => allowed.contains(c.id)).toList();
    final places = allowed == null
        ? _favPlaces
        : _favPlaces.where((p) => allowed.contains(p.id)).toList();

    final isEmpty = showingItineraries ? itins.isEmpty : places.isEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Column(
        children: [
          _buildFavSubTabs(),
          const SizedBox(height: 16),
          _buildFolderChips(showingItineraries),
          if (selFolder != null) _buildFolderActions(showingItineraries, selFolder),
          if (isEmpty)
            _buildFavEmpty(showingItineraries)
          else if (showingItineraries)
            ...itins.map(_buildFavItineraryCard)
          else
            ...places.map(_buildFavPlaceCard),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildFolderChips(bool itineraries) {
    final folders = itineraries ? _itinFolders : _placeFolders;
    final selected = itineraries ? _selItinFolder : _selPlaceFolder;

    Widget chip(String label, String? id) {
      final isSel = selected == id;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: GestureDetector(
          onTap: () => setState(() {
            if (itineraries) {
              _selItinFolder = id;
            } else {
              _selPlaceFolder = id;
            }
          }),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isSel ? kPrimary : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: isSel ? kPrimary : const Color(0xFFE5E7EB)),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isSel ? Colors.white : const Color(0xFF6B7280),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: SizedBox(
        height: 36,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            chip('All', null),
            for (final f in folders) chip('${f.name} (${f.itemCount})', f.id),
            // ＋ Nueva carpeta
            GestureDetector(
              onTap: () => _createFolderDialog(itineraries),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: kPrimary),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add, size: 16, color: kPrimary),
                    SizedBox(width: 4),
                    Text('New folder',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: kPrimary,
                        )),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Fila de acción al seleccionar una carpeta: abrirla (votos, compartir).
  Widget _buildFolderActions(bool itineraries, String folderId) {
    final folders = itineraries ? _itinFolders : _placeFolders;
    final folder = folders.where((f) => f.id == folderId).toList();
    if (folder.isEmpty) return const SizedBox.shrink();
    final f = folder.first;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: GestureDetector(
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => FolderDetailScreen(folder: f)),
          );
          _loadFavourites();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: kPrimary.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(f.isShared ? Icons.group : Icons.folder_open,
                  size: 18, color: kPrimary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  f.isShared
                      ? 'Shared folder — open to vote with your group'
                      : 'Open folder — vote items or share with a group',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: kPrimary,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right, size: 18, color: kPrimary),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _createFolderDialog(bool itineraries) async {    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(itineraries ? 'New itinerary folder' : 'New place folder'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Folder name'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Create')),
        ],
      ),
    );
    if (ok != true) return;
    final name = ctrl.text.trim();
    if (name.isEmpty) return;
    final id = await FavoriteFolderService.createFolder(
        name, itineraries ? 'itinerary' : 'place');
    if (!mounted) return;
    if (id == null) {
      _show('Could not create folder', Colors.redAccent);
      return;
    }
    // Selecciona la carpeta recién creada y refresca.
    setState(() {
      if (itineraries) {
        _selItinFolder = id;
      } else {
        _selPlaceFolder = id;
      }
    });
    _loadFavourites();
  }

  Widget _buildFavSubTabs() {
    Widget seg(String label, int index) {
      final selected = _favSubTab == index;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _favSubTab = index),
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
                color: selected ? Colors.white : const Color(0xFF9CA3AF),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F0F0),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          seg('Itineraries', 0),
          seg('Places', 1),
        ],
      ),
    );
  }

  Widget _buildFavEmpty(bool itineraries) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Text(itineraries ? '🗺️' : '📍',
              style: const TextStyle(fontSize: 52)),
          const SizedBox(height: 16),
          Text(
            itineraries ? 'No saved itineraries yet' : 'No saved places yet',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A1A2E),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            itineraries
                ? 'Tap the heart on any public\nitinerary to save it here.'
                : 'Save places and restaurants\nyou love to find them here.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF9CA3AF),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFavItineraryCard(ItineraryCard c) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: GestureDetector(
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ItineraryDetailScreen(itineraryId: c.id),
            ),
          );
          _loadFavourites(); // refresca por si quitó el favorito
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Text(c.countryFlag, style: const TextStyle(fontSize: 30)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${c.destination} · ${c.totalDays} ${c.totalDays == 1 ? 'day' : 'days'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF9CA3AF),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Icon(Icons.star_rounded,
                            size: 15, color: kOrange),
                        const SizedBox(width: 3),
                        Text(
                          '${c.avgRating.toStringAsFixed(1)} (${c.ratingsCount})',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                        if (c.groupSize > 0) ...[
                          const SizedBox(width: 10),
                          const Text('👥', style: TextStyle(fontSize: 12)),
                          const SizedBox(width: 3),
                          Text('${c.groupSize}',
                              style: const TextStyle(
                                  fontSize: 12, color: Color(0xFF6B7280))),
                        ],
                        if (c.budgetPerPerson > 0) ...[
                          const SizedBox(width: 10),
                          const Text('💰', style: TextStyle(fontSize: 12)),
                          const SizedBox(width: 3),
                          Text(
                              '${c.currency}${c.budgetPerPerson.toStringAsFixed(0)}/p',
                              style: const TextStyle(
                                  fontSize: 12, color: Color(0xFF6B7280))),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.favorite, color: kOrange, size: 22),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFavPlaceCard(PlaceCard p) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: GestureDetector(
        onTap: () => _openPlace(p),
        child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Text(p.countryFlag, style: const TextStyle(fontSize: 30)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.placeName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    p.category.isEmpty ? p.location : '${p.category} · ${p.location}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF9CA3AF),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.star_rounded, size: 15, color: kOrange),
                      const SizedBox(width: 3),
                      Text(
                        '${p.avgRating.toStringAsFixed(1)} (${p.ratingsCount})',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: () => _unfavPlace(p),
              child: const Icon(Icons.favorite, color: kOrange, size: 22),
            ),
          ],
        ),
      ),
      ),
    );
  }

  // ── Map section ──────────────────────────────────────────
  Widget _buildMapSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Your Map · ${_visitedCountryCodes.length} ${_visitedCountryCodes.length == 1 ? 'country' : 'countries'}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A1A2E),
                ),
              ),
              Row(
                children: [
                  _mapActionButton(
                      Icons.add_circle_outline, _showAddCountrySheet),
                  const SizedBox(width: 8),
                  _mapActionButton(Icons.ios_share, _shareMap),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Rectángulo con 5 cuadrados (continentes) y las banderas
          // de los países visitados en cada uno. Sin GeoJSON ni mapa.
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: const Color(0xFFEEF0F4),
              child: _mapLoading
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: CircularProgressIndicator(
                            color: kPrimary, strokeWidth: 2.5),
                      ),
                    )
                  : GridView.count(
                      crossAxisCount: 3,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 1,
                      children: _continentBuckets()
                          .map(_buildContinentSquare)
                          .toList(),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // Agrupa los países visitados en 5 continentes (N+S América juntas).
  List<({String name, List<String> flags})> _continentBuckets() {
    const order = ['Europe', 'Asia', 'Africa', 'America', 'Oceania'];
    final buckets = {for (final c in order) c: <String>[]};
    for (final v in _visitedCountries) {
      var cont = v.continent ?? '';
      if (cont == 'North America' || cont == 'South America' || cont == 'Americas') {
        cont = 'America';
      }
      if (!buckets.containsKey(cont)) continue; // p. ej. Antarctica
      buckets[cont]!.add(flagFromIso3(v.countryCode));
    }
    return order.map((c) => (name: c, flags: buckets[c]!)).toList();
  }

  Widget _buildContinentSquare(({String name, List<String> flags}) b) {
    final hasVisits = b.flags.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: hasVisits ? Colors.white : Colors.white.withOpacity(0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: hasVisits ? const Color(0xFF3B6FAF) : const Color(0xFFD6DAE3),
          width: hasVisits ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            b.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
              color: hasVisits
                  ? const Color(0xFF2D5A8E)
                  : const Color(0xFF9CA3AF),
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: hasVisits
                ? SingleChildScrollView(
                    physics: const NeverScrollableScrollPhysics(),
                    child: Wrap(
                      spacing: 2,
                      runSpacing: 0,
                      children: b.flags
                          .map((f) =>
                              Text(f, style: const TextStyle(fontSize: 15)))
                          .toList(),
                    ),
                  )
                : const Center(
                    child: Text('—',
                        style: TextStyle(
                            fontSize: 14, color: Color(0xFFD6DAE3))),
                  ),
          ),
          if (hasVisits)
            Text(
              '${b.flags.length}',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Color(0xFF9CA3AF),
              ),
            ),
        ],
      ),
    );
  }

  Widget _mapActionButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Icon(icon, size: 18, color: const Color(0xFF6B7280)),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// STAT CARD WIDGET
// ══════════════════════════════════════════════════════════════

class _StatCard extends StatelessWidget {
  final Widget icon;
  final String value;
  final String label;

  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          icon,
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF9CA3AF),
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
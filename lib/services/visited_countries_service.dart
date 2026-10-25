import 'package:supabase_flutter/supabase_flutter.dart';

// ══════════════════════════════════════════════════════════════
// SERVICIO: Países visitados del usuario
// ══════════════════════════════════════════════════════════════
//
// Archivo: lib/services/visited_countries_service.dart
//
// Gestiona la tabla user_visited_countries en Supabase
// vinculada al firebase_uid del usuario.
//
// Dependencia:
//   supabase_flutter: ^2.0.0
//
// Inicialización (en main.dart):
//   await Supabase.initialize(
//     url: 'TU_SUPABASE_URL',
//     anonKey: 'TU_SUPABASE_ANON_KEY',
//   );

class VisitedCountriesService {
  final SupabaseClient _client = Supabase.instance.client;
  final String _table = 'user_visited_countries';
  final String _detailView = 'user_visited_countries_detail';

  // ── MODELO ──────────────────────────────────────────────

  /// Obtener todos los países visitados por un usuario.
  /// Devuelve lista de mapas con: country_code, name_es, name_en,
  /// continent, visit_count, first_visited.
  Future<List<VisitedCountry>> getVisitedCountries(String firebaseUid) async {
    final response = await _client
        .from(_detailView)
        .select()
        .eq('firebase_uid', firebaseUid)
        .order('first_visited', ascending: false);

    return (response as List)
        .map((row) => VisitedCountry.fromMap(row))
        .toList();
  }

  /// Obtener solo los códigos de país (para pintar el mapa).
  Future<Set<String>> getVisitedCountryCodes(String firebaseUid) async {
    final response = await _client
        .from(_table)
        .select('country_code')
        .eq('firebase_uid', firebaseUid);

    return (response as List)
        .map((row) => row['country_code'] as String)
        .toSet();
  }

  /// Añadir un país visitado.
  /// Si ya existe, incrementa visit_count.
  Future<void> addCountry({
    required String firebaseUid,
    required String countryCode,
    DateTime? firstVisited,
  }) async {
    // Normalizado ANTES de comparar: si no, un code en minúsculas/mixto no
    // haría match con la fila ya guardada en mayúsculas y duplicaría el país
    // en vez de incrementar su visit_count.
    final code = countryCode.toUpperCase();

    // Intentar insertar
    final existing = await _client
        .from(_table)
        .select('id, visit_count')
        .eq('firebase_uid', firebaseUid)
        .eq('country_code', code)
        .maybeSingle();

    if (existing != null) {
      // Ya existe → incrementar visit_count
      await _client.from(_table).update({
        'visit_count': (existing['visit_count'] as int) + 1,
      }).eq('id', existing['id']);
    } else {
      // Nuevo → insertar
      await _client.from(_table).insert({
        'firebase_uid': firebaseUid,
        'country_code': code,
        'visit_count': 1,
        'first_visited': firstVisited?.toIso8601String() ??
            DateTime.now().toIso8601String(),
      });
    }
  }

  /// Eliminar un país de la lista de visitados.
  Future<void> removeCountry({
    required String firebaseUid,
    required String countryCode,
  }) async {
    await _client
        .from(_table)
        .delete()
        .eq('firebase_uid', firebaseUid)
        .eq('country_code', countryCode);
  }

  /// Actualizar la fecha de primera visita.
  Future<void> updateFirstVisited({
    required String firebaseUid,
    required String countryCode,
    required DateTime firstVisited,
  }) async {
    await _client
        .from(_table)
        .update({'first_visited': firstVisited.toIso8601String()})
        .eq('firebase_uid', firebaseUid)
        .eq('country_code', countryCode);
  }

  /// Incrementar manualmente el visit_count.
  Future<void> incrementVisitCount({
    required String firebaseUid,
    required String countryCode,
  }) async {
    final existing = await _client
        .from(_table)
        .select('id, visit_count')
        .eq('firebase_uid', firebaseUid)
        .eq('country_code', countryCode)
        .single();

    await _client.from(_table).update({
      'visit_count': (existing['visit_count'] as int) + 1,
    }).eq('id', existing['id']);
  }

  /// Obtener el conteo total de países visitados.
  Future<int> getVisitedCount(String firebaseUid) async {
    final response = await _client
        .from(_table)
        .select('id')
        .eq('firebase_uid', firebaseUid);

    return (response as List).length;
  }

  /// Obtener todos los países disponibles (para el selector).
  Future<List<CountryRef>> getAllCountries() async {
    final response = await _client
        .from('countries')
        .select()
        .order('name_es', ascending: true);

    return (response as List)
        .map((row) => CountryRef.fromMap(row))
        .toList();
  }

  /// Buscar países por nombre (para el buscador).
  Future<List<CountryRef>> searchCountries(String query) async {
    final response = await _client
        .from('countries')
        .select()
        .or('name_es.ilike.%$query%,name_en.ilike.%$query%,code.ilike.%$query%')
        .order('name_es', ascending: true)
        .limit(20);

    return (response as List)
        .map((row) => CountryRef.fromMap(row))
        .toList();
  }
}

// ══════════════════════════════════════════════════════════════
// MODELOS DE DATOS
// ══════════════════════════════════════════════════════════════

class VisitedCountry {
  final int id;
  final String firebaseUid;
  final String countryCode;
  final String? nameEn;
  final String? nameEs;
  final String? continent;
  final int visitCount;
  final DateTime? firstVisited;
  final DateTime createdAt;

  VisitedCountry({
    required this.id,
    required this.firebaseUid,
    required this.countryCode,
    this.nameEn,
    this.nameEs,
    this.continent,
    required this.visitCount,
    this.firstVisited,
    required this.createdAt,
  });

  factory VisitedCountry.fromMap(Map<String, dynamic> map) {
    return VisitedCountry(
      id: map['id'] as int,
      firebaseUid: map['firebase_uid'] as String,
      countryCode: map['country_code'] as String,
      nameEn: map['name_en'] as String?,
      nameEs: map['name_es'] as String?,
      continent: map['continent'] as String?,
      visitCount: map['visit_count'] as int? ?? 1,
      firstVisited: map['first_visited'] != null
          ? DateTime.parse(map['first_visited'] as String)
          : null,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  /// Nombre localizado (español por defecto).
  String get displayName => nameEs ?? nameEn ?? countryCode;
}

class CountryRef {
  final String code;
  final String nameEn;
  final String nameEs;
  final String continent;

  CountryRef({
    required this.code,
    required this.nameEn,
    required this.nameEs,
    required this.continent,
  });

  factory CountryRef.fromMap(Map<String, dynamic> map) {
    return CountryRef(
      code: map['code'] as String,
      nameEn: map['name_en'] as String,
      nameEs: map['name_es'] as String,
      continent: map['continent'] as String,
    );
  }
}
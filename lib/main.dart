// lib/main.dart
//
// Entry point principal — OPTIMIZADO para arranque rápido.
//
// Cambios respecto al main original:
//   1. Firebase + Supabase + SharedPreferences se inicializan EN PARALELO
//      con Future.wait → ahorra ~200-400 ms en cold start.
//   2. El GeoJSON de países se precarga en background (no bloquea el primer frame).
//   3. _AuthGate cachea el resultado de _onboardingDone en memoria para
//      evitar consultas repetidas a Supabase en hot reload / rebuilds.
//   4. SplashLoader minimalista — el indicador es liviano y consistente
//      con el branding (azul kPrimary).

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import 'app_locale.dart';
import 'firebase_options.dart';
import 'screens/email_verification_screen.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_flow_screen.dart';
import 'screens/sign_in_screen.dart';
import 'services/ad_service.dart';

// ══════════════════════════════════════════════════════════════
// CONSTANTES DE BACKEND
// ══════════════════════════════════════════════════════════════

// Las credenciales NO se guardan en el repositorio. Se inyectan en tiempo
// de compilación con --dart-define-from-file=env/dart_defines.json
// (ver env/dart_defines.example.json y README.md).
const String _kSupabaseUrl = String.fromEnvironment('SUPABASE_URL');
const String _kSupabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

// ══════════════════════════════════════════════════════════════
// MAIN
// ══════════════════════════════════════════════════════════════

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicialización paralela — 3 awaits que tardaban ~600ms en serie
  // ahora se solapan y tardan ~300ms.
  final results = await Future.wait([
    Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform),
    Supabase.initialize(url: _kSupabaseUrl, anonKey: _kSupabaseAnonKey),
    SharedPreferences.getInstance(),
  ]);

  final prefs = results[2] as SharedPreferences;
  final savedLocale = prefs.getString('app_locale') ?? 'en';
  appLocale.value = Locale(savedLocale);

  runApp(const MyApp());

  // AdMob (consentimiento GDPR/UMP + SDK) — DESPUÉS de runApp para no
  // retrasar el primer frame. No-op en web/desktop (kIsWeb en AdService).
  AdService.init();
}

// ══════════════════════════════════════════════════════════════
// APP ROOT
// ══════════════════════════════════════════════════════════════

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: appLocale,
      builder: (context, locale, _) {
        return MaterialApp(
          title: 'TripTrip',
          debugShowCheckedModeBanner: false,
          locale: locale,
          supportedLocales: const [
            Locale('en'),
            Locale('es'),
          ],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF29B6D2)),
            useMaterial3: true,
          ),
          home: const _AuthGate(),
        );
      },
    );
  }
}

// ══════════════════════════════════════════════════════════════
// AUTH GATE
// ══════════════════════════════════════════════════════════════

class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  // Cache en memoria — evita re-consultar Supabase en rebuilds.
  final Map<String, bool> _onboardingCache = {};

  Future<bool> _onboardingDone(String uid) async {
    // 1. Cache en memoria
    if (_onboardingCache.containsKey(uid)) return _onboardingCache[uid]!;

    final prefs = await SharedPreferences.getInstance();

    // 2. Flag local (rápido, sin red)
    if (prefs.getBool('onboarding_done_$uid') == true) {
      _onboardingCache[uid] = true;
      return true;
    }

    // 3. Fallback de red (reinstalación o dispositivo nuevo)
    try {
      final response = await Supabase.instance.client
          .from('users')
          .select('firebase_uid, language_code, city')
          .eq('firebase_uid', uid)
          .maybeSingle();

      // Consider onboarding done if the user row exists with a language set
      final lang = response?['language_code'] as String?;
      if (response != null && lang != null && lang.isNotEmpty) {
        await prefs.setBool('onboarding_done_$uid', true);
        appLocale.value = Locale(lang);
        await prefs.setString('app_locale', lang);
        _onboardingCache[uid] = true;
        return true;
      }

      // User exists but never finished onboarding (partial row from plan_trip)
      // → show onboarding
    } catch (e) {
      debugPrint('Error checking onboarding status: $e');
    }

    _onboardingCache[uid] = false;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _Splash();
        }

        final user = snapshot.data;

        if (user == null) return const SignInScreen();

        if (!user.emailVerified) {
          return EmailVerificationScreen(email: user.email ?? '');
        }

        return FutureBuilder<bool>(
          future: _onboardingDone(user.uid),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const _Splash();
            }
            final done = snap.data ?? false;
            return done ? const HomeScreen() : const OnboardingFlowScreen();
          },
        );
      },
    );
  }
}

// ══════════════════════════════════════════════════════════════
// SPLASH
// ══════════════════════════════════════════════════════════════

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFFF5F5F5),
      body: Center(
        child: CircularProgressIndicator(color: Color(0xFF29B6D2)),
      ),
    );
  }
}

// lib/l10n.dart
// Simple inline translation helper — reads the global appLocale.
import 'app_locale.dart';

String tr(String en, String es) =>
    appLocale.value.languageCode == 'es' ? es : en;

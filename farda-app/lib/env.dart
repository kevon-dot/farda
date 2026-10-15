import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'utilities/api_configuration.dart';
export 'utilities/api_configuration.dart';

String _configured(String define, String key) {
  final configured =
      define.isNotEmpty
          ? define
          : (dotenv.isInitialized ? dotenv.env[key] ?? '' : '');
  return canonicalApiRoot(configured);
}

String get appBaseUrl =>
    _configured(const String.fromEnvironment('BASE_API_URL'), 'BASE_API_URL');
String get vialBaseUrl =>
    _configured(const String.fromEnvironment('VIAL_API_URL'), 'VIAL_API_URL');

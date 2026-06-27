import 'package:flutter_dotenv/flutter_dotenv.dart';

String get appBaseUrl => dotenv.env['BASE_API_URL'] ?? "http://10.10.13.27:8000/api";
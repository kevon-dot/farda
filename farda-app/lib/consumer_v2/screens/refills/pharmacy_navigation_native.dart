import 'package:url_launcher/url_launcher.dart';

Future<bool> openPharmacyUrl(Uri uri) async {
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

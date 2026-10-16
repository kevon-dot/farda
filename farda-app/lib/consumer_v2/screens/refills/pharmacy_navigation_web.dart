// ignore: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;

Future<bool> openPharmacyUrl(Uri uri) async {
  // Same-tab navigation is reliable after the account session recheck.
  // Prevent the pharmacy from receiving the Farda page as a referrer.
  final link =
      html.AnchorElement(href: uri.toString())
        ..rel = 'noreferrer noopener'
        ..target = '_self';
  link.click();
  return true;
}

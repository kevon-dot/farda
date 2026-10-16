// This implementation is imported only on web via a conditional export.
// ignore: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;

Future<bool> openBillingUrl(Uri uri) async {
  html.window.location.assign(uri.toString());
  return true;
}

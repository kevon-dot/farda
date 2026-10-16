import 'package:shared_preferences/shared_preferences.dart';

/// A local, account-scoped presentation preference; never a paid entitlement.
class MembershipOfferGate {
  static Future<bool> claim(String userId, bool Function() isCurrent) async {
    if (userId.isEmpty || !isCurrent()) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'farda.membershipOffer.v1.${Uri.encodeComponent(userId)}';
      if (!isCurrent() || prefs.getBool(key) == true) return false;
      final saved = await prefs.setBool(key, true);
      return saved && isCurrent();
    } catch (_) {
      return false; // Optional discovery must never interrupt the saved routine.
    }
  }
}

/// Captures an opaque session check without exposing credentials to widgets.
abstract interface class BillingSessionGuard {
  Future<Future<bool> Function()> captureBillingSession();
}

/// Server-authoritative membership state. No locally inferred entitlements.
abstract interface class BillingRepository {
  Future<BillingCatalog> loadBillingCatalog();
  Future<BillingStatus> loadBillingStatus();
  Future<Uri> createBillingCheckout(String priceKey, Uri returnUri);
  Future<Uri> createBillingPortal(Uri returnUri);
}

class BillingPrice {
  const BillingPrice(
    this.key,
    this.interval,
    this.amount, {
    this.available = false,
  });
  final String key;
  final String interval;
  final int amount;
  final bool available;
  String get dollars => '\$${(amount / 100).toStringAsFixed(2)}';
}

class BillingPlan {
  const BillingPlan(this.tier, this.prices);
  final String tier;
  final List<BillingPrice> prices;
}

class BillingCatalog {
  const BillingCatalog({required this.plans, this.checkoutEnabled = false});
  final List<BillingPlan> plans;
  final bool checkoutEnabled;
  factory BillingCatalog.fromJson(Map<String, dynamic> json) => BillingCatalog(
    checkoutEnabled:
        json['checkoutEnabled'] == true && json['currency'] == 'USD',
    plans:
        (json['plans'] as List? ?? [])
            .map(
              (p) => BillingPlan(
                p['tier'] as String,
                (p['prices'] as List? ?? [])
                    .map(
                      (v) => BillingPrice(
                        v['key'] as String,
                        v['interval'] as String,
                        (v['amount'] as num).toInt(),
                        available: v['available'] == true,
                      ),
                    )
                    .toList(),
              ),
            )
            .toList(),
  );
  static const proposal = BillingCatalog(
    plans: [
      BillingPlan('plus', [
        BillingPrice('plus_monthly', 'month', 1499),
        BillingPrice('plus_annual', 'year', 14999),
      ]),
      BillingPlan('family', [
        BillingPrice('family_monthly', 'month', 2499),
        BillingPrice('family_annual', 'year', 24999),
      ]),
    ],
  );
}

class BillingStatus {
  const BillingStatus({
    this.tier = 'free',
    this.status = 'inactive',
    this.aiRefillHelp = false,
    this.familyAlerts = false,
    this.managementAvailable = false,
    this.cancelAtPeriodEnd = false,
    this.renewsAt,
    this.source,
  });
  final String tier, status;
  final String? source;
  final bool aiRefillHelp, familyAlerts, managementAvailable, cancelAtPeriodEnd;
  final DateTime? renewsAt;
  bool get hasMembership => tier != 'free';
  factory BillingStatus.fromJson(Map<String, dynamic> json) {
    final caps = json['capabilities'] as Map? ?? {};
    return BillingStatus(
      tier: json['tier'] as String? ?? 'free',
      source: json['source'] as String?,
      status: json['status'] as String? ?? 'inactive',
      aiRefillHelp: caps['aiRefillHelp'] == true,
      familyAlerts: caps['familyAlerts'] == true,
      managementAvailable: json['managementAvailable'] == true,
      cancelAtPeriodEnd: json['cancelAtPeriodEnd'] == true,
      renewsAt: DateTime.tryParse(json['renewsAt'] as String? ?? ''),
    );
  }
}

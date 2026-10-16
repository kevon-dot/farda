import 'dart:async';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'billing.dart';

abstract interface class NativeBillingRepository {
  Future<NativeBillingConfig> loadNativeBillingConfig(String platform);
  Future<NativeBillingConfig> prepareNativeBilling(
    String platform,
    Future<bool> Function() sessionCurrent,
  );
  Future<BillingStatus> syncNativeBilling(
    Future<bool> Function() sessionCurrent,
  );
}

class NativeBillingConfig {
  const NativeBillingConfig({
    this.enabled = false,
    this.appUserId = '',
    this.apiKey = '',
    this.products = const {},
    this.termsUrl,
    this.privacyUrl,
  });
  final bool enabled;
  final Uri? termsUrl, privacyUrl;
  bool get policiesAvailable => [termsUrl, privacyUrl].every(
    (u) =>
        u != null &&
        u.scheme == 'https' &&
        u.host.isNotEmpty &&
        u.userInfo.isEmpty,
  );
  final String appUserId, apiKey;
  final Map<String, String> products;
  factory NativeBillingConfig.fromJson(Map<String, dynamic> json) =>
      NativeBillingConfig(
        enabled: json['enabled'] == true,
        termsUrl: Uri.tryParse(json['termsUrl'] as String? ?? ''),
        privacyUrl: Uri.tryParse(json['privacyUrl'] as String? ?? ''),
        appUserId: json['appUserId'] as String? ?? '',
        apiKey: json['apiKey'] as String? ?? '',
        products: {
          for (final p in json['products'] as List? ?? [])
            p['id'] as String: p['tier'] as String,
        },
      );
}

class NativeOffer {
  const NativeOffer({
    required this.id,
    required this.tier,
    required this.annual,
    required this.price,
    required this.package,
  });
  final String id, tier, price;
  final bool annual;
  final Object package;
}

abstract interface class NativePurchaseAdapter {
  Future<List<NativeOffer>> configure(NativeBillingConfig config);
  Future<void> purchase(NativeOffer offer);
  Future<void> restore();
  Future<void> reset();
}

/// All SDK calls, including logout, are serialized across paywall instances.
/// No CustomerInfo entitlement is used locally and no long-lived listener is attached.
class RevenueCatPurchaseAdapter implements NativePurchaseAdapter {
  static Future<void> _queue = Future.value();
  static String? _owner;
  final Object _lease = Object();
  int _epoch = 0;
  static Object? _activeLease;
  Future<T> _serial<T>(Future<T> Function() operation) {
    final result = _queue.then((_) => operation());
    _queue = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  @override
  Future<List<NativeOffer>> configure(NativeBillingConfig config) {
    final epoch = _epoch;
    return _serial(() async {
      if (epoch != _epoch) throw StateError('Store session changed');
      if (!config.enabled ||
          config.apiKey.isEmpty ||
          config.appUserId.isEmpty) {
        return [];
      }
      if (!await Purchases.isConfigured) {
        await Purchases.configure(
          PurchasesConfiguration(config.apiKey)..appUserID = config.appUserId,
        );
      } else if (_owner != config.appUserId) {
        if (!await Purchases.isAnonymous) await Purchases.logOut();
        await Purchases.logIn(config.appUserId);
      }
      if (epoch != _epoch) {
        if (!await Purchases.isAnonymous) await Purchases.logOut();
        _owner = null;
        throw StateError('Store session changed');
      }
      _owner = config.appUserId;
      _activeLease = _lease;
      final offerings = await Purchases.getOfferings();
      if (epoch != _epoch || _activeLease != _lease) {
        throw StateError('Store session changed');
      }
      final packages = offerings.current?.availablePackages ?? <Package>[];
      return [
        for (final p in packages)
          if (config.products.containsKey(p.storeProduct.identifier) &&
              (p.packageType == PackageType.annual ||
                  p.packageType == PackageType.monthly))
            NativeOffer(
              id: p.storeProduct.identifier,
              tier: config.products[p.storeProduct.identifier]!,
              annual: p.packageType == PackageType.annual,
              price: p.storeProduct.priceString,
              package: p,
            ),
      ];
    });
  }

  void _requireOwner() {
    if (_activeLease != _lease) throw StateError('Store session changed');
  }

  @override
  Future<void> purchase(NativeOffer offer) => _serial(() async {
    _requireOwner();
    await Purchases.purchase(PurchaseParams.package(offer.package as Package));
  });
  @override
  Future<void> restore() => _serial(() async {
    _requireOwner();
    await Purchases.restorePurchases();
  });
  @override
  Future<void> reset() {
    // Invalidate immediately so a queued operation cannot start after logout.
    _epoch++;
    final owned = _activeLease == _lease;
    if (owned) _activeLease = null;
    return _serial(() async {
      if (owned && _activeLease == null && await Purchases.isConfigured) {
        if (!await Purchases.isAnonymous) await Purchases.logOut();
        _owner = null;
      }
    });
  }
}

String nativePurchaseError(Object error) {
  if (error is PlatformException) {
    switch (PurchasesErrorHelper.getErrorCode(error)) {
      case PurchasesErrorCode.purchaseCancelledError:
        return 'Purchase cancelled. Your free routine is still here.';
      case PurchasesErrorCode.paymentPendingError:
        return 'Your purchase is awaiting store approval. Refresh membership after it is approved.';
      case PurchasesErrorCode.networkError:
        return 'The store could not connect. Check your connection and try again.';
      default:
        break;
    }
  }
  return 'We couldn’t confirm your store membership. Try Restore purchases or refresh. Your free routine is still here.';
}

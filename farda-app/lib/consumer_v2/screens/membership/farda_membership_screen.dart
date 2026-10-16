import 'package:farda/application/authentication/storage/auth_storage.dart';
import 'dart:async';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart';
import 'package:farda/features/consumer/data/native_billing.dart';
import 'package:flutter/material.dart';
import 'package:farda/features/consumer/data/billing.dart';
import '../../design_system/farda_consumer_tokens.dart';
import 'billing_navigation.dart';

/// Optional membership; free routine care never depends on this route.
class FardaMembershipScreen extends StatefulWidget {
  const FardaMembershipScreen({
    super.key,
    this.repository,
    this.nativeAdapter,
    this.initialTier = 'plus',
    this.onboardingOffer = false,
  });
  final BillingRepository? repository;
  final NativePurchaseAdapter? nativeAdapter;
  final String initialTier;
  final bool onboardingOffer;
  @override
  State<FardaMembershipScreen> createState() => _FardaMembershipScreenState();
}

class _FardaMembershipScreenState extends State<FardaMembershipScreen>
    with WidgetsBindingObserver {
  late final NativePurchaseAdapter _native =
      widget.nativeAdapter ?? RevenueCatPurchaseAdapter();
  List<NativeOffer> _offers = [];
  bool _nativeReady = false;
  NativeBillingConfig? _nativeConfig;
  bool get _nativePlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);
  BillingCatalog? _catalog;
  BillingStatus? _status;
  late String _tier;
  bool _annual = true, _loading = true, _busy = false;
  String? _error;
  int _generation = 0;
  Future<bool> Function()? _sessionCurrent;
  @override
  void initState() {
    super.initState();
    _tier = widget.initialTier == 'family' ? 'family' : 'plus';
    WidgetsBinding.instance.addObserver(this);
    AuthStorage.sessionRevision.addListener(_onSessionRevision);
    _load();
  }

  @override
  void dispose() {
    _generation++;
    unawaited(_native.reset().catchError((Object _) {}));
    AuthStorage.sessionRevision.removeListener(_onSessionRevision);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_busy) return; // Store sheets can pause/resume the app mid-purchase.
    if (state == AppLifecycleState.resumed) {
      _load();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _clearSessionView();
    }
  }

  void _onSessionRevision() {
    if (widget.onboardingOffer) {
      Navigator.maybePop(context);
    }
    unawaited(_native.reset().catchError((Object _) {}));
    _clearSessionView();
    final generation = _generation;
    Future.microtask(() {
      if (mounted && generation == _generation) _load();
    });
  }

  void _clearSessionView() {
    _generation++;
    if (mounted) {
      setState(() {
        _nativeConfig = null;
        _offers = [];
        _nativeReady = false;
        _catalog = null;
        _status = null;
        _sessionCurrent = null;
        _busy = false;
        _loading = true;
      });
    }
  }

  @override
  void didUpdateWidget(covariant FardaMembershipScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      unawaited(_native.reset().catchError((Object _) {}));
      _load();
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _nativeConfig = null;
      _offers = [];
      _nativeReady = false;
      _error = null;
      _catalog = null;
      _status = null;
      _sessionCurrent = null;
    });
    if (widget.repository == null) {
      setState(() {
        _loading = false;
      });
      return;
    }
    try {
      final repository = widget.repository!;
      final check =
          repository is BillingSessionGuard
              ? await (repository as BillingSessionGuard)
                  .captureBillingSession()
              : () async => true;
      final result = await Future.wait([
        widget.repository!.loadBillingCatalog(),
        widget.repository!.loadBillingStatus(),
      ]);
      if (!mounted || generation != _generation) return;
      if (!await check()) throw StateError('Session changed');
      if (!mounted || generation != _generation) return;
      if (_nativePlatform && repository is NativeBillingRepository) {
        final config = await (repository as NativeBillingRepository)
            .loadNativeBillingConfig(
              defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
            );
        if (!mounted || generation != _generation || !await check()) return;
        if (config.enabled && config.policiesAvailable) {
          final offers = await _native.configure(config);
          if (!mounted || generation != _generation || !await check()) return;
          _nativeConfig = config;
          _offers = offers;
          _nativeReady = true;
        }
      }
      setState(() {
        _sessionCurrent = check;
        _catalog = result[0] as BillingCatalog;
        _status = result[1] as BillingStatus;
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _error =
              'We couldn’t load your membership. Your free routine is still here.';
          _catalog = null;
          _status = null;
        });
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _purchase(BillingPrice price) async {
    if (!kIsWeb ||
        widget.repository == null ||
        _catalog?.checkoutEnabled != true ||
        !price.available ||
        _busy) {
      return;
    }
    await _open(
      () => widget.repository!.createBillingCheckout(price.key, Uri.base),
    );
  }

  Future<void> _nativeAction([NativeOffer? offer]) async {
    if (_busy || !_nativeReady) return;
    final generation = _generation;
    final check = _sessionCurrent;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (check == null ||
          !await check() ||
          !mounted ||
          generation != _generation) {
        return;
      }
      if (offer == null) {
        await _native.restore();
      } else {
        final prepared = await (widget.repository! as NativeBillingRepository)
            .prepareNativeBilling(
              defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
              check,
            );
        if (!mounted || generation != _generation || !await check()) return;
        if (!prepared.enabled ||
            !prepared.policiesAvailable ||
            prepared.appUserId != _nativeConfig?.appUserId ||
            prepared.apiKey != _nativeConfig?.apiKey ||
            prepared.products[offer.id] != offer.tier) {
          throw StateError('Store offer changed');
        }
        await _native.purchase(offer);
      }
      if (!mounted || generation != _generation || !await check()) return;
      final status = await (widget.repository! as NativeBillingRepository)
          .syncNativeBilling(check);
      if (!mounted || generation != _generation || !await check()) return;
      setState(() {
        _status = status;
        _error =
            status.hasMembership
                ? null
                : 'No active store membership has been confirmed yet. If your payment is pending, refresh after store approval.';
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = nativePurchaseError(error));
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _manageStore() async {
    final generation = _generation;
    final check = _sessionCurrent;
    if (check == null ||
        !await check() ||
        !mounted ||
        generation != _generation) {
      return;
    }
    try {
      final uri = Uri.parse(
        defaultTargetPlatform == TargetPlatform.iOS
            ? 'https://apps.apple.com/account/subscriptions'
            : 'https://play.google.com/store/account/subscriptions',
      );
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw StateError('Unavailable');
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(
          () =>
              _error =
                  'Open your app store subscription settings to manage or cancel your membership.',
        );
      }
    }
  }

  Future<void> _open(Future<Uri> Function() create) async {
    final generation = _generation;
    final check = _sessionCurrent;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (check == null || !await check()) throw StateError('Session changed');
      if (!mounted || generation != _generation) return;
      final uri = await create();
      if (!await check()) throw StateError('Session changed');
      if (!mounted || generation != _generation) return;
      if (!await openBillingUrl(uri)) throw StateError('unavailable');
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(
          () =>
              _error =
                  'Billing couldn’t open. Please try again. No membership change was confirmed.',
        );
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Text _text(
    String value, {
    double size = 14,
    Color color = Colors.white,
    FontWeight weight = FontWeight.w400,
  }) => Text(
    value,
    style: TextStyle(
      fontFamily: 'Outfit',
      fontSize: size,
      height: 1.35,
      color: color,
      fontWeight: weight,
    ),
  );
  @override
  Widget build(BuildContext context) {
    final catalog = _catalog ?? BillingCatalog.proposal;
    final plans = catalog.plans.where((p) => p.tier == _tier);
    final prices =
        plans.isEmpty
            ? <BillingPrice>[]
            : plans.first.prices
                .where((p) => p.interval == (_annual ? 'year' : 'month'))
                .toList();
    final price = prices.isEmpty ? null : prices.first;
    final matchingOffers = _offers.where(
      (o) => o.tier == _tier && o.annual == _annual,
    );
    final nativeOffer = matchingOffers.isEmpty ? null : matchingOffers.first;
    final active = _status?.hasMembership == true;
    final hasBillingAccount = active || _status?.managementAvailable == true;
    final canBuy =
        !_loading &&
        !_busy &&
        !hasBillingAccount &&
        (kIsWeb
            ? _catalog?.checkoutEnabled == true &&
                price != null &&
                price.available
            : _nativeReady && nativeOffer != null);
    const muted = Color(0xFFC7D2E5);
    return Scaffold(
      backgroundColor: FardaConsumerColors.deep,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _text('farda', size: 25, weight: FontWeight.w600),
                    ),
                    IconButton(
                      tooltip: 'Close membership',
                      onPressed: () => Navigator.maybePop(context),
                      icon: const Icon(Icons.close, color: Colors.white),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Center(
                  child: FardaCompanion(
                    size: 112,
                    pose: FardaCompanionPose.quiet,
                    floating: true,
                  ),
                ),
                const SizedBox(height: 16),
                _text(
                  hasBillingAccount
                      ? 'Your membership.'
                      : widget.onboardingOffer
                      ? 'Your routine, supported.'
                      : 'A little more support.',
                  size: 32,
                  weight: FontWeight.w600,
                ),
                const SizedBox(height: 8),
                _text(
                  hasBillingAccount
                      ? active
                          ? 'Care that fits your everyday.'
                          : 'Review your billing. Your free routine is still here.'
                      : widget.onboardingOffer
                      ? 'Your medication is saved. Choose a little extra support, or keep going free.'
                      : 'For you. And the people in your corner.',
                  color: muted,
                  size: 16,
                ),
                const SizedBox(height: 24),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                  )
                else if (hasBillingAccount) ...[
                  _panel(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _text(
                          active
                              ? 'FARDA ${_status!.tier.toUpperCase()}'
                              : 'FARDA MEMBERSHIP',
                          size: 12,
                          weight: FontWeight.w600,
                        ),
                        const SizedBox(height: 8),
                        _text(
                          _status!.status.replaceAll('_', ' '),
                          size: 26,
                          weight: FontWeight.w600,
                        ),
                        if (active && _status!.renewsAt != null) ...[
                          const SizedBox(height: 8),
                          _text(
                            '${_status!.cancelAtPeriodEnd ? 'Access ends' : 'Renews'} ${MaterialLocalizations.of(context).formatMediumDate(_status!.renewsAt!.toLocal())}',
                            color: muted,
                          ),
                        ],
                        const SizedBox(height: 16),
                        _text(
                          _status!.familyAlerts
                              ? 'AI refill guidance · in-app family check-ins'
                              : _status!.aiRefillHelp
                              ? 'AI refill guidance'
                              : 'Premium access is not active. Your free essentials remain available.',
                          color: muted,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed:
                        _nativePlatform &&
                                (_status!.source == 'native' ||
                                    _status!.source == 'multiple') &&
                                !_busy
                            ? _manageStore
                            : kIsWeb &&
                                _status!.source != 'native' &&
                                _status!.managementAvailable &&
                                !_busy
                            ? () => _open(
                              () => widget.repository!.createBillingPortal(
                                Uri.base,
                              ),
                            )
                            : null,
                    style: _buttonStyle(),
                    child: const Text('Manage membership'),
                  ),
                  const SizedBox(height: 8),
                  _text(
                    kIsWeb &&
                            _status!.source != 'native' &&
                            _status!.managementAvailable
                        ? 'Opens secure Stripe billing to manage or cancel.'
                        : !kIsWeb && _status!.source == 'web'
                        ? 'This membership is billed on the web. Open Farda in your browser and choose Manage membership to update payment details or cancel.'
                        : !kIsWeb
                        ? 'Manage or cancel store subscriptions in your App Store or Google Play subscription settings.'
                        : 'Membership management is unavailable on this device.',
                    color: muted,
                    size: 12,
                  ),
                  if (_status!.source == 'multiple') ...[
                    const SizedBox(height: 12),
                    _text(
                      kIsWeb
                          ? 'You have web and store subscriptions. This button manages web billing only. To stop store renewal, open the App Store or Google Play subscription settings used for your purchase.'
                          : 'You have web and store subscriptions. This button manages store billing only. To stop web renewal, open Farda in your browser and choose Manage membership. Each subscription must be managed separately.',
                      color: FardaConsumerColors.peach,
                      size: 12,
                    ),
                  ],
                ] else ...[
                  _choiceRow(
                    ['Plus', 'Family'],
                    _tier == 'plus' ? 0 : 1,
                    (i) => setState(() => _tier = i == 0 ? 'plus' : 'family'),
                  ),
                  const SizedBox(height: 16),
                  _choiceRow(
                    ['Yearly', 'Monthly'],
                    _annual ? 0 : 1,
                    (i) => setState(() => _annual = i == 0),
                  ),
                  const SizedBox(height: 16),
                  _panel(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _text(
                          'FARDA ${_tier.toUpperCase()}',
                          size: 12,
                          weight: FontWeight.w600,
                        ),
                        const SizedBox(height: 8),
                        _text(
                          !kIsWeb
                              ? nativeOffer == null
                                  ? 'Price unavailable'
                                  : '${nativeOffer.price} / ${_annual ? 'year' : 'month'}'
                              : price == null
                              ? 'Price unavailable'
                              : '${price.dollars} / ${_annual ? 'year' : 'month'}',
                          size: 30,
                          weight: FontWeight.w600,
                        ),
                        const SizedBox(height: 4),
                        _text(
                          !kIsWeb
                              ? nativeOffer == null
                                  ? 'Store pricing will appear when available.'
                                  : 'Billed ${_annual ? 'yearly' : 'monthly'} through your app store.'
                              : price == null
                              ? 'Try refreshing membership.'
                              : _annual
                              ? '${price.dollars} billed yearly · USD'
                              : '${price.dollars} billed monthly · USD',
                          color: muted,
                          size: 13,
                        ),
                        if (kIsWeb && _annual && price != null) ...[
                          const SizedBox(height: 8),
                          _text(
                            'About \$${(price.amount / 1200).toStringAsFixed(2)} / month, billed yearly',
                            color: const Color(0xFFF8EDD8),
                            size: 13,
                            weight: FontWeight.w600,
                          ),
                        ],
                        if (_tier == 'family') ...[
                          const SizedBox(height: 8),
                          _text(
                            'Per routine owner · Invited viewers stay free',
                            size: 12,
                            color: muted,
                          ),
                        ],
                        const SizedBox(height: 20),
                        _benefit(
                          Icons.auto_awesome_outlined,
                          'AI refill guidance',
                          'Help understanding your next refill step.',
                        ),
                        if (_tier == 'family') ...[
                          const SizedBox(height: 16),
                          _benefit(
                            Icons.favorite_border,
                            'In-app family check-ins',
                            'See shared routines that still need confirmation in your Circle.',
                          ),
                        ],
                        const SizedBox(height: 12),
                        _text(
                          _tier == 'family'
                              ? 'Check-ins need consent. They aren’t emergency monitoring.'
                              : 'Guidance supports your decisions; your pharmacy confirms refills.',
                          size: 12,
                          color: muted,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed:
                        canBuy
                            ? () =>
                                kIsWeb
                                    ? _purchase(price!)
                                    : _nativeAction(nativeOffer)
                            : null,
                    style: _buttonStyle(),
                    child: Text(
                      _busy
                          ? kIsWeb
                              ? 'Opening secure billing…'
                              : 'Confirming with the store…'
                          : canBuy
                          ? 'Continue with ${_tier == 'plus' ? 'Plus' : 'Family'}'
                          : 'Purchases unavailable',
                    ),
                  ),
                  const SizedBox(height: 10),
                  _text(
                    canBuy
                        ? kIsWeb
                            ? 'Renews automatically. Cancel in membership settings. Opens secure Stripe checkout.'
                            : 'Renews automatically. Confirm the price in your app store. Cancel in your store subscription settings.'
                        : !kIsWeb
                        ? 'Store purchases are unavailable right now. You can keep using Farda free.'
                        : 'Purchases are not configured. No payment will be taken.',
                    size: 12,
                    color: muted,
                  ),
                ],
                if (widget.onboardingOffer) ...[
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => Navigator.maybePop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xFFC7D2E5)),
                      minimumSize: const Size(double.infinity, 52),
                    ),
                    child: const Text('Continue free'),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Semantics(
                    liveRegion: true,
                    child: _text(_error!, color: FardaConsumerColors.peach),
                  ),
                ],
                const SizedBox(height: 24),
                _text(
                  'Always here. Always free.',
                  size: 18,
                  weight: FontWeight.w600,
                ),
                const SizedBox(height: 6),
                _text(
                  'Reminders, dose history, manual refill tracking and your basic Circle.',
                  color: muted,
                ),
                const SizedBox(height: 12),
                _text(
                  'Farda vial: \$35 separately. A membership does not include hardware.',
                  size: 12,
                  color: muted,
                ),
                const SizedBox(height: 16),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed:
                          _loading || _busy || widget.repository == null
                              ? null
                              : _load,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        disabledForegroundColor: muted,
                      ),
                      child: const Text('Refresh membership'),
                    ),
                    if (_nativeConfig?.policiesAvailable == true) ...[
                      TextButton(
                        onPressed:
                            () => launchUrl(
                              _nativeConfig!.termsUrl!,
                              mode: LaunchMode.externalApplication,
                            ),
                        child: const Text('Terms of service'),
                      ),
                      TextButton(
                        onPressed:
                            () => launchUrl(
                              _nativeConfig!.privacyUrl!,
                              mode: LaunchMode.externalApplication,
                            ),
                        child: const Text('Privacy policy'),
                      ),
                    ],
                    if (!kIsWeb)
                      TextButton(
                        onPressed:
                            _nativeReady && !_busy && !_loading
                                ? () => _nativeAction()
                                : null,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          disabledForegroundColor: muted,
                        ),
                        child: const Text('Restore purchases'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  ButtonStyle _buttonStyle() => FilledButton.styleFrom(
    backgroundColor: FardaConsumerColors.warm,
    foregroundColor: FardaConsumerColors.deep,
    disabledBackgroundColor: const Color(0xFF334866),
    disabledForegroundColor: const Color(0xFFC7D2E5),
    minimumSize: const Size.fromHeight(54),
    padding: const EdgeInsets.all(16),
  );
  Widget _panel(Widget child) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: FardaConsumerColors.brand,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: const Color(0xFF405575)),
    ),
    child: child,
  );
  Widget _benefit(IconData icon, String title, String detail) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, color: FardaConsumerColors.warm, size: 22),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _text(title, weight: FontWeight.w600),
            const SizedBox(height: 4),
            _text(detail, color: const Color(0xFFC7D2E5), size: 13),
          ],
        ),
      ),
    ],
  );
  Widget _choiceRow(
    List<String> labels,
    int selected,
    ValueChanged<int> onChanged,
  ) => Row(
    children: [
      for (var i = 0; i < labels.length; i++) ...[
        if (i > 0) const SizedBox(width: 8),
        Expanded(
          child: Semantics(
            selected: selected == i,
            child: OutlinedButton(
              onPressed: _busy ? null : () => onChanged(i),
              style: OutlinedButton.styleFrom(
                backgroundColor:
                    selected == i
                        ? FardaConsumerColors.warm
                        : Colors.transparent,
                foregroundColor:
                    selected == i ? FardaConsumerColors.deep : Colors.white,
                side: const BorderSide(color: Color(0xFF50627E)),
                minimumSize: const Size(0, 48),
                padding: const EdgeInsets.all(10),
              ),
              child: Text(
                labels[i],
                style: const TextStyle(
                  fontFamily: 'Outfit',
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ],
    ],
  );
}

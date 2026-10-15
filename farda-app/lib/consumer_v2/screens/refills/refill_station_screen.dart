import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:farda/consumer_v2/design_system/farda_consumer_tokens.dart';

import 'refill_station_state.dart';
import 'refills_figma_parts.dart';
import 'refills_handoff_screen.dart';

typedef PharmacyContactCallback = void Function(RefillStationState state);

/// Stable keys for host integration and isolated widget tests.
abstract final class RefillStationKeys {
  static const supplySummary = Key('refill-supply-summary');
  static const journey = Key('refill-journey');
  static const primaryAction = Key('refill-primary-action');
  static const handoffCard = Key('refill-handoff-card');
  static const receiptCard = Key('refill-receipt-card');
}

/// Consumer v2 refill planning experience.
///
/// This widget is intentionally route-agnostic. Provide a [controller] when
/// state should be owned by a parent; otherwise the screen creates and disposes
/// a local controller. [onOpenPharmacyContact] is only a host handoff to an
/// official pharmacy contact surface. It is never treated as a refill request.
class RefillStationScreen extends StatefulWidget {
  const RefillStationScreen({
    super.key,
    this.controller,
    this.initialState,
    this.onStateChanged,
    this.onOpenPharmacyContact,
    this.onReviewVial,
    this.onOpenProfile,
  }) : assert(controller == null || initialState == null);

  final RefillStationController? controller;
  final RefillStationState? initialState;
  final ValueChanged<RefillStationState>? onStateChanged;
  final PharmacyContactCallback? onOpenPharmacyContact;
  final VoidCallback? onReviewVial;
  final VoidCallback? onOpenProfile;

  @override
  State<RefillStationScreen> createState() => _RefillStationScreenState();
}

class _RefillStationScreenState extends State<RefillStationScreen> {
  late RefillStationController _controller;
  late bool _ownsController;

  @override
  void initState() {
    super.initState();
    _attachController();
  }

  @override
  void didUpdateWidget(covariant RefillStationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        (widget.controller == null &&
            oldWidget.initialState != widget.initialState)) {
      _detachController();
      _attachController();
    }
  }

  void _attachController() {
    _ownsController = widget.controller == null;
    _controller =
        widget.controller ??
        RefillStationController(initialState: widget.initialState);
    _controller.addListener(_handleControllerChange);
  }

  void _detachController() {
    _controller.removeListener(_handleControllerChange);
    if (_ownsController) _controller.dispose();
  }

  void _handleControllerChange() {
    if (!mounted) return;
    setState(() {});
    widget.onStateChanged?.call(_controller.state);
  }

  @override
  void dispose() {
    _detachController();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseTheme = Theme.of(context);
    final textTheme = baseTheme.textTheme.apply(
      fontFamily: 'Outfit',
      bodyColor: _RefillPalette.navy,
      displayColor: _RefillPalette.navy,
    );
    final localTheme = baseTheme.copyWith(
      scaffoldBackgroundColor: _RefillPalette.ivory,
      colorScheme: baseTheme.colorScheme.copyWith(
        primary: _RefillPalette.navy,
        onPrimary: Colors.white,
        surface: _RefillPalette.card,
        onSurface: _RefillPalette.navy,
      ),
      textTheme: textTheme,
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          foregroundColor: _RefillPalette.navy,
          side: const BorderSide(color: _RefillPalette.line),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: _RefillPalette.blue,
          minimumSize: const Size(48, 48),
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _RefillPalette.soft,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: _RefillPalette.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: _RefillPalette.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: _RefillPalette.blue, width: 2),
        ),
      ),
    );

    final state = _controller.state;
    return Theme(
      data: localTheme,
      child: Builder(
        builder: (context) {
          return Scaffold(
            backgroundColor: _RefillPalette.ivory,
            body: SafeArea(
              bottom: false,
              child: CustomScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(22, 8, 22, 40),
                    sliver: SliverList.list(
                      children: [
                        RefillsPageHeader(onOpenProfile: widget.onOpenProfile),
                        const SizedBox(height: 16),
                        const RefillsIntro(),
                        const SizedBox(height: 16),
                        RefillsSupplyHero(
                          key: RefillStationKeys.supplySummary,
                          headline: 'ESTIMATED SUPPLY',
                          value: '${state.estimatedDays}',
                          unit: state.estimatedDays == 1 ? 'day' : 'days',
                          detail: 'From your count + daily schedule.',
                          fraction:
                              (state.estimatedDays / 10)
                                  .clamp(0.0, 1.0)
                                  .toDouble(),
                        ),
                        const SizedBox(height: 16),
                        RefillsPrimaryAction(
                          key: RefillStationKeys.primaryAction,
                          onPressed:
                              state.stage == RefillJourneyStage.reconciled &&
                                      widget.onReviewVial == null
                                  ? null
                                  : _handleJourneyAction,
                          label: switch (state.stage) {
                            RefillJourneyStage.planAhead => 'Plan my refill',
                            RefillJourneyStage.handoffPrepared =>
                              'I contacted my pharmacy',
                            RefillJourneyStage.pharmacyContacted =>
                              'Update pharmacy status',
                            RefillJourneyStage.ready => 'I received my refill',
                            RefillJourneyStage.received =>
                              'Add the supply I received',
                            RefillJourneyStage.reconciled =>
                              widget.onReviewVial == null
                                  ? 'Supply reconciled'
                                  : 'Review my vial',
                          },
                        ),
                        const SizedBox(height: 16),
                        const RefillsSafetyBanner(),
                        const SizedBox(height: 16),
                        const Text(
                          'Your refill journey',
                          style: TextStyle(
                            fontFamily: 'Outfit',
                            fontSize: 18,
                            height: 24 / 18,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF142C55),
                          ),
                        ),
                        const SizedBox(height: 16),
                        RefillsJourneyCard(
                          key: RefillStationKeys.journey,
                          medicationName: state.medicationName,
                          pharmacyLabel:
                              '${state.pharmacyName} · Rx ending ${state.rxLastFour}',
                          activeStep: switch (state.stage) {
                            RefillJourneyStage.planAhead => 1,
                            RefillJourneyStage.handoffPrepared => 1,
                            RefillJourneyStage.pharmacyContacted => 2,
                            RefillJourneyStage.ready => 3,
                            RefillJourneyStage.received ||
                            RefillJourneyStage.reconciled => 4,
                          },
                          onOpenDetails:
                              () => _showHandoffSheet(advance: false),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: _showCountSheet,
                            iconAlignment: IconAlignment.end,
                            icon: const FardaVectorIcon(
                              'icon-arrow-small',
                              size: 14,
                            ),
                            label: const Text('Update my count'),
                          ),
                        ),
                        const SizedBox(height: 24),
                        const _SectionTitle(title: 'Your medication supply'),
                        _MedicationSupplyCard(state: state),
                        if (state.stage.index >=
                            RefillJourneyStage.handoffPrepared.index) ...[
                          const SizedBox(height: 16),
                          _HandoffCard(
                            key: RefillStationKeys.handoffCard,
                            state: state,
                            onReview: () => _showHandoffSheet(advance: false),
                            onOpenContact:
                                widget.onOpenPharmacyContact == null
                                    ? null
                                    : () =>
                                        widget.onOpenPharmacyContact!(state),
                          ),
                        ],
                        if (state.hasReceipt) ...[
                          const SizedBox(height: 16),
                          _ReceiptCard(
                            key: RefillStationKeys.receiptCard,
                            state: state,
                            onReviewVial: widget.onReviewVial,
                          ),
                        ],
                        const SizedBox(height: 18),
                        const _NoticeCard(
                          title: 'Your pharmacy stays in charge',
                          message:
                              'Farda does not submit, authorize, or fulfill prescriptions. Your pharmacy or prescriber confirms refills, eligibility, and timing.',
                        ),
                        const SizedBox(height: 4),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: _showLowSupplyHelp,
                            icon: const Icon(Icons.support_agent_rounded),
                            label: const Text(
                              'No refills left, or supply running low?',
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: _showAboutDialog,
                          child: const Text('About the refill station'),
                        ),
                        const SizedBox(height: 72),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _handleJourneyAction() {
    switch (_controller.state.stage) {
      case RefillJourneyStage.planAhead:
        _showHandoffView();
        return;
      case RefillJourneyStage.handoffPrepared:
        if (_controller.markPharmacyContacted()) {
          _showMessage(
            'Saved your update. Farda has not received a pharmacy confirmation.',
          );
        }
        return;
      case RefillJourneyStage.pharmacyContacted:
        _showPharmacyStatusSheet();
        return;
      case RefillJourneyStage.ready:
        _showReceiptConfirmation();
        return;
      case RefillJourneyStage.received:
        _showReconcileSheet();
        return;
      case RefillJourneyStage.reconciled:
        widget.onReviewVial?.call();
        return;
    }
  }

  Future<void> _showHandoffView() => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder:
          (_) => RefillsHandoffScreen(
            medicationName: _controller.state.medicationName,
            rxLabel: 'Rx ending ${_controller.state.rxLastFour} · Saved by you',
            actionLabel: 'Prepare pharmacy handoff',
            onSavePlan: () async {
              _controller.prepareHandoff();
              return null;
            },
            onOpenContact:
                widget.onOpenPharmacyContact == null
                    ? null
                    : () => widget.onOpenPharmacyContact!(_controller.state),
            onOpenProfile: widget.onOpenProfile,
          ),
    ),
  );

  Future<void> _showHandoffSheet({required bool advance}) async {
    final state = _controller.state;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _RefillPalette.ivory,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        return _SheetScaffold(
          title: 'Your pharmacy,\nyour next step.',
          intro:
              'Review your prescription details, then contact your pharmacy through its official app, website, or phone number.',
          children: [
            _SheetMedicationCard(state: state),
            const SizedBox(height: 16),
            const _InlineDisclosure(
              icon: Icons.outbox_outlined,
              title: 'No request is sent from here',
              message:
                  'This handoff helps you prepare. It does not place an order or reserve a pickup.',
            ),
            const SizedBox(height: 12),
            const _InlineDisclosure(
              icon: Icons.verified_user_outlined,
              title: 'Eligibility is not verified',
              message:
                  'Your pharmacy or prescriber confirms refills remaining, timing, and any next steps.',
            ),
            const SizedBox(height: 22),
            if (advance)
              FilledButton(
                onPressed: () {
                  _controller.prepareHandoff();
                  Navigator.of(sheetContext).pop();
                  _showMessage(
                    'Handoff prepared. Farda has not sent a refill request.',
                  );
                },
                child: const Text('Prepare pharmacy handoff'),
              )
            else
              FilledButton(
                onPressed: () => Navigator.of(sheetContext).pop(),
                child: const Text('Done'),
              ),
          ],
        );
      },
    );
  }

  Future<void> _showPharmacyStatusSheet() async {
    final state = _controller.state;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _RefillPalette.ivory,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        void complete(bool changed, String message) {
          if (!changed) return;
          Navigator.of(sheetContext).pop();
          _showMessage(message);
        }

        return _SheetScaffold(
          title: 'What did your\npharmacy say?',
          intro:
              'These are updates you provide. They are not live confirmations from ${state.pharmacyName}.',
          children: [
            _StatusChoice(
              icon: Icons.inventory_2_outlined,
              title: 'They said it’s ready',
              subtitle: 'Save this as your report, not a pharmacy feed.',
              onTap:
                  () => complete(
                    _controller.markReady(),
                    'Saved: you reported that the refill is ready.',
                  ),
            ),
            const SizedBox(height: 10),
            _StatusChoice(
              icon: Icons.receipt_long_outlined,
              title: 'I already received it',
              subtitle: 'Create a receipt, then add only the supply received.',
              onTap:
                  () => complete(
                    _controller.markReceived(),
                    'Receipt saved. Your inventory has not changed yet.',
                  ),
            ),
            const SizedBox(height: 10),
            _StatusChoice(
              icon: Icons.schedule_rounded,
              title: 'Still waiting',
              subtitle: 'Keep the current step and save this check-in.',
              onTap:
                  () => complete(
                    _controller.markStillWaiting(),
                    'Saved: you’re still waiting for a pharmacy update.',
                  ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showReceiptConfirmation() async {
    final state = _controller.state;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: _RefillPalette.ivory,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Text('Did you receive this refill?'),
          content: Text(
            'Confirm only after you receive ${state.medicationName}. This saves your report; it does not add tablets to inventory yet.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Not yet'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Save receipt'),
            ),
          ],
        );
      },
    );
    if (confirmed == true && _controller.markReceived()) {
      _showMessage('Receipt saved. Your inventory has not changed yet.');
    }
  }

  Future<void> _showReconcileSheet() async {
    final quantityController = TextEditingController();
    var checked = false;
    String? error;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _RefillPalette.ivory,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            void submit() {
              final quantity = int.tryParse(quantityController.text.trim());
              if (quantity == null || quantity < 1 || quantity > 999) {
                setSheetState(
                  () => error = 'Enter the actual amount received (1–999).',
                );
                return;
              }
              if (!checked) {
                setSheetState(
                  () =>
                      error =
                          'Confirm the medication and count before adding supply.',
                );
                return;
              }
              if (!_controller.reconcileReceivedSupply(quantity)) {
                setSheetState(
                  () =>
                      error =
                          'That count could not be added. Review the current inventory and try again.',
                );
                return;
              }
              Navigator.of(sheetContext).pop();
              _showMessage(
                '$quantity tablets added from your confirmed count.',
              );
            }

            return _SheetScaffold(
              title: 'Add what you\nreceived.',
              intro:
                  'Receiving a refill and adding supply are separate steps. Enter only the amount you actually received.',
              includeKeyboardInset: true,
              children: [
                TextField(
                  controller: quantityController,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(3),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Tablets received',
                    hintText: 'Enter the actual count',
                    suffixText: 'tablets',
                  ),
                  onSubmitted: (_) => submit(),
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  value: checked,
                  onChanged:
                      (value) => setSheetState(() {
                        checked = value ?? false;
                        error = null;
                      }),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'I checked the medication label and counted the supply received.',
                    style: TextStyle(fontSize: 14, height: 1.35),
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 4),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      error!,
                      style: const TextStyle(
                        color: _RefillPalette.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: submit,
                  child: const Text('Confirm supply received'),
                ),
                const SizedBox(height: 10),
                const Text(
                  'This updates your estimate. Loading a vial requires its own medication and count check.',
                  style: TextStyle(
                    color: _RefillPalette.muted,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
    quantityController.dispose();
  }

  Future<void> _showCountSheet() async {
    final countController = TextEditingController(
      text: _controller.state.inventoryUnits.toString(),
    );
    String? error;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _RefillPalette.ivory,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            void submit() {
              final count = int.tryParse(countController.text.trim());
              if (count == null || count < 0 || count > 999) {
                setSheetState(
                  () => error = 'Enter the count you verified (0–999).',
                );
                return;
              }
              _controller.correctInventoryCount(count);
              Navigator.of(sheetContext).pop();
              _showMessage('Your verified supply count is saved.');
            }

            return _SheetScaffold(
              title: 'Let’s check\nyour supply.',
              intro:
                  'Enter the total count you verified. Estimates are only as reliable as this count and your saved schedule.',
              includeKeyboardInset: true,
              children: [
                TextField(
                  controller: countController,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(3),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Tablets available',
                    suffixText: 'tablets',
                  ),
                  onSubmitted: (_) => submit(),
                ),
                if (error != null) ...[
                  const SizedBox(height: 10),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      error!,
                      style: const TextStyle(
                        color: _RefillPalette.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: submit,
                  child: const Text('Save verified count'),
                ),
              ],
            );
          },
        );
      },
    );
    countController.dispose();
  }

  Future<void> _showAboutDialog() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: _RefillPalette.ivory,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Text('About the refill station'),
          content: const Text(
            'Farda helps you estimate supply, prepare a pharmacy handoff, and record what you report. It does not prescribe medication or submit and fulfill refill orders.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Got it'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showLowSupplyHelp() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: _RefillPalette.ivory,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          icon: const Icon(
            Icons.local_pharmacy_outlined,
            color: _RefillPalette.navy,
          ),
          title: const Text('Let your pharmacy help'),
          content: const Text(
            'Contact your pharmacy or prescriber about eligibility, timing, and next steps if no refills remain or you are concerned about running out. Do not change how you take a medication based on this estimate.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
            if (widget.onOpenPharmacyContact != null)
              FilledButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  widget.onOpenPharmacyContact!(_controller.state);
                },
                child: const Text('Contact options'),
              ),
          ],
        );
      },
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: _RefillPalette.navy,
        ),
      );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.25,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MedicationSupplyCard extends StatelessWidget {
  const _MedicationSupplyCard({required this.state});

  final RefillStationState state;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MedicationRow(state: state),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final itemWidth =
                  constraints.maxWidth >= 300
                      ? (constraints.maxWidth - 10) / 2
                      : constraints.maxWidth;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  SizedBox(
                    width: itemWidth,
                    child: _SupplyMetric(
                      label: 'Count on hand',
                      value: '${state.inventoryUnits} tablets',
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: _SupplyMetric(
                      label: 'Saved schedule',
                      value:
                          '${state.dailyUnits} ${state.dailyUnits == 1 ? 'tablet' : 'tablets'} / day',
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: _SupplyMetric(
                      label: 'Estimated supply',
                      value:
                          '${state.estimatedDays} ${state.estimatedDays == 1 ? 'day' : 'days'}',
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: _SupplyMetric(
                      label: 'Refills remaining',
                      value:
                          state.refillsRemaining == null
                              ? 'Not verified'
                              : '${state.refillsRemaining}',
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 17,
                color: _RefillPalette.muted,
              ),
              SizedBox(width: 7),
              Expanded(
                child: Text(
                  'Inventory comes from your confirmed count. Update it whenever the number changes.',
                  style: TextStyle(
                    color: _RefillPalette.muted,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HandoffCard extends StatelessWidget {
  const _HandoffCard({
    super.key,
    required this.state,
    required this.onReview,
    this.onOpenContact,
  });

  final RefillStationState state;
  final VoidCallback onReview;
  final VoidCallback? onOpenContact;

  @override
  Widget build(BuildContext context) {
    return _Card(
      color: _RefillPalette.navy,
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: Colors.white),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.local_pharmacy_outlined,
                  color: _RefillPalette.lightBlue,
                ),
                SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'Pharmacy handoff',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 17),
            _InverseDetailRow(label: 'Pharmacy', value: state.pharmacyName),
            _InverseDetailRow(
              label: 'Prescription',
              value: 'Rx ending ${state.rxLastFour}',
            ),
            const _InverseDetailRow(
              label: 'Request sent by Farda',
              value: 'No',
            ),
            _InverseDetailRow(
              label: 'Refills remaining',
              value:
                  state.refillsRemaining == null
                      ? 'Not verified'
                      : '${state.refillsRemaining}',
            ),
            const SizedBox(height: 14),
            Text(
              _handoffStatus(state.stage),
              style: const TextStyle(
                color: _RefillPalette.lightBlue,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            if (onOpenContact != null) ...[
              FilledButton.icon(
                onPressed: onOpenContact,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: _RefillPalette.navy,
                ),
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('Open official contact options'),
              ),
              const SizedBox(height: 4),
            ],
            TextButton(
              onPressed: onReview,
              style: TextButton.styleFrom(
                foregroundColor: _RefillPalette.lightBlue,
                padding: EdgeInsets.zero,
              ),
              child: const Text('Review handoff details'),
            ),
          ],
        ),
      ),
    );
  }

  static String _handoffStatus(RefillJourneyStage stage) {
    switch (stage) {
      case RefillJourneyStage.planAhead:
        return 'Not prepared';
      case RefillJourneyStage.handoffPrepared:
        return 'PREPARED ON THIS DEVICE · NOTHING SENT';
      case RefillJourneyStage.pharmacyContacted:
        return 'CONTACTED · YOU REPORTED';
      case RefillJourneyStage.ready:
        return 'READY · YOU REPORTED';
      case RefillJourneyStage.received:
      case RefillJourneyStage.reconciled:
        return 'RECEIVED · YOU REPORTED';
    }
  }
}

class _ReceiptCard extends StatelessWidget {
  const _ReceiptCard({super.key, required this.state, this.onReviewVial});

  final RefillStationState state;
  final VoidCallback? onReviewVial;

  @override
  Widget build(BuildContext context) {
    final receivedAt = state.receiptRecordedAt;
    final recorded =
        receivedAt == null
            ? 'Time not recorded'
            : _formatLocalDateTime(context, receivedAt);
    final reconciled = state.inventoryIsReconciled;

    return _Card(
      color: reconciled ? _RefillPalette.successSoft : _RefillPalette.card,
      borderColor:
          reconciled ? _RefillPalette.successBorder : _RefillPalette.line,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                reconciled
                    ? Icons.check_circle_rounded
                    : Icons.receipt_long_outlined,
                color:
                    reconciled ? _RefillPalette.success : _RefillPalette.blue,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  reconciled ? 'Supply reconciled' : 'Refill receipt',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const _StatusBadge(label: 'YOU REPORTED'),
            ],
          ),
          const SizedBox(height: 16),
          _ReceiptDetail(label: 'Medication', value: state.medicationName),
          _ReceiptDetail(label: 'Received', value: recorded),
          _ReceiptDetail(
            label: 'Supply added',
            value:
                reconciled
                    ? '${state.receivedQuantity} tablets'
                    : 'Not added yet',
          ),
          _ReceiptDetail(
            label: 'Current inventory',
            value: '${state.inventoryUnits} tablets',
          ),
          const SizedBox(height: 12),
          Text(
            reconciled
                ? 'Source: the count you confirmed. Vial loading remains a separate check.'
                : 'This receipt does not change your supply estimate until you confirm the amount received.',
            style: const TextStyle(
              color: _RefillPalette.muted,
              fontSize: 12,
              height: 1.4,
            ),
          ),
          if (reconciled && onReviewVial != null) ...[
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: onReviewVial,
              icon: const Icon(Icons.medication_liquid_outlined),
              label: const Text('Next: loading the right vial'),
            ),
          ],
        ],
      ),
    );
  }
}

class _MedicationRow extends StatelessWidget {
  const _MedicationRow({required this.state});

  final RefillStationState state;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: const BoxDecoration(
            color: _RefillPalette.softBlue,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.medication_outlined,
            color: _RefillPalette.navy,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                state.medicationName,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${state.pharmacyName} · Rx ending ${state.rxLastFour}',
                style: const TextStyle(
                  color: _RefillPalette.muted,
                  fontSize: 12,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SupplyMetric extends StatelessWidget {
  const _SupplyMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: _RefillPalette.soft,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: _RefillPalette.muted, fontSize: 11),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _RefillPalette.softBlue,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: _RefillPalette.blue,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _RefillPalette.warm,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _RefillPalette.warmBorder),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.shield_outlined,
              size: 21,
              color: _RefillPalette.warmText,
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: _RefillPalette.warmText,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message,
                    style: const TextStyle(
                      color: _RefillPalette.warmText,
                      fontSize: 12,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.child,
    this.color = _RefillPalette.card,
    this.borderColor = _RefillPalette.line,
  });

  final Widget child;
  final Color color;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderColor),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D13294C),
            blurRadius: 18,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _InverseDetailRow extends StatelessWidget {
  const _InverseDetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Color(0xFFB9C8DF), fontSize: 12),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReceiptDetail extends StatelessWidget {
  const _ReceiptDetail({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: _RefillPalette.muted, fontSize: 12),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetScaffold extends StatelessWidget {
  const _SheetScaffold({
    required this.title,
    required this.intro,
    required this.children,
    this.includeKeyboardInset = false,
  });

  final String title;
  final String intro;
  final List<Widget> children;
  final bool includeKeyboardInset;

  @override
  Widget build(BuildContext context) {
    final keyboardInset =
        includeKeyboardInset ? MediaQuery.viewInsetsOf(context).bottom : 0.0;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(22, 12, 22, 24 + keyboardInset),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 5,
                decoration: BoxDecoration(
                  color: _RefillPalette.line,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 22),
            Semantics(
              header: true,
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 30,
                  height: 1.04,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.9,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              intro,
              style: const TextStyle(
                color: _RefillPalette.muted,
                fontSize: 14,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 20),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _SheetMedicationCard extends StatelessWidget {
  const _SheetMedicationCard({required this.state});

  final RefillStationState state;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _RefillPalette.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _RefillPalette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            state.medicationName,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            '${state.pharmacyName} · Rx ending ${state.rxLastFour}\nRefills remaining: ${state.refillsRemaining ?? 'not verified'}\nPickup timing: ask your pharmacy',
            style: const TextStyle(
              color: _RefillPalette.muted,
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineDisclosure extends StatelessWidget {
  const _InlineDisclosure({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: const BoxDecoration(
            color: _RefillPalette.softBlue,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 20, color: _RefillPalette.navy),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                message,
                style: const TextStyle(
                  color: _RefillPalette.muted,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusChoice extends StatelessWidget {
  const _StatusChoice({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: Material(
        color: _RefillPalette.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: _RefillPalette.line),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Row(
              children: [
                Icon(icon, color: _RefillPalette.blue),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: _RefillPalette.muted,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.arrow_forward_rounded,
                  color: _RefillPalette.muted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _formatLocalDateTime(BuildContext context, DateTime dateTime) {
  final local = dateTime.toLocal();
  final localizations = MaterialLocalizations.of(context);
  final date = localizations.formatMediumDate(local);
  final time = localizations.formatTimeOfDay(TimeOfDay.fromDateTime(local));
  return '$date at $time';
}

abstract final class _RefillPalette {
  static const navy = Color(0xFF142C55);
  static const blue = Color(0xFF426AA6);
  static const lightBlue = Color(0xFFD8E6FA);
  static const ivory = Color(0xFFF6F5F0);
  static const card = Color(0xFFFFFFFF);
  static const soft = Color(0xFFF2F0E9);
  static const softBlue = Color(0xFFE3EAF6);
  static const line = Color(0xFFD8DEE8);
  static const muted = Color(0xFF637187);
  static const warm = Color(0xFFFFF3DC);
  static const warmBorder = Color(0xFFE8CC97);
  static const warmText = Color(0xFF73501F);
  static const success = Color(0xFF287B5D);
  static const successSoft = Color(0xFFE9F5EF);
  static const successBorder = Color(0xFFBBDCCF);
  static const error = Color(0xFF9A3328);
}

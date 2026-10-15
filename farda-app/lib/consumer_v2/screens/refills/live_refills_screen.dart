import 'package:farda/consumer_v2/design_system/farda_consumer_tokens.dart';
import 'package:farda/features/consumer/data/consumer_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'refills_figma_parts.dart';
import 'refills_handoff_screen.dart';

typedef InventoryUpdate =
    Future<String?> Function(String prescriptionId, int quantity);
typedef RefillUpdate =
    Future<String?> Function(
      String prescriptionId,
      RefillStage stage, {
      bool startNew,
    });
typedef ReceiptReconciliation =
    Future<String?> Function(
      String prescriptionId, {
      required int quantity,
      required bool alreadyIncluded,
    });

/// Account-backed refill view. Pharmacy status is always a user report;
/// planning and handoff never imply an order or confirmation.
class LiveRefillsScreen extends StatelessWidget {
  const LiveRefillsScreen({
    super.key,
    required this.snapshot,
    this.onUpdateInventory,
    this.onUpdateRefill,
    this.onReconcileReceipt,
    this.onOpenRefillTools,
    this.onOpenProfile,
  });

  final ConsumerSnapshot snapshot;
  final InventoryUpdate? onUpdateInventory;
  final RefillUpdate? onUpdateRefill;
  final ReceiptReconciliation? onReconcileReceipt;
  final VoidCallback? onOpenRefillTools;
  final VoidCallback? onOpenProfile;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: FardaConsumerColors.canvas,
    body: SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(22, 8, 22, 96),
        children: [
          RefillsPageHeader(onOpenProfile: onOpenProfile),
          const SizedBox(height: 16),
          const RefillsIntro(),
          const SizedBox(height: 16),
          if (snapshot.prescriptions.isEmpty)
            FardaConsumerCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.medication_outlined,
                    color: FardaConsumerColors.brand,
                    size: 34,
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'No prescriptions yet',
                    style: FardaConsumerType.title,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Add your label details before tracking supply or planning a refill.',
                    style: FardaConsumerType.body,
                  ),
                  if (onOpenRefillTools != null) ...[
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: onOpenRefillTools,
                      child: const Text('Open account tools'),
                    ),
                  ],
                ],
              ),
            )
          else
            for (final prescription in snapshot.prescriptions) ...[
              _SupplySection(
                key: ValueKey('refill-${prescription.id}'),
                prescription: prescription,
                inventory: snapshot.supply(prescription.id),
                countEnabled: snapshot.capabilities.inventoryEnabled,
                refillEnabled: snapshot.capabilities.refillsEnabled,
                onUpdateInventory: onUpdateInventory,
                onUpdateRefill: onUpdateRefill,
                onReconcileReceipt: onReconcileReceipt,
                onOpenRefillTools: onOpenRefillTools,
              ),
              const SizedBox(height: 24),
            ],
          if (snapshot.prescriptions.isEmpty) ...[
            const SizedBox(height: 16),
            const RefillsSafetyBanner(),
          ],
          const SizedBox(height: 12),
          const Text(
            'Farda does not place an order or promise a pickup date. Use the contact details on your label for pharmacy or prescriber questions.',
            style: FardaConsumerType.caption,
          ),
        ],
      ),
    ),
  );
}

class _SupplySection extends StatelessWidget {
  const _SupplySection({
    super.key,
    required this.prescription,
    required this.inventory,
    required this.countEnabled,
    required this.refillEnabled,
    required this.onUpdateInventory,
    required this.onUpdateRefill,
    required this.onReconcileReceipt,
    required this.onOpenRefillTools,
  });

  final ConsumerPrescription prescription;
  final ConsumerInventory? inventory;
  final bool countEnabled;
  final bool refillEnabled;
  final InventoryUpdate? onUpdateInventory;
  final RefillUpdate? onUpdateRefill;
  final ReceiptReconciliation? onReconcileReceipt;
  final VoidCallback? onOpenRefillTools;

  @override
  Widget build(BuildContext context) {
    final count = inventory?.quantity;
    final estimate = inventory?.stale == true ? null : inventory?.estimatedDays;
    final stage = inventory?.refillId == null ? null : inventory!.stage;
    final pharmacy = prescription.pharmacy?.trim();
    final rx = prescription.rxNumber?.trim();
    final pharmacyLabel = [
      if (pharmacy != null && pharmacy.isNotEmpty) pharmacy,
      if (rx != null && rx.length >= 4)
        'Rx ending ${rx.substring(rx.length - 4)}',
    ].join(' · ');
    final nextLabel = switch (stage) {
      null => 'Plan my refill',
      RefillStage.planning => 'I contacted my pharmacy',
      RefillStage.contacted => 'I was told it is ready',
      RefillStage.ready => 'I received my refill',
      RefillStage.received =>
        inventory?.receiptReconciled == true
            ? 'Plan my next refill'
            : 'Reconcile my refill',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RefillsSupplyHero(
          headline:
              inventory?.stale == true
                  ? 'COUNT NEEDS REFRESH'
                  : estimate != null
                  ? 'ESTIMATED SUPPLY'
                  : count != null
                  ? 'YOUR LAST COUNT'
                  : 'SUPPLY NOT COUNTED',
          value: estimate?.toString() ?? count?.toString() ?? '—',
          unit: estimate != null ? (estimate == 1 ? 'day' : 'days') : null,
          detail:
              inventory?.stale == true
                  ? 'This count is out of date. Recount before relying on it.'
                  : estimate != null
                  ? 'From your count + daily schedule.'
                  : count != null
                  ? 'From the count you last entered.'
                  : 'Enter a count to track supply.',
          fraction:
              estimate == null
                  ? null
                  : (estimate / 10).clamp(0.0, 1.0).toDouble(),
        ),
        const SizedBox(height: 16),
        RefillsPrimaryAction(
          label: nextLabel,
          onPressed:
              !refillEnabled || onUpdateRefill == null
                  ? null
                  : () =>
                      stage == null
                          ? Navigator.of(context).push<void>(
                            MaterialPageRoute(
                              builder:
                                  (_) => RefillsHandoffScreen(
                                    medicationName: prescription.name,
                                    rxLabel:
                                        rx != null && rx.length >= 4
                                            ? 'Rx ending ${rx.substring(rx.length - 4)} · Saved by you'
                                            : 'Saved by you',
                                    actionLabel: 'Save my refill plan',
                                    onSavePlan:
                                        () => onUpdateRefill!(
                                          prescription.id,
                                          RefillStage.planning,
                                        ),
                                    onOpenContact:
                                        onOpenRefillTools == null
                                            ? null
                                            : () {
                                              Navigator.of(context).pop();
                                              onOpenRefillTools!();
                                            },
                                    contactLabel:
                                        onOpenRefillTools == null
                                            ? 'Find pharmacy contact'
                                            : 'Open account tools',
                                  ),
                            ),
                          )
                          : showDialog<void>(
                            context: context,
                            builder:
                                (_) =>
                                    stage == RefillStage.received &&
                                            inventory?.receiptReconciled != true
                                        ? _ReceiptDialog(
                                          prescription: prescription,
                                          inventory: inventory,
                                          onReconcileReceipt:
                                              onReconcileReceipt,
                                          onOpenRefillTools: onOpenRefillTools,
                                        )
                                        : _RefillDialog(
                                          prescription: prescription,
                                          stage: stage,
                                          onUpdateRefill: onUpdateRefill!,
                                        ),
                          ),
        ),
        if (!refillEnabled) ...[
          const SizedBox(height: 4),
          const Text(
            'Refill updates are unavailable for this account.',
            style: FardaConsumerType.caption,
          ),
        ],
        const SizedBox(height: 16),
        const RefillsSafetyBanner(),
        const SizedBox(height: 16),
        const Text('Your refill journey', style: FardaConsumerType.title),
        const SizedBox(height: 16),
        RefillsJourneyCard(
          medicationName: prescription.name,
          pharmacyLabel:
              pharmacyLabel.isEmpty ? 'Your prescription' : pharmacyLabel,
          activeStep: switch (stage) {
            null => 0,
            RefillStage.planning => 1,
            RefillStage.contacted => 2,
            RefillStage.ready => 3,
            RefillStage.received => 4,
          },
          onOpenDetails: onOpenRefillTools,
        ),
        if (stage != null) ...[
          const SizedBox(height: 8),
          Text(switch (stage) {
            RefillStage.planning => 'You recorded a refill plan.',
            RefillStage.contacted => 'You reported contacting your pharmacy.',
            RefillStage.ready =>
              'You reported that your pharmacy said it is ready.',
            RefillStage.received => 'You reported receiving your refill.',
          }, style: FardaConsumerType.caption),
        ] else ...[
          const SizedBox(height: 8),
          const Text(
            'No refill plan recorded.',
            style: FardaConsumerType.caption,
          ),
        ],
        if (inventory?.plannedFor != null) ...[
          const SizedBox(height: 4),
          Text(
            'Plan date · ${DateFormat.yMMMd().format(inventory!.plannedFor!.toLocal())}',
            style: FardaConsumerType.caption,
          ),
        ],
        if (stage == RefillStage.received) ...[
          const SizedBox(height: 4),
          Text(
            inventory!.receiptReconciled
                ? 'Your received supply was reconciled with your count.'
                : 'Received supply has not been added to your count.',
            style: FardaConsumerType.caption,
          ),
          if (inventory?.receiptReconciled != true)
            TextButton(
              onPressed:
                  !refillEnabled || onUpdateRefill == null
                      ? null
                      : () => showDialog<void>(
                        context: context,
                        builder:
                            (_) => _RefillDialog(
                              prescription: prescription,
                              stage: stage,
                              onUpdateRefill: onUpdateRefill!,
                              unreconciled:
                                  inventory?.receiptReconciled != true,
                            ),
                      ),
              child: const Text('Plan my next refill'),
            ),
        ],
        const SizedBox(height: 6),
        TextButton.icon(
          onPressed:
              countEnabled && onUpdateInventory != null
                  ? () => showDialog<void>(
                    context: context,
                    builder:
                        (_) => _CountDialog(
                          prescription: prescription,
                          onUpdateInventory: onUpdateInventory!,
                        ),
                  )
                  : null,
          iconAlignment: IconAlignment.end,
          icon: const FardaVectorIcon('icon-arrow-small', size: 14),
          label: const Text('Update my count'),
        ),
        if (!countEnabled)
          const Text(
            'Count updates are unavailable for this account.',
            style: FardaConsumerType.caption,
          ),
        if (onOpenRefillTools != null)
          TextButton(
            onPressed: onOpenRefillTools,
            child: const Text('Open account tools'),
          ),
      ],
    );
  }
}

class _CountDialog extends StatefulWidget {
  const _CountDialog({
    required this.prescription,
    required this.onUpdateInventory,
  });
  final ConsumerPrescription prescription;
  final InventoryUpdate onUpdateInventory;

  @override
  State<_CountDialog> createState() => _CountDialogState();
}

class _CountDialogState extends State<_CountDialog> {
  final _text = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final count = int.tryParse(_text.text.trim());
    if (count == null || count < 0 || count > 100000) {
      setState(() => _error = 'Enter an actual count from 0 to 100,000.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    String? error;
    try {
      error = await widget.onUpdateInventory(widget.prescription.id, count);
    } catch (_) {
      error = 'This count was not saved. Please try again.';
    }
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _saving = false;
        _error = error;
      });
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(
      const SnackBar(content: Text('Your count was saved.')),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Count ${widget.prescription.name}'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Enter what you counted. This is not a live vial measurement.',
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('live-refill-count-input'),
          controller: _text,
          enabled: !_saving,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          decoration: InputDecoration(
            labelText: 'Units counted',
            errorText: _error,
          ),
          onSubmitted: (_) => _save(),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const Key('live-refill-save-count'),
        onPressed: _saving ? null : _save,
        child: Text(_saving ? 'Saving…' : 'Save count'),
      ),
    ],
  );
}

class _RefillDialog extends StatefulWidget {
  const _RefillDialog({
    required this.prescription,
    required this.stage,
    required this.onUpdateRefill,
    this.unreconciled = false,
  });
  final ConsumerPrescription prescription;
  final RefillStage? stage;
  final RefillUpdate onUpdateRefill;
  final bool unreconciled;

  @override
  State<_RefillDialog> createState() => _RefillDialogState();
}

class _RefillDialogState extends State<_RefillDialog> {
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final next = switch (widget.stage) {
      null || RefillStage.received => RefillStage.planning,
      RefillStage.planning => RefillStage.contacted,
      RefillStage.contacted => RefillStage.ready,
      RefillStage.ready => RefillStage.received,
    };
    String? error;
    try {
      error = await widget.onUpdateRefill(
        widget.prescription.id,
        next,
        startNew: widget.stage == RefillStage.received,
      );
    } catch (_) {
      error = 'Your refill update was not saved. Please try again.';
    }
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _saving = false;
        _error = error;
      });
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Your refill update was saved.')),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(switch (widget.stage) {
      null => 'Plan a refill',
      RefillStage.planning => 'Contacted your pharmacy?',
      RefillStage.contacted => 'Pharmacy said it is ready?',
      RefillStage.ready => 'Received your refill?',
      RefillStage.received => 'Plan the next refill?',
    }),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(switch (widget.stage) {
          null =>
            'Save a plan for ${widget.prescription.name}. This does not contact your pharmacy or submit an order.',
          RefillStage.planning =>
            'Contact your pharmacy using your label details first. This records only that you contacted them; it does not submit a request.',
          RefillStage.contacted =>
            'Only record ready after your pharmacy tells you. This is your report, not pharmacy confirmation in Farda.',
          RefillStage.ready =>
            'Only record this once you actually receive the refill. Your supply count will stay unchanged until you reconcile the receipt.',
          RefillStage.received =>
            widget.unreconciled
                ? 'Your previous receipt is not reconciled. Starting a new plan leaves your last count unchanged and skips that receipt in this view.'
                : 'Start another plan for ${widget.prescription.name}. This does not submit an order.',
        }),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Not yet'),
      ),
      FilledButton(
        key: const Key('live-refill-confirm-stage'),
        onPressed: _saving ? null : _save,
        child: Text(
          _saving
              ? 'Saving…'
              : switch (widget.stage) {
                null => 'Save my plan',
                RefillStage.planning => 'I contacted them',
                RefillStage.contacted => 'Record my report',
                RefillStage.ready => 'I received it',
                RefillStage.received =>
                  widget.unreconciled
                      ? 'Skip and start plan'
                      : 'Start my next plan',
              },
        ),
      ),
    ],
  );
}

class _ReceiptDialog extends StatefulWidget {
  const _ReceiptDialog({
    required this.prescription,
    required this.inventory,
    required this.onReconcileReceipt,
    required this.onOpenRefillTools,
  });
  final ConsumerPrescription prescription;
  final ConsumerInventory? inventory;
  final ReceiptReconciliation? onReconcileReceipt;
  final VoidCallback? onOpenRefillTools;

  @override
  State<_ReceiptDialog> createState() => _ReceiptDialogState();
}

class _ReceiptDialogState extends State<_ReceiptDialog> {
  final _quantity = TextEditingController();
  bool? _alreadyIncluded;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _quantity.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final quantity = int.tryParse(_quantity.text.trim());
    if (quantity == null || quantity < 1 || quantity > 100000) {
      setState(
        () => _error = 'Enter the actual quantity received, from 1 to 100,000.',
      );
      return;
    }
    if (_alreadyIncluded == null) {
      setState(
        () =>
            _error =
                'Choose whether this refill is already included in your last count.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    String? error;
    try {
      error = await widget.onReconcileReceipt!(
        widget.prescription.id,
        quantity: quantity,
        alreadyIncluded: _alreadyIncluded!,
      );
    } catch (_) {
      error = 'The receipt was not saved. Please try again.';
    }
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _saving = false;
        _error = error;
      });
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Your receipt and count were reconciled.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.inventory?.quantity;
    final quantity = int.tryParse(_quantity.text.trim());
    final projected =
        count == null || _alreadyIncluded == null || quantity == null
            ? null
            : count + (_alreadyIncluded! ? 0 : quantity);
    final canReconcile =
        count != null &&
        widget.inventory?.stale != true &&
        widget.onReconcileReceipt != null;
    return AlertDialog(
      title: Text('Reconcile ${widget.prescription.name}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              count == null
                  ? 'Save a current supply count before reconciling this received refill.'
                  : widget.inventory?.stale == true
                  ? 'Your last count is out of date. Recount before reconciling this received refill.'
                  : 'Your last count is $count. Enter what you actually received and whether it is already included in that count.',
            ),
            if (canReconcile) ...[
              const SizedBox(height: 16),
              TextField(
                key: const Key('live-refill-receipt-quantity'),
                controller: _quantity,
                enabled: !_saving,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                decoration: const InputDecoration(
                  labelText: 'Quantity actually received',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              const Text('Is this refill already in your last count?'),
              AbsorbPointer(
                absorbing: _saving,
                child: RadioGroup<bool>(
                  groupValue: _alreadyIncluded,
                  onChanged:
                      (value) => setState(() => _alreadyIncluded = value),
                  child: const Column(
                    children: [
                      RadioListTile<bool>(
                        key: Key('live-refill-receipt-included'),
                        title: Text('Yes, already included'),
                        value: true,
                      ),
                      RadioListTile<bool>(
                        key: Key('live-refill-receipt-add'),
                        title: Text('No, add received quantity'),
                        value: false,
                      ),
                    ],
                  ),
                ),
              ),
              if (projected != null)
                Text('Count after reconciliation: $projected'),
              const Text('Recount first if your last count is out of date.'),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        if (canReconcile)
          FilledButton(
            key: const Key('live-refill-confirm-receipt'),
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Saving…' : 'Confirm receipt and count'),
          )
        else if (widget.onOpenRefillTools != null)
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              widget.onOpenRefillTools!();
            },
            child: const Text('Open account tools'),
          ),
      ],
    );
  }
}

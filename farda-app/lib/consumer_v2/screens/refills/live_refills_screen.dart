import 'package:farda/consumer_v2/design_system/farda_consumer_tokens.dart';
import 'package:farda/features/consumer/data/consumer_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

typedef InventoryUpdate = Future<String?> Function(
  String prescriptionId,
  int quantity,
);
typedef RefillUpdate = Future<String?> Function(
  String prescriptionId,
  RefillStage stage, {
  bool startNew,
});
typedef ReceiptReconciliation = Future<String?> Function(
  String prescriptionId, {
  required int quantity,
  required bool alreadyIncluded,
});

/// Account-backed refill view. A pharmacy status is always shown as a user
/// report; neither this view nor a handoff represents an order or confirmation.
class LiveRefillsScreen extends StatelessWidget {
  const LiveRefillsScreen({
    super.key,
    required this.snapshot,
    this.onUpdateInventory,
    this.onUpdateRefill,
    this.onReconcileReceipt,
    this.onOpenRefillTools,
  });

  final ConsumerSnapshot snapshot;
  final InventoryUpdate? onUpdateInventory;
  final RefillUpdate? onUpdateRefill;
  final ReceiptReconciliation? onReconcileReceipt;
  final VoidCallback? onOpenRefillTools;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FardaConsumerColors.canvas,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 96),
          children: [
            const Text('REFILLS · YOUR RECORD', style: FardaConsumerType.label),
            const SizedBox(height: 10),
            const Text('Your refill\nstation.', style: FardaConsumerType.display),
            const SizedBox(height: 9),
            const Text(
              'A clear view of your supply and the next step you choose.',
              style: FardaConsumerType.body,
            ),
            const SizedBox(height: 28),
            if (snapshot.prescriptions.isEmpty)
              FardaConsumerCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.medication_outlined,
                        color: FardaConsumerColors.brand, size: 34),
                    const SizedBox(height: 14),
                    const Text('No prescriptions yet',
                        style: FardaConsumerType.title),
                    const SizedBox(height: 8),
                    const Text(
                      'Add your label details to your account before tracking supply or planning a refill.',
                      style: FardaConsumerType.body,
                    ),
                    if (onOpenRefillTools != null) ...[
                      const SizedBox(height: 16),
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
                _SupplyCard(
                  key: ValueKey('refill-${prescription.id}'),
                  prescription: prescription,
                  inventory: snapshot.supply(prescription.id),
                  countEnabled: snapshot.capabilities.inventoryEnabled,
                  onUpdateInventory: onUpdateInventory,
                  refillEnabled: snapshot.capabilities.refillsEnabled,
                  onUpdateRefill: onUpdateRefill,
                  onReconcileReceipt: onReconcileReceipt,
                  onOpenRefillTools: onOpenRefillTools,
                ),
                const SizedBox(height: 16),
              ],
            const SizedBox(height: 12),
            FardaConsumerCard(
              color: FardaConsumerColors.warm,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Row(children: [
                    Icon(Icons.verified_user_outlined,
                        color: FardaConsumerColors.textWarm, size: 21),
                    SizedBox(width: 9),
                    Expanded(child: Text('Your pharmacy is the source',
                      style: FardaConsumerType.title)),
                  ]),
                  SizedBox(height: 6),
                  Text(
                    'A plan here does not place an order or confirm a pickup date. Check the details on your label to contact your pharmacy or prescriber.',
                    style: FardaConsumerType.body,
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

class _SupplyCard extends StatelessWidget {
  const _SupplyCard({
    super.key,
    required this.prescription,
    required this.inventory,
    required this.countEnabled,
    required this.onUpdateInventory,
    required this.refillEnabled,
    required this.onUpdateRefill,
    required this.onReconcileReceipt,
    required this.onOpenRefillTools,
  });

  final ConsumerPrescription prescription;
  final ConsumerInventory? inventory;
  final bool countEnabled;
  final InventoryUpdate? onUpdateInventory;
  final bool refillEnabled;
  final RefillUpdate? onUpdateRefill;
  final ReceiptReconciliation? onReconcileReceipt;
  final VoidCallback? onOpenRefillTools;

  @override
  Widget build(BuildContext context) {
    final count = inventory?.quantity;
    final estimate = inventory?.stale == true ? null : inventory?.estimatedDays;
    final pharmacy = prescription.pharmacy?.trim();
    final rx = prescription.rxNumber?.trim();
    final stage = inventory?.refillId == null ? null : inventory!.stage;
    final steps = <String>['Plan', 'Contact', 'Ready', 'Received'];
    return FardaConsumerCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 24),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [FardaConsumerColors.deep, FardaConsumerColors.brand],
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    width: 34, height: 34,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .13),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: const Icon(Icons.medication_outlined,
                        color: Colors.white, size: 19),
                  ),
                  const SizedBox(width: 10),
                  const Text('YOUR PRESCRIPTION',
                      style: TextStyle(color: Color(0xFFCED9EA),
                          fontFamily: 'Outfit', fontSize: 10,
                          fontWeight: FontWeight.w600, letterSpacing: 1.2)),
                ]),
                const SizedBox(height: 16),
                Text(prescription.name,
                    style: FardaConsumerType.heading.copyWith(color: Colors.white)),
                if (pharmacy != null && pharmacy.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(pharmacy,
                      style: const TextStyle(color: Color(0xFFCED9EA))),
                ],
                if (rx != null && rx.length >= 4) ...[
                  const SizedBox(height: 3),
                  Text('Rx ending ${rx.substring(rx.length - 4)}',
                      style: const TextStyle(color: Color(0xFFCED9EA))),
                ],
                const SizedBox(height: 25),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFFE9EEF7).withValues(alpha: .15),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: Colors.white.withValues(alpha: .19)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                    child: Text(
                      inventory?.stale == true ? 'COUNT NEEDS REFRESH' :
                        estimate != null ? 'ESTIMATED SUPPLY' :
                        count != null ? 'YOUR LAST COUNT' : 'SUPPLY NOT COUNTED',
                      style: const TextStyle(color: Color(0xFFE5EDFA),
                          fontFamily: 'Outfit', fontSize: 10,
                          fontWeight: FontWeight.w600, letterSpacing: .8),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  estimate != null ? '$estimate days estimated' :
                    count != null ? '$count at last count' : 'No count recorded',
                  style: FardaConsumerType.heading.copyWith(
                    color: Colors.white, fontSize: 30),
                ),
                const SizedBox(height: 5),
                Text(
                  inventory?.stale == true
                      ? 'This count is out of date. Recount before relying on it.'
                      : estimate != null
                          ? 'From your entered count and fixed schedule; not a live vial measurement.'
                          : count != null
                              ? 'A days-left estimate needs a supported fixed schedule.'
                              : 'Enter a count when you are ready.',
                  style: const TextStyle(color: Color(0xFFCED9EA), fontSize: 12),
                ),
                if (inventory?.countedAt != null) ...[
                  const SizedBox(height: 6),
                  Text('Counted ${DateFormat.yMMMd().format(inventory!.countedAt!.toLocal())}',
                      style: const TextStyle(color: Color(0xFFCED9EA), fontSize: 12)),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Your refill journey', style: FardaConsumerType.title),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 8,
                  children: [
                    for (var index = 0; index < steps.length; index++)
                      _JourneyPill(
                        label: steps[index],
                        complete: stage != null && index <= stage.index,
                        current: stage != null && index == stage.index,
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  switch (stage) {
                    null => 'No refill plan recorded.',
                    RefillStage.planning => 'You recorded a refill plan.',
                    RefillStage.contacted => 'You reported contacting your pharmacy.',
                    RefillStage.ready => 'You reported that your pharmacy said it is ready.',
                    RefillStage.received => 'You reported receiving your refill.',
                  },
                  style: FardaConsumerType.body,
                ),
                if (inventory?.plannedFor != null) ...[
                  const SizedBox(height: 5),
                  Text('Plan date · ${DateFormat.yMMMd().format(inventory!.plannedFor!.toLocal())}',
                      style: FardaConsumerType.caption),
                ],
                if (stage == RefillStage.received) ...[
                  const SizedBox(height: 6),
                  Text(inventory!.receiptReconciled
                      ? 'Your received supply was reconciled with your count.'
                      : 'Received supply has not been added to your count.',
                      style: FardaConsumerType.caption),
                ],
                const SizedBox(height: 20),
                if (refillEnabled && onUpdateRefill != null) ...[
                  SizedBox(width: double.infinity, child: FilledButton(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 16),
                      backgroundColor: FardaConsumerColors.brand,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15)),
                    ),
                    onPressed: stage == RefillStage.received &&
                            inventory?.receiptReconciled == true
                        ? null
                        : () => showDialog<void>(
                              context: context,
                              builder: (_) => stage == RefillStage.received
                                  ? _ReceiptDialog(
                                      prescription: prescription,
                                      inventory: inventory,
                                      onReconcileReceipt: onReconcileReceipt,
                                      onOpenRefillTools: onOpenRefillTools,
                                    )
                                  : _RefillDialog(
                                      prescription: prescription,
                                      stage: stage,
                                      onUpdateRefill: onUpdateRefill!,
                                    ),
                            ),
                    child: Row(children: [
                      const Icon(Icons.arrow_forward_rounded, size: 19),
                      const SizedBox(width: 10),
                      Expanded(child: Text(
                        switch (stage) {
                          null => 'Plan my refill',
                          RefillStage.planning => 'I contacted my pharmacy',
                          RefillStage.contacted => 'I was told it is ready',
                          RefillStage.ready => 'I received my refill',
                          RefillStage.received => inventory?.receiptReconciled == true
                              ? 'Receipt reconciled' : 'Reconcile my refill',
                        },
                        textAlign: TextAlign.center,
                      )),
                    ]),
                  )),
                  if (stage == RefillStage.received) TextButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => _RefillDialog(
                        prescription: prescription,
                        stage: stage,
                        onUpdateRefill: onUpdateRefill!,
                        unreconciled: inventory?.receiptReconciled != true,
                      ),
                    ),
                    child: const Text('Plan my next refill'),
                  ),
                ] else if (!refillEnabled) ...[
                  const SizedBox(height: 5),
                  const Text('Refill updates are unavailable for this account.',
                      style: FardaConsumerType.caption),
                ],
                const SizedBox(height: 9),
                SizedBox(width: double.infinity, child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                    side: const BorderSide(color: FardaConsumerColors.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15)),
                  ),
                  onPressed: countEnabled && onUpdateInventory != null
                      ? () => showDialog<void>(
                            context: context,
                            builder: (_) => _CountDialog(
                              prescription: prescription,
                              onUpdateInventory: onUpdateInventory!,
                            ),
                          )
                      : null,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Update my count'),
                )),
                if (!countEnabled) ...[
                  const SizedBox(height: 5),
                  const Text('Count updates are unavailable for this account.',
                      style: FardaConsumerType.caption),
                ],
                if (onOpenRefillTools != null) ...[
                  const SizedBox(height: 2),
                  TextButton(
                    onPressed: onOpenRefillTools,
                    child: const Text('Open account tools'),
                  ),
                ] else ...[
                  const SizedBox(height: 4),
                  const Text(
                    'Refill progress updates are available in your account tools.',
                    style: FardaConsumerType.caption,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _JourneyPill extends StatelessWidget {
  const _JourneyPill({
    required this.label,
    required this.complete,
    required this.current,
  });

  final String label;
  final bool complete;
  final bool current;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$label, ${current ? 'your latest reported step' : complete ? 'you reported this step' : 'not yet reported'}',
    child: ExcludeSemantics(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: current
              ? FardaConsumerColors.brand
              : complete
                  ? FardaConsumerColors.soft
                  : FardaConsumerColors.canvas,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: current
              ? FardaConsumerColors.brand
              : FardaConsumerColors.border),
        ),
        child: Text(label,
          style: FardaConsumerType.caption.copyWith(
            color: current ? Colors.white :
                complete ? FardaConsumerColors.brand :
                FardaConsumerColors.textSecondary,
            fontWeight: current || complete ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    ),
  );
}

class _CountDialog extends StatefulWidget {
  const _CountDialog({required this.prescription, required this.onUpdateInventory});
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
    if (count == null || count < 0 || count > 999) {
      setState(() => _error = 'Enter an actual count from 0 to 999.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    String? error;
    try {
      error = await widget.onUpdateInventory(widget.prescription.id, count);
    } catch (_) {
      error = 'This count was not saved. Please try again.';
    }
    if (!mounted) return;
    if (error != null) {
      setState(() { _saving = false; _error = error; });
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
        const Text('Enter what you counted. This is not a live vial measurement.'),
        const SizedBox(height: 16),
        TextField(
          key: const Key('live-refill-count-input'),
          controller: _text,
          enabled: !_saving,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(3)],
          decoration: InputDecoration(labelText: 'Units counted', errorText: _error),
          onSubmitted: (_) => _save(),
        ),
      ],
    ),
    actions: [
      TextButton(onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel')),
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
    setState(() { _saving = true; _error = null; });
    final next = switch (widget.stage) {
      null || RefillStage.received => RefillStage.planning,
      RefillStage.planning => RefillStage.contacted,
      RefillStage.contacted => RefillStage.ready,
      RefillStage.ready => RefillStage.received,
    };
    String? error;
    try {
      error = await widget.onUpdateRefill(widget.prescription.id, next,
          startNew: widget.stage == RefillStage.received);
    } catch (_) {
      error = 'Your refill update was not saved. Please try again.';
    }
    if (!mounted) return;
    if (error != null) {
      setState(() { _saving = false; _error = error; });
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger.showSnackBar(const SnackBar(content: Text('Your refill update was saved.')));
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
    content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(switch (widget.stage) {
          null => 'Save a plan for ${widget.prescription.name}. This does not contact your pharmacy or submit an order.',
          RefillStage.planning => 'Contact your pharmacy using your label details first. This records only that you contacted them; it does not submit a request.',
          RefillStage.contacted => 'Only record ready after your pharmacy tells you. This is your report, not pharmacy confirmation in Farda.',
          RefillStage.ready => 'Only record this once you actually receive the refill. Your supply count will stay unchanged until you reconcile the receipt.',
          RefillStage.received => widget.unreconciled
              ? 'Your previous receipt is not reconciled. Starting a new plan leaves your last count unchanged and skips that receipt in this view.'
              : 'Start another plan for ${widget.prescription.name}. This does not submit an order.',
        }),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
      ],
    ),
    actions: [
      TextButton(onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Not yet')),
      FilledButton(
        key: const Key('live-refill-confirm-stage'),
        onPressed: _saving ? null : _save,
        child: Text(_saving ? 'Saving…' : switch (widget.stage) {
          null => 'Save my plan',
          RefillStage.planning => 'I contacted them',
          RefillStage.contacted => 'Record my report',
          RefillStage.ready => 'I received it',
          RefillStage.received => widget.unreconciled
              ? 'Skip and start plan' : 'Start my next plan',
        }),
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
      setState(() => _error = 'Enter the actual quantity received, from 1 to 100,000.');
      return;
    }
    if (_alreadyIncluded == null) {
      setState(() => _error = 'Choose whether this refill is already included in your last count.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    String? error;
    try {
      error = await widget.onReconcileReceipt!(widget.prescription.id,
          quantity: quantity, alreadyIncluded: _alreadyIncluded!);
    } catch (_) {
      error = 'The receipt was not saved. Please try again.';
    }
    if (!mounted) return;
    if (error != null) {
      setState(() { _saving = false; _error = error; });
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger.showSnackBar(const SnackBar(content: Text('Your receipt and count were reconciled.')));
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.inventory?.quantity;
    final quantity = int.tryParse(_quantity.text.trim());
    final projected = count == null || _alreadyIncluded == null || quantity == null
        ? null : count + (_alreadyIncluded! ? 0 : quantity);
    final canReconcile = count != null &&
        widget.inventory?.stale != true &&
        widget.onReconcileReceipt != null;
    return AlertDialog(
      title: Text('Reconcile ${widget.prescription.name}'),
      content: SingleChildScrollView(child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(count == null
              ? 'Save a current supply count before reconciling this received refill.'
              : widget.inventory?.stale == true
                  ? 'Your last count is out of date. Recount before reconciling this received refill.'
                  : 'Your last count is $count. Enter what you actually received and whether it is already included in that count.'),
          if (canReconcile) ...[
            const SizedBox(height: 16),
            TextField(
              key: const Key('live-refill-receipt-quantity'),
              controller: _quantity,
              enabled: !_saving,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6)],
              decoration: const InputDecoration(labelText: 'Quantity actually received'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            const Text('Is this refill already in your last count?'),
            RadioListTile<bool>(
              key: const Key('live-refill-receipt-included'),
              title: const Text('Yes, already included'),
              value: true,
              groupValue: _alreadyIncluded,
              onChanged: _saving ? null : (value) => setState(() => _alreadyIncluded = value),
            ),
            RadioListTile<bool>(
              key: const Key('live-refill-receipt-add'),
              title: const Text('No, add received quantity'),
              value: false,
              groupValue: _alreadyIncluded,
              onChanged: _saving ? null : (value) => setState(() => _alreadyIncluded = value),
            ),
            if (projected != null) Text('Count after reconciliation: $projected'),
            const Text('Recount first if your last count is out of date.'),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ],
      )),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('Cancel')),
        if (canReconcile)
          FilledButton(
            key: const Key('live-refill-confirm-receipt'),
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Saving…' : 'Confirm receipt and count'),
          ) else if (widget.onOpenRefillTools != null)
          TextButton(onPressed: () {
            Navigator.pop(context);
            widget.onOpenRefillTools!();
          }, child: const Text('Open account tools')),
      ],
    );
  }
}

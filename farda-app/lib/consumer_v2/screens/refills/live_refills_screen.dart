import 'package:farda/consumer_v2/design_system/farda_consumer_tokens.dart';
import 'package:farda/features/consumer/data/consumer_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

typedef InventoryUpdate = Future<String?> Function(
  String prescriptionId,
  int quantity,
);

/// Account-backed refill view. A pharmacy status is always shown as a user
/// report; neither this view nor a handoff represents an order or confirmation.
class LiveRefillsScreen extends StatelessWidget {
  const LiveRefillsScreen({
    super.key,
    required this.snapshot,
    this.onUpdateInventory,
    this.onOpenRefillTools,
  });

  final ConsumerSnapshot snapshot;
  final InventoryUpdate? onUpdateInventory;
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
              'Your prescriptions, last counts, and the next step you recorded.',
              style: FardaConsumerType.body,
            ),
            const SizedBox(height: 25),
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
                  onOpenRefillTools: onOpenRefillTools,
                ),
                const SizedBox(height: 16),
              ],
            const SizedBox(height: 8),
            FardaConsumerCard(
              color: FardaConsumerColors.warm,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Icon(Icons.shield_outlined,
                      color: FardaConsumerColors.textWarm),
                  SizedBox(height: 9),
                  Text('Your pharmacy confirms your refill',
                      style: FardaConsumerType.title),
                  SizedBox(height: 6),
                  Text(
                    'Farda does not submit an order, check eligibility, or promise a pickup date. Contact your pharmacy or prescriber using the details on your label.',
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
    required this.onOpenRefillTools,
  });

  final ConsumerPrescription prescription;
  final ConsumerInventory? inventory;
  final bool countEnabled;
  final InventoryUpdate? onUpdateInventory;
  final VoidCallback? onOpenRefillTools;

  @override
  Widget build(BuildContext context) {
    final count = inventory?.quantity;
    final estimate = inventory?.stale == true ? null : inventory?.estimatedDays;
    final pharmacy = prescription.pharmacy?.trim();
    final rx = prescription.rxNumber?.trim();
    final stage = inventory?.refillId == null ? null : inventory!.stage;
    return FardaConsumerCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: const BoxDecoration(
              color: FardaConsumerColors.deep,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('YOUR PRESCRIPTION',
                    style: TextStyle(color: Color(0xFFB8C9E4),
                        fontFamily: 'Outfit', fontSize: 10,
                        fontWeight: FontWeight.w600, letterSpacing: 1.2)),
                const SizedBox(height: 10),
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
                const SizedBox(height: 22),
                Text(
                  estimate != null ? '$estimate days estimated' :
                    count != null ? '$count at last count' : 'No count recorded',
                  style: FardaConsumerType.heading.copyWith(color: Colors.white),
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
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Your refill journey', style: FardaConsumerType.title),
                const SizedBox(height: 9),
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
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: countEnabled && onUpdateInventory != null
                      ? () => showDialog<void>(
                            context: context,
                            builder: (_) => _CountDialog(
                              prescription: prescription,
                              onUpdateInventory: onUpdateInventory!,
                            ),
                          )
                      : null,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Update my count'),
                ),
                if (!countEnabled) ...[
                  const SizedBox(height: 5),
                  const Text('Count updates are unavailable for this account.',
                      style: FardaConsumerType.caption),
                ],
                if (onOpenRefillTools != null) ...[
                  const SizedBox(height: 2),
                  TextButton(
                    onPressed: onOpenRefillTools,
                    child: const Text('Plan or update a refill'),
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

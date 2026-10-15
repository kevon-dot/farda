import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'consumer_controller.dart';
import 'consumer_widgets.dart';
import 'data/consumer_models.dart';

class ConsumerPrescriptionForm extends StatefulWidget {
  const ConsumerPrescriptionForm({
    super.key,
    required this.controller,
    this.editing,
  });
  final ConsumerController controller;
  final ConsumerPrescription? editing;
  @override
  State<ConsumerPrescriptionForm> createState() =>
      _ConsumerPrescriptionFormState();
}

class _ConsumerPrescriptionFormState extends State<ConsumerPrescriptionForm> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _directions = TextEditingController();
  final _pharmacy = TextEditingController();
  final _rx = TextEditingController();
  final _days = TextEditingController(text: '30');
  final List<TimeOfDay> _times = [const TimeOfDay(hour: 9, minute: 0)];
  late DateTime _start;
  String _zone = 'America/Los_Angeles';
  bool _review = false;
  bool _confirmed = false;
  bool _saving = false;
  String? _error;
  String _requestId = _newRequestId();
  String? _lastDraftSignature;
  static String _newRequestId() =>
      'consumer-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(0x7fffffff)}';
  @override
  void initState() {
    super.initState();
    _start = ConsumerController.day(widget.controller.clock());
    final existing = widget.editing;
    if (existing != null) {
      _name.text = existing.name;
      _directions.text = existing.directions ?? '';
      _pharmacy.text = existing.pharmacy ?? '';
      _rx.text = existing.rxNumber ?? '';
      _zone = existing.timeZone;
      if (existing.times.isNotEmpty) {
        _times.clear();
        _times.addAll(
          existing.times.map((value) {
            final parts = value.split(':');
            return TimeOfDay(
              hour: int.parse(parts.first),
              minute: int.parse(parts.last),
            );
          }),
        );
      }
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _directions, _pharmacy, _rx, _days]) {
      c.dispose();
    }
    super.dispose();
  }

  String _time(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  ConsumerPrescriptionDraft get _draft => ConsumerPrescriptionDraft(
    name: _name.text,
    directions: _directions.text,
    labelReviewed: _confirmed,
    timeZone: _zone,
    times: _times.map(_time).toList()..sort(),
    startDate: _start,
    durationDays: int.tryParse(_days.text) ?? 0,
    pharmacy: _pharmacy.text,
    rxNumber: _rx.text,
    clientRequestId: _requestId,
  );
  Future<void> _save() async {
    final signatureFields = _draft.toJson()..remove('clientRequestId');
    final signature = jsonEncode(signatureFields);
    if (_lastDraftSignature != signature) {
      _requestId = _newRequestId();
      _lastDraftSignature = signature;
    }
    final draft = _draft;
    if (draft.validationError != null) {
      setState(() => _error = draft.validationError);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final error = await widget.controller.mutate(
      () =>
          widget.editing == null
              ? widget.controller.repository.savePrescription(draft)
              : widget.controller.repository.updateSchedule(
                widget.editing!.id,
                draft,
              ),
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      _error = error;
    });
    if (error == null) Navigator.pop(context, true);
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool required = false,
    int lines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextFormField(
      controller: controller,
      readOnly: widget.editing != null,
      maxLines: lines,
      maxLength: lines > 1 ? 1000 : 200,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(labelText: label, counterText: ''),
      validator:
          required
              ? (v) =>
                  v == null || v.trim().isEmpty ? 'Please enter $label.' : null
              : null,
    ),
  );
  @override
  Widget build(BuildContext context) => _FormShell(
    title:
        _review
            ? 'One final look.'
            : widget.editing != null
            ? 'Adjust your reminders.'
            : 'Make it your routine.',
    subtitle:
        _review
            ? 'Compare these details with your prescription label before saving.'
            : widget.editing != null
            ? 'Changes apply to future reminders. Your past entries stay in your record.'
            : 'Enter the details from your label. You can start without a vial.',
    child: Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!_review) ...[
            _field(_name, 'Medication name', required: true),
            _field(
              _directions,
              'Directions exactly as written',
              required: true,
              lines: 3,
            ),
            _field(_pharmacy, 'Pharmacy or prescriber (optional)'),
            _field(_rx, 'Prescription number (optional)'),
            const ConsumerNotice(
              'If part of the label is unreadable, check with your pharmacy before saving. Farda does not fill in missing directions.',
            ),
            Text(
              'Daily reminder times',
              style: consumerText(17, weight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              'These set reminders. They do not change your prescription directions.',
              style: consumerText(12, color: ConsumerPalette.muted),
            ),
            const SizedBox(height: 12),
            ..._times.asMap().entries.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.schedule_rounded),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(48, 52),
                        ),
                        label: Text(entry.value.format(context)),
                        onPressed: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: entry.value,
                          );
                          if (picked != null && mounted) {
                            setState(() => _times[entry.key] = picked);
                          }
                        },
                      ),
                    ),
                    if (_times.length > 1)
                      IconButton(
                        tooltip: 'Remove reminder time',
                        onPressed:
                            () => setState(() => _times.removeAt(entry.key)),
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                  ],
                ),
              ),
            ),
            if (_times.length < 4)
              TextButton.icon(
                onPressed: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: const TimeOfDay(hour: 20, minute: 0),
                  );
                  if (picked != null && mounted) {
                    setState(() => _times.add(picked));
                  }
                },
                icon: const Icon(Icons.add),
                label: const Text('Add another reminder'),
              ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _zone,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Reminder timezone'),
              items: [
                const DropdownMenuItem(
                  value: 'America/Los_Angeles',
                  child: Text('Pacific · Los Angeles'),
                ),
                const DropdownMenuItem(
                  value: 'America/Denver',
                  child: Text('Mountain · Denver'),
                ),
                const DropdownMenuItem(
                  value: 'America/Chicago',
                  child: Text('Central · Chicago'),
                ),
                const DropdownMenuItem(
                  value: 'America/New_York',
                  child: Text('Eastern · New York'),
                ),
                const DropdownMenuItem(value: 'UTC', child: Text('UTC')),
                if (![
                  'America/Los_Angeles',
                  'America/Denver',
                  'America/Chicago',
                  'America/New_York',
                  'UTC',
                ].contains(_zone))
                  DropdownMenuItem(value: _zone, child: Text(_zone)),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _zone = v);
              },
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () async {
                final today = ConsumerController.day(widget.controller.clock());
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _start,
                  firstDate: today,
                  lastDate: today.add(const Duration(days: 365)),
                );
                if (picked != null && mounted) setState(() => _start = picked);
              },
              icon: const Icon(Icons.calendar_today_outlined),
              label: Text('Starts ${DateFormat.yMMMd().format(_start)}'),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _days,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Create reminders for (days)',
                helperText:
                    'Reminder horizon only; follow your prescription duration.',
              ),
              validator: (v) {
                final n = int.tryParse(v ?? '');
                return n == null || n < 1 || n > 365
                    ? 'Enter 1–365 days.'
                    : null;
              },
            ),
            const SizedBox(height: 24),
            ConsumerButton(
              'Review my routine',
              icon: Icons.arrow_forward_rounded,
              onPressed: () {
                if (_form.currentState!.validate()) {
                  setState(() {
                    _review = true;
                    _error = null;
                  });
                }
              },
            ),
          ] else ...[
            ConsumerCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const ConsumerPill('LABEL REVIEW'),
                  const SizedBox(height: 14),
                  Text(
                    _name.text,
                    style: consumerText(24, weight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  Text(_directions.text, style: consumerText(15)),
                  const Divider(height: 32),
                  Text(
                    'Reminders: ${_times.map((t) => t.format(context)).join(', ')}',
                    style: consumerText(15, weight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Daily · $_zone\n${DateFormat.yMMMd().format(_start)} · ${_days.text} days',
                    style: consumerText(12, color: ConsumerPalette.muted),
                  ),
                  if (_pharmacy.text.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(_pharmacy.text, style: consumerText(13)),
                    ),
                ],
              ),
            ),
            CheckboxListTile(
              value: _confirmed,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                'I checked the medication, directions, and reminder times against my label.',
                style: consumerText(14),
              ),
              onChanged:
                  _saving
                      ? null
                      : (v) => setState(() => _confirmed = v ?? false),
            ),
            const SizedBox(height: 14),
            if (_error != null) ConsumerNotice(_error!, attention: true),
            ConsumerButton(
              'Save my routine',
              busy: _saving,
              onPressed: _confirmed ? _save : null,
            ),
            TextButton(
              onPressed: _saving ? null : () => setState(() => _review = false),
              child: const Text('Go back and edit'),
            ),
          ],
        ],
      ),
    ),
  );
}

class ConsumerEntryForm extends StatefulWidget {
  const ConsumerEntryForm({
    super.key,
    required this.controller,
    required this.occurrence,
    required this.medicationName,
    this.noteOnly = false,
  });
  final ConsumerController controller;
  final ConsumerOccurrence occurrence;
  final String medicationName;
  final bool noteOnly;
  @override
  State<ConsumerEntryForm> createState() => _ConsumerEntryFormState();
}

class _ConsumerEntryFormState extends State<ConsumerEntryForm> {
  late OccurrenceStatus _status;
  late DateTime _takenAt;
  late TextEditingController _note;
  final _reason = TextEditingController();
  bool _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _status =
        widget.occurrence.status == OccurrenceStatus.unconfirmed
            ? OccurrenceStatus.taken
            : widget.occurrence.status;
    _takenAt =
        widget.occurrence.recordedAt?.toLocal() ?? widget.controller.clock();
    _note = TextEditingController(text: widget.occurrence.note);
  }

  @override
  void dispose() {
    _note.dispose();
    _reason.dispose();
    super.dispose();
  }

  bool get _correction =>
      !widget.noteOnly &&
      widget.occurrence.status != OccurrenceStatus.unconfirmed;
  Future<void> _save() async {
    if (_correction && _reason.text.trim().isEmpty) {
      setState(() => _error = 'Add a short reason for this correction.');
      return;
    }
    if (!widget.noteOnly &&
        _status == OccurrenceStatus.taken &&
        _takenAt.isAfter(widget.controller.clock())) {
      setState(
        () =>
            _error = 'Choose the time you already took it, not a future time.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final update = ConsumerOccurrenceUpdate(
      id: widget.occurrence.id,
      expectedRevision: widget.occurrence.revision,
      status: widget.noteOnly ? null : _status,
      takenAt:
          !widget.noteOnly && _status == OccurrenceStatus.taken
              ? _takenAt
              : null,
      note: _note.text.trim(),
      reason: _reason.text.trim().isEmpty ? null : _reason.text.trim(),
    );
    final error = await widget.controller.mutate(
      () => widget.controller.repository.recordOccurrence(update),
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      _error = error;
    });
    if (error == null) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => _FormShell(
    title:
        widget.noteOnly
            ? 'A note for yourself.'
            : _correction
            ? 'Let’s correct that.'
            : 'Your check-in.',
    subtitle: widget.medicationName,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConsumerNotice(
          widget.noteOnly
              ? 'A note does not change whether a dose is recorded as taken.'
              : 'This entry records what you tell us. Answering a call or moving a vial does not log a dose.',
        ),
        if (!widget.noteOnly) ...[
          RadioGroup<OccurrenceStatus>(
            groupValue: _status,
            onChanged: (value) {
              if (!_saving && value != null) setState(() => _status = value);
            },
            child: Column(
              children:
                  <OccurrenceStatus, String>{
                        OccurrenceStatus.taken: 'I already took it',
                        OccurrenceStatus.skipped: 'Record as skipped',
                        OccurrenceStatus.unconfirmed: 'Leave unconfirmed',
                      }.entries
                      .map(
                        (item) => RadioListTile<OccurrenceStatus>(
                          value: item.key,
                          contentPadding: EdgeInsets.zero,
                          title: Text(item.value, style: consumerText(16)),
                          enabled: !_saving,
                        ),
                      )
                      .toList(),
            ),
          ),
          if (_status == OccurrenceStatus.taken) ...[
            const SizedBox(height: 12),
            Text(
              'When you took it',
              style: consumerText(13, weight: FontWeight.w600),
            ),
            Wrap(
              spacing: 10,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.calendar_today_outlined, size: 18),
                  label: Text(DateFormat.yMMMd().format(_takenAt)),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: ConsumerController.day(_takenAt),
                      firstDate: DateTime(2020),
                      lastDate: widget.controller.clock(),
                    );
                    if (picked != null && mounted) {
                      setState(
                        () =>
                            _takenAt = DateTime(
                              picked.year,
                              picked.month,
                              picked.day,
                              _takenAt.hour,
                              _takenAt.minute,
                            ),
                      );
                    }
                  },
                ),
                TextButton.icon(
                  icon: const Icon(Icons.schedule, size: 18),
                  label: Text(DateFormat.jm().format(_takenAt)),
                  onPressed: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.fromDateTime(_takenAt),
                    );
                    if (picked != null && mounted) {
                      setState(
                        () =>
                            _takenAt = DateTime(
                              _takenAt.year,
                              _takenAt.month,
                              _takenAt.day,
                              picked.hour,
                              picked.minute,
                            ),
                      );
                    }
                  },
                ),
              ],
            ),
          ],
        ],
        const SizedBox(height: 18),
        TextField(
          controller: _note,
          maxLines: 3,
          maxLength: 1000,
          decoration: const InputDecoration(
            labelText: 'Note (optional)',
            alignLabelWithHint: true,
          ),
        ),
        if (_correction)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: TextField(
              controller: _reason,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'Reason for correction',
              ),
            ),
          ),
        const SizedBox(height: 18),
        if (_error != null) ConsumerNotice(_error!, attention: true),
        ConsumerButton(
          widget.noteOnly
              ? 'Save note only'
              : _correction
              ? 'Save correction'
              : _status == OccurrenceStatus.taken
              ? 'Confirm: I already took it'
              : _status == OccurrenceStatus.skipped
              ? 'Confirm skipped entry'
              : 'Keep unconfirmed',
          busy: _saving,
          onPressed: _save,
        ),
      ],
    ),
  );
}

class ConsumerCountForm extends StatefulWidget {
  const ConsumerCountForm({
    super.key,
    required this.controller,
    required this.prescription,
  });
  final ConsumerController controller;
  final ConsumerPrescription prescription;
  @override
  State<ConsumerCountForm> createState() => _ConsumerCountFormState();
}

class _ConsumerCountFormState extends State<ConsumerCountForm> {
  final _count = TextEditingController();
  String? _error;
  bool _saving = false;
  @override
  void dispose() {
    _count.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _FormShell(
    title: 'Count what’s here.',
    subtitle: widget.prescription.name,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ConsumerNotice(
          'Enter your current total supply, including any refill you already added. This replaces the last count; it does not add to it.',
        ),
        TextField(
          controller: _count,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Current total quantity',
            hintText: '0',
          ),
        ),
        const SizedBox(height: 20),
        if (_error != null) ConsumerNotice(_error!, attention: true),
        ConsumerButton(
          'Save my confirmed count',
          busy: _saving,
          onPressed: () async {
            final count = int.tryParse(_count.text);
            if (count == null || count < 0 || count > 100000) {
              setState(
                () => _error = 'Enter a whole number from 0 to 100,000.',
              );
              return;
            }
            setState(() {
              _saving = true;
              _error = null;
            });
            final error = await widget.controller.mutate(
              () => widget.controller.repository.updateInventory(
                widget.prescription.id,
                count,
              ),
            );
            if (!mounted) return;
            setState(() {
              _saving = false;
              _error = error;
            });
            if (error == null && context.mounted) Navigator.pop(context, true);
          },
        ),
      ],
    ),
  );
}

class ConsumerReceiptForm extends StatefulWidget {
  const ConsumerReceiptForm({
    super.key,
    required this.controller,
    required this.prescription,
  });
  final ConsumerController controller;
  final ConsumerPrescription prescription;
  @override
  State<ConsumerReceiptForm> createState() => _ConsumerReceiptFormState();
}

class _ConsumerReceiptFormState extends State<ConsumerReceiptForm> {
  final _quantity = TextEditingController();
  bool _alreadyIncluded = true;
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    _quantity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current =
        widget.controller.snapshot?.supply(widget.prescription.id)?.quantity;
    final received = int.tryParse(_quantity.text);
    final total =
        current == null
            ? null
            : _alreadyIncluded
            ? current
            : received == null
            ? null
            : current + received;
    return _FormShell(
      title: 'Let’s count it once.',
      subtitle: widget.prescription.name,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConsumerNotice(
            'Your last confirmed count is ${current ?? 'unknown'}. Record the quantity you actually received and tell us whether it is already in that count.',
          ),
          TextField(
            controller: _quantity,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Quantity received in this refill',
            ),
          ),
          const SizedBox(height: 16),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _alreadyIncluded,
            onChanged:
                _saving
                    ? null
                    : (value) =>
                        setState(() => _alreadyIncluded = value ?? true),
            title: Text(
              'This refill is already included in my last count.',
              style: consumerText(14),
            ),
          ),
          const SizedBox(height: 16),
          ConsumerCard(
            color: ConsumerPalette.pale,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  total == null
                      ? 'Enter the received quantity.'
                      : 'Count after reconciliation: $total',
                  style: consumerText(19, weight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  _alreadyIncluded
                      ? 'The receipt is recorded without adding stock again.'
                      : 'The received quantity will be added to your last count. Recount first if that count is out of date.',
                  style: consumerText(12, color: ConsumerPalette.muted),
                ),
              ],
            ),
          ),
          if (_error != null) ConsumerNotice(_error!, attention: true),
          ConsumerButton(
            'Confirm receipt and count',
            busy: _saving,
            onPressed: () async {
              final quantity = int.tryParse(_quantity.text);
              if (quantity == null || quantity < 1 || quantity > 100000) {
                setState(
                  () =>
                      _error =
                          'Enter the quantity you received, from 1 to 100,000.',
                );
                return;
              }
              setState(() {
                _saving = true;
                _error = null;
              });
              final error = await widget.controller.mutate(
                () => widget.controller.repository.reconcileReceipt(
                  widget.prescription.id,
                  quantity: quantity,
                  alreadyIncluded: _alreadyIncluded,
                ),
              );
              if (!mounted) return;
              setState(() {
                _saving = false;
                _error = error;
              });
              if (error == null && context.mounted) {
                Navigator.pop(context, true);
              }
            },
          ),
        ],
      ),
    );
  }
}

class _FormShell extends StatelessWidget {
  const _FormShell({
    required this.title,
    required this.subtitle,
    required this.child,
  });
  final String title;
  final String subtitle;
  final Widget child;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 4,
                  decoration: BoxDecoration(
                    color: ConsumerPalette.line,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            ConsumerHeading(title, subtitle: subtitle),
            child,
          ],
        ),
      ),
    ),
  );
}

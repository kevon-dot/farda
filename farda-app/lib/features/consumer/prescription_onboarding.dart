import 'dart:convert';
import 'dart:math';

import 'package:farda/application/authentication/storage/auth_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'consumer_controller.dart';
import 'consumer_widgets.dart';
import 'data/consumer_models.dart';
import 'data/label_scan.dart';
import 'guided_label_capture.dart';

/// Camera and manual entry share one editable draft. Nothing is written until
/// the user reviews the label and explicitly saves the supported schedule.
class PrescriptionOnboarding extends StatefulWidget {
  const PrescriptionOnboarding({
    super.key,
    required this.controller,
    this.scanLabel,
  });
  final ConsumerController controller;
  final Future<LabelScanDraft?> Function(BuildContext context)? scanLabel;

  @override
  State<PrescriptionOnboarding> createState() => _PrescriptionOnboardingState();
}

class _PrescriptionOnboardingState extends State<PrescriptionOnboarding> {
  final _name = TextEditingController();
  final _directions = TextEditingController();
  final _pharmacy = TextEditingController();
  final _rx = TextEditingController();
  final _days = TextEditingController(text: '30');
  final _scroll = ScrollController();
  final _times = <TimeOfDay>[];
  late DateTime _start;
  String _zone = 'America/Los_Angeles';
  int _step = 0;
  bool? _daily;
  bool _confirmed = false;
  bool _saving = false;
  bool _scanning = false;
  bool _scanned = false;
  bool _sessionEnded = false;
  late final int _sessionRevision;
  int _scanGeneration = 0;
  String? get _scanNotice {
    if (!_scanned) return null;
    final missing = <String>[
      if (_name.text.trim().isEmpty) 'medication name and strength',
      if (_directions.text.trim().isEmpty) 'complete directions',
    ];
    return missing.isEmpty
        ? 'Scan added. Check every field against your label; scans can miss or misread text.'
        : 'Still needed: ${missing.join(' and ')}. Copy this from your label, scan another section, or ask your pharmacy if it is unclear.';
  }

  String? _error;
  String? _signature;
  String _requestId = _newRequestId();
  static String _newRequestId() =>
      'consumer-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(0x7fffffff)}';

  @override
  void initState() {
    super.initState();
    _start = ConsumerController.day(widget.controller.clock());
    _sessionRevision = AuthStorage.sessionRevision.value;
    _sessionEnded = widget.controller.sessionExpired;
    AuthStorage.sessionRevision.addListener(_checkSession);
    widget.controller.addListener(_checkSession);
  }

  void _checkSession() {
    // A successful reload for another account can leave sessionExpired false.
    // This draft belongs permanently to the session that opened it.
    if (!mounted ||
        _sessionEnded ||
        (!widget.controller.sessionExpired &&
            AuthStorage.sessionRevision.value == _sessionRevision)) {
      return;
    }
    ++_scanGeneration;
    for (final field in [_name, _directions, _pharmacy, _rx, _days]) {
      field.clear();
    }
    setState(() {
      _sessionEnded = true;
      _times.clear();
      _confirmed = false;
      _scanned = false;
    });
  }

  @override
  void dispose() {
    ++_scanGeneration;
    widget.controller.removeListener(_checkSession);
    AuthStorage.sessionRevision.removeListener(_checkSession);
    for (final field in [_name, _directions, _pharmacy, _rx, _days]) {
      field.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  void _go(int step) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _step = step;
      _error = null;
      _confirmed = false;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _scan() async {
    if (_scanning || _sessionEnded) return;
    final generation = ++_scanGeneration;
    setState(() => _scanning = true);
    try {
      final draft =
          await (widget.scanLabel?.call(context) ??
              Navigator.of(context).push<LabelScanDraft>(
                MaterialPageRoute(
                  builder:
                      (_) => GuidedLabelCaptureScreen(
                        controller: widget.controller,
                      ),
                ),
              ));
      if (!mounted ||
          _sessionEnded ||
          generation != _scanGeneration ||
          draft == null) {
        return;
      }
      // A rescan may fill blanks, but must never replace the user's corrections.
      void fill(TextEditingController field, String? candidate) {
        if (field.text.trim().isEmpty && candidate != null) {
          field.text = candidate;
        }
      }

      fill(_name, draft.medicationName);
      fill(_directions, draft.directions);
      fill(_pharmacy, draft.pharmacy);
      fill(_rx, draft.rxNumber);
      _scanned = !draft.manualEntry;
      _go(_step == 0 ? 1 : _step);
    } catch (_) {
      if (mounted && !_sessionEnded && generation == _scanGeneration) {
        setState(
          () =>
              _error =
                  'We could not open the scan. You can enter the label details instead.',
        );
      }
    } finally {
      if (mounted && generation == _scanGeneration) {
        setState(() => _scanning = false);
      }
    }
  }

  String _time(TimeOfDay value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  ConsumerPrescriptionDraft get _draft => ConsumerPrescriptionDraft(
    name: _name.text,
    directions: _directions.text,
    pharmacy: _pharmacy.text,
    rxNumber: _rx.text,
    labelReviewed: _confirmed,
    remindersEnabled: _daily == true,
    timeZone: _zone,
    times: _times.map(_time).toList()..sort(),
    startDate: _start,
    durationDays: int.tryParse(_days.text) ?? 0,
    clientRequestId: _requestId,
  );

  void _next() {
    String? error;
    if (_step == 1 &&
        (_name.text.trim().isEmpty || _name.text.trim().length > 200)) {
      error =
          'Enter the medication name and any strength printed on your label.';
    } else if (_step == 2 &&
        (_directions.text.trim().isEmpty ||
            _directions.text.trim().length > 2000)) {
      error =
          _directions.text.trim().isEmpty
              ? 'Copy the complete directions. If they are unclear, check with your pharmacy.'
              : 'Directions exceed the 2,000-character limit. Your full text is preserved; review before saving.';
    } else if (_step == 3 &&
        (_pharmacy.text.trim().length > 200 || _rx.text.trim().length > 100)) {
      error =
          'Use up to 200 characters for the pharmacy and 100 for the prescription number.';
    } else if (_step == 4 && _daily != false) {
      if (_daily == null) {
        error = 'Choose daily reminders or save without daily reminders.';
      } else if (_times.isEmpty) {
        error = 'Choose at least one reminder time.';
      } else if (_times.map(_time).toSet().length != _times.length) {
        error = 'Choose different times for each reminder.';
      } else if ((int.tryParse(_days.text) ?? 0) < 1 ||
          (int.tryParse(_days.text) ?? 0) > 365) {
        error = 'Choose a reminder period from 1 to 365 days.';
      }
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    _go(_step + 1);
  }

  Future<void> _save() async {
    if (_saving || _sessionEnded || !_confirmed || _daily == null) return;
    final fields = _draft.toJson()..remove('clientRequestId');
    final signature = jsonEncode(fields);
    if (_signature != signature) {
      _requestId = _newRequestId();
      _signature = signature;
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
      () => widget.controller.repository.savePrescription(draft),
    );
    if (!mounted || _sessionEnded) return;
    setState(() {
      _saving = false;
      _error = error;
    });
    if (error == null) _go(6);
  }

  Future<void> _pickTime([int? index]) async {
    final result = await showTimePicker(
      context: context,
      initialTime:
          index == null ? const TimeOfDay(hour: 9, minute: 0) : _times[index],
    );
    if (result != null && mounted && !_sessionEnded) {
      setState(() {
        if (index == null) {
          _times.add(result);
        } else {
          _times[index] = result;
        }
        _confirmed = false;
      });
    }
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    String? hint,
    int lines = 1,
    int limit = 200,
  }) => TextField(
    controller: controller,
    maxLength: limit,
    maxLengthEnforcement: MaxLengthEnforcement.none,
    minLines: lines,
    maxLines: lines == 1 ? 3 : 10,
    textCapitalization: TextCapitalization.sentences,
    autocorrect: false,
    enableSuggestions: false,
    onChanged: (_) => setState(() => _confirmed = false),
    decoration: InputDecoration(
      labelText: label,
      alignLabelWithHint: true,
      hintText: hint,
    ),
  );

  Widget _primary(
    String label, {
    VoidCallback? onPressed,
    bool busy = false,
    IconData? icon,
  }) => FilledButton(
    onPressed: busy ? null : onPressed,
    style: FilledButton.styleFrom(
      minimumSize: const Size(double.infinity, 54),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      backgroundColor: const Color(0xFFBDEBD9),
      foregroundColor: ConsumerPalette.navy,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    child: Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      children: [
        if (busy)
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        Text(
          label,
          textAlign: TextAlign.center,
          style: consumerText(16, weight: FontWeight.w600),
        ),
        if (icon != null && !busy) Icon(icon, size: 20),
      ],
    ),
  );

  Widget _choice(
    String title,
    String subtitle,
    IconData icon,
    VoidCallback? action, {
    bool selected = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Material(
      color: selected ? ConsumerPalette.pale : Colors.white,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: action,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Icon(icon, color: ConsumerPalette.navy, size: 26),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: consumerText(18, weight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: consumerText(13, color: ConsumerPalette.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.chevron_right_rounded,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    ),
  );

  List<Widget> _body() {
    switch (_step) {
      case 0:
        return [
          const Center(child: ConsumerCompanion(size: 116)),
          const SizedBox(height: 16),
          _choice(
            'Scan label',
            'Long label? Capture it in sections.',
            Icons.document_scanner_outlined,
            _scanning ? null : _scan,
          ),
          _choice(
            'Enter manually',
            'A few small steps. No camera needed.',
            Icons.edit_outlined,
            _scanning ? null : () => _go(1),
          ),
          if (_scanning) const Center(child: CircularProgressIndicator()),
          Text(
            'You will review everything before saving.',
            style: consumerText(13, color: ConsumerPalette.muted),
            textAlign: TextAlign.center,
          ),
        ];
      case 1:
        return [
          _field(
            _name,
            'Medication name + strength',
            hint: 'Exactly as printed',
          ),
          const SizedBox(height: 14),
          if (_scanned)
            const ConsumerNotice(
              'Check the spelling, strength and formulation against your label. Scans can miss text.',
            ),
          Text(
            'Keep the printed strength and formulation with the name.',
            style: consumerText(14, color: ConsumerPalette.muted),
          ),
          TextButton.icon(
            onPressed: _scanning ? null : _scan,
            icon: const Icon(Icons.document_scanner_outlined),
            label: const Text('Scan another section'),
          ),
          Text(
            'A new scan fills empty fields; your edits stay as they are.',
            style: consumerText(12, color: ConsumerPalette.muted),
          ),
        ];
      case 2:
        return [
          _field(
            _directions,
            'Complete directions',
            lines: 5,
            limit: 2000,
            hint: 'Copy every instruction from the label',
          ),
          const SizedBox(height: 16),
          const ConsumerNotice(
            'Include text that continues around the bottle. If anything is unclear, check with your pharmacy; Farda will not fill in missing instructions.',
          ),
          TextButton.icon(
            onPressed: _scanning ? null : _scan,
            icon: const Icon(Icons.document_scanner_outlined),
            label: const Text('Scan another section'),
          ),
        ];
      case 3:
        return [
          _field(_pharmacy, 'Pharmacy (optional)'),
          const SizedBox(height: 16),
          _field(_rx, 'Prescription number (optional)', limit: 100),
          const SizedBox(height: 16),
          ConsumerCard(
            color: ConsumerPalette.warm,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.local_pharmacy_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Keep these handy for refill help. Adding a pharmacy does not connect to it or send a request.',
                    style: consumerText(14),
                  ),
                ),
              ],
            ),
          ),
        ];
      case 4:
        return [
          _choice(
            'Daily',
            'The same reminder times each day.',
            Icons.schedule_rounded,
            () => setState(() => _daily = true),
            selected: _daily == true,
          ),
          _choice(
            'No daily reminders',
            'For as-needed or changing schedules.',
            Icons.tune_rounded,
            () => setState(() => _daily = false),
            selected: _daily == false,
          ),
          if (_daily == false) ...[
            const ConsumerNotice(
              'We will save your medication and label details without a reminder schedule. Follow your prescription directions; Farda will not infer times or doses.',
            ),
          ],
          if (_daily == true) ...[
            Text(
              'Reminders do not change your prescribed directions.',
              style: consumerText(13, color: ConsumerPalette.muted),
            ),
            const SizedBox(height: 14),
            for (final entry in _times.asMap().entries)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickTime(entry.key),
                      icon: const Icon(Icons.schedule),
                      label: Text(entry.value.format(context)),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove reminder time',
                    onPressed: () => setState(() => _times.removeAt(entry.key)),
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                ],
              ),
            if (_times.length < 4)
              OutlinedButton.icon(
                onPressed: _pickTime,
                icon: const Icon(Icons.add),
                label: const Text('Choose reminder time'),
              ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _zone,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Reminder timezone'),
              items: const [
                DropdownMenuItem(
                  value: 'America/Los_Angeles',
                  child: Text('Pacific · Los Angeles'),
                ),
                DropdownMenuItem(
                  value: 'America/Denver',
                  child: Text('Mountain · Denver'),
                ),
                DropdownMenuItem(
                  value: 'America/Chicago',
                  child: Text('Central · Chicago'),
                ),
                DropdownMenuItem(
                  value: 'America/New_York',
                  child: Text('Eastern · New York'),
                ),
                DropdownMenuItem(value: 'UTC', child: Text('UTC')),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _zone = value);
              },
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final today = ConsumerController.day(widget.controller.clock());
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _start.isBefore(today) ? today : _start,
                  firstDate: today,
                  lastDate: DateTime(today.year + 1, today.month, today.day),
                );
                if (picked != null && mounted && !_sessionEnded) {
                  setState(() => _start = picked);
                }
              },
              icon: const Icon(Icons.calendar_today_outlined),
              label: Text('Starts ${DateFormat.yMMMd().format(_start)}'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _days,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Reminder period (days)',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '1–365 days. This is a reminder period, not a prescription duration.',
              style: consumerText(12, color: ConsumerPalette.muted),
            ),
          ],
        ];
      case 5:
        return [
          ConsumerCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ConsumerPill('YOUR LABEL'),
                const SizedBox(height: 12),
                Text(
                  _name.text,
                  style: consumerText(24, weight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                Text(_directions.text, style: consumerText(15)),
                if (_pharmacy.text.trim().isNotEmpty) ...[
                  const Divider(height: 28),
                  Text('Pharmacy: ${_pharmacy.text}', style: consumerText(14)),
                ],
                if (_rx.text.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('Rx: ${_rx.text}', style: consumerText(14)),
                ],
                const Divider(height: 28),
                Text(
                  _daily == true ? 'Daily reminders' : 'No daily reminders',
                  style: consumerText(16, weight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                if (_daily == true)
                  Text(
                    _times.map((time) => time.format(context)).join(' · '),
                    style: consumerText(18),
                  ),
                if (_daily == true)
                  Text(
                    '$_zone\nStarts ${DateFormat.yMMMd().format(_start)} · ${_days.text} days',
                    style: consumerText(13, color: ConsumerPalette.muted),
                  ),
              ],
            ),
          ),
          CheckboxListTile(
            value: _confirmed,
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: Text(
              _daily == true
                  ? 'I checked the complete label, directions and reminder times.'
                  : 'I checked the medication and complete directions against my label.',
              style: consumerText(14),
            ),
            onChanged:
                _saving
                    ? null
                    : (value) => setState(() => _confirmed = value ?? false),
          ),
        ];
      default:
        return [
          const Center(child: ConsumerCompanion(size: 116)),
          const SizedBox(height: 16),
          ConsumerCard(
            color: ConsumerPalette.pale,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _name.text,
                  style: consumerText(22, weight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  _daily == true
                      ? 'Daily · ${_times.map((time) => time.format(context)).join(' · ')}'
                      : 'Saved without daily reminders',
                  style: consumerText(16),
                ),
              ],
            ),
          ),
          const ConsumerNotice(
            'Next, add your remaining count in Refills for a supply estimate. No pharmacy request has been sent.',
          ),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    const titles = [
      'A little setup. A steadier day.',
      'What’s on your label?',
      'Every word matters.',
      'Your pharmacy, handy.',
      'Make room for reminders.',
      'One final look.',
      'Your medication is saved.',
    ];
    const subtitles = [
      'Add your medication, your way.',
      'Keep the name and strength together.',
      'Copy the directions exactly as printed.',
      'Optional now. Useful at refill time.',
      'Choose what matches your prescription.',
      'Compare everything with your label.',
      'One less thing to keep in your head.',
    ];
    if (_sessionEnded) {
      return Theme(
        data: ConsumerPalette.theme,
        child: Scaffold(
          appBar: AppBar(title: const Text('Session ended')),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  'Sign in again to continue',
                  style: consumerText(28, weight: FontWeight.w600),
                ),
                const SizedBox(height: 16),
                Text(
                  'Your session ended. This unsaved draft has been cleared.',
                  style: consumerText(16),
                ),
                const SizedBox(height: 24),
                _primary(
                  'Close setup',
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Theme(
      data: ConsumerPalette.theme,
      child: PopScope(
        canPop: !_saving && (_step == 0 || _step == 6),
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && !_saving && _step > 0 && _step < 6) _go(_step - 1);
        },
        child: Scaffold(
          backgroundColor: ConsumerPalette.cream,
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                      child: Row(
                        children: [
                          IconButton(
                            tooltip:
                                _step == 0 || _step == 6 ? 'Close' : 'Back',
                            onPressed:
                                _saving || _scanning
                                    ? null
                                    : () {
                                      if (_step == 0 || _step == 6) {
                                        Navigator.pop(context, _step == 6);
                                      } else {
                                        _go(_step - 1);
                                      }
                                    },
                            icon: Icon(
                              _step == 0 || _step == 6
                                  ? Icons.close
                                  : Icons.arrow_back,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              _step > 0 && _step < 6
                                  ? 'Step $_step of 5'
                                  : 'YOUR ROUTINE',
                              textAlign: TextAlign.center,
                              style: consumerText(12, weight: FontWeight.w600),
                            ),
                          ),
                          const SizedBox(width: 48),
                        ],
                      ),
                    ),
                    if (_step > 0 && _step < 6)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                        child: LinearProgressIndicator(
                          value: _step / 5,
                          minHeight: 4,
                          borderRadius: BorderRadius.circular(4),
                          backgroundColor: ConsumerPalette.line,
                          color: ConsumerPalette.navy,
                        ),
                      ),
                    Expanded(
                      child: SingleChildScrollView(
                        controller: _scroll,
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              titles[_step],
                              style: consumerText(
                                30,
                                weight: FontWeight.w600,
                                height: 1.15,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              subtitles[_step],
                              style: consumerText(
                                15,
                                color: ConsumerPalette.muted,
                              ),
                            ),
                            const SizedBox(height: 24),
                            if (_scanNotice != null &&
                                (_step == 1 || _step == 2)) ...[
                              Semantics(
                                liveRegion: true,
                                child: ConsumerNotice(_scanNotice!),
                              ),
                              const SizedBox(height: 16),
                            ],
                            ..._body(),
                            if (_error != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Semantics(
                                  liveRegion: true,
                                  child: ConsumerNotice(
                                    _error!,
                                    attention: true,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 20),
                            if (_step > 0 && _step < 5)
                              _primary(
                                _step == 3
                                    ? 'Continue'
                                    : _step == 4
                                    ? 'Review my routine'
                                    : 'Continue',
                                onPressed: _scanning ? null : _next,
                                icon: Icons.arrow_forward_rounded,
                              ),
                            if (_step == 5)
                              _primary(
                                'Save my routine',
                                busy: _saving,
                                onPressed:
                                    _confirmed && !_saving ? _save : null,
                              ),
                            if (_step == 5)
                              TextButton(
                                onPressed: _saving ? null : () => _go(1),
                                child: const Text('Go back and edit'),
                              ),
                            if (_step == 6)
                              _primary(
                                'Done',
                                onPressed: () => Navigator.pop(context, true),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

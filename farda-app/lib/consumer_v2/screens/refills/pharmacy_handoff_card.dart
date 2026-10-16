import 'package:farda/application/authentication/storage/auth_storage.dart';
import 'package:farda/consumer_v2/design_system/farda_consumer_tokens.dart';
import 'package:farda/features/consumer/data/consumer_models.dart';
import 'package:farda/features/consumer/data/pharmacy_handoff.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'pharmacy_navigation.dart';

class PharmacyHandoffCard extends StatefulWidget {
  const PharmacyHandoffCard({
    super.key,
    required this.prescriptionId,
    required this.repository,
    required this.medicationName,
    this.rxNumber,
    this.savedPharmacy,
    this.openUrl,
    this.onPurposeChanged,
  });
  final String prescriptionId;
  final PharmacyHandoffRepository repository;
  final String medicationName;
  final String? rxNumber;
  final String? savedPharmacy;
  final Future<bool> Function(Uri)? openUrl;
  final ValueChanged<String>? onPurposeChanged;
  @override
  State<PharmacyHandoffCard> createState() => _PharmacyHandoffCardState();
}

class _PharmacyHandoffCardState extends State<PharmacyHandoffCard> {
  List<PharmacyDestination> _directory = [];
  PharmacyDestination? _selected;
  PharmacyHandoff? _handoff;
  Future<bool> Function()? _session;
  String _purpose = 'refill';
  String? _error;
  bool _busy = true;
  bool _acting = false;
  bool _manualLink = false;
  bool _invalidSession = false;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    AuthStorage.sessionRevision.addListener(_invalidateSession);
    _load();
  }

  void _invalidateSession() {
    ++_generation;
    if (!mounted) return;
    setState(() {
      _session = null;
      _handoff = null;
      _selected = null;
      _directory = [];
      _busy = false;
      _acting = false;
      _invalidSession = true;
      _error = 'Your account session changed. Refresh to continue.';
    });
  }

  @override
  void dispose() {
    AuthStorage.sessionRevision.removeListener(_invalidateSession);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PharmacyHandoffCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.prescriptionId != widget.prescriptionId) {
      _load();
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
      _handoff = null;
      _selected = null;
      _directory = [];
      _session = null;
      _manualLink = false;
      _acting = false;
      _invalidSession = false;
    });
    try {
      final session = await widget.repository.capturePharmacySession();
      final directory = await widget.repository.loadPharmacyDirectory();
      if (!mounted || generation != _generation) return;
      if (!await session()) {
        throw const ConsumerRepositoryException(
          'Sign in again to continue.',
          sessionExpired: true,
        );
      }
      if (!mounted || generation != _generation) return;
      setState(() {
        _directory = directory;
        _session = session;
        final matches =
            directory.where((p) => p.matches(widget.savedPharmacy)).toList();
        _selected = matches.length == 1 ? matches.single : null;
        _busy = false;
      });
      if (_selected != null) await _prepare();
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _busy = false;
          _error = _message(error);
        });
      }
    }
  }

  String _message(Object error) =>
      error is ConsumerRepositoryException && error.sessionExpired
          ? error.message
          : 'Pharmacy links are unavailable. Use the number on your label or copy a request below.';
  Future<void> _prepare() async {
    final selected = _selected;
    if (selected == null) return;
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _handoff = null;
      _error = null;
      _manualLink = false;
    });
    try {
      final handoff = await widget.repository.preparePharmacyHandoff(
        widget.prescriptionId,
        pharmacyId: selected.id,
        purpose: _purpose,
      );
      if (!mounted || generation != _generation) return;
      if (_session == null || !await _session!()) {
        _invalidateSession();
        return;
      }
      if (!mounted || generation != _generation) return;
      if (handoff.pharmacyId != selected.id || handoff.purpose != _purpose) {
        throw StateError('Mismatched handoff');
      }
      if (handoff.mode == 'external_site' &&
          !handoff.hasSafeDestination(selected)) {
        throw StateError('Unverified destination');
      }
      setState(() {
        _handoff = handoff;
        _busy = false;
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _busy = false;
          _error = _message(error);
        });
      }
    }
  }

  Future<void> _act(Future<void> Function() action) async {
    if (_acting || _busy) return;
    final generation = _generation;
    setState(() => _acting = true);
    try {
      if (_session == null || !await _session!()) {
        _invalidateSession();
        return;
      }
      if (!mounted || generation != _generation) return;
      await action();
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _handoff = null;
          _error = _message(error);
        });
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _acting = false);
    }
  }

  Future<void> _copy(String value, String message) => _act(() async {
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  });
  @override
  Widget build(BuildContext context) {
    if (_invalidSession) {
      return FardaConsumerCard(
        child: Text(
          _error ?? 'Sign in again to continue.',
          style: FardaConsumerType.body,
        ),
      );
    }
    final handoff = _handoff;
    final safe =
        handoff != null &&
        _selected != null &&
        handoff.hasSafeDestination(_selected!);
    return FardaConsumerCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('YOUR PHARMACY', style: FardaConsumerType.label),
          const SizedBox(height: 8),
          const Text(
            'Finish with your pharmacy',
            style: FardaConsumerType.title,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey('pharmacy-choice-${_selected?.id}'),
            initialValue: _selected?.id,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Pharmacy'),
            items:
                _directory
                    .map(
                      (p) => DropdownMenuItem(
                        value: p.id,
                        child: Text(p.name, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
            onChanged:
                _busy || _acting
                    ? null
                    : (id) {
                      setState(
                        () =>
                            _selected = _directory.firstWhere(
                              (p) => p.id == id,
                            ),
                      );
                      _prepare();
                    },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: const Key('pharmacy-purpose'),
            initialValue: _purpose,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'What do you need?'),
            items: const [
              DropdownMenuItem(value: 'refill', child: Text('Refill')),
              DropdownMenuItem(value: 'renewal', child: Text('Renewal')),
              DropdownMenuItem(value: 'transfer', child: Text('Transfer')),
              DropdownMenuItem(
                value: 'new_rx',
                child: Text('New prescription'),
              ),
            ],
            onChanged:
                _busy || _acting
                    ? null
                    : (value) {
                      setState(() => _purpose = value!);
                      widget.onPurposeChanged?.call(_purpose);
                      _prepare();
                    },
          ),
          const SizedBox(height: 14),
          Text(widget.medicationName, style: FardaConsumerType.bodyStrong),
          if (widget.rxNumber?.trim().isNotEmpty == true) ...[
            SelectableText(
              'Rx ${widget.rxNumber!.trim()}',
              style: FardaConsumerType.body,
            ),
            TextButton.icon(
              key: const Key('pharmacy-copy-rx'),
              onPressed:
                  _busy || _acting || _session == null
                      ? null
                      : () => _copy(
                        widget.rxNumber!.trim(),
                        'Rx number copied. Paste it only on your pharmacy’s official page.',
                      ),
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text('Copy Rx number'),
            ),
          ] else
            const Text(
              'Have your prescription label ready.',
              style: FardaConsumerType.caption,
            ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: LinearProgressIndicator(),
            )
          else if (_error != null) ...[
            Text(_error!, style: FardaConsumerType.body),
            TextButton(onPressed: _load, child: const Text('Try again')),
          ] else if (handoff != null) ...[
            Text(handoff.notice, style: FardaConsumerType.caption),
            if (safe) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const Key('pharmacy-continue'),
                  style: FilledButton.styleFrom(
                    backgroundColor: FardaConsumerColors.brand,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(48, 52),
                  ),
                  onPressed:
                      _acting
                          ? null
                          : () => _act(() async {
                            bool opened = false;
                            try {
                              opened = await (widget.openUrl ??
                                  openPharmacyUrl)(handoff.url!);
                            } catch (_) {
                              /* Preserve the reviewed URL for manual navigation. */
                            }
                            if (mounted && !opened) {
                              setState(() => _manualLink = true);
                            }
                          }),
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: Text('Continue at ${handoff.pharmacyName}'),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Nothing is sent from Farda. Sign in and complete your request there.',
                style: FardaConsumerType.caption,
              ),
              if (_manualLink) ...[
                const SizedBox(height: 8),
                const Text(
                  'Open this official address in your browser:',
                  style: FardaConsumerType.caption,
                ),
                SelectableText(
                  handoff.url.toString(),
                  style: FardaConsumerType.caption,
                ),
                TextButton(
                  onPressed:
                      _acting
                          ? null
                          : () => _copy(
                            handoff.url.toString(),
                            'Official pharmacy address copied.',
                          ),
                  child: const Text('Copy website address'),
                ),
              ],
            ],
          ] else
            const Text(
              'Choose your pharmacy. For an independent pharmacy, use the number on your label.',
              style: FardaConsumerType.caption,
            ),
        ],
      ),
    );
  }
}

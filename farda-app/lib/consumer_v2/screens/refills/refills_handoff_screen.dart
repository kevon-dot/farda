import 'package:farda/consumer_v2/design_system/farda_consumer_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'refills_figma_parts.dart';
import 'refill_agent_card.dart';
import 'refill_question_card.dart';
import 'package:farda/features/consumer/data/refill_agent.dart';

/// A local planning handoff. Copying text never changes the saved refill stage.
/// Contact information and pharmacy eligibility are never inferred here.
class RefillsHandoffScreen extends StatefulWidget {
  const RefillsHandoffScreen({
    super.key,
    required this.medicationName,
    required this.rxLabel,
    required this.actionLabel,
    required this.onSavePlan,
    this.showSavePlan = true,
    this.rxNumber,
    this.directions,
    this.pharmacy,
    this.onOpenContact,
    this.contactLabel = 'Find pharmacy contact',
    this.onOpenProfile,
    this.prescriptionId,
    this.agentRepository,
  });

  final String? prescriptionId;
  final RefillAgentRepository? agentRepository;
  final String medicationName;
  final String rxLabel;
  final String? rxNumber;
  final String? directions;
  final String? pharmacy;
  final String actionLabel;
  final bool showSavePlan;
  final Future<String?> Function() onSavePlan;
  final VoidCallback? onOpenContact;
  final String contactLabel;
  final VoidCallback? onOpenProfile;

  @override
  State<RefillsHandoffScreen> createState() => _RefillsHandoffScreenState();
}

class _RefillsHandoffScreenState extends State<RefillsHandoffScreen> {
  bool _saving = false;
  String? _error;
  String? _draft;

  String _clean(String? value) => value?.trim() ?? '';

  String get _request => [
    'Hello${_clean(widget.pharmacy).isEmpty ? '' : ' ${_clean(widget.pharmacy)}'},',
    'I would like to ask about a refill for ${widget.medicationName.trim()}.',
    if (_clean(widget.rxNumber).isNotEmpty)
      'Prescription number: ${_clean(widget.rxNumber)}.',
    if (_clean(widget.directions).isNotEmpty)
      'Directions on my saved label: ${_clean(widget.directions)}',
    'Please confirm whether a refill is available and the next steps. Thank you.',
  ].join('\n\n');

  Future<void> _reviewRequest() async {
    final draft = await showDialog<String>(
      context: context,
      builder:
          (_) => _RequestReviewDialog(
            request: _draft ?? _request,
            onDraftChanged: (value) => _draft = value,
          ),
    );
    if (draft != null && mounted) setState(() => _draft = draft);
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    String? error;
    try {
      error = await widget.onSavePlan();
    } catch (_) {
      error = 'Your plan was not saved. Please try again.';
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
      const SnackBar(content: Text('Your refill plan was saved.')),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: FardaConsumerColors.canvas,
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Back to refill station',
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                icon: const Icon(Icons.arrow_back_rounded),
                color: FardaConsumerColors.brand,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Refill assistant',
                  style: FardaConsumerType.bodyStrong,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FardaSceneCard(
            scene: FardaScene.refills,
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'ONE STEP AT A TIME',
                        style: TextStyle(
                          fontFamily: 'Outfit',
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Let’s get\nyou ready.',
                        style: TextStyle(
                          fontFamily: 'Outfit',
                          fontSize:
                              MediaQuery.sizeOf(context).width < 350 ? 24 : 28,
                          height: 1.12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Your words, ready to share.',
                        style: FardaConsumerType.caption.copyWith(
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FardaCompanion(
                  size: MediaQuery.sizeOf(context).width < 350 ? 56 : 72,
                  pose: FardaCompanionPose.quiet,
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          if (widget.agentRepository != null &&
              widget.prescriptionId != null) ...[
            RefillAgentCard(
              prescriptionId: widget.prescriptionId!,
              repository: widget.agentRepository!,
            ),
            const SizedBox(height: 18),
            const Text(
              'Prefer to contact your pharmacy?',
              style: FardaConsumerType.title,
            ),
            const SizedBox(height: 12),
          ],
          FardaConsumerCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('CHECK YOUR LABEL', style: FardaConsumerType.label),
                const SizedBox(height: 10),
                Text(widget.medicationName, style: FardaConsumerType.title),
                const SizedBox(height: 8),
                SelectableText(
                  _clean(widget.rxNumber).isEmpty
                      ? widget.rxLabel
                      : 'Rx ${_clean(widget.rxNumber)}',
                  style: FardaConsumerType.body,
                ),
                if (_clean(widget.directions).isNotEmpty) ...[
                  const SizedBox(height: 14),
                  const Text(
                    'Saved directions',
                    style: FardaConsumerType.caption,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _clean(widget.directions),
                    style: FardaConsumerType.body,
                  ),
                ],
                const SizedBox(height: 14),
                const Text('Pharmacy', style: FardaConsumerType.caption),
                const SizedBox(height: 4),
                Text(
                  _clean(widget.pharmacy).isEmpty
                      ? 'Check your prescription label'
                      : _clean(widget.pharmacy),
                  style: FardaConsumerType.bodyStrong,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Use the phone number or official website on your label.',
                  style: FardaConsumerType.caption,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _reviewRequest,
            style: FilledButton.styleFrom(
              minimumSize: const Size(48, 52),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              backgroundColor: FardaConsumerColors.mint,
              foregroundColor: FardaConsumerColors.brand,
              textStyle: FardaConsumerType.bodyStrong,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text(
              'Review refill request',
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Review, edit and copy. You choose where to share it.',
            style: FardaConsumerType.caption,
            textAlign: TextAlign.center,
          ),
          if (widget.onOpenContact != null) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: widget.onOpenContact,
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              child: Text(widget.contactLabel, textAlign: TextAlign.center),
            ),
          ],
          if (widget.agentRepository is RefillQuestionRepository &&
              widget.prescriptionId != null) ...[
            const SizedBox(height: 16),
            RefillQuestionCard(
              prescriptionId: widget.prescriptionId!,
              repository: widget.agentRepository as RefillQuestionRepository,
            ),
          ],
          const SizedBox(height: 16),
          const RefillsSafetyBanner(),
          const SizedBox(height: 8),
          Text(
            widget.agentRepository == null
                ? 'No refill order is submitted. Saving a plan does not contact your pharmacy.'
                : 'Copying a request or saving a plan does not contact your pharmacy.',
            style: FardaConsumerType.caption,
          ),
          const SizedBox(height: 16),
          if (widget.showSavePlan)
            OutlinedButton(
              key: const Key('refill-save-plan'),
              onPressed: _saving ? null : _save,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(48, 48),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                foregroundColor: FardaConsumerColors.brand,
                textStyle: FardaConsumerType.bodyStrong,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                _saving ? 'Saving…' : widget.actionLabel,
                textAlign: TextAlign.center,
              ),
            ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Semantics(
              liveRegion: true,
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

class _RequestReviewDialog extends StatefulWidget {
  const _RequestReviewDialog({
    required this.request,
    required this.onDraftChanged,
  });
  final String request;
  final ValueChanged<String> onDraftChanged;

  @override
  State<_RequestReviewDialog> createState() => _RequestReviewDialogState();
}

class _RequestReviewDialogState extends State<_RequestReviewDialog> {
  late final TextEditingController _text = TextEditingController(
    text: widget.request,
  );
  bool _copying = false;
  bool _copied = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _copy() async {
    if (_copying) return;
    if (_text.text.trim().isEmpty) {
      setState(() => _error = 'Add a message before copying.');
      return;
    }
    setState(() {
      _copying = true;
      _error = null;
    });
    try {
      await Clipboard.setData(ClipboardData(text: _text.text.trim()));
      if (!mounted) return;
      setState(() {
        _copying = false;
        _copied = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _copying = false;
        _error = 'Could not copy. Try again or select the text manually.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: FardaConsumerColors.canvas,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    titleTextStyle: FardaConsumerType.title,
    contentTextStyle: FardaConsumerType.body,
    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
    title: const Text('Your refill request'),
    content: SizedBox(
      width: 360,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Check the details before sharing with your pharmacy.'),
            const SizedBox(height: 16),
            TextField(
              key: const Key('refill-request-text'),
              controller: _text,
              minLines: 5,
              maxLines: null,
              style: FardaConsumerType.body,
              decoration: const InputDecoration(
                labelText: 'Your message',
                alignLabelWithHint: true,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(
                    color: FardaConsumerColors.brand,
                    width: 2,
                  ),
                ),
              ),
              onChanged: (value) {
                widget.onDraftChanged(value);
                setState(() {
                  _copied = false;
                  _error = null;
                });
              },
            ),
          ],
        ),
      ),
    ),
    actions: [
      SizedBox(
        width: double.infinity,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            SizedBox(
              width: double.infinity,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    _error ??
                        (_copied
                            ? 'Copied. Nothing has been sent.'
                            : 'Copying includes your prescription details.'),
                    style: FardaConsumerType.caption.copyWith(
                      color:
                          _error == null
                              ? FardaConsumerColors.textSecondary
                              : Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ),
            ),
            Wrap(
              spacing: 8,
              alignment: WrapAlignment.end,
              children: [
                TextButton(
                  onPressed:
                      _copying
                          ? null
                          : () => Navigator.pop(context, _text.text),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    foregroundColor: FardaConsumerColors.brand,
                  ),
                  child: const Text('Done'),
                ),
                FilledButton(
                  key: const Key('refill-copy-request'),
                  onPressed: _copying ? null : _copy,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    backgroundColor: FardaConsumerColors.mint,
                    foregroundColor: FardaConsumerColors.brand,
                  ),
                  child: Text(
                    _copying
                        ? 'Copying…'
                        : _copied
                        ? 'Copy again'
                        : 'Copy request',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ],
  );
}

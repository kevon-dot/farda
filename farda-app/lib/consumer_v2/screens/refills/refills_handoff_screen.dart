import 'package:farda/consumer_v2/design_system/farda_consumer_tokens.dart';
import 'package:flutter/material.dart';

import 'refills_figma_parts.dart';

/// A local planning handoff. The only saved status comes from [onSavePlan].
/// Contact information and pharmacy eligibility are never inferred here.
class RefillsHandoffScreen extends StatefulWidget {
  const RefillsHandoffScreen({
    super.key,
    required this.medicationName,
    required this.rxLabel,
    required this.actionLabel,
    required this.onSavePlan,
    this.onOpenContact,
    this.contactLabel = 'Find pharmacy contact',
    this.onOpenProfile,
  });

  final String medicationName;
  final String rxLabel;
  final String actionLabel;
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
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Your refill plan was saved.')),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: FardaConsumerColors.canvas,
    body: SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(22, 8, 22, 32),
        children: [
          RefillsPageHeader(
            onOpenProfile:
                widget.onOpenProfile == null
                    ? null
                    : () {
                      Navigator.of(context).pop();
                      widget.onOpenProfile!();
                    },
          ),
          const SizedBox(height: 16),
          const Text('YOUR NEXT STEP', style: FardaConsumerType.label),
          const SizedBox(height: 8),
          const Text(
            'Let’s get\nyou ready.',
            style: TextStyle(
              fontFamily: 'Outfit',
              fontSize: 34,
              height: 37 / 34,
              fontWeight: FontWeight.w600,
              color: FardaConsumerColors.brand,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Get ready to contact your pharmacy.',
            style: FardaConsumerType.body,
          ),
          const SizedBox(height: 16),
          FardaConsumerCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: FardaConsumerColors.soft,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const FardaVectorIcon('icon-pill', size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.medicationName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: FardaConsumerType.bodyStrong,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            widget.rxLabel,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: FardaConsumerType.caption,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                for (final line in const [
                  'Check your prescription label',
                  'Check pharmacy contact details',
                  'Ask about timing and refills',
                ]) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const FardaVectorIcon('icon-check', size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(line, style: FardaConsumerType.body),
                      ),
                    ],
                  ),
                  if (line != 'Ask about timing and refills')
                    const SizedBox(height: 14),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          FardaSceneCard(
            scene: FardaScene.refills,
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Your pharmacy',
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 18,
                    height: 24 / 18,
                    fontWeight: FontWeight.w600,
                    color: FardaConsumerColors.canvas,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Use the phone number on your label.',
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 14,
                    height: 20 / 14,
                    color: FardaConsumerColors.canvas,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed:
                        widget.onOpenContact ??
                        () => showDialog<void>(
                          context: context,
                          builder:
                              (dialogContext) => AlertDialog(
                                title: const Text('Contact your pharmacy'),
                                content: const Text(
                                  'Use the phone number or official contact details on your prescription label. Farda has not sent a refill request.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed:
                                        () => Navigator.pop(dialogContext),
                                    child: const Text('Done'),
                                  ),
                                ],
                              ),
                        ),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      backgroundColor: FardaConsumerColors.canvas,
                      foregroundColor: FardaConsumerColors.brand,
                      textStyle: FardaConsumerType.bodyStrong,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(widget.contactLabel),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: _saving ? null : _save,
                  iconAlignment: IconAlignment.end,
                  icon: const FardaVectorIcon(
                    'icon-arrow-small',
                    size: 14,
                    color: FardaConsumerColors.canvas,
                  ),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 24),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: FardaConsumerColors.canvas,
                    textStyle: FardaConsumerType.caption.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  label: Text(_saving ? 'Saving…' : widget.actionLabel),
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: FardaConsumerColors.warm,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FardaVectorIcon('icon-info', size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'No refill order is submitted. Your pharmacy confirms eligibility and timing.',
                    style: TextStyle(
                      fontFamily: 'Outfit',
                      fontSize: 12,
                      height: 17 / 12,
                      color: FardaConsumerColors.textWarm,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              iconAlignment: IconAlignment.end,
              icon: const FardaVectorIcon('icon-arrow-small', size: 14),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 24),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: FardaConsumerColors.brand,
                textStyle: FardaConsumerType.caption.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              label: const Text('Back to refill station'),
            ),
          ),
        ],
      ),
    ),
  );
}

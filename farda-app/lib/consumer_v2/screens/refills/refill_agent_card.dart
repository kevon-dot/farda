import 'package:farda/consumer_v2/design_system/farda_consumer_tokens.dart';
import 'package:farda/features/consumer/data/consumer_models.dart';
import 'package:farda/features/consumer/data/refill_agent.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// External provider state never changes a user's supply or reported journey.
class RefillAgentCard extends StatefulWidget {
  const RefillAgentCard({
    super.key,
    required this.prescriptionId,
    required this.repository,
  });
  final String prescriptionId;
  final RefillAgentRepository repository;
  @override
  State<RefillAgentCard> createState() => _RefillAgentCardState();
}

class _RefillAgentCardState extends State<RefillAgentCard> {
  RefillAgentState? _state;
  bool _busy = true;
  bool _submitting = false;
  bool _uncertain = false;
  String? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant RefillAgentCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.prescriptionId != widget.prescriptionId ||
        oldWidget.repository != widget.repository) {
      _state = null;
      _uncertain = false;
      _load();
    }
  }

  Future<void> _load({bool refresh = false}) async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result =
          refresh
              ? await widget.repository.refreshRefillAgent(
                widget.prescriptionId,
              )
              : await widget.repository.loadRefillAgent(widget.prescriptionId);
      if (!mounted || generation != _generation) return;
      setState(() {
        _state = result;
        _uncertain = result.latestRequest?.uncertain == true;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        // Never display an old ready-to-send review after a failed refresh.
        _state = null;
        _error =
            error is ConsumerRepositoryException && error.sessionExpired
                ? error.message
                : 'Connection details could not be checked. You can still copy a request below.';
      });
    } finally {
      if (mounted && generation == _generation) {
        setState(() {
          _busy = false;
          _submitting = false;
        });
      }
    }
  }

  Future<void> _review() async {
    final prescriptionId = widget.prescriptionId;
    final repository = widget.repository;
    final reviewGeneration = _generation;
    final state = _state;
    final review = state?.review;
    if (_busy || _uncertain || state?.canSubmit != true || review == null) {
      return;
    }
    if (!review.expiresAt.isAfter(DateTime.now())) {
      await _load();
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (_) => _ProviderReviewDialog(
            review: review,
            environment: state!.environment,
          ),
    );
    if (!mounted ||
        confirmed != true ||
        prescriptionId != widget.prescriptionId ||
        repository != widget.repository ||
        reviewGeneration != _generation) {
      return;
    }
    if (!review.expiresAt.isAfter(DateTime.now())) {
      setState(
        () =>
            _error =
                'The review expired. Check the latest details before sending.',
      );
      await _load();
      return;
    }
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _submitting = true;
      _error = null;
    });
    try {
      final result = await widget.repository.submitRefillAgent(
        widget.prescriptionId,
        reviewToken: review.token,
        idempotencyKey: 'refill-${DateTime.now().microsecondsSinceEpoch}',
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _state = result;
        _uncertain = result.latestRequest?.uncertain == true;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      // Even an unreadable success response could hide an accepted order.
      // No send retry is offered until the server has reconciled its state.
      setState(() {
        _uncertain = true;
        _error = null;
      });
    } finally {
      if (mounted && generation == _generation) {
        setState(() {
          _busy = false;
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    final request = state?.latestRequest;
    final uncertain = _uncertain || request?.uncertain == true;
    final eligible =
        state?.canSubmit == true && state?.review != null && !uncertain;
    final title =
        _submitting
            ? 'Sending your request…'
            : uncertain
            ? 'We’re checking your request'
            : request != null
            ? request.statusLabel
            : eligible
            ? 'Ready to review'
            : 'Send through your pharmacy';
    final message =
        _busy && state == null && !uncertain
            ? 'Checking whether a supported pharmacy connection is available.'
            : _submitting
            ? 'We’re waiting for a response from the provider.'
            : uncertain
            ? 'It may have been sent. Check status before trying again.'
            : request != null
            ? switch (request.status) {
              'sent' =>
                'Your request reached the provider. Your pharmacy still needs to confirm readiness.',
              'ready' =>
                'The provider reports your refill is ready. Check pickup details with your pharmacy.',
              'failed' =>
                'This request needs attention. Contact your pharmacy before starting another.',
              'canceled' =>
                'This request was canceled. Contact your pharmacy for next steps.',
              'received' =>
                'The pharmacy has received the request. It is not ready for pickup yet.',
              'shipped' => 'The provider reports your refill has shipped.',
              'delivered' || 'picked_up' || 'completed' =>
                'The provider updated this request. Your supply count has not changed.',
              _ => 'Check for the latest verified update.',
            }
            : eligible
            ? 'Review your linked prescription and pharmacy before sending.'
            : 'Refill sending isn’t available here. Call your pharmacy or copy a request below.';
    return FardaConsumerCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('REFILL CONNECTION', style: FardaConsumerType.label),
          if (state?.environment == 'sandbox') ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFE7DFF6),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'Sandbox · no live order',
                style: FardaConsumerType.caption,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            _busy && state == null && !uncertain
                ? 'Checking your connection…'
                : title,
            style: FardaConsumerType.title,
          ),
          const SizedBox(height: 8),
          Semantics(
            liveRegion: true,
            child: Text(_error ?? message, style: FardaConsumerType.body),
          ),
          if (request?.lastCheckedAt != null) ...[
            const SizedBox(height: 8),
            Text(
              'Checked ${DateFormat.MMMd().add_jm().format(request!.lastCheckedAt!.toLocal())} · ${state!.provider}',
              style: FardaConsumerType.caption,
            ),
          ],
          const SizedBox(height: 14),
          if (eligible && !_busy)
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const Key('refill-agent-review'),
                onPressed: _review,
                style: _primaryStyle,
                child: const Text('Review & send'),
              ),
            )
          else if (!_busy)
            OutlinedButton.icon(
              key: const Key('refill-agent-refresh'),
              onPressed:
                  () =>
                      _load(refresh: uncertain || request?.canRefresh == true),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(
                uncertain || request != null
                    ? 'Check status'
                    : 'Check connection',
              ),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(48, 48),
                foregroundColor: FardaConsumerColors.brand,
                textStyle: FardaConsumerType.bodyStrong,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            )
          else
            const SizedBox(
              height: 24,
              width: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
    );
  }
}

final _primaryStyle = FilledButton.styleFrom(
  minimumSize: const Size(48, 52),
  backgroundColor: FardaConsumerColors.mint,
  foregroundColor: FardaConsumerColors.brand,
  textStyle: FardaConsumerType.bodyStrong,
  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
);

class _ProviderReviewDialog extends StatefulWidget {
  const _ProviderReviewDialog({
    required this.review,
    required this.environment,
  });
  final RefillAgentReview review;
  final String? environment;
  @override
  State<_ProviderReviewDialog> createState() => _ProviderReviewDialogState();
}

class _ProviderReviewDialogState extends State<_ProviderReviewDialog> {
  bool _confirmed = false;
  @override
  Widget build(BuildContext context) {
    final review = widget.review;
    return AlertDialog(
      backgroundColor: FardaConsumerColors.canvas,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      titleTextStyle: FardaConsumerType.title.copyWith(fontSize: 24),
      title: const Text('Review your refill'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.environment == 'sandbox') ...[
                const Text(
                  'Sandbox · no live order',
                  style: FardaConsumerType.bodyStrong,
                ),
                const SizedBox(height: 16),
              ],
              Text(review.medicationName, style: FardaConsumerType.title),
              if (review.instructions?.isNotEmpty == true) ...[
                const SizedBox(height: 8),
                Text(review.instructions!, style: FardaConsumerType.body),
              ],
              const SizedBox(height: 16),
              const Text('Pharmacy', style: FardaConsumerType.caption),
              Text(review.pharmacyName, style: FardaConsumerType.bodyStrong),
              const SizedBox(height: 16),
              const Text(
                'Address shared with provider',
                style: FardaConsumerType.caption,
              ),
              Text(review.address, style: FardaConsumerType.body),
              const SizedBox(height: 16),
              const Text(
                'Sending requests a refill. It does not guarantee approval, price or pickup time.',
                style: FardaConsumerType.caption,
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                key: const Key('refill-agent-consent'),
                activeColor: FardaConsumerColors.brand,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(review.consentText, style: FardaConsumerType.body),
                value: _confirmed,
                onChanged:
                    (value) => setState(() => _confirmed = value == true),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          style: TextButton.styleFrom(
            foregroundColor: FardaConsumerColors.brand,
          ),
          child: const Text('Not now'),
        ),
        FilledButton(
          key: const Key('refill-agent-send'),
          style: _primaryStyle,
          onPressed: _confirmed ? () => Navigator.pop(context, true) : null,
          child: const Text('Send refill request'),
        ),
      ],
    );
  }
}

import 'package:farda/consumer_v2/design_system/farda_consumer_tokens.dart';
import 'package:farda/features/consumer/data/refill_agent.dart';
import 'package:farda/features/consumer/data/consumer_models.dart';
import 'package:flutter/material.dart';
import 'package:farda/features/consumer/data/billing.dart';
import '../membership/farda_membership_screen.dart';

class RefillQuestionCard extends StatefulWidget {
  const RefillQuestionCard({
    super.key,
    required this.prescriptionId,
    required this.repository,
  });
  final String prescriptionId;
  final RefillQuestionRepository repository;
  @override
  State<RefillQuestionCard> createState() => _RefillQuestionCardState();
}

class _RefillQuestionCardState extends State<RefillQuestionCard> {
  final _question = TextEditingController();
  final _focus = FocusNode();
  bool _consent = false;
  bool _busy = false;
  int _generation = 0;
  String? _error;
  RefillAgentAnswer? _answer;
  @override
  void didUpdateWidget(covariant RefillQuestionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.prescriptionId != widget.prescriptionId ||
        oldWidget.repository != widget.repository) {
      _generation++;
      _focus.unfocus();
      _question.clear();
      _consent = false;
      _busy = false;
      _error = null;
      _answer = null;
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _question.dispose();
    super.dispose();
  }

  Future<void> _ask() async {
    if (_busy || !_consent || _question.text.trim().isEmpty) return;
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
      _answer = null;
    });
    try {
      final answer = await widget.repository.askRefillQuestion(
        widget.prescriptionId,
        _question.text.trim(),
      );
      if (mounted && generation == _generation) {
        setState(() => _answer = answer);
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        if (error is ConsumerRepositoryException && error.sessionExpired) {
          _focus.unfocus();
          _question.clear();
          _consent = false;
        }
        setState(
          () =>
              _error =
                  'The helper is unavailable. Use the refill steps or contact your pharmacy.',
        );
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => FardaConsumerCard(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    child: ExpansionTile(
      iconColor: FardaConsumerColors.brand,
      collapsedIconColor: FardaConsumerColors.brand,
      shape: const Border(),
      collapsedShape: const Border(),
      title: const Text(
        'Ask about this refill',
        style: FardaConsumerType.bodyStrong,
      ),
      leading: const Icon(
        Icons.auto_awesome_rounded,
        color: FardaConsumerColors.brand,
      ),
      childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 14),
      children: [
        const Text(
          'Find your next step. For medication or dosing questions, ask your pharmacist.',
          style: FardaConsumerType.caption,
        ),
        if (widget.repository is BillingRepository) ...[
          const SizedBox(height: 8),
          const Text(
            'AI guidance is included with Plus. Guided refill steps stay free.',
            style: FardaConsumerType.caption,
          ),
          TextButton(
            onPressed:
                () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder:
                        (_) => FardaMembershipScreen(
                          repository: widget.repository as BillingRepository,
                        ),
                  ),
                ),
            child: const Text('Explore Plus'),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          key: const Key('refill-agent-question'),
          controller: _question,
          focusNode: _focus,
          enabled: !_busy,
          maxLength: 1000,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: 'Your question',
            border: OutlineInputBorder(),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(
                color: FardaConsumerColors.brand,
                width: 2,
              ),
            ),
            floatingLabelStyle: TextStyle(color: FardaConsumerColors.brand),
          ),
          onChanged:
              (_) => setState(() {
                _answer = null;
                _error = null;
              }),
        ),
        CheckboxListTile(
          key: const Key('refill-agent-ai-consent'),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          activeColor: FardaConsumerColors.brand,
          value: _consent,
          onChanged:
              _busy
                  ? null
                  : (value) => setState(() => _consent = value == true),
          title: const Text(
            'Send this question to AI. Medication details aren’t included automatically.',
            style: FardaConsumerType.caption,
          ),
        ),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            key: const Key('refill-agent-ask'),
            onPressed:
                !_busy && _consent && _question.text.trim().isNotEmpty
                    ? _ask
                    : null,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(48, 48),
              foregroundColor: FardaConsumerColors.brand,
            ),
            child: Text(_busy ? 'Finding your next step…' : 'Ask helper'),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_error!, style: FardaConsumerType.body),
          ),
        if (_answer != null)
          Semantics(
            liveRegion: true,
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_answer!.title, style: FardaConsumerType.bodyStrong),
                  const SizedBox(height: 6),
                  Text(_answer!.message, style: FardaConsumerType.body),
                  const SizedBox(height: 8),
                  Text(
                    _answer!.source == 'ai'
                        ? 'AI-assisted navigation · nothing sent'
                        : 'Guided help · nothing sent',
                    style: FardaConsumerType.caption,
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}

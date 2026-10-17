import 'package:flutter/material.dart';
import 'package:farda/features/consumer/data/circle_models.dart';

import '../../design_system/farda_consumer_tokens.dart' as design;
import '../today/farda_companion.dart';
import 'you_widgets.dart';

/// A read-only overview of the evidence the owner has chosen to share.
/// Missing records and device activity never count as reported taken.
class CircleRoutineSummary extends StatelessWidget {
  const CircleRoutineSummary({super.key, required this.routine});
  final CircleRoutine routine;

  @override
  Widget build(BuildContext context) {
    final permissions = routine.permissions;
    final paused = !permissions.doseStatus && !permissions.reminders;
    final taken =
        routine.items
            .where(
              (item) =>
                  item.evidence == CircleEvidence.selfReport &&
                  item.state == CircleRoutineState.taken,
            )
            .length;
    final skipped =
        routine.items
            .where(
              (item) =>
                  item.evidence == CircleEvidence.selfReport &&
                  item.state == CircleRoutineState.skipped,
            )
            .length;
    final snoozed =
        routine.items
            .where(
              (item) =>
                  item.evidence == CircleEvidence.selfReport &&
                  item.state == CircleRoutineState.snoozed,
            )
            .length;
    final unconfirmed = routine.items.length - taken - skipped - snoozed;
    final title =
        paused
            ? 'Still connected. Sharing paused.'
            : 'A little support goes a long way.';
    final detail =
        paused
            ? 'Your person is keeping their routine private for now.'
            : !permissions.doseStatus
            ? 'Reminder times are shared. Dose updates stay private.'
            : routine.items.isEmpty
            ? 'No shared entries today. You can check back when it suits you.'
            : 'Here’s what your person has shared today. No confirmation doesn’t mean a dose was missed.';
    final counts = <String>[
      if (taken > 0) '$taken reported taken',
      if (skipped > 0) '$skipped reported skipped',
      if (snoozed > 0) '$snoozed snoozed',
      if (unconfirmed > 0) '$unconfirmed not confirmed',
    ];
    return FardaYouCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FardaCompanion(size: 64, mood: FardaCompanionMood.quiet),
          const SizedBox(height: 12),
          Text(title, style: design.FardaConsumerType.title),
          const SizedBox(height: 8),
          Text(detail, style: design.FardaConsumerType.body),
          if (permissions.doseStatus && counts.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final count in counts)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: design.FardaConsumerColors.soft,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      count,
                      style: design.FardaConsumerType.bodyStrong,
                    ),
                  ),
              ],
            ),
          ],
          if (permissions.doseStatus && !permissions.reminders) ...[
            const SizedBox(height: 12),
            const Text(
              'Reminder times stay private.',
              style: design.FardaConsumerType.caption,
            ),
          ],
        ],
      ),
    );
  }
}

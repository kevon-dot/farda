import 'package:flutter/material.dart';

import '../../design_system/farda_consumer_tokens.dart' as design;
import 'farda_companion.dart';
import 'today_models.dart';

class FardaTodayRoutineCard extends StatelessWidget {
  const FardaTodayRoutineCard({
    super.key,
    required this.timeLabel,
    required this.status,
    required this.isSnoozed,
    required this.onOpenLog,
    required this.onSnooze,
    required this.onMoreOptions,
    required this.onCorrectEntry,
    this.neutralCopy = false,
    this.isSaving = false,
  });

  static const logDoseButtonKey = Key('today_log_dose_button');
  static const snoozeButtonKey = Key('today_snooze_button');
  static const moreOptionsButtonKey = Key('today_more_options_button');
  static const correctEntryButtonKey = Key('today_correct_entry_button');

  final String timeLabel;
  final TodayDoseStatus status;
  final bool isSnoozed;
  final VoidCallback onOpenLog;
  final VoidCallback onSnooze;
  final VoidCallback onMoreOptions;
  final VoidCallback onCorrectEntry;
  final bool neutralCopy;
  final bool isSaving;

  @override
  Widget build(BuildContext context) {
    final copy = _RoutineCopy.forState(status, isSnoozed, timeLabel);
    final isPending = status == TodayDoseStatus.pending;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final compact =
        MediaQuery.sizeOf(context).width <= 340 ||
        MediaQuery.textScalerOf(context).scale(14) > 18;
    final companionSize = compact ? 72.0 : 104.0;
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 21;
    final switchDuration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 220);

    return Semantics(
      container: true,
      label: neutralCopy ? 'Selected routine' : 'Morning routine',
      child: design.FardaSceneCard(
        scene: design.FardaScene.today,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${neutralCopy ? 'YOUR ROUTINE' : 'YOUR MORNING'} · $timeLabel',
              style: _fardaTodayText(
                size: 10,
                lineHeight: 14,
                weight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 104),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AnimatedSwitcher(
                          duration: switchDuration,
                          child: Text(
                            copy.headline,
                            key: ValueKey(copy.headline),
                            style: _fardaTodayText(
                              size: isPending ? 28 : 26,
                              lineHeight: 30,
                              weight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(height: 9),
                        Text(
                          copy.support,
                          style: _fardaTodayText(
                            size: 12,
                            lineHeight: 17,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!largeText)
                    Container(
                      width: companionSize,
                      height: companionSize,
                      decoration: const BoxDecoration(
                        color: _canvas,
                        shape: BoxShape.circle,
                      ),
                      child: FardaCompanion(
                        size: companionSize,
                        mood: switch (status) {
                          TodayDoseStatus.confirmed =>
                            FardaCompanionMood.confirmed,
                          TodayDoseStatus.skipped => FardaCompanionMood.skipped,
                          TodayDoseStatus.pending when isSnoozed =>
                            FardaCompanionMood.snoozed,
                          TodayDoseStatus.pending => FardaCompanionMood.waving,
                        },
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: AnimatedSwitcher(
                duration: switchDuration,
                child: Container(
                  key: ValueKey(isSaving ? 'saving' : copy.statusLine),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: design.FardaConsumerColors.deep,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF6684B1)),
                  ),
                  child: Text(
                    isSaving ? 'Saving your choice…' : copy.statusLine,
                    style: _fardaTodayText(
                      size: 12,
                      lineHeight: 17,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (isPending) ...[
              _RoutineButton(
                key: logDoseButtonKey,
                label: 'Log my dose',
                backgroundColor: _canvas,
                onPressed: isSaving ? null : onOpenLog,
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final textScale = MediaQuery.textScalerOf(context).scale(14);
                  final shouldStack =
                      constraints.maxWidth < 300 || textScale > 18;
                  final snooze = _RoutineSecondaryAction(
                    key: snoozeButtonKey,
                    label: isSnoozed ? 'Snoozed 15 min' : 'Remind in 15 min',
                    onPressed: isSnoozed || isSaving ? null : onSnooze,
                  );
                  final more = _RoutineSecondaryAction(
                    key: moreOptionsButtonKey,
                    label: 'More options',
                    onPressed: isSaving ? null : onMoreOptions,
                  );

                  if (shouldStack) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [snooze, const SizedBox(height: 8), more],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: snooze),
                      const SizedBox(width: 8),
                      Expanded(child: more),
                    ],
                  );
                },
              ),
            ] else
              _RoutineButton(
                key: correctEntryButtonKey,
                label: 'Correct this entry',
                backgroundColor: _canvas,
                onPressed: isSaving ? null : onCorrectEntry,
              ),
          ],
        ),
      ),
    );
  }
}

class _RoutineSecondaryAction extends StatelessWidget {
  const _RoutineSecondaryAction({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          disabledForegroundColor: const Color(0xFFBFCBE0),
          side: const BorderSide(color: Color(0xFF6684B1)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          textStyle: _fardaTodayText(
            size: 14,
            lineHeight: 19,
            weight: FontWeight.w600,
          ),
        ),
        child: Text(label, textAlign: TextAlign.center),
      ),
    );
  }
}

class _RoutineButton extends StatelessWidget {
  const _RoutineButton({
    super.key,
    required this.label,
    required this.backgroundColor,
    required this.onPressed,
  });

  final String label;
  final Color backgroundColor;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minWidth: double.infinity,
        minHeight: 48,
      ),
      child: FilledButton(
        style: FilledButton.styleFrom(
          elevation: 0,
          backgroundColor: backgroundColor,
          foregroundColor: _navy,
          disabledBackgroundColor: const Color(0xFFDCE2EB),
          disabledForegroundColor: _navy,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: _fardaTodayText(
            size: 14,
            lineHeight: 19,
            weight: FontWeight.w600,
          ),
        ),
        onPressed: onPressed,
        child: Text(label, textAlign: TextAlign.center),
      ),
    );
  }
}

class _RoutineCopy {
  const _RoutineCopy({
    required this.headline,
    required this.support,
    required this.statusLine,
  });

  factory _RoutineCopy.forState(
    TodayDoseStatus status,
    bool isSnoozed,
    String timeLabel,
  ) {
    if (status == TodayDoseStatus.confirmed) {
      return _RoutineCopy(
        headline: 'More room\nfor your day.',
        support: 'Your entry is saved.',
        statusLine: 'You confirmed · $timeLabel',
      );
    }
    if (status == TodayDoseStatus.skipped) {
      return const _RoutineCopy(
        headline: 'Your record.\nYour call.',
        support: 'Saved as skipped.',
        statusLine: 'You recorded a skipped dose',
      );
    }
    if (isSnoozed) {
      return _RoutineCopy(
        headline: 'A little\nbreathing room.',
        support: 'Your plan stays the same.',
        statusLine: 'Reminder snoozed · Not yet confirmed',
      );
    }
    return _RoutineCopy(
      headline: 'A moment\nfor you.',
      support: 'Your routine, your pace.',
      statusLine: 'Not yet confirmed',
    );
  }

  final String headline;
  final String support;
  final String statusLine;
}

const _canvas = Color(0xFFF6F5F0);
const _navy = Color(0xFF142C55);

TextStyle _fardaTodayText({
  required double size,
  required double lineHeight,
  FontWeight weight = FontWeight.w400,
  Color color = _navy,
}) {
  return TextStyle(
    fontFamily: 'Outfit',
    fontSize: size,
    height: lineHeight / size,
    fontWeight: weight,
    color: color,
  );
}

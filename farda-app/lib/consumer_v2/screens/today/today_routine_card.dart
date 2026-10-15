import 'package:flutter/material.dart';

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

  @override
  Widget build(BuildContext context) {
    final copy = _RoutineCopy.forState(status, isSnoozed, timeLabel);
    final isPending = status == TodayDoseStatus.pending;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final switchDuration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 220);

    return Semantics(
      container: true,
      label: neutralCopy ? 'Selected routine' : 'Morning routine',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _navy,
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(
              color: Color(0x26142C55),
              offset: Offset(0, 9),
              blurRadius: 20,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isPending ? 'YOUR ROUTINE' : 'YOUR RECORD',
              style: _fardaTodayText(
                size: 10,
                lineHeight: 14,
                weight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: AnimatedSwitcher(
                    duration: switchDuration,
                    child: Text(
                      copy.headline,
                      key: ValueKey(copy.headline),
                      style: _fardaTodayText(
                        size: 26,
                        lineHeight: 30,
                        weight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                FardaCompanion(
                  size: 112,
                  mood: switch (status) {
                    TodayDoseStatus.confirmed => FardaCompanionMood.confirmed,
                    TodayDoseStatus.skipped => FardaCompanionMood.skipped,
                    TodayDoseStatus.pending when isSnoozed =>
                      FardaCompanionMood.snoozed,
                    TodayDoseStatus.pending => FardaCompanionMood.waving,
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            AnimatedSwitcher(
              duration: switchDuration,
              child: Text(
                copy.statusLine,
                key: ValueKey(copy.statusLine),
                style: _fardaTodayText(
                  size: 12,
                  lineHeight: 17,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (isPending) ...[
              _RoutineButton(
                key: logDoseButtonKey,
                label: 'Log my dose',
                backgroundColor: _canvas,
                onPressed: onOpenLog,
              ),
              const SizedBox(height: 8),
              LayoutBuilder(
                builder: (context, constraints) {
                  final textScale = MediaQuery.textScalerOf(
                    context,
                  ).scale(14);
                  final shouldStack =
                      constraints.maxWidth < 300 || textScale > 18;
                  final snooze = _RoutineSecondaryAction(
                    key: snoozeButtonKey,
                    icon: Icons.snooze_rounded,
                    label: isSnoozed ? 'Snoozed 15 min' : 'Remind in 15 min',
                    onPressed: isSnoozed ? null : onSnooze,
                  );
                  final more = _RoutineSecondaryAction(
                    key: moreOptionsButtonKey,
                    icon: Icons.more_horiz_rounded,
                    label: 'Options',
                    onPressed: onMoreOptions,
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
                onPressed: onCorrectEntry,
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
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: TextButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: FittedBox(fit: BoxFit.scaleDown, child: Text(label)),
        style: TextButton.styleFrom(
          foregroundColor: Colors.white,
          disabledForegroundColor: const Color(0xFFBFCBE0),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          textStyle: _fardaTodayText(
            size: 13,
            lineHeight: 18,
            weight: FontWeight.w600,
          ),
        ),
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
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: FilledButton(
        style: FilledButton.styleFrom(
          elevation: 0,
          backgroundColor: backgroundColor,
          foregroundColor: _navy,
          padding: const EdgeInsets.symmetric(horizontal: 14),
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
        child: FittedBox(fit: BoxFit.scaleDown, child: Text(label)),
      ),
    );
  }
}

class _RoutineCopy {
  const _RoutineCopy({
    required this.headline,
    required this.statusLine,
  });

  factory _RoutineCopy.forState(
    TodayDoseStatus status,
    bool isSnoozed,
    String timeLabel,
  ) {
    if (status == TodayDoseStatus.confirmed) {
      return _RoutineCopy(
        headline: 'A little more\nroom today.',
        statusLine: 'You confirmed · $timeLabel',
      );
    }
    if (status == TodayDoseStatus.skipped) {
      return const _RoutineCopy(
        headline: 'Your record.\nYour call.',
        statusLine: 'You recorded a skipped dose',
      );
    }
    if (isSnoozed) {
      return _RoutineCopy(
        headline: 'A little\nbreathing room.',
        statusLine: 'Reminder snoozed · Not yet confirmed',
      );
    }
    return _RoutineCopy(
      headline: 'A moment\nfor your routine.',
      statusLine: '$timeLabel · Not yet confirmed',
    );
  }

  final String headline;
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

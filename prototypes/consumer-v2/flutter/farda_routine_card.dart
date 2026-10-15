import 'package:farda/components/_components.dart';
import 'package:flutter/material.dart';

/// Flutter handoff example adapted from Figma node 4:155 (Today / routine).
/// Uses existing Farda buttons. Callbacks must be connected to the routine
/// controller; this widget never infers or records medication ingestion.
class FardaRoutineCard extends StatelessWidget {
  const FardaRoutineCard({
    super.key,
    required this.timeLabel,
    required this.onOpenLog,
    required this.onSnooze,
    required this.onMoreOptions,
    this.companion,
  });

  final String timeLabel;
  final VoidCallback onOpenLog;
  final VoidCallback onSnooze;
  final VoidCallback onMoreOptions;
  final Widget? companion;

  static const _navy = Color(0xFF142C55);
  static const _cream = Color(0xFFF6F5F0);
  static const _pale = Color(0xFFE9EEF7);

  TextStyle _type(double size, double lineHeight,
          {FontWeight weight = FontWeight.w400, Color color = Colors.white}) =>
      TextStyle(
        fontFamily: 'Outfit',
        fontSize: size,
        height: lineHeight / size,
        fontWeight: weight,
        color: color,
      );

  ButtonStyle _buttonStyle(Color background) => ElevatedButton.styleFrom(
        backgroundColor: background,
        foregroundColor: _navy,
        elevation: 0,
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      );

  @override
  Widget build(BuildContext context) {
    final buttonText =
        _type(14, 20, weight: FontWeight.w600, color: _navy);
    return Container(
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
          Text('YOUR MORNING · $timeLabel',
              style: _type(10, 14, weight: FontWeight.w600)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('A moment\nfor your routine.',
                        style: _type(26, 30, weight: FontWeight.w600)),
                    const SizedBox(height: 9),
                    Text('One less thing to hold in mind.',
                        style: _type(12, 17)),
                  ],
                ),
              ),
              if (companion != null)
                ExcludeSemantics(
                  child: SizedBox(width: 100, height: 100, child: companion),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text('$timeLabel · Not yet confirmed', style: _type(12, 17)),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ButtonPrimary(
              text: 'Log my dose',
              textStyle: buttonText,
              buttonStyle: _buttonStyle(_cream),
              onClick: onOpenLog,
            ),
          ),
          const SizedBox(height: 8),
          LayoutBuilder(builder: (context, constraints) {
            final snooze = ButtonSecondary(
              text: 'Remind in 15 min',
              textStyle: buttonText,
              buttonStyle: _buttonStyle(_pale),
              onClick: onSnooze,
            );
            final more = ButtonSecondary(
              text: 'More options',
              textStyle: buttonText,
              buttonStyle: _buttonStyle(_pale),
              onClick: onMoreOptions,
            );
            final stack = constraints.maxWidth < 300 ||
                MediaQuery.textScalerOf(context).scale(14) > 18;
            if (stack) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [snooze, const SizedBox(height: 8), more],
              );
            }
            return Row(children: [
              Expanded(child: snooze),
              const SizedBox(width: 8),
              Expanded(child: more),
            ]);
          }),
        ],
      ),
    );
  }
}

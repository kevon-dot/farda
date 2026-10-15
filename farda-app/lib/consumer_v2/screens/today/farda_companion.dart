import 'package:flutter/material.dart';

enum FardaCompanionMood { waving, quiet, resting, snoozed, confirmed, skipped }

/// Farda's existing three-pose, navy companion. The additional record moods
/// use quiet, nonjudgmental symbols; neither a reminder nor vial movement
/// changes the character into a saved-record state.
class FardaCompanion extends StatefulWidget {
  const FardaCompanion({
    super.key,
    this.size = 100,
    this.mood = FardaCompanionMood.waving,
    this.decorative = true,
  });

  final double size;
  final FardaCompanionMood mood;
  final bool decorative;

  @override
  State<FardaCompanion> createState() => _FardaCompanionState();
}

class _FardaCompanionState extends State<FardaCompanion>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    )..forward();
  }

  @override
  void didUpdateWidget(covariant FardaCompanion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mood != widget.mood) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final poseIndex = switch (widget.mood) {
      FardaCompanionMood.waving => 0,
      FardaCompanionMood.quiet || FardaCompanionMood.confirmed ||
      FardaCompanionMood.skipped => 1,
      FardaCompanionMood.resting || FardaCompanionMood.snoozed => 2,
    };
    final symbol = switch (widget.mood) {
      FardaCompanionMood.confirmed => Icons.check_rounded,
      FardaCompanionMood.skipped => Icons.remove_rounded,
      FardaCompanionMood.snoozed => Icons.schedule_rounded,
      _ => null,
    };
    final pose = SizedBox.square(
      dimension: widget.size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: ClipRect(
              child: Stack(
                children: [
                  Positioned(
                    left: -poseIndex * widget.size,
                    top: 0,
                    width: widget.size * 3,
                    height: widget.size,
                    child: Image.asset(
                      'assets/images/farda_companion_trio.png',
                      fit: BoxFit.fill,
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (symbol != null)
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                width: 25,
                height: 25,
                decoration: const BoxDecoration(
                  color: Color(0xFFF6F5F0),
                  shape: BoxShape.circle,
                ),
                child: Icon(symbol, size: 16, color: const Color(0xFF142C55)),
              ),
            ),
        ],
      ),
    );

    final animatedPose = disableAnimations
        ? pose
        : AnimatedBuilder(
            animation: _controller,
            child: pose,
            builder: (context, child) {
              final curved = Curves.easeOutCubic.transform(_controller.value);
              return Transform.translate(
                offset: Offset(0, (1 - curved) * 4),
                child: Transform.scale(
                  scale: 0.96 + (0.04 * curved),
                  child: child,
                ),
              );
            },
          );

    if (widget.decorative) {
      return ExcludeSemantics(child: animatedPose);
    }
    final label = switch (widget.mood) {
      FardaCompanionMood.waving => 'Farda companion waving',
      FardaCompanionMood.quiet => 'Farda companion with a reminder card',
      FardaCompanionMood.resting => 'Farda companion resting',
      FardaCompanionMood.snoozed => 'Farda companion resting while reminder is snoozed',
      FardaCompanionMood.confirmed => 'Farda companion beside saved entry',
      FardaCompanionMood.skipped => 'Farda companion beside skipped entry',
    };
    return Semantics(label: label, child: animatedPose);
  }
}

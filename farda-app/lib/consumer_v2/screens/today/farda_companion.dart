import 'package:flutter/material.dart';

import '../../design_system/farda_consumer_tokens.dart' as design;

/// Existing Today/You interface to the exact exported Figma companion poses.
/// Confirmed, snoozed, and skipped records use the quiet expression; the
/// adjacent text always carries the explicit record meaning.
enum FardaCompanionMood { waving, quiet, resting, snoozed, confirmed, skipped }

class FardaCompanion extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final pose = mood == FardaCompanionMood.waving
        ? design.FardaCompanionPose.wave
        : design.FardaCompanionPose.quiet;
    final artwork = design.FardaCompanion(
      pose: pose,
      size: size,
      floating: true,
    );
    if (decorative) return artwork;
    final label = switch (mood) {
      FardaCompanionMood.waving => 'Farda companion waving',
      FardaCompanionMood.quiet => 'Farda companion resting',
      FardaCompanionMood.resting => 'Farda companion resting',
      FardaCompanionMood.snoozed =>
        'Farda companion resting while reminder is snoozed',
      FardaCompanionMood.confirmed => 'Farda companion beside saved entry',
      FardaCompanionMood.skipped => 'Farda companion beside skipped entry',
    };
    return Semantics(label: label, child: artwork);
  }
}

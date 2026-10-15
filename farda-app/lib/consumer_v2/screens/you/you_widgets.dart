import 'package:flutter/material.dart';

import '../../design_system/farda_scene.dart';

abstract final class FardaYouPalette {
  static const ivory = Color(0xFFF6F5F0);
  static const card = Color(0xFFFFFFFF);
  static const navy = Color(0xFF142C55);
  static const navyDeep = Color(0xFF0D2042);
  static const blue = Color(0xFF365C99);
  static const paleBlue = Color(0xFFE9EEF7);
  static const softBlue = Color(0xFFD9E4F4);
  static const textSecondary = Color(0xFF58677D);
  static const border = Color(0xFFDCE2EB);
  static const warm = Color(0xFF80500E);
  static const warmBackground = Color(0xFFF7EAD5);
  static const amber = Color(0xFFF2C983);
  static const danger = Color(0xFF8B303A);
  static const dangerBackground = Color(0xFFF8E7E9);
}

TextStyle fardaYouText({
  double size = 14,
  double? height,
  FontWeight weight = FontWeight.w400,
  Color color = FardaYouPalette.navy,
  double? letterSpacing,
}) {
  return TextStyle(
    fontFamily: 'Outfit',
    fontSize: size,
    height: height == null ? null : height / size,
    fontWeight: weight,
    color: color,
    letterSpacing: letterSpacing,
  );
}

class FardaYouPageCanvas extends StatelessWidget {
  const FardaYouPageCanvas({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.fromLTRB(22, 8, 22, 36),
  });

  final List<Widget> children;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: padding,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ),
    );
  }
}

class FardaYouBrandHeader extends StatelessWidget {
  const FardaYouBrandHeader({
    super.key,
    this.profileLabel = 'YO',
    this.onProfilePressed,
    this.selected = false,
  });

  final String profileLabel;
  final VoidCallback? onProfilePressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 18;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Semantics(
          header: true,
          child: Text(
            'farda.',
            style: fardaYouText(
              size: largeText ? 24 : 30,
              height: 39,
              weight: FontWeight.w600,
              letterSpacing: -1.8,
            ),
          ),
        ),
        Semantics(
          button: true,
          selected: selected,
          label: selected ? 'Your space, current page' : 'Open your space',
          child: Material(
            color: FardaYouPalette.paleBlue,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onProfilePressed,
              child: ConstrainedBox(
                constraints: const BoxConstraints.tightFor(
                  width: 36,
                  height: 36,
                ),
                child: Center(
                  child: Text(
                    profileLabel,
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    style: fardaYouText(size: 11, weight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class FardaYouBackButton extends StatelessWidget {
  const FardaYouBackButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Back to your space',
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: FardaYouPalette.navy,
          minimumSize: const Size(48, 44),
          padding: EdgeInsets.zero,
          alignment: Alignment.centerLeft,
          textStyle: fardaYouText(size: 12, weight: FontWeight.w600),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: Text('Back to your space')),
            SizedBox(width: 6),
            Icon(Icons.arrow_forward_ios_rounded, size: 12),
          ],
        ),
      ),
    );
  }
}

class FardaYouPageHeader extends StatelessWidget {
  const FardaYouPageHeader({
    super.key,
    required this.eyebrow,
    required this.title,
    this.supportingText,
  });

  final String eyebrow;
  final String title;
  final String? supportingText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow.toUpperCase(),
          style: fardaYouText(
            size: 10,
            height: 14,
            weight: FontWeight.w600,
            color: FardaYouPalette.textSecondary,
            letterSpacing: 1.45,
          ),
        ),
        const SizedBox(height: 8),
        Semantics(
          header: true,
          child: Text(
            title,
            style: fardaYouText(
              size: 34,
              height: 38,
              weight: FontWeight.w600,
              letterSpacing: -0.8,
            ),
          ),
        ),
        if (supportingText != null) ...[
          const SizedBox(height: 10),
          Text(
            supportingText!,
            style: fardaYouText(
              size: 14,
              height: 20,
              color: FardaYouPalette.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}

class FardaYouCard extends StatelessWidget {
  const FardaYouCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.color = FardaYouPalette.card,
    this.borderColor = Colors.transparent,
    this.radius = 24,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color color;
  final Color borderColor;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class FardaYouLinkRow extends StatelessWidget {
  const FardaYouLinkRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.vectorIcon,
    required this.onTap,
    this.preview = false,
  });

  final String title;
  final String subtitle;
  final String vectorIcon;
  final VoidCallback onTap;
  final bool preview;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$title. ${preview ? 'Local preview. ' : ''}$subtitle',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: FardaYouPalette.paleBlue,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: FardaVectorIcon(vectorIcon),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        style: fardaYouText(
                          size: 14,
                          height: 20,
                          weight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: fardaYouText(
                          size: 12,
                          height: 17,
                          color: FardaYouPalette.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (preview) ...[
                  const SizedBox(width: 8),
                  Container(
                    width: 44,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: FardaYouPalette.paleBlue,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'TRY',
                      style: fardaYouText(
                        size: 10,
                        height: 14,
                        weight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                const FardaVectorIcon('icon-arrow', size: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class FardaYouIconTile extends StatelessWidget {
  const FardaYouIconTile({
    super.key,
    this.icon,
    this.vectorIcon,
    this.warm = false,
    this.size = 44,
  }) : assert(icon != null || vectorIcon != null);

  final IconData? icon;
  final String? vectorIcon;
  final bool warm;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: warm ? FardaYouPalette.warmBackground : FardaYouPalette.paleBlue,
        borderRadius: BorderRadius.circular(size * 0.33),
      ),
      alignment: Alignment.center,
      child:
          vectorIcon != null
              ? FardaVectorIcon(vectorIcon!, size: size * 0.55)
              : Icon(
                icon,
                size: size * 0.5,
                color: warm ? FardaYouPalette.warm : FardaYouPalette.navy,
              ),
    );
  }
}

class FardaYouSettingRow extends StatelessWidget {
  const FardaYouSettingRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.showDivider = true,
    this.compact = false,
  });

  final String title;
  final String subtitle;
  final Widget trailing;
  final bool showDivider;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(minHeight: compact ? 40 : 72),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: compact ? 0 : 11),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: fardaYouText(
                          size: compact ? 14 : 15,
                          height: 20,
                          weight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: fardaYouText(
                          size: 12,
                          height: 17,
                          color: FardaYouPalette.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                trailing,
              ],
            ),
          ),
        ),
        if (showDivider)
          const Divider(height: 1, color: FardaYouPalette.border),
      ],
    );
  }
}

class FardaYouSwitch extends StatelessWidget {
  const FardaYouSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    required this.semanticLabel,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final duration =
        MediaQuery.maybeOf(context)?.disableAnimations == true
            ? Duration.zero
            : const Duration(milliseconds: 180);
    return Semantics(
      toggled: value,
      label: semanticLabel,
      enabled: onChanged != null,
      child: InkWell(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(
          width: 44,
          height: 40,
          child: Center(
            child: AnimatedContainer(
              duration: duration,
              width: 44,
              height: 28,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: value ? FardaYouPalette.navy : const Color(0xFFDCE2EB),
                borderRadius: BorderRadius.circular(16),
              ),
              child: AnimatedAlign(
                duration: duration,
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: SizedBox.square(dimension: 22),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class FardaYouNotice extends StatelessWidget {
  const FardaYouNotice({super.key, required this.text, this.warm = false});

  final String text;
  final bool warm;

  @override
  Widget build(BuildContext context) {
    final foreground =
        warm ? FardaYouPalette.warm : FardaYouPalette.textSecondary;
    return Semantics(
      container: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color:
              warm ? FardaYouPalette.warmBackground : FardaYouPalette.paleBlue,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FardaVectorIcon('icon-info', size: 18, color: foreground),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: fardaYouText(size: 12, height: 18, color: foreground),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FardaYouPrimaryButton extends StatelessWidget {
  const FardaYouPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.backgroundColor = FardaYouPalette.navy,
    this.foregroundColor = Colors.white,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 50),
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          disabledBackgroundColor: const Color(0xFFD6DDE7),
          disabledForegroundColor: const Color(0xFF7A879A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          textStyle: fardaYouText(
            size: 14,
            weight: FontWeight.w600,
            color: foregroundColor,
          ),
        ),
        icon: icon == null ? const SizedBox.shrink() : Icon(icon, size: 20),
        label: Text(label),
      ),
    );
  }
}

class FardaYouSecondaryButton extends StatelessWidget {
  const FardaYouSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.foregroundColor = FardaYouPalette.navy,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 50),
          foregroundColor: foregroundColor,
          side: const BorderSide(color: Color(0xFFBCC8DA)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          textStyle: fardaYouText(
            size: 14,
            weight: FontWeight.w600,
            color: foregroundColor,
          ),
        ),
        icon: icon == null ? const SizedBox.shrink() : Icon(icon, size: 20),
        label: Text(label),
      ),
    );
  }
}

class FardaPreviewBadge extends StatelessWidget {
  const FardaPreviewBadge({
    super.key,
    required this.label,
    this.onDark = false,
  });

  final String label;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color:
            onDark
                ? Colors.white.withValues(alpha: 0.12)
                : FardaYouPalette.paleBlue,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label.toUpperCase(),
        style: fardaYouText(
          size: 10,
          height: 13,
          weight: FontWeight.w600,
          color: onDark ? Colors.white : FardaYouPalette.navy,
          letterSpacing: 0.65,
        ),
      ),
    );
  }
}

class FardaReminderCadence extends StatelessWidget {
  const FardaReminderCadence({
    super.key,
    required this.callDelayMinutes,
    this.activeIndex = 1,
    this.onStepPressed,
    this.onDark = false,
  });

  final int callDelayMinutes;
  final int activeIndex;
  final ValueChanged<int>? onStepPressed;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final foreground = onDark ? Colors.white : FardaYouPalette.navy;
    final secondary =
        onDark
            ? Colors.white.withValues(alpha: 0.72)
            : FardaYouPalette.textSecondary;
    final steps = [
      ('8:50', 'Heads-up'),
      ('9:00', 'Routine due'),
      ('9:${callDelayMinutes.toString().padLeft(2, '0')}', 'Optional call'),
    ];

    return Semantics(
      container: true,
      label:
          'Reminder rhythm. 8:50 heads-up, 9:00 routine due, 9:${callDelayMinutes.toString().padLeft(2, '0')} optional call.',
      child: FardaYouCard(
        color:
            onDark
                ? Colors.white.withValues(alpha: 0.09)
                : FardaYouPalette.card,
        borderColor:
            onDark
                ? Colors.white.withValues(alpha: 0.16)
                : FardaYouPalette.border,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'YOUR REMINDER RHYTHM',
              style: fardaYouText(
                size: 10,
                weight: FontWeight.w600,
                color: secondary,
                letterSpacing: 1.25,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              'A heads-up. A moment. A real ring.',
              style: fardaYouText(
                size: 15,
                height: 20,
                weight: FontWeight.w600,
                color: foreground,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var index = 0; index < steps.length; index++) ...[
                  Expanded(
                    child: _CadenceStep(
                      time: steps[index].$1,
                      label: steps[index].$2,
                      selected: index == activeIndex,
                      onPressed:
                          onStepPressed == null
                              ? null
                              : () => onStepPressed!(index),
                      onDark: onDark,
                    ),
                  ),
                  if (index < steps.length - 1)
                    Container(
                      height: 2,
                      margin: const EdgeInsets.only(top: 9),
                      color:
                          onDark
                              ? Colors.white.withValues(alpha: 0.2)
                              : FardaYouPalette.softBlue,
                      width: 14,
                    ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CadenceStep extends StatelessWidget {
  const _CadenceStep({
    required this.time,
    required this.label,
    required this.selected,
    required this.onPressed,
    required this.onDark,
  });

  final String time;
  final String label;
  final bool selected;
  final VoidCallback? onPressed;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final foreground = onDark ? Colors.white : FardaYouPalette.navy;
    final secondary =
        onDark
            ? Colors.white.withValues(alpha: 0.68)
            : FardaYouPalette.textSecondary;
    final child = Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: selected ? 20 : 14,
          height: selected ? 20 : 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color:
                selected
                    ? (onDark ? Colors.white : FardaYouPalette.navy)
                    : Colors.transparent,
            border: Border.all(
              color:
                  onDark
                      ? Colors.white.withValues(alpha: 0.72)
                      : FardaYouPalette.blue,
              width: 2,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          time,
          style: fardaYouText(
            size: 13,
            weight: FontWeight.w600,
            color: foreground,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: TextAlign.center,
          style: fardaYouText(size: 10, height: 14, color: secondary),
        ),
      ],
    );

    if (onPressed == null) return child;
    return Semantics(
      button: true,
      selected: selected,
      label: '$time, $label',
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 68),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: child,
          ),
        ),
      ),
    );
  }
}

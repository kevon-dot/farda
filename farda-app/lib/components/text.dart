part of '_components.dart';

class TextMedium extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;

  const TextMedium({super.key, required this.text, this.style, this.textAlign});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FardaColors>();
    final mergeStyle = theme.textTheme.bodyLarge
        ?.copyWith(color: colors?.baseBlack)
        .merge(style);
    return Text(text, style: mergeStyle, textAlign: textAlign);
  }
}

class DividerTextHorizontal extends StatelessWidget {
  final String text;
  final Color? dividerColor;
  final TextStyle? textStyle;

  const DividerTextHorizontal({
    super.key,
    required this.text,
    this.dividerColor,
    this.textStyle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FardaColors>()!;
    final mergeStyle = theme.textTheme.bodySmall
        ?.merge(TextStyle(color: colors.slate.shade300, fontSize: 14.sp))
        .merge(textStyle);
    return Row(
      children: [
        Expanded(
          child: Divider(
            color: dividerColor ?? colors.slate.shade300,
            thickness: 1.h,
            endIndent: 8,
          ),
        ),
        Text(text, style: mergeStyle),
        Expanded(
          child: Divider(
            color: dividerColor ?? colors.slate.shade300,
            thickness: 1.h,
            indent: 8,
          ),
        ),
      ],
    );
  }
}

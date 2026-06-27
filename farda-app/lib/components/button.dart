part of '_components.dart';

class ButtonPrimary extends StatelessWidget {
  final String text;
  final TextStyle? textStyle;
  final ButtonStyle? buttonStyle;
  final Function()? onClick;

  const ButtonPrimary({
    super.key,
    required this.text,
    this.textStyle,
    this.buttonStyle,
    this.onClick,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mergeStyle = TextStyle(
      fontFamily: 'Outfit',
      fontWeight: FontWeight.w600,
      fontSize: 16.sp,
      color: theme.colorScheme.onPrimary,
    ).merge(textStyle);
    final buttonStyleMerge = Theme.of(
      context,
    ).elevatedButtonTheme.style?.merge(buttonStyle);
    return ElevatedButton(
      style: buttonStyleMerge,
      onPressed: onClick,
      child: Text(text, style: mergeStyle),
    );
  }
}

class ButtonSecondary extends StatelessWidget {
  final String text;
  final TextStyle? textStyle;
  final ButtonStyle? buttonStyle;
  final Widget? prefixIcon; // Optional icon
  final Function()? onClick;

  const ButtonSecondary({
    super.key,
    required this.text,
    this.textStyle,
    this.buttonStyle,
    this.prefixIcon,
    this.onClick,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FardaColors>()!;
    final mergeStyle = TextStyle(
      fontFamily: 'Outfit',
      fontWeight: FontWeight.w500,
      fontSize: 16.sp,
      color: theme.colorScheme.onSecondary,
    ).merge(textStyle);

    final buttonStyleMerge = ButtonStyle(
      backgroundColor: WidgetStatePropertyAll(colors.slate.shade100),
      foregroundColor: WidgetStatePropertyAll(colors.baseBlack),
    ).merge(Theme.of(context).elevatedButtonTheme.style).merge(buttonStyle);

    return ElevatedButton(
      style: buttonStyleMerge,
      onPressed: onClick,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (prefixIcon != null) ...[prefixIcon!, const SizedBox(width: 8)],
          Text(text, style: mergeStyle),
        ],
      ),
    );
  }
}

class ButtonTertiary extends StatelessWidget {
  final String text;
  final TextStyle? textStyle;
  final ButtonStyle? buttonStyle;
  final Widget? prefixIcon;
  final Function()? onClick;

  const ButtonTertiary({
    super.key,
    required this.text,
    this.textStyle,
    this.buttonStyle,
    this.prefixIcon,
    this.onClick,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FardaColors>()!;
    final mergeStyle = TextStyle(
      fontFamily: 'Outfit',
      fontWeight: FontWeight.w500,
      fontSize: 16.sp,
      color: colors.baseBlack,
    ).merge(textStyle);

    final outlineStyle = OutlinedButton.styleFrom(
      foregroundColor: colors.baseBlack,
      side: BorderSide(color: colors.slate.shade400),
      padding: EdgeInsets.symmetric(horizontal: 28.w, vertical: 14.h),
    ).merge(buttonStyle);

    return OutlinedButton(
      style: outlineStyle,
      onPressed: onClick,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (prefixIcon != null) ...[prefixIcon!, const SizedBox(width: 8)],
          Text(text, style: mergeStyle,overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class FeelingChip extends StatelessWidget {
  final String label;
  final String count;
  final VoidCallback? onTap;

  const FeelingChip({
    super.key,
    required this.label,
    required this.count,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // final textTheme = theme.textTheme;
    final colors = theme.extension<FardaColors>()!;
    // final spacing = theme.extension<Spacing>()!;
    return Material(
      color: colors.baseBlack,
      borderRadius: BorderRadius.circular(40),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(40),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 32.h,
                height: 32.h,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: TextMedium(
                  text: count,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                ),
              ),
              12.horizontalSpace,
              TextMedium(
                text: label,
                style: TextStyle(
                  color: colors.baseWhite,
                  fontWeight: FontWeight.w600,
                ),
              ),
              12.horizontalSpace,
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

abstract final class ConsumerPalette {
  static const navy = Color(0xFF142C55);
  static const deep = Color(0xFF0B1D3C);
  static const blue = Color(0xFF365C99);
  static const pale = Color(0xFFE9EEF7);
  static const cream = Color(0xFFF6F5F0);
  static const muted = Color(0xFF58677D);
  static const line = Color(0xFFDCE2EB);
  static const amber = Color(0xFF80500E);
  static const warm = Color(0xFFF8ECD8);
  static ThemeData get theme => ThemeData(
    useMaterial3: true,
    fontFamily: 'Outfit',
    scaffoldBackgroundColor: cream,
    colorScheme: ColorScheme.fromSeed(
      seedColor: navy,
      primary: navy,
      surface: cream,
      onSurface: navy,
    ),
    textTheme: ThemeData(
      fontFamily: 'Outfit',
    ).textTheme.apply(bodyColor: navy, displayColor: navy),
    dividerColor: line,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.all(16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: line),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: cream,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: cream,
      indicatorColor: pale,
      labelTextStyle: WidgetStateProperty.all(
        const TextStyle(
          fontFamily: 'Outfit',
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: navy,
        ),
      ),
    ),
  );
}

TextStyle consumerText(
  double size, {
  Color color = ConsumerPalette.navy,
  FontWeight weight = FontWeight.w400,
  double height = 1.35,
}) => TextStyle(
  fontFamily: 'Outfit',
  fontSize: size,
  color: color,
  fontWeight: weight,
  height: height,
);

class ConsumerCompanion extends StatelessWidget {
  const ConsumerCompanion({super.key, this.size = 96, this.quiet = false});
  final double size;
  final bool quiet;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      width: size,
      height: size,
      child: Opacity(
        opacity: quiet ? .9 : 1,
        child: SvgPicture.asset('assets/images/farda-companion-wave.svg'),
      ),
    ),
  );
}

class ConsumerCard extends StatelessWidget {
  const ConsumerCard({
    super.key,
    required this.child,
    this.color = Colors.white,
    this.padding = const EdgeInsets.all(20),
    this.margin = const EdgeInsets.only(bottom: 14),
  });
  final Widget child;
  final Color color;
  final EdgeInsets padding;
  final EdgeInsets margin;
  @override
  Widget build(BuildContext context) => Container(
    margin: margin,
    padding: padding,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: ConsumerPalette.line.withValues(alpha: .55)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x06142C55),
          blurRadius: 20,
          offset: Offset(0, 5),
        ),
      ],
    ),
    child: Material(type: MaterialType.transparency, child: child),
  );
}

class ConsumerButton extends StatelessWidget {
  const ConsumerButton(
    this.label, {
    super.key,
    required this.onPressed,
    this.secondary = false,
    this.light = false,
    this.icon,
    this.busy = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool secondary;
  final bool light;
  final IconData? icon;
  final bool busy;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: FilledButton(
      onPressed: busy ? null : onPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 52),
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 15),
        backgroundColor:
            light
                ? ConsumerPalette.cream
                : secondary
                ? ConsumerPalette.pale
                : ConsumerPalette.navy,
        foregroundColor:
            light || secondary ? ConsumerPalette.navy : Colors.white,
        disabledBackgroundColor: ConsumerPalette.line,
        disabledForegroundColor: ConsumerPalette.muted,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        children: [
          if (busy)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          if (icon != null && !busy) Icon(icon, size: 19),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    ),
  );
}

class ConsumerHeading extends StatelessWidget {
  const ConsumerHeading(this.title, {super.key, this.eyebrow, this.subtitle});
  final String title;
  final String? eyebrow;
  final String? subtitle;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (eyebrow != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              eyebrow!,
              style: consumerText(
                10,
                color: ConsumerPalette.muted,
                weight: FontWeight.w600,
              ).copyWith(letterSpacing: 1.4),
            ),
          ),
        Text(
          title,
          style: consumerText(
            36,
            weight: FontWeight.w600,
            height: 1.06,
          ).copyWith(letterSpacing: -1.2),
        ),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              subtitle!,
              style: consumerText(14, color: ConsumerPalette.muted),
            ),
          ),
      ],
    ),
  );
}

class ConsumerNotice extends StatelessWidget {
  const ConsumerNotice(
    this.text, {
    super.key,
    this.attention = false,
    this.action,
    this.actionLabel,
  });
  final String text;
  final bool attention;
  final VoidCallback? action;
  final String? actionLabel;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: attention ? ConsumerPalette.warm : ConsumerPalette.pale,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2, right: 10),
              child: Icon(
                attention
                    ? Icons.info_outline_rounded
                    : Icons.lock_outline_rounded,
                size: 17,
                color: attention ? ConsumerPalette.amber : ConsumerPalette.blue,
              ),
            ),
            Expanded(
              child: Text(
                text,
                style: consumerText(
                  12,
                  color:
                      attention ? ConsumerPalette.amber : ConsumerPalette.muted,
                ),
              ),
            ),
          ],
        ),
        if (action != null)
          TextButton(
            onPressed: action,
            child: Text(actionLabel ?? 'Try again'),
          ),
      ],
    ),
  );
}

class ConsumerLink extends StatelessWidget {
  const ConsumerLink(
    this.title,
    this.subtitle,
    this.icon, {
    super.key,
    required this.onTap,
  });
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(16),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: ConsumerPalette.pale,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: ConsumerPalette.navy, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: consumerText(15, weight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: consumerText(12, color: ConsumerPalette.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right_rounded, size: 22),
        ],
      ),
    ),
  );
}

class ConsumerPill extends StatelessWidget {
  const ConsumerPill(this.label, {super.key, this.light = false, this.icon});
  final String label;
  final bool light;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: light ? Colors.white.withValues(alpha: .12) : ConsumerPalette.pale,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(
            icon,
            size: 13,
            color: light ? Colors.white : ConsumerPalette.blue,
          ),
          const SizedBox(width: 5),
        ],
        Flexible(
          child: Text(
            label,
            style: consumerText(
              10,
              color: light ? Colors.white : ConsumerPalette.blue,
              weight: FontWeight.w500,
            ),
          ),
        ),
      ],
    ),
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Semantic tokens from the editable consumer-v2 Figma file.
///
/// Keeping these separate from the legacy app theme lets the new experience
/// ship without changing authentication, onboarding, or setup screens.
abstract final class FardaConsumerColors {
  static const canvas = Color(0xFFF6F5F0);
  static const card = Color(0xFFFFFFFF);
  static const brand = Color(0xFF142C55);
  static const deep = Color(0xFF0B1D3C);
  static const soft = Color(0xFFE9EEF7);
  static const warm = Color(0xFFF8ECD8);
  static const peach = Color(0xFFF4D9C9);
  static const lilac = Color(0xFFECE8F7);
  static const mint = Color(0xFFDDEFE5);
  static const textPrimary = Color(0xFF142C55);
  static const textSecondary = Color(0xFF58677D);
  static const textInverse = Color(0xFFFFFFFF);
  static const textWarm = Color(0xFF80500E);
  static const border = Color(0xFFDCE2EB);
  static const accent = Color(0xFF365C99);
  static const success = Color(0xFF18744A);
  static const warning = Color(0xFF9A6400);
}

abstract final class FardaConsumerSpace {
  static const xxs = 4.0;
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 20.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const page = 22.0;
}

abstract final class FardaConsumerRadius {
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
}

abstract final class FardaConsumerType {
  static const display = TextStyle(
    fontFamily: 'Outfit',
    fontSize: 34,
    height: 37 / 34,
    fontWeight: FontWeight.w600,
    color: FardaConsumerColors.textPrimary,
  );

  static const heading = TextStyle(
    fontFamily: 'Outfit',
    fontSize: 26,
    height: 30 / 26,
    fontWeight: FontWeight.w600,
    color: FardaConsumerColors.textPrimary,
  );

  static const title = TextStyle(
    fontFamily: 'Outfit',
    fontSize: 18,
    height: 24 / 18,
    fontWeight: FontWeight.w600,
    color: FardaConsumerColors.textPrimary,
  );

  static const bodyStrong = TextStyle(
    fontFamily: 'Outfit',
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w600,
    color: FardaConsumerColors.textPrimary,
  );

  static const body = TextStyle(
    fontFamily: 'Outfit',
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w400,
    color: FardaConsumerColors.textPrimary,
  );

  static const caption = TextStyle(
    fontFamily: 'Outfit',
    fontSize: 12,
    height: 17 / 12,
    fontWeight: FontWeight.w400,
    color: FardaConsumerColors.textSecondary,
  );

  static const label = TextStyle(
    fontFamily: 'Outfit',
    fontSize: 10,
    height: 14 / 10,
    fontWeight: FontWeight.w600,
    color: FardaConsumerColors.textPrimary,
  );
}

abstract final class FardaConsumerTheme {
  static ThemeData from(ThemeData base) {
    final scheme = base.colorScheme.copyWith(
      primary: FardaConsumerColors.brand,
      onPrimary: FardaConsumerColors.textInverse,
      secondary: FardaConsumerColors.soft,
      onSecondary: FardaConsumerColors.textPrimary,
      surface: FardaConsumerColors.canvas,
      onSurface: FardaConsumerColors.textPrimary,
      outline: FardaConsumerColors.border,
    );

    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: FardaConsumerColors.canvas,
      canvasColor: FardaConsumerColors.canvas,
      dividerColor: FardaConsumerColors.border,
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: FardaConsumerColors.brand,
          foregroundColor: FardaConsumerColors.textInverse,
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(FardaConsumerRadius.md),
          ),
          textStyle: FardaConsumerType.bodyStrong,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: FardaConsumerColors.brand,
          minimumSize: const Size(0, 48),
          side: const BorderSide(color: FardaConsumerColors.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(FardaConsumerRadius.md),
          ),
          textStyle: FardaConsumerType.bodyStrong,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: FardaConsumerColors.soft,
        selectedColor: FardaConsumerColors.brand,
        labelStyle: FardaConsumerType.caption.copyWith(
          color: FardaConsumerColors.brand,
          fontWeight: FontWeight.w600,
        ),
        secondaryLabelStyle: FardaConsumerType.caption.copyWith(
          color: FardaConsumerColors.textInverse,
          fontWeight: FontWeight.w600,
        ),
        side: BorderSide.none,
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      ),
      textTheme: base.textTheme.apply(
        fontFamily: 'Outfit',
        bodyColor: FardaConsumerColors.textPrimary,
        displayColor: FardaConsumerColors.textPrimary,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: FardaConsumerColors.canvas,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: FardaConsumerColors.canvas,
        surfaceTintColor: Colors.transparent,
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: FardaConsumerColors.deep,
        contentTextStyle: TextStyle(
          fontFamily: 'Outfit',
          color: FardaConsumerColors.textInverse,
        ),
        behavior: SnackBarBehavior.floating,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? FardaConsumerColors.card
              : FardaConsumerColors.textSecondary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? FardaConsumerColors.brand
              : FardaConsumerColors.border,
        ),
      ),
    );
  }
}

class FardaConsumerCard extends StatelessWidget {
  const FardaConsumerCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(FardaConsumerSpace.lg),
    this.color = FardaConsumerColors.card,
    this.radius = FardaConsumerRadius.lg,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final double radius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Padding(padding: padding, child: child);
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(radius),
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? content
          : InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(radius),
              child: content,
            ),
    );
  }
}

class FardaBrandHeader extends StatelessWidget {
  const FardaBrandHeader({super.key, this.onProfileTap});

  final VoidCallback? onProfileTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          'farda.',
          style: TextStyle(
            fontFamily: 'Outfit',
            fontSize: 30,
            height: 39 / 30,
            fontWeight: FontWeight.w600,
            color: FardaConsumerColors.brand,
          ),
        ),
        Semantics(
          button: true,
          label: 'Open your space',
          child: Material(
            color: FardaConsumerColors.soft,
            borderRadius: BorderRadius.circular(FardaConsumerRadius.md),
            child: InkWell(
              onTap: onProfileTap,
              borderRadius: BorderRadius.circular(FardaConsumerRadius.md),
              child: const SizedBox(
                width: 44,
                height: 44,
                child: Center(child: Text('YO', style: FardaConsumerType.label)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

enum FardaCompanionPose { wave, calendar, quiet }

class FardaCompanion extends StatelessWidget {
  const FardaCompanion({
    super.key,
    this.pose = FardaCompanionPose.wave,
    this.size = 100,
    this.useVectorForWave = true,
  });

  final FardaCompanionPose pose;
  final double size;
  final bool useVectorForWave;

  @override
  Widget build(BuildContext context) {
    if (pose == FardaCompanionPose.wave && useVectorForWave) {
      return ExcludeSemantics(
        child: SvgPicture.asset(
          'assets/images/farda_companion_wave.svg',
          width: size,
          height: size,
        ),
      );
    }

    final alignment = switch (pose) {
      FardaCompanionPose.wave => Alignment.centerLeft,
      FardaCompanionPose.calendar => Alignment.center,
      FardaCompanionPose.quiet => Alignment.centerRight,
    };

    return ExcludeSemantics(
      child: ClipRect(
        child: SizedBox(
          width: size,
          height: size,
          child: OverflowBox(
            alignment: alignment,
            minWidth: size * 3,
            maxWidth: size * 3,
            minHeight: size,
            maxHeight: size,
            child: Image.asset(
              'assets/images/farda_companion_trio.png',
              width: size * 3,
              height: size,
              fit: BoxFit.fill,
              filterQuality: FilterQuality.high,
            ),
          ),
        ),
      ),
    );
  }
}

class FardaInfoNotice extends StatelessWidget {
  const FardaInfoNotice({super.key, required this.message, this.icon});

  final String message;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(FardaConsumerSpace.sm),
      decoration: BoxDecoration(
        color: FardaConsumerColors.soft,
        borderRadius: BorderRadius.circular(FardaConsumerRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon ?? Icons.info_outline_rounded,
            size: 18,
            color: FardaConsumerColors.textSecondary,
          ),
          const SizedBox(width: FardaConsumerSpace.xs),
          Expanded(child: Text(message, style: FardaConsumerType.caption)),
        ],
      ),
    );
  }
}

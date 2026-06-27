import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

@immutable
class FardaColors extends ThemeExtension<FardaColors> {
  final ColorSwatch<int> success;
  final ColorSwatch<int> warning;
  final ColorSwatch<int> error;
  final MaterialColor slate;

  final Color baseWhite;
  final Color baseBlack;
  final Color blue;

  const FardaColors({
    required this.success,
    required this.warning,
    required this.error,
    required this.slate,
    this.baseWhite = const Color(0xFFFFFFFF),
    this.baseBlack = const Color(0xFF000000),
    this.blue = const Color(0xFF2D9CDB),
  });

  // Default light theme colors with baseWhite and baseBlack included
  static const FardaColors light = FardaColors(
    slate: MaterialColor(0xFF64748B, <int, Color>{
      50: Color(0xFFF8FAFC),
      100: Color(0xFFF1F5F9),
      200: Color(0xFFE2E8F0),
      300: Color(0xFFCBD5E1),
      400: Color(0xFF94A3B8),
      500: Color(0xFF64748B),
      600: Color(0xFF475569),
      700: Color(0xFF334155),
      800: Color(0xFF1E293B),
      900: Color(0xFF0F172A),
      950: Color(0xFF020617),
    }),
    success: ColorSwatch(500, <int, Color>{
      25: Color(0xFFF6FEF9),
      50: Color(0xFFECFDF3),
      100: Color(0xFFDCFAD6),
      200: Color(0xFFABEFC6),
      300: Color(0xFF75E0A7),
      400: Color(0xFF47CD89),
      500: Color(0xFF17B26A),
      600: Color(0xFF079455),
      700: Color(0xFF067647),
      800: Color(0xFF085D3A),
      900: Color(0xFF074D31),
      950: Color(0xFF053321),
    }),
    warning: ColorSwatch(500, <int, Color>{
      25: Color(0xFFFFFCF5),
      50: Color(0xFFFFFAEB),
      100: Color(0xFFFEEFC7),
      200: Color(0xFFFEDF89),
      300: Color(0xFFFEC84B),
      400: Color(0xFFFDB022),
      500: Color(0xFFF79009),
      600: Color(0xFFDC6803),
      700: Color(0xFFB54708),
      800: Color(0xFF93370D),
      900: Color(0xFF7A2E0E),
      950: Color(0xFF4E1D09),
    }),
    error: ColorSwatch(500, <int, Color>{
      25: Color(0xFFFFFBFA),
      50: Color(0xFFFEF3F2),
      100: Color(0xFFFEE4E2),
      200: Color(0xFFFECDCA),
      300: Color(0xFFFDA29B),
      400: Color(0xFFF97066),
      500: Color(0xFFF04438),
      600: Color(0xFFD92D20),
      700: Color(0xFFB42318),
      800: Color(0xFF912018),
      900: Color(0xFF7A271A),
    }),
    baseWhite: Color(0xFFFFFFFF),
    baseBlack: Color(0xFF000000),
  );

  @override
  FardaColors copyWith({
    ColorSwatch<int>? success,
    ColorSwatch<int>? warning,
    ColorSwatch<int>? error,
    MaterialColor? slate,
    Color? baseWhite,
    Color? baseBlack,
  }) {
    return FardaColors(
      success: success ?? this.success,
      warning: warning ?? this.warning,
      error: error ?? this.error,
      slate: slate ?? this.slate,
      baseWhite: baseWhite ?? this.baseWhite,
      baseBlack: baseBlack ?? this.baseBlack,
    );
  }

  @override
  FardaColors lerp(ThemeExtension<FardaColors>? other, double t) {
    if (other is! FardaColors) return this;
    return t < 0.5 ? this : other;
  }
}

@immutable
class Spacing extends ThemeExtension<Spacing> {
  final double xs;
  final double sm;
  final double md;
  final double lg;
  final double xl;

  const Spacing({
    required this.xs,
    required this.sm,
    required this.md,
    required this.lg,
    required this.xl,
  });

  @override
  Spacing copyWith({
    double? xs,
    double? sm,
    double? md,
    double? lg,
    double? xl,
  }) {
    return Spacing(
      xs: xs ?? this.xs,
      sm: sm ?? this.sm,
      md: md ?? this.md,
      lg: lg ?? this.lg,
      xl: xl ?? this.xl,
    );
  }

  @override
  Spacing lerp(ThemeExtension<Spacing>? other, double t) {
    if (other is! Spacing) return this;

    return Spacing(
      xs: lerpDouble(xs, other.xs, t) ?? xs,
      sm: lerpDouble(sm, other.sm, t) ?? sm,
      md: lerpDouble(md, other.md, t) ?? md,
      lg: lerpDouble(lg, other.lg, t) ?? lg,
      xl: lerpDouble(xl, other.xl, t) ?? xl,
    );
  }

  static Spacing light = Spacing(
    xs: 4.r,
    sm: 8.r,
    md: 16.r,
    lg: 24.r,
    xl: 32.r,
  );

  EdgeInsets get allM => EdgeInsets.all(16.w);

  EdgeInsets get horizontalDefault => EdgeInsets.symmetric(horizontal: 20.w);

  EdgeInsets get verticalS => EdgeInsets.symmetric(vertical: 8.h);
}

class AppTypo {
  static TextTheme typography = TextTheme(
    displayLarge: TextStyle(
      debugLabel: 'outfit displayLarge',
      fontFamily: 'Outfit',
      inherit: false,
      fontSize: 96.sp,
      fontWeight: FontWeight.w300,
      textBaseline: TextBaseline.alphabetic,
      letterSpacing: -1.5,
    ),
    displayMedium: TextStyle(
      debugLabel: 'outfit displayMedium',
      fontFamily: 'Outfit',
      inherit: false,
      fontSize: 60.sp,
      fontWeight: FontWeight.w300,
      textBaseline: TextBaseline.alphabetic,
      letterSpacing: -0.5,
    ),
    displaySmall: TextStyle(
      debugLabel: 'outfit displaySmall',
      fontFamily: 'Outfit',
      inherit: false,
      fontSize: 48.sp,
      fontWeight: FontWeight.w400,
      textBaseline: TextBaseline.alphabetic,
      letterSpacing: 0.0,
    ),
    headlineLarge: TextStyle(
      debugLabel: 'outfit headlineLarge',
      fontFamily: 'Outfit',
      inherit: false,
      fontSize: 40.sp,
      fontWeight: FontWeight.w400,
      textBaseline: TextBaseline.alphabetic,
      letterSpacing: 0.25,
    ),
    headlineMedium: TextStyle(
      debugLabel: 'outfit headlineMedium',
      fontFamily: 'Outfit',
      inherit: false,
      fontSize: 34.sp,
      fontWeight: FontWeight.w400,
      textBaseline: TextBaseline.alphabetic,
      letterSpacing: 0.25,
    ),
    headlineSmall: TextStyle(
      debugLabel: 'outfit headlineSmall',
      fontFamily: 'Outfit',
      inherit: false,
      fontSize: 24.sp,
      fontWeight: FontWeight.w400,
      textBaseline: TextBaseline.alphabetic,
      letterSpacing: 0.0,
    ),
    titleLarge: TextStyle(
      debugLabel: 'outfit titleLarge',
      fontFamily: 'Outfit',
      inherit: false,
      fontSize: 24.sp,
      fontWeight: FontWeight.w600,
      textBaseline: TextBaseline.alphabetic,
      letterSpacing: 0.15,
    ),
    titleMedium: TextStyle(
      debugLabel: 'outfit titleMedium',
      fontFamily: 'Outfit',
      inherit: false,
      fontSize: 20.sp,
      fontWeight: FontWeight.w500,
      textBaseline: TextBaseline.alphabetic,
      letterSpacing: 0.15,
    ),
    titleSmall: TextStyle(
      debugLabel: 'outfit titleSmall',
      fontFamily: 'Outfit',
      inherit: false,
      fontSize: 16.sp,
      fontWeight: FontWeight.w500,
      textBaseline: TextBaseline.alphabetic,
      letterSpacing: 0.1,
    ),
    bodyLarge: TextStyle(
      debugLabel: 'outfit bodyLarge',
      fontFamily: 'Outfit',
      inherit: false,
      fontSize: 16.sp,
      fontWeight: FontWeight.w400,
      textBaseline: TextBaseline.alphabetic,
      letterSpacing: 0.5,
    ),
    bodyMedium: TextStyle(
      debugLabel: 'outfit bodyMedium',
      fontFamily: 'Outfit',
      inherit: false,
      fontSize: 14.sp,
      fontWeight: FontWeight.w400,
      textBaseline: TextBaseline.alphabetic,
      letterSpacing: 0.25,
    ),
    bodySmall: TextStyle(
      debugLabel: 'outfit bodySmall',
      fontFamily: 'Outfit',
      inherit: false,
      fontSize: 12.sp,
      fontWeight: FontWeight.w400,
      textBaseline: TextBaseline.alphabetic,
      letterSpacing: 0.4,
    ),
    labelLarge: TextStyle(
      debugLabel: 'outfit labelLarge',
      fontFamily: 'Outfit',
      inherit: false,
      fontSize: 14.sp,
      fontWeight: FontWeight.w500,
      textBaseline: TextBaseline.alphabetic,
      letterSpacing: 1.25,
    ),
    labelMedium: TextStyle(
      debugLabel: 'outfit labelMedium',
      fontFamily: 'Outfit',
      inherit: false,
      fontSize: 11.sp,
      fontWeight: FontWeight.w400,
      textBaseline: TextBaseline.alphabetic,
      letterSpacing: 1.5,
    ),
    labelSmall: TextStyle(
      debugLabel: 'outfit labelSmall',
      fontFamily: 'Outfit',
      inherit: false,
      fontSize: 10.sp,
      fontWeight: FontWeight.w400,
      textBaseline: TextBaseline.alphabetic,
      letterSpacing: 1.5,
    ),
  );
}

class AppTheme {
  AppTheme._();

  static final theme = ThemeData(
    primarySwatch: FardaColors.light.slate,
    textTheme: AppTypo.typography.apply(
      fontSizeFactor: 1.1.sp,
      bodyColor: FardaColors.light.baseBlack,
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10.r), // Rounded corners
        borderSide: BorderSide(color: FardaColors.light.slate.shade200),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10.r),
        borderSide: BorderSide(color: FardaColors.light.slate.shade200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10.r),
        borderSide: BorderSide(color: FardaColors.light.slate.shade400),
      ),
      contentPadding: const EdgeInsets.all(16.0).w,
      hintStyle: TextStyle(color: FardaColors.light.slate[400]),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: const WidgetStatePropertyAll(Color(0xFF000000)),
        foregroundColor: const WidgetStatePropertyAll(Color(0xFFFFFFFF)),
        elevation: const WidgetStatePropertyAll(0),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(100.r)),
        ),
        textStyle: WidgetStatePropertyAll(
          TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold),
        ),
        padding: WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 28.w, vertical: 16.h),
        ),
      ),
    ),
    colorScheme: ColorScheme(
      brightness: Brightness.light,
      primary: FardaColors.light.baseBlack,
      onPrimary: FardaColors.light.baseWhite,
      secondary: FardaColors.light.slate.shade100,
      onSecondary: FardaColors.light.baseBlack,
      error: FardaColors.light.error[500]!,
      // error color
      onError: FardaColors.light.baseWhite,
      surface: FardaColors.light.baseWhite,
      onSurface: FardaColors.light.baseBlack,
    ),
    extensions: [FardaColors.light, Spacing.light],
  );
}

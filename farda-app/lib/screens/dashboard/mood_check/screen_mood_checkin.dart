
import 'package:farda/components/_components.dart';
import 'package:farda/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/svg.dart';

class ScreenMoodCheckIn extends StatelessWidget {
  const ScreenMoodCheckIn({super.key});

  @override
  Widget build(BuildContext context) {
    final chipLabels = ["Different feeling", "Day Streak", "Calm", "Focused"];

    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final colors = theme.extension<FardaColors>()!;
    final spacing = theme.extension<Spacing>()!;

    void onCheckInPressed() {
      showDialog(context: context, builder: (_) => const ThoughtDialog());
    }

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: spacing.horizontalDefault,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              20.verticalSpace,
              Text(
                "How are you feeling\nthis morning?",
                textAlign: TextAlign.center,
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 32),

              /// Color wheel with icon in center
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 0.65.sw,
                    height: 0.65.sw,
                    child: CircularProgressIndicator(
                      value: 1,
                      strokeWidth: 16,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Colors.transparent,
                      ),
                      backgroundColor: Colors.transparent,
                    ),
                  ),
                  ShaderMask(
                    shaderCallback: (rect) {
                      return SweepGradient(
                        colors: [
                          Colors.red,
                          Colors.purple,
                          Colors.blue,
                          Colors.green,
                          Colors.yellow,
                          Colors.orange,
                          Colors.red,
                        ],
                        startAngle: 0.0,
                        endAngle: 3.14 * 2,
                        tileMode: TileMode.clamp,
                      ).createShader(rect);
                    },
                    child: SizedBox(
                      width: 0.65.sw,
                      height: 0.65.sw,
                      child: CircularProgressIndicator(
                        strokeAlign: -1,
                        value: 1,
                        strokeWidth: 16,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Colors.white,
                        ),
                        backgroundColor: Colors.transparent,
                      ),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: onCheckInPressed,
                        icon: SvgPicture.asset("assets/icons/check_in_add.svg"),
                        color: Colors.black,
                      ),
                      TextMedium(
                        text: "Check in",
                        style: TextStyle(color: colors.slate.shade600),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 32),

              /// Chips
              Wrap(
                spacing: 12.w,
                runSpacing: 6.h,
                alignment: WrapAlignment.center,
                children:
                    chipLabels.map((label) {
                      return FeelingChip(
                        count: "4",
                        label: label,
                        onTap: () {
                          // handle chip tap
                        },
                      );
                    }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
  }


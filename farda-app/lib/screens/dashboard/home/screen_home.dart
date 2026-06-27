
import 'package:farda/components/_components.dart';
import 'package:farda/screens/dashboard/calendar/calender_provider.dart';
import 'package:farda/screens/dashboard/home/home_provider.dart';
import 'package:farda/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

class ScreenHome extends StatefulWidget {
  const ScreenHome({super.key});

  @override
  State<ScreenHome> createState() => _ScreenHomeState();
}

class _ScreenHomeState extends State<ScreenHome> {
  int selectedTab = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final colors = theme.extension<FardaColors>()!;
    final spacing = theme.extension<Spacing>()!;
    final provider = context.watch<CalenderProvider>();
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: spacing.horizontalDefault,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              20.verticalSpace,
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text("👋 Welcome back", style: textTheme.bodyMedium),
                  Text("2025", style: textTheme.bodyMedium),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Terry Roberts", style: textTheme.titleMedium),
                  Text(
                    "Sunday",
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              40.verticalSpace,
              PillProgressSection(
                remainingValue: "480",
                consumedValue: 740,
                consumedMax: 1000,
                targetValue: "1220",
              ),
              40.verticalSpace,
              Row(
                children: [
                  Expanded(
                    child: _doseCard(
                      context,
                      cardName: "Now",
                      emoji: "😕",
                      label: "First dose",
                      time: "8:00 AM",
                    ),
                  ),
                  12.horizontalSpace,
                  Expanded(
                    child: _doseCard(
                      context,
                      cardName: "Upcoming",
                      emoji: "🥞",
                      label: "Second dose",
                      time: "2:00 PM",
                    ),
                  ),
                ],
              ),
              40.verticalSpace,
              CustomTabSelector(
                tabs: ["Consumed", "Remaining"],
                selectedIndex: selectedTab,
                onTabSelected: (index) {
                  setState(() => selectedTab = index);
                },
              ),
              20.verticalSpace,
              TextMedium(
                text: "Insights & Analytics",
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              20.verticalSpace,
              Row(
                children: [
                  Expanded(
                    child: _analyticCard(
                      context,
                      title: "Pill Left Trend",
                      time: "19 Aug - Now",
                      isRtl: false,
                      color: colors.success[500]!,
                    ),
                  ),
                  12.horizontalSpace,
                  Expanded(
                    child: _analyticCard(
                      context,
                      title: "Pill Taking Trend",
                      time: "19 Aug - Now",
                      isRtl: true,
                      color: colors.error[500]!,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _analyticCard(
    BuildContext context, {
    required String title,
    required String time,
    required Color color,
    required bool isRtl,
  }) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final colors = theme.extension<FardaColors>()!;
    return Container(
      height: 150.h,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: colors.baseWhite,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: colors.slate.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            offset: Offset(0, 2),
            blurRadius: 24.r,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          16.verticalSpace,
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16).r,
            child: Text(
              title,
              style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16).r,
            child: Text(
              time,
              style: textTheme.bodyMedium?.copyWith(
                color: colors.slate.shade600,
              ),
            ),
          ),
          12.verticalSpace,
          Expanded(child: AnimatedChart(primaryColor: color, isRtl: isRtl)),
        ],
      ),
    );
  }

  Widget _doseCard(
    BuildContext context, {
    required String cardName,
    required String label,
    required String emoji,
    required String time,
  }) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final colors = theme.extension<FardaColors>()!;
    return Container(
      padding: EdgeInsets.all(16).r,
      decoration: BoxDecoration(
        color: colors.baseWhite,
        borderRadius: BorderRadius.circular(8.r),
        border: Border.all(color: colors.slate.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            offset: Offset(0, 2),
            blurRadius: 24.r,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                cardName,
                style: textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(emoji, style: textTheme.bodyLarge),
            ],
          ),
          8.verticalSpace,
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                "$label:",
                style: textTheme.bodyMedium?.copyWith(
                  color: colors.slate.shade700,
                  fontSize: 13.sp,
                ),
              ),
              Text(
                time,
                style: textTheme.bodyMedium?.copyWith(
                  color: colors.slate.shade400,
                  fontSize: 12.sp,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

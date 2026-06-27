
import 'package:farda/components/_components.dart';
import 'package:farda/screens/dashboard/calendar/calender_provider.dart';
import 'package:farda/screens/dashboard/home/home_data.dart';
import 'package:farda/screens/login/login_provider.dart';
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
    final loginProvider = context.watch<LoginProvider>();
    final patientName =
        loginProvider.name.isNotEmpty ? loginProvider.name : "Patient";

    // Real provider data -> Home view models (pure mapping in home_data.dart).
    final doses = dosesFromCalender(provider.doseTimeModel);
    final pillCounts = pillCountsFromCalender(provider.doseTimeModel);
    final adherenceSeries =
        adherenceSeriesFromCalender(provider.doseTimeModel);
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
                  Text(patientName, style: textTheme.titleMedium),
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
                remainingValue: pillCounts.remaining.toString(),
                consumedValue: pillCounts.consumed.toDouble(),
                // Avoid a zero max (division-by-zero in the progress arc) while
                // there is no real target yet.
                consumedMax: pillCounts.target > 0
                    ? pillCounts.target.toDouble()
                    : 1,
                targetValue: pillCounts.target.toString(),
              ),
              40.verticalSpace,
              _doseRow(context, doses),
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
                      isRtl: false,
                      color: colors.success[500]!,
                      series: adherenceSeries,
                    ),
                  ),
                  12.horizontalSpace,
                  Expanded(
                    child: _analyticCard(
                      context,
                      title: "Pill Taking Trend",
                      isRtl: true,
                      color: colors.error[500]!,
                      series: adherenceSeries,
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
    required Color color,
    required bool isRtl,
    required List<double> series,
  }) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final colors = theme.extension<FardaColors>()!;
    final hasSeries = series.length >= 2;
    return Container(
      height: 150.h,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: colors.baseWhite,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: colors.slate.shade200),
        boxShadow: [
          BoxShadow(
            color: colors.baseBlack.withValues(alpha: 0.06),
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
          // Only show a date range when there is a real series to range over.
          if (hasSeries)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16).r,
              child: Text(
                "Recent",
                style: textTheme.bodyMedium?.copyWith(
                  color: colors.slate.shade600,
                ),
              ),
            ),
          12.verticalSpace,
          Expanded(
            child: AnimatedChart(
              primaryColor: color,
              isRtl: isRtl,
              data: hasSeries ? series : null,
            ),
          ),
        ],
      ),
    );
  }

  /// Renders the row of upcoming-dose cards from real provider data. Shows the
  /// first two configured dose windows; if none are configured yet (providers
  /// still loading / empty), shows an explicit empty-state card instead of the
  /// old fabricated "First dose 8:00 AM / Second dose 2:00 PM" cards.
  Widget _doseRow(BuildContext context, List<HomeDose> doses) {
    if (doses.isEmpty) {
      return _emptyDoseCard(context);
    }

    final cards = <Widget>[];
    final count = doses.length < 2 ? doses.length : 2;
    for (var i = 0; i < count; i++) {
      if (i > 0) cards.add(12.horizontalSpace);
      cards.add(
        Expanded(
          child: _doseCard(
            context,
            cardName: i == 0 ? "Next" : "Upcoming",
            dose: doses[i],
          ),
        ),
      );
    }
    return Row(children: cards);
  }

  Widget _emptyDoseCard(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final colors = theme.extension<FardaColors>()!;
    return Container(
      padding: EdgeInsets.all(16).r,
      decoration: BoxDecoration(
        color: colors.baseWhite,
        borderRadius: BorderRadius.circular(8.r),
        border: Border.all(color: colors.slate.shade200),
      ),
      child: Text(
        "No dose times yet",
        style: textTheme.bodyMedium?.copyWith(color: colors.slate.shade600),
      ),
    );
  }

  Widget _doseCard(
    BuildContext context, {
    required String cardName,
    required HomeDose dose,
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
            color: colors.baseBlack.withValues(alpha: 0.06),
            offset: Offset(0, 2),
            blurRadius: 24.r,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            cardName,
            style: textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          8.verticalSpace,
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  "${dose.name}:",
                  style: textTheme.bodyMedium?.copyWith(
                    color: colors.slate.shade700,
                    fontSize: 13.sp,
                  ),
                ),
              ),
              Text(
                dose.time.isNotEmpty ? dose.time : "--",
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

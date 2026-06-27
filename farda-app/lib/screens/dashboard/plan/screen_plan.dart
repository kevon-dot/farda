import 'package:farda/components/_components.dart';
import 'package:farda/screens/dashboard/calendar/calender_provider.dart';
import 'package:farda/screens/dashboard/plan/plan_view_model.dart';
import 'package:farda/screens/prescription_info/prescription_provider.dart';
import 'package:farda/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

/// The "Plan" tab: a minimal, real view of the user's daily dose schedule /
/// adherence plan, derived from live provider data (dose times + the active
/// prescription's medicine). Ordering/derivation lives in [PlanViewModel] so it
/// stays unit-testable; this widget only renders.
class ScreenPlanHope extends StatelessWidget {
  const ScreenPlanHope({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FardaColors>()!;
    final spacing = theme.extension<Spacing>()!;

    final calendar = context.watch<CalenderProvider>();
    final prescription = context.watch<PrescriptionProvider>();

    final medicineName = _firstMedicineName(prescription);
    final items = PlanViewModel.scheduleFromDoses(
      calendar.doseTimeModel,
      medicineName: medicineName,
    );

    return Scaffold(
      backgroundColor: colors.baseWhite,
      body: SafeArea(
        child: Padding(
          padding: spacing.horizontalDefault,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              20.verticalSpace,
              Text(
                "Your Plan",
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              4.verticalSpace,
              TextMedium(
                text: "Your daily dose schedule and adherence plan",
                style: TextStyle(color: colors.slate.shade600),
              ),
              24.verticalSpace,
              Expanded(
                child: items.isEmpty
                    ? _EmptyPlan(colors: colors)
                    : ListView.separated(
                        itemCount: items.length,
                        separatorBuilder: (_, __) => 12.verticalSpace,
                        itemBuilder: (context, index) => _PlanItemCard(
                          item: items[index],
                          colors: colors,
                          theme: theme,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The medicine the user is adhering to: the first medicine of their first
  /// active prescription, if any.
  String? _firstMedicineName(PrescriptionProvider provider) {
    for (final p in provider.prescriptionModelList) {
      final meds = p.medicines;
      if (meds == null || meds.isEmpty) continue;
      final name = (meds.first.medicineName ?? '').trim();
      if (name.isNotEmpty) return name;
    }
    return null;
  }
}

class _PlanItemCard extends StatelessWidget {
  final PlanScheduleItem item;
  final FardaColors colors;
  final ThemeData theme;

  const _PlanItemCard({
    required this.item,
    required this.colors,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: colors.baseWhite,
        borderRadius: BorderRadius.circular(16.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            offset: const Offset(0, 2),
            blurRadius: 16,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            height: 48.h,
            width: 48.h,
            decoration: BoxDecoration(
              color: colors.slate.shade100,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.medication_outlined,
              color: theme.primaryColor,
              size: 24.h,
            ),
          ),
          16.horizontalSpace,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextMedium(
                  text: item.name,
                  style: TextStyle(
                    color: colors.baseBlack,
                    fontWeight: FontWeight.w600,
                    fontSize: 16.sp,
                  ),
                ),
                if (item.medicineName != null) ...[
                  4.verticalSpace,
                  TextMedium(
                    text: item.medicineName!,
                    style: TextStyle(color: colors.slate.shade600),
                  ),
                ],
              ],
            ),
          ),
          if (item.time.isNotEmpty)
            TextMedium(
              text: item.time,
              style: TextStyle(
                color: colors.slate.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyPlan extends StatelessWidget {
  final FardaColors colors;

  const _EmptyPlan({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.event_available_outlined,
            size: 48.h,
            color: colors.slate.shade300,
          ),
          16.verticalSpace,
          TextMedium(
            text: "No dose schedule yet",
            style: TextStyle(
              color: colors.slate.shade600,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          4.verticalSpace,
          TextMedium(
            text: "Your dose plan will appear here once it's set up.",
            style: TextStyle(color: colors.slate.shade400),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

import 'package:farda/application/refill/model/refill_model.dart';
import 'package:farda/components/_components.dart';
import 'package:farda/components/custom_snackbar.dart';
import 'package:farda/screens/refill/refill_provider.dart';
import 'package:farda/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

/// GTM-541 — the refill prediction + pharmacy-readiness screen.
///
/// Surfaces, per prescription:
///   * predicted depletion + refill-due dates and days-left (from the backend
///     `/refills` calc: remaining = qty − doses taken, rate = schedule),
///   * an in-app refill reminder banner when any prescription is due,
///   * a "pharmacy-readiness" pill (ready to request / requested) + actions to
///     capture refill events (requested / completed) back to the backend.
///
/// FLAG: "remaining" is an ESTIMATE from qty − logged doses today. When the
/// smart-vial weight sensor lands it will give a precise count; the UI already
/// distinguishes the source via [RefillModel.remainingSource].
class ScreenRefill extends StatefulWidget {
  const ScreenRefill({super.key});

  @override
  State<ScreenRefill> createState() => _ScreenRefillState();
}

class _ScreenRefillState extends State<ScreenRefill> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() => context.read<RefillProvider>().load();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FardaColors>()!;
    final spacing = theme.extension<Spacing>()!;
    final provider = context.watch<RefillProvider>();

    return ExtendedScaffold(
      appBar: CustomAppBar(
        titleType: AppBarTitleType.text,
        titleText: 'Refills',
        onBack: () =>
            context.canPop() ? context.pop() : context.go('/dashboard'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (provider.isLoading)
              LinearProgressIndicator(color: colors.blue),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: _body(context, provider, colors, spacing),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    RefillProvider provider,
    FardaColors colors,
    Spacing spacing,
  ) {
    if (!provider.isLoading &&
        provider.refills.isEmpty &&
        provider.error != null) {
      return ListView(
        children: [
          SizedBox(height: 120.h),
          Center(
            child: TextMedium(
              text: provider.error!,
              style: TextStyle(color: colors.slate.shade600),
            ),
          ),
        ],
      );
    }

    if (!provider.isLoading && provider.refills.isEmpty) {
      return ListView(
        children: [
          SizedBox(height: 120.h),
          Center(
            child: TextMedium(
              text: 'No prescriptions to track yet.',
              style: TextStyle(color: colors.slate.shade600),
            ),
          ),
        ],
      );
    }

    return ListView(
      padding: spacing.allM,
      children: [
        if (provider.hasDueRefills)
          _DueBanner(count: provider.dueRefills.length, colors: colors),
        _MetricsCard(metrics: provider.metrics, colors: colors),
        12.verticalSpace,
        ...provider.refills.map(
          (r) => Padding(
            padding: EdgeInsets.only(bottom: 12.h),
            child: _RefillCard(refill: r, colors: colors),
          ),
        ),
        20.verticalSpace,
      ],
    );
  }
}

/// In-app refill reminder banner (reuses the in-app surfacing pattern rather
/// than the local-notification plumbing). FLAG: a scheduled local notification
/// (via the GTM-537 NotificationService) could also fire on the refill-due date
/// — wiring that is a follow-up; surfaced in-app here for now.
class _DueBanner extends StatelessWidget {
  const _DueBanner({required this.count, required this.colors});

  final int count;
  final FardaColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      padding: EdgeInsets.all(14.r),
      decoration: BoxDecoration(
        color: colors.warning[100]!,
        borderRadius: BorderRadius.circular(14.r),
      ),
      child: Row(
        children: [
          Icon(Icons.notifications_active_outlined,
              color: colors.warning[700]!, size: 22.r),
          12.horizontalSpace,
          Expanded(
            child: TextMedium(
              text: count == 1
                  ? '1 prescription is due for a refill.'
                  : '$count prescriptions are due for a refill.',
              style: TextStyle(
                color: colors.warning[700]!,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricsCard extends StatelessWidget {
  const _MetricsCard({required this.metrics, required this.colors});

  final RefillMetrics metrics;
  final FardaColors colors;

  @override
  Widget build(BuildContext context) {
    final rate = metrics.completionRate;
    final rateLabel =
        rate == null ? '—' : '${(rate * 100).round()}%';
    return Container(
      padding: EdgeInsets.all(14.r),
      decoration: BoxDecoration(
        color: colors.baseWhite,
        borderRadius: BorderRadius.circular(14.r),
        boxShadow: [
          BoxShadow(
            color: colors.baseBlack.withValues(alpha: 0.06),
            offset: const Offset(0, 2),
            blurRadius: 16,
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _metric('On-time rate', rateLabel, colors),
          _metric('Requested', '${metrics.requested}', colors),
          _metric('Completed', '${metrics.completed}', colors),
          _metric('Delayed', '${metrics.delayed}', colors),
        ],
      ),
    );
  }

  Widget _metric(String label, String value, FardaColors colors) {
    return Column(
      children: [
        TextMedium(
          text: value,
          style: TextStyle(
            color: colors.baseBlack,
            fontWeight: FontWeight.w700,
            fontSize: 18.sp,
          ),
        ),
        4.verticalSpace,
        TextMedium(
          text: label,
          style: TextStyle(color: colors.slate.shade600, fontSize: 11.sp),
        ),
      ],
    );
  }
}

class _RefillCard extends StatelessWidget {
  const _RefillCard({
    required this.refill,
    required this.colors,
  });

  final RefillModel refill;
  final FardaColors colors;

  String _fmt(DateTime? d) =>
      d == null ? '—' : DateFormat('MMM d, yyyy').format(d.toLocal());

  @override
  Widget build(BuildContext context) {
    final name = refill.medicineName ?? refill.rxNumber ?? 'Prescription';
    final due = refill.isRefillDue;

    return Container(
      padding: EdgeInsets.all(16.r),
      decoration: BoxDecoration(
        color: colors.baseWhite,
        borderRadius: BorderRadius.circular(16.r),
        boxShadow: [
          BoxShadow(
            color: colors.baseBlack.withValues(alpha: 0.06),
            offset: const Offset(0, 2),
            blurRadius: 16,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextMedium(
                  text: name,
                  style: TextStyle(
                    color: colors.baseBlack,
                    fontWeight: FontWeight.w700,
                    fontSize: 16.sp,
                  ),
                ),
              ),
              _readinessPill(due, colors),
            ],
          ),
          10.verticalSpace,
          if (refill.hasForecast) ...[
            _row('Supply left',
                '${refill.daysLeft} day${refill.daysLeft == 1 ? '' : 's'}'),
            _row('Refill by', _fmt(refill.refillDue)),
            _row('Runs out', _fmt(refill.predictedDepletion)),
          ] else
            TextMedium(
              text:
                  'Not enough data to predict yet — add a pill quantity and dose schedule.',
              style: TextStyle(color: colors.slate.shade600, fontSize: 12.sp),
            ),
          if (refill.remaining != null) ...[
            6.verticalSpace,
            TextMedium(
              text: refill.remainingSource == RemainingSource.measured
                  ? '${refill.remaining} pills left (measured)'
                  : '${refill.remaining} pills left (estimated from doses)',
              style: TextStyle(color: colors.slate.shade500, fontSize: 11.sp),
            ),
          ],
          12.verticalSpace,
          Row(
            children: [
              Expanded(
                child: ButtonPrimary(
                  text: 'Request refill',
                  onClick: () => _capture(
                    context,
                    requested: true,
                  ),
                ),
              ),
              12.horizontalSpace,
              Expanded(
                child: ButtonSecondary(
                  text: 'Mark picked up',
                  onClick: () => _capture(
                    context,
                    requested: false,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 3.h),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TextMedium(
            text: label,
            style: TextStyle(color: colors.slate.shade600, fontSize: 13.sp),
          ),
          TextMedium(
            text: value,
            style: TextStyle(
              color: colors.baseBlack,
              fontWeight: FontWeight.w600,
              fontSize: 13.sp,
            ),
          ),
        ],
      ),
    );
  }

  Widget _readinessPill(bool due, FardaColors colors) {
    final bg = due ? colors.warning[100]! : colors.success[100]!;
    final fg = due ? colors.warning[700]! : colors.success[700]!;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 5.h),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20.r),
      ),
      child: TextMedium(
        text: due ? 'Refill due' : 'On track',
        style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 11.sp),
      ),
    );
  }

  Future<void> _capture(BuildContext context, {required bool requested}) async {
    final provider = context.read<RefillProvider>();
    final ok = requested
        ? await provider.requestRefill(refill)
        : await provider.markRefillCompleted(refill);
    if (!context.mounted) return;
    CustomSnackbar.show(
      context,
      message: ok
          ? (requested ? 'Refill requested.' : 'Marked as picked up.')
          : 'Could not save. Please try again.',
      icon: ok ? Icons.check_circle_outline : Icons.error_outline,
    );
  }
}

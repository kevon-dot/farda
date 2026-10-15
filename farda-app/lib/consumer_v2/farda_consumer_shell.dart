import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'package:farda/features/consumer/consumer_controller.dart';
import 'package:farda/features/consumer/data/consumer_models.dart';

import 'design_system/farda_consumer_tokens.dart';
import 'screens/calendar/farda_calendar_screen.dart';
import 'screens/today/today_models.dart';
import 'screens/refills/farda_refills_screen.dart';
import 'screens/today/farda_today_screen.dart';
import 'screens/you/farda_you_screen.dart';

/// The production Flutter entry point for the consumer-v2 Farda experience.
///
/// An [IndexedStack] preserves local page state while changing tabs. This
/// replaces the previous split local-index/ShellRoute navigation behavior.
class FardaConsumerShell extends StatefulWidget {
  const FardaConsumerShell({
    super.key,
    this.initialIndex = 0,
    this.onTabSelected,
    this.controller,
    this.onOpenAccount,
  });

  final int initialIndex;
  final ValueChanged<int>? onTabSelected;
  final ConsumerController? controller;
  final VoidCallback? onOpenAccount;

  @override
  State<FardaConsumerShell> createState() => _FardaConsumerShellState();
}

class _FardaConsumerShellState extends State<FardaConsumerShell> {
  late int _selectedIndex;
  bool _hideBottomNavigation = false;

  @override
  void initState() {
    super.initState();
    _selectedIndex = _safeIndex(widget.initialIndex);
  }

  @override
  void didUpdateWidget(covariant FardaConsumerShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialIndex != widget.initialIndex) {
      _selectedIndex = _safeIndex(widget.initialIndex);
      if (_selectedIndex != 3) _hideBottomNavigation = false;
    }
  }

  int _safeIndex(int value) {
    if (value < 0) return 0;
    if (value > 3) return 3;
    return value;
  }

  void _selectTab(int index) {
    if (_selectedIndex == index && !_hideBottomNavigation) return;
    setState(() {
      _selectedIndex = index;
      if (index != 3) _hideBottomNavigation = false;
    });
    widget.onTabSelected?.call(index);
  }

  TodayDoseStatus _todayStatus(ConsumerOccurrence occurrence) =>
      switch (occurrence.status) {
        OccurrenceStatus.taken => TodayDoseStatus.confirmed,
        OccurrenceStatus.skipped => TodayDoseStatus.skipped,
        _ => TodayDoseStatus.pending,
      };

  List<ConsumerCalendarEvent> _calendarEvents(ConsumerSnapshot snapshot) {
    final events = <ConsumerCalendarEvent>[];
    for (final occurrence in snapshot.occurrences) {
      if (occurrence.status == OccurrenceStatus.cancelled) continue;
      final local = occurrence.scheduledFor.toLocal();
      final name = snapshot.prescription(occurrence.prescriptionId)?.name ??
          'Your routine';
      final status = switch (occurrence.status) {
        OccurrenceStatus.taken || OccurrenceStatus.skipped =>
          ConsumerCalendarEventStatus.recorded,
        OccurrenceStatus.unconfirmed when local.isBefore(DateTime.now()) =>
          ConsumerCalendarEventStatus.unconfirmed,
        _ => ConsumerCalendarEventStatus.pending,
      };
      events.add(ConsumerCalendarEvent(
        id: occurrence.id,
        date: local,
        type: ConsumerCalendarEventType.routine,
        status: status,
        eyebrow: DateFormat.jm().format(local),
        title: name,
        description: switch (occurrence.status) {
          OccurrenceStatus.taken => 'You recorded this dose as taken.',
          OccurrenceStatus.skipped => 'You recorded this dose as skipped.',
          _ => 'No dose has been confirmed.',
        },
      ));
    }
    for (final inventory in snapshot.inventory) {
      final date = inventory.plannedFor;
      if (date == null) continue;
      events.add(ConsumerCalendarEvent(
        id: inventory.refillId ?? inventory.prescriptionId,
        date: date.toLocal(),
        type: ConsumerCalendarEventType.refill,
        status: ConsumerCalendarEventStatus.planned,
        eyebrow: 'REFILL PLAN',
        title: snapshot.prescription(inventory.prescriptionId)?.name ??
            'Your refill',
        description: 'A plan you recorded; no pharmacy order was placed.',
      ));
    }
    return events;
  }

  Future<String?> _record(ConsumerOccurrence occurrence,
      TodayDoseStatus status) async {
    final controller = widget.controller!;
    return controller.mutate(() => controller.repository.recordOccurrence(
      ConsumerOccurrenceUpdate(
        id: occurrence.id,
        status: status == TodayDoseStatus.confirmed
            ? OccurrenceStatus.taken
            : OccurrenceStatus.skipped,
        expectedRevision: occurrence.revision,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final consumerTheme = FardaConsumerTheme.from(Theme.of(context));
    final controller = widget.controller;
    final snapshot = controller?.snapshot;
    final selected = controller == null
        ? <ConsumerOccurrence>[]
        : controller.occurrencesFor(controller.selectedDate)
            .where((item) => item.status != OccurrenceStatus.cancelled)
            .toList();
    final occurrence = selected.isEmpty ? null : selected.first;
    return Theme(
      data: consumerTheme,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarBrightness: Brightness.light,
          statusBarIconBrightness: Brightness.dark,
          systemNavigationBarColor: FardaConsumerColors.card,
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
        child: Scaffold(
          backgroundColor: FardaConsumerColors.canvas,
          body: IndexedStack(
            index: _selectedIndex,
            children: [
              FardaTodayScreen(
                key: ValueKey(occurrence?.id ??
                    'empty-${controller?.selectedDate.toIso8601String()}'),
                showBottomNavigation: false,
                liveRecords: controller != null,
                hasRoutine: controller == null || occurrence != null,
                initialDate: controller?.selectedDate,
                initialDoseStatus: occurrence == null
                    ? TodayDoseStatus.pending
                    : _todayStatus(occurrence),
                initiallySnoozed: occurrence?.snoozedUntil
                        ?.isAfter(DateTime.now()) ?? false,
                morningTimeLabel: occurrence == null
                    ? '9:00 AM'
                    : DateFormat.jm().format(occurrence.scheduledFor.toLocal()),
                medicationLabel: occurrence == null
                    ? 'Your routine'
                    : snapshot?.prescription(occurrence.prescriptionId)?.name ??
                        'Your routine',
                additionalRoutineCount: selected.length > 1
                    ? selected.length - 1
                    : 0,
                onDaySelected: controller?.selectDay,
                onPersistDose: occurrence == null
                    ? null
                    : (status) => _record(occurrence, status),
                onPersistSnooze: occurrence == null
                    ? null
                    : () => controller!.mutate(() => controller.repository
                        .snoozeOccurrence(occurrence.id,
                            const Duration(minutes: 15))),
                onReviewRoutineTap: widget.onOpenAccount,
                onOpenCalendar: () => _selectTab(1),
                onOpenRefills: () => _selectTab(2),
                onOpenProfile: () => _selectTab(3),
              ),
              FardaCalendarScreen(
                events: snapshot == null ? null : _calendarEvents(snapshot),
                initialSelectedDate: controller?.selectedDate,
                initialVisibleMonth: controller?.visibleMonth,
                onSelectedDateChanged: controller?.selectDay,
                onVisibleMonthChanged: controller == null
                    ? null
                    : (month) {
                        controller.visibleMonth = month;
                        controller.load();
                      },
              ),
              const FardaRefillsScreen(),
              FardaYouScreen(
                onNativePreviewChanged: (isNativePreview) {
                  if (_hideBottomNavigation == isNativePreview) return;
                  setState(
                    () => _hideBottomNavigation = isNativePreview,
                  );
                },
              ),
            ],
          ),
          bottomNavigationBar: _hideBottomNavigation
              ? null
              : FardaConsumerNavigationBar(
                  selectedIndex: _selectedIndex,
                  onSelected: _selectTab,
                ),
        ),
      ),
    );
  }
}

class FardaConsumerNavigationBar extends StatelessWidget {
  const FardaConsumerNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const _items = <({String label, IconData icon})>[
    (label: 'Today', icon: Icons.home_outlined),
    (label: 'Calendar', icon: Icons.calendar_today_outlined),
    (label: 'Refills', icon: Icons.sync_rounded),
    (label: 'You', icon: Icons.person_outline_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: FardaConsumerColors.card,
        border: Border(
          top: BorderSide(color: FardaConsumerColors.border, width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(22, 8, 22, 6),
        child: SizedBox(
          height: 62,
          child: Row(
            children: List.generate(_items.length, (index) {
              final item = _items[index];
              final selected = selectedIndex == index;
              return Expanded(
                child: Semantics(
                  selected: selected,
                  button: true,
                  label: '${item.label} tab',
                  child: InkWell(
                    onTap: () => onSelected(index),
                    borderRadius: BorderRadius.circular(
                      FardaConsumerRadius.sm,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          curve: Curves.easeOut,
                          width: 38,
                          height: 32,
                          decoration: BoxDecoration(
                            color: selected
                                ? FardaConsumerColors.soft
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(
                              FardaConsumerRadius.sm,
                            ),
                          ),
                          child: Icon(
                            item.icon,
                            size: 22,
                            color: selected
                                ? FardaConsumerColors.brand
                                : FardaConsumerColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.label,
                          maxLines: 1,
                          style: FardaConsumerType.label.copyWith(
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: selected
                                ? FardaConsumerColors.brand
                                : FardaConsumerColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

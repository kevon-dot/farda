import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../design_system/farda_consumer_tokens.dart';
import 'calendar_models.dart';

typedef ConsumerCalendarEventCallback =
    void Function(ConsumerCalendarEvent event);

enum _CalendarMood { open, saved, snoozed, empty }

_CalendarMood _moodForDay(DateTime day, List<ConsumerCalendarEvent> events) {
  final items =
      events.where((event) => isSameCalendarDay(event.date, day)).toList();
  if (items.isEmpty) return _CalendarMood.empty;
  if (items.any(
    (event) =>
        event.type == ConsumerCalendarEventType.refill ||
        event.status == ConsumerCalendarEventStatus.pending ||
        event.status == ConsumerCalendarEventStatus.planned ||
        event.status == ConsumerCalendarEventStatus.unconfirmed,
  )) {
    return _CalendarMood.open;
  }
  if (items.any(
    (event) => event.status == ConsumerCalendarEventStatus.snoozed,
  )) {
    return _CalendarMood.snoozed;
  }
  return _CalendarMood.saved;
}

/// The consumer-v2 calendar translated from the Figma handoff (node 2:12).
///
/// Date selection stays local while records and outward actions are injectable.
/// The authenticated route supplies real events; this presentation layer never
/// infers a saved dose from a reminder or device signal.
class FardaCalendarScreen extends StatefulWidget {
  const FardaCalendarScreen({
    super.key,
    this.events,
    this.initialSelectedDate,
    this.initialVisibleMonth,
    this.initialFilter = ConsumerCalendarFilter.all,
    this.today,
    this.onSelectedDateChanged,
    this.onVisibleMonthChanged,
    this.onFilterChanged,
    this.onEventAction,
    this.onProfilePressed,
    this.profileLabel = 'YO',
    this.showBrandHeader = true,
    this.bottomNavigationBar,
  });

  /// Records to render. When omitted, a local sample matching the handoff is
  /// generated around [today]. Pass an empty list for a completely blank view.
  final List<ConsumerCalendarEvent>? events;
  final DateTime? initialSelectedDate;
  final DateTime? initialVisibleMonth;
  final ConsumerCalendarFilter initialFilter;
  final DateTime? today;
  final ValueChanged<DateTime>? onSelectedDateChanged;
  final ValueChanged<DateTime>? onVisibleMonthChanged;
  final ValueChanged<ConsumerCalendarFilter>? onFilterChanged;

  /// Receives the tapped record. Action affordances are omitted when null so
  /// the screen never presents a control that cannot complete an action.
  final ConsumerCalendarEventCallback? onEventAction;
  final VoidCallback? onProfilePressed;
  final String profileLabel;
  final bool showBrandHeader;

  /// Allows the app shell to inject its own fixed navigation without this
  /// feature depending on shared routes.
  final Widget? bottomNavigationBar;

  @override
  State<FardaCalendarScreen> createState() => _FardaCalendarScreenState();
}

class _FardaCalendarScreenState extends State<FardaCalendarScreen> {
  late DateTime _today;
  late DateTime _selectedDate;
  late DateTime _visibleMonth;
  late ConsumerCalendarFilter _filter;
  bool _monthExpanded = false;

  List<ConsumerCalendarEvent> get _events =>
      widget.events ?? _prototypeEvents(_today);

  @override
  void initState() {
    super.initState();
    _today = calendarDay(widget.today ?? DateTime.now());
    _selectedDate = calendarDay(widget.initialSelectedDate ?? _today);
    _visibleMonth = calendarMonth(widget.initialVisibleMonth ?? _selectedDate);
    _filter = widget.initialFilter;
  }

  @override
  void didUpdateWidget(covariant FardaCalendarScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.today != oldWidget.today && widget.today != null) {
      _today = calendarDay(widget.today!);
    }
    if (widget.initialSelectedDate != oldWidget.initialSelectedDate &&
        widget.initialSelectedDate != null) {
      _selectedDate = calendarDay(widget.initialSelectedDate!);
    }
    if (widget.initialVisibleMonth != oldWidget.initialVisibleMonth &&
        widget.initialVisibleMonth != null) {
      _visibleMonth = calendarMonth(widget.initialVisibleMonth!);
    }
    if (widget.initialFilter != oldWidget.initialFilter) {
      _filter = widget.initialFilter;
    }
  }

  void _selectDate(DateTime date) {
    final normalized = calendarDay(date);
    final nextMonth = calendarMonth(normalized);
    final changedMonth = nextMonth != _visibleMonth;
    setState(() {
      _selectedDate = normalized;
      _visibleMonth = nextMonth;
    });
    if (changedMonth) widget.onVisibleMonthChanged?.call(nextMonth);
    widget.onSelectedDateChanged?.call(normalized);
  }

  void _changeMonth(int offset) {
    final candidate = DateTime(
      _visibleMonth.year,
      _visibleMonth.month + offset,
    );
    final lastDay = DateTime(candidate.year, candidate.month + 1, 0).day;
    final nextSelected = DateTime(
      candidate.year,
      candidate.month,
      math.min(_selectedDate.day, lastDay),
    );

    setState(() {
      _visibleMonth = candidate;
      _selectedDate = nextSelected;
    });
    widget.onVisibleMonthChanged?.call(candidate);
    widget.onSelectedDateChanged?.call(nextSelected);
  }

  void _changeWeek(int offset) {
    final candidate = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day + 7 * offset,
    );
    _selectDate(candidate);
  }

  void _toggleMonth() => setState(() => _monthExpanded = !_monthExpanded);

  void _selectFilter(ConsumerCalendarFilter filter) {
    if (_filter == filter) return;
    setState(() => _filter = filter);
    widget.onFilterChanged?.call(filter);
  }

  void _returnToToday() {
    final changedMonth =
        _visibleMonth.year != _today.year ||
        _visibleMonth.month != _today.month;
    setState(() {
      _selectedDate = _today;
      _visibleMonth = calendarMonth(_today);
    });
    if (changedMonth) {
      widget.onVisibleMonthChanged?.call(_visibleMonth);
    }
    widget.onSelectedDateChanged?.call(_selectedDate);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _FardaCalendarColors.ivory,
      bottomNavigationBar: widget.bottomNavigationBar,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            MediaQuery.sizeOf(context).width <= 340 ? 6 : 22,
            8,
            MediaQuery.sizeOf(context).width <= 340 ? 6 : 22,
            32,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.showBrandHeader) ...[
                    _BrandHeader(
                      profileLabel: widget.profileLabel,
                      onProfilePressed: widget.onProfilePressed,
                    ),
                    const SizedBox(height: 11),
                  ],
                  _CalendarHero(mood: _moodForDay(_selectedDate, _events)),
                  const SizedBox(height: 16),
                  _PeriodControls(
                    selectedDate: _selectedDate,
                    monthExpanded: _monthExpanded,
                    onToggleMonth: _toggleMonth,
                    onPrevious:
                        () =>
                            _monthExpanded ? _changeMonth(-1) : _changeWeek(-1),
                    onNext:
                        () => _monthExpanded ? _changeMonth(1) : _changeWeek(1),
                    onToday: _returnToToday,
                  ),
                  const SizedBox(height: 10),
                  _WeekRail(
                    selectedDate: _selectedDate,
                    today: _today,
                    events: _events,
                    onDateSelected: _selectDate,
                  ),
                  AnimatedSize(
                    duration:
                        MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child:
                        _monthExpanded
                            ? Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: _CalendarCard(
                                visibleMonth: _visibleMonth,
                                selectedDate: _selectedDate,
                                today: _today,
                                events: _events,
                                onDateSelected: _selectDate,
                              ),
                            )
                            : const SizedBox(width: double.infinity),
                  ),
                  const SizedBox(height: 16),
                  AnimatedSwitcher(
                    duration:
                        MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 220),
                    child: _SelectedDayAgenda(
                      key: ValueKey(
                        '${_selectedDate.toIso8601String()}-${_filter.name}',
                      ),
                      selectedDate: _selectedDate,
                      filter: _filter,
                      events: _events,
                      onEventAction: widget.onEventAction,
                      emptyActionLabel:
                          _filter != ConsumerCalendarFilter.all
                              ? 'Show all entries'
                              : !isSameCalendarDay(_selectedDate, _today)
                              ? 'Back to today'
                              : 'Your routines',
                      onEmptyAction:
                          _filter != ConsumerCalendarFilter.all
                              ? () => _selectFilter(ConsumerCalendarFilter.all)
                              : !isSameCalendarDay(_selectedDate, _today)
                              ? _returnToToday
                              : widget.onProfilePressed,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _FilterRow(
                    selectedFilter: _filter,
                    onFilterSelected: _selectFilter,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader({
    required this.profileLabel,
    required this.onProfilePressed,
  });

  final String profileLabel;
  final VoidCallback? onProfilePressed;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Semantics(
          header: true,
          child: Text(
            'farda.',
            style: _FardaCalendarType.style(
              size: 30,
              lineHeight: 36,
              weight: FontWeight.w600,
            ),
          ),
        ),
        Semantics(
          button: onProfilePressed != null,
          label:
              onProfilePressed == null
                  ? 'Your profile, $profileLabel'
                  : 'Open your profile',
          onTap: onProfilePressed,
          child: ExcludeSemantics(
            child: Material(
              color: _FardaCalendarColors.paleBlue,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                onTap: onProfilePressed,
                borderRadius: BorderRadius.circular(16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                  child: Center(
                    child: Text(
                      profileLabel,
                      style: _FardaCalendarType.style(
                        size: 11,
                        lineHeight: 14,
                        weight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CalendarHero extends StatelessWidget {
  const _CalendarHero({required this.mood});
  final _CalendarMood mood;
  @override
  Widget build(BuildContext context) {
    final compact =
        MediaQuery.sizeOf(context).width <= 340 ||
        MediaQuery.textScalerOf(context).scale(14) > 18;
    return FardaSceneCard(
      scene: FardaScene.calendar,
      padding: const EdgeInsets.all(18),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 104),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'YOUR CALENDAR',
                    style: FardaConsumerType.label.copyWith(
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    switch (mood) {
                      _CalendarMood.open => 'A little room\nfor your week.',
                      _CalendarMood.saved => 'Your day,\nin your words.',
                      _CalendarMood.snoozed => 'A little\nmore room.',
                      _CalendarMood.empty => 'Room for\na quieter day.',
                    },
                    style: FardaConsumerType.heading.copyWith(
                      fontSize: compact ? 22 : 26,
                      height: compact ? 26 / 22 : 30 / 26,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 5),
            DecoratedBox(
              decoration: const BoxDecoration(
                color: FardaConsumerColors.canvas,
                shape: BoxShape.circle,
              ),
              child: FardaCompanion(
                pose:
                    mood == _CalendarMood.open
                        ? FardaCompanionPose.calendar
                        : FardaCompanionPose.quiet,
                size: compact ? 72 : 104,
                floating: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PeriodControls extends StatelessWidget {
  const _PeriodControls({
    required this.selectedDate,
    required this.monthExpanded,
    required this.onToggleMonth,
    required this.onPrevious,
    required this.onNext,
    required this.onToday,
  });
  final DateTime selectedDate;
  final bool monthExpanded;
  final VoidCallback onToggleMonth;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    final month = DateFormat('MMMM yyyy').format(selectedDate);
    final compact =
        MediaQuery.sizeOf(context).width <= 340 ||
        MediaQuery.textScalerOf(context).scale(14) > 18;
    final visibleMonth =
        compact ? DateFormat('MMM yyyy').format(selectedDate) : month;
    return Row(
      children: [
        Expanded(
          child: Semantics(
            button: true,
            expanded: monthExpanded,
            label: '$month, ${monthExpanded ? 'hide' : 'show'} full month',
            onTap: onToggleMonth,
            child: ExcludeSemantics(
              child: TextButton.icon(
                key: const Key('calendar-month-toggle'),
                onPressed: onToggleMonth,
                style: TextButton.styleFrom(
                  minimumSize: const Size(44, 44),
                  foregroundColor: _FardaCalendarColors.navy,
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                ),
                iconAlignment: IconAlignment.end,
                icon: Icon(
                  monthExpanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 20,
                ),
                label: Text(
                  visibleMonth,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _FardaCalendarType.style(
                    size: 18,
                    lineHeight: 24,
                    weight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: monthExpanded ? 'Previous month' : 'Previous week',
          onPressed: onPrevious,
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        IconButton(
          tooltip: monthExpanded ? 'Next month' : 'Next week',
          onPressed: onNext,
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          icon: const Icon(Icons.chevron_right_rounded),
        ),
        TextButton(
          onPressed: onToday,
          style: TextButton.styleFrom(
            foregroundColor: _FardaCalendarColors.navy,
            backgroundColor: _FardaCalendarColors.paleBlue,
            minimumSize: const Size(64, 44),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            shape: const StadiumBorder(),
          ),
          child: const Text('Today'),
        ),
      ],
    );
  }
}

class _WeekRail extends StatelessWidget {
  const _WeekRail({
    required this.selectedDate,
    required this.today,
    required this.events,
    required this.onDateSelected,
  });
  final DateTime selectedDate;
  final DateTime today;
  final List<ConsumerCalendarEvent> events;
  final ValueChanged<DateTime> onDateSelected;

  @override
  Widget build(BuildContext context) {
    final days = List.generate(
      7,
      (index) => DateTime(
        selectedDate.year,
        selectedDate.month,
        selectedDate.day - selectedDate.weekday + 1 + index,
      ),
    );
    return SizedBox(
      height: 68,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final gap = constraints.maxWidth >= 338 ? 4.0 : 0.0;
          final cellWidth = (constraints.maxWidth - gap * 6) / 7;
          return Row(
            children: [
              for (var i = 0; i < days.length; i++) ...[
                if (i > 0) SizedBox(width: gap),
                SizedBox(
                  width: cellWidth,
                  child: _WeekDay(
                    date: days[i],
                    selected: isSameCalendarDay(days[i], selectedDate),
                    today: isSameCalendarDay(days[i], today),
                    markers: _markersForDate(events, days[i]),
                    onPressed: () => onDateSelected(days[i]),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _WeekDay extends StatelessWidget {
  const _WeekDay({
    required this.date,
    required this.selected,
    required this.today,
    required this.markers,
    required this.onPressed,
  });
  final DateTime date;
  final bool selected;
  final bool today;
  final List<ConsumerCalendarMarker> markers;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final label =
        '${DateFormat('EEEE, MMMM d, yyyy').format(date)}'
        '${today ? ', today' : ''}'
        '${markers.isEmpty ? '' : ', ${markers.map(_markerSemanticLabel).join(', ')}'}';
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      onTap: onPressed,
      child: ExcludeSemantics(
        child: Material(
          color:
              selected ? _FardaCalendarColors.navy : _FardaCalendarColors.white,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            key: Key('calendar-day-${date.toIso8601String().substring(0, 10)}'),
            onTap: onPressed,
            borderRadius: BorderRadius.circular(18),
            child: Container(
              constraints: const BoxConstraints(minWidth: 44, minHeight: 68),
              decoration:
                  today && !selected
                      ? BoxDecoration(
                        border: Border.all(
                          color: _FardaCalendarColors.sand,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(18),
                      )
                      : null,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    DateFormat.E().format(date).substring(0, 1),
                    style: _FardaCalendarType.style(
                      size: 10,
                      lineHeight: 14,
                      color:
                          selected
                              ? _FardaCalendarColors.white
                              : _FardaCalendarColors.muted,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${date.day}',
                    style: _FardaCalendarType.style(
                      size: 16,
                      lineHeight: 20,
                      weight: FontWeight.w600,
                      color:
                          selected
                              ? _FardaCalendarColors.white
                              : _FardaCalendarColors.navy,
                    ),
                  ),
                  const SizedBox(height: 3),
                  SizedBox(
                    height: 6,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < markers.length && i < 3; i++) ...[
                          if (i > 0) const SizedBox(width: 2),
                          _StatusMark(
                            marker: markers[i],
                            selected: selected,
                            size: 5,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CalendarCard extends StatelessWidget {
  const _CalendarCard({
    required this.visibleMonth,
    required this.selectedDate,
    required this.today,
    required this.events,
    required this.onDateSelected,
  });
  final DateTime visibleMonth;
  final DateTime selectedDate;
  final DateTime today;
  final List<ConsumerCalendarEvent> events;
  final ValueChanged<DateTime> onDateSelected;
  @override
  Widget build(BuildContext context) {
    final markers = ConsumerCalendarMarker.values
        .where(
          (marker) => events.any(
            (event) =>
                event.date.year == visibleMonth.year &&
                event.date.month == visibleMonth.month &&
                event.marker == marker,
          ),
        )
        .toList(growable: false);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: MediaQuery.sizeOf(context).width <= 340 ? 0 : 13,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          const _WeekdayLabels(),
          const SizedBox(height: 4),
          _MonthGrid(
            visibleMonth: visibleMonth,
            selectedDate: selectedDate,
            today: today,
            events: events,
            onDateSelected: onDateSelected,
          ),
          if (markers.isNotEmpty) ...[
            const SizedBox(height: 4),
            _CalendarLegend(markers: markers),
          ],
        ],
      ),
    );
  }
}

class _WeekdayLabels extends StatelessWidget {
  const _WeekdayLabels();

  static const _labels = <String>['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Row(
        children: _labels
            .map(
              (label) => Expanded(
                child: Center(
                  child: Text(
                    label,
                    style: _FardaCalendarType.style(
                      size: 10,
                      lineHeight: 14,
                      color: _FardaCalendarColors.muted,
                    ),
                  ),
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.visibleMonth,
    required this.selectedDate,
    required this.today,
    required this.events,
    required this.onDateSelected,
  });

  final DateTime visibleMonth;
  final DateTime selectedDate;
  final DateTime today;
  final List<ConsumerCalendarEvent> events;
  final ValueChanged<DateTime> onDateSelected;

  @override
  Widget build(BuildContext context) {
    final daysInMonth =
        DateTime(visibleMonth.year, visibleMonth.month + 1, 0).day;
    final mondayOffset = visibleMonth.weekday - DateTime.monday;
    final usedCells = mondayOffset + daysInMonth;
    final cellCount = ((usedCells + 6) ~/ 7) * 7;

    return Semantics(
      container: true,
      label: DateFormat('MMMM yyyy').format(visibleMonth),
      child: GridView.builder(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 7,
          mainAxisSpacing: 2,
          crossAxisSpacing: MediaQuery.sizeOf(context).width <= 340 ? 0 : 2,
          mainAxisExtent: MediaQuery.textScalerOf(context).scale(44),
        ),
        itemCount: cellCount,
        itemBuilder: (context, index) {
          final day = index - mondayOffset + 1;
          if (day < 1 || day > daysInMonth) {
            return const SizedBox.shrink();
          }

          final date = DateTime(visibleMonth.year, visibleMonth.month, day);
          final markers = _markersForDate(events, date);
          return _CalendarDay(
            date: date,
            selected: isSameCalendarDay(date, selectedDate),
            today: isSameCalendarDay(date, today),
            markers: markers,
            onPressed: () => onDateSelected(date),
          );
        },
      ),
    );
  }
}

class _CalendarDay extends StatelessWidget {
  const _CalendarDay({
    required this.date,
    required this.selected,
    required this.today,
    required this.markers,
    required this.onPressed,
  });

  final DateTime date;
  final bool selected;
  final bool today;
  final List<ConsumerCalendarMarker> markers;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final statusDescription =
        markers.isEmpty
            ? ''
            : '. ${markers.map(_markerSemanticLabel).join(', ')}';
    final todayDescription = today ? '. Today' : '';
    final fullLabel =
        '${DateFormat('EEEE, MMMM d, yyyy').format(date)}$todayDescription$statusDescription';

    return Semantics(
      button: true,
      selected: selected,
      label: fullLabel,
      onTap: onPressed,
      child: ExcludeSemantics(
        child: AnimatedContainer(
          duration:
              MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 170),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color:
                selected
                    ? _FardaCalendarColors.navy
                    : _FardaCalendarColors.transparent,
            borderRadius: BorderRadius.circular(13),
            border:
                selected
                    ? Border.all(color: _FardaCalendarColors.sand, width: 2)
                    : today
                    ? Border.all(color: _FardaCalendarColors.todayOutline)
                    : null,
          ),
          child: Material(
            type: MaterialType.transparency,
            borderRadius: BorderRadius.circular(13),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: Key(
                'calendar-month-day-${date.toIso8601String().substring(0, 10)}',
              ),
              onTap: onPressed,
              borderRadius: BorderRadius.circular(13),
              child: SizedBox.expand(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${date.day}',
                      style: _FardaCalendarType.style(
                        size: 14,
                        lineHeight: 18,
                        color:
                            selected
                                ? _FardaCalendarColors.white
                                : _FardaCalendarColors.navy,
                      ),
                    ),
                    const SizedBox(height: 3),
                    SizedBox(
                      height: 6,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (
                            var index = 0;
                            index < markers.length && index < 3;
                            index++
                          ) ...[
                            if (index > 0) const SizedBox(width: 3),
                            _StatusMark(
                              marker: markers[index],
                              selected: selected,
                              size: 5,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CalendarLegend extends StatelessWidget {
  const _CalendarLegend({required this.markers});

  final List<ConsumerCalendarMarker> markers;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Calendar status legend',
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        children: [
          for (final marker in markers)
            _LegendItem(
              marker: marker,
              label: switch (marker) {
                ConsumerCalendarMarker.recorded => 'Recorded',
                ConsumerCalendarMarker.skipped => 'Skipped',
                ConsumerCalendarMarker.snoozed => 'Snoozed',
                ConsumerCalendarMarker.unconfirmed => 'Unconfirmed',
                ConsumerCalendarMarker.scheduled => 'Scheduled',
                ConsumerCalendarMarker.refill => 'Refill',
              },
            ),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.marker, required this.label});

  final ConsumerCalendarMarker marker;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StatusMark(marker: marker, selected: false, size: 6),
        const SizedBox(width: 5),
        Text(
          label,
          style: _FardaCalendarType.style(
            size: 10,
            lineHeight: 14,
            color: _FardaCalendarColors.muted,
          ),
        ),
      ],
    );
  }
}

class _StatusMark extends StatelessWidget {
  const _StatusMark({
    required this.marker,
    required this.selected,
    required this.size,
  });

  final ConsumerCalendarMarker marker;
  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context) {
    final selectedColor = _FardaCalendarColors.selectedMark;
    return switch (marker) {
      ConsumerCalendarMarker.recorded => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? selectedColor : _FardaCalendarColors.accentBlue,
        ),
      ),
      ConsumerCalendarMarker.skipped => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: selected ? selectedColor : _FardaCalendarColors.muted,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      ConsumerCalendarMarker.snoozed => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? selectedColor : _FardaCalendarColors.amber,
        ),
      ),
      ConsumerCalendarMarker.unconfirmed => Container(
        width: size + 1,
        height: size + 1,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? selectedColor : _FardaCalendarColors.muted,
            width: 1,
          ),
        ),
      ),
      ConsumerCalendarMarker.scheduled => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? selectedColor : _FardaCalendarColors.todayOutline,
        ),
      ),
      ConsumerCalendarMarker.refill => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: selected ? selectedColor : _FardaCalendarColors.amber,
          borderRadius: BorderRadius.circular(1),
        ),
      ),
    };
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.selectedFilter,
    required this.onFilterSelected,
  });

  final ConsumerCalendarFilter selectedFilter;
  final ValueChanged<ConsumerCalendarFilter> onFilterSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 8,
            children: ConsumerCalendarFilter.values
                .map(
                  (filter) => _FilterChip(
                    filter: filter,
                    selected: filter == selectedFilter,
                    onPressed: () => onFilterSelected(filter),
                  ),
                )
                .toList(growable: false),
          ),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.filter,
    required this.selected,
    required this.onPressed,
  });
  final ConsumerCalendarFilter filter;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: 'Show ${filter.label.toLowerCase()} calendar items',
    onTap: onPressed,
    child: ExcludeSemantics(
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
          child: Center(
            widthFactor: 1,
            child: AnimatedContainer(
              duration:
                  MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
              decoration: BoxDecoration(
                color:
                    selected
                        ? FardaConsumerColors.brand
                        : FardaConsumerColors.soft,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                filter.label,
                style: FardaConsumerType.label.copyWith(
                  color:
                      selected
                          ? FardaConsumerColors.textInverse
                          : FardaConsumerColors.brand,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _SelectedDayAgenda extends StatelessWidget {
  const _SelectedDayAgenda({
    super.key,
    required this.selectedDate,
    required this.filter,
    required this.events,
    required this.onEventAction,
    required this.emptyActionLabel,
    required this.onEmptyAction,
  });
  final DateTime selectedDate;
  final ConsumerCalendarFilter filter;
  final List<ConsumerCalendarEvent> events;
  final ConsumerCalendarEventCallback? onEventAction;
  final String emptyActionLabel;
  final VoidCallback? onEmptyAction;
  @override
  Widget build(BuildContext context) {
    final selected =
        events
            .where(
              (event) =>
                  isSameCalendarDay(event.date, selectedDate) &&
                  event.isVisibleFor(filter),
            )
            .toList()
          ..sort((a, b) {
            int priority(ConsumerCalendarEvent event) {
              if (event.type == ConsumerCalendarEventType.refill) return 1;
              return switch (event.status) {
                ConsumerCalendarEventStatus.recorded ||
                ConsumerCalendarEventStatus.skipped => 2,
                _ => 0,
              };
            }

            final byPriority = priority(a).compareTo(priority(b));
            return byPriority != 0 ? byPriority : a.date.compareTo(b.date);
          });
    return Semantics(
      container: true,
      label:
          '${selected.length} calendar ${selected.length == 1 ? 'item' : 'items'}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              DateFormat('EEEE, MMMM d').format(selectedDate),
              style: _FardaCalendarType.style(
                size: 18,
                lineHeight: 24,
                weight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (selected.isEmpty)
            _EmptyAgendaCard(
              filter: filter,
              actionLabel: emptyActionLabel,
              onAction: onEmptyAction,
            ),
          for (var i = 0; i < selected.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            _EventCard(
              event: selected[i],
              primary: i == 0,
              onAction:
                  onEventAction == null || selected[i].actionLabel == null
                      ? null
                      : () => onEventAction!(selected[i]),
            ),
          ],
        ],
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({
    required this.event,
    required this.primary,
    required this.onAction,
  });
  final ConsumerCalendarEvent event;
  final bool primary;
  final VoidCallback? onAction;

  String get _statusLabel {
    if (event.type == ConsumerCalendarEventType.refill) return 'Refill plan';
    return switch (event.status) {
      ConsumerCalendarEventStatus.recorded => 'Recorded as taken',
      ConsumerCalendarEventStatus.skipped => 'Skipped · recorded by you',
      ConsumerCalendarEventStatus.snoozed => 'Snoozed',
      ConsumerCalendarEventStatus.unconfirmed => 'Not yet confirmed',
      ConsumerCalendarEventStatus.pending => 'Upcoming',
      ConsumerCalendarEventStatus.planned => 'Planned',
    };
  }

  @override
  Widget build(BuildContext context) {
    final name = event.routineName ?? event.title;
    final time =
        event.type == ConsumerCalendarEventType.refill
            ? event.eyebrow
            : event.routineName == null
            ? event.eyebrow
            : DateFormat.jm().format(event.date);
    if (!primary) {
      return Semantics(
        container: true,
        button: onAction != null,
        label: '$name. $time. $_statusLabel. ${event.description}',
        onTap: onAction,
        child: ExcludeSemantics(
          child: Material(
            color: FardaConsumerColors.card,
            borderRadius: BorderRadius.circular(22),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onAction,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 18,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: FardaConsumerColors.soft,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Icon(
                        event.type == ConsumerCalendarEventType.refill
                            ? Icons.local_pharmacy_outlined
                            : Icons.schedule_rounded,
                        color: FardaConsumerColors.brand,
                        size: 21,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: FardaConsumerType.bodyStrong,
                          ),
                          Text(
                            '$time · $_statusLabel',
                            maxLines: 2,
                            style: FardaConsumerType.caption,
                          ),
                          if (event.type == ConsumerCalendarEventType.refill)
                            Text(
                              event.description,
                              maxLines: 2,
                              style: FardaConsumerType.caption,
                            ),
                        ],
                      ),
                    ),
                    if (onAction != null) ...[
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: FardaConsumerColors.brand,
                        size: 20,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(time, style: FardaConsumerType.label),
          const SizedBox(height: 8),
          Text(name, style: FardaConsumerType.title),
          const SizedBox(height: 3),
          Text(_statusLabel, style: FardaConsumerType.caption),
          if (event.type == ConsumerCalendarEventType.refill) ...[
            const SizedBox(height: 4),
            Text(event.description, style: FardaConsumerType.caption),
          ] else if (event.status == ConsumerCalendarEventStatus.snoozed ||
              event.status == ConsumerCalendarEventStatus.recorded ||
              event.status == ConsumerCalendarEventStatus.skipped) ...[
            const SizedBox(height: 4),
            Text(event.description, style: FardaConsumerType.caption),
          ],
          if (onAction != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onAction,
                child: Text(event.actionLabel!),
              ),
            ),
          ],
        ],
      ),
    );
    return Semantics(
      container: true,
      label: '$name. $_statusLabel. ${event.description}',
      child: Material(
        color: switch (event.status) {
          ConsumerCalendarEventStatus.recorded => const Color(0xFFDDEFE5),
          ConsumerCalendarEventStatus.skipped ||
          ConsumerCalendarEventStatus.snoozed => _FardaCalendarColors.paleBlue,
          _ => FardaConsumerColors.warm,
        },
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: content,
      ),
    );
  }
}

class _EmptyAgendaCard extends StatelessWidget {
  const _EmptyAgendaCard({
    required this.filter,
    required this.actionLabel,
    required this.onAction,
  });
  final ConsumerCalendarFilter filter;
  final String actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final message = switch (filter) {
      ConsumerCalendarFilter.all => 'Choose another day or view your routine.',
      ConsumerCalendarFilter.routines => 'No routine entries here.',
      ConsumerCalendarFilter.refills => 'No refill plans here.',
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: FardaConsumerColors.card,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Nothing planned here.', style: FardaConsumerType.title),
          const SizedBox(height: 4),
          Text(message, style: FardaConsumerType.caption),
          if (onAction != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(44, 44),
                alignment: Alignment.centerLeft,
              ),
              child: Text(actionLabel),
            ),
        ],
      ),
    );
  }
}

class _FardaCalendarColors {
  const _FardaCalendarColors._();

  static const navy = Color(0xFF142C55);
  static const accentBlue = Color(0xFF365C99);
  static const paleBlue = Color(0xFFE9EEF7);
  static const ivory = Color(0xFFF6F5F0);
  static const white = Color(0xFFFFFFFF);
  static const muted = Color(0xFF58677D);
  static const amber = Color(0xFF80500E);
  static const sand = Color(0xFFF8ECD8);
  static const todayOutline = Color(0xFF7897C4);
  static const selectedMark = Color(0xFFD6E3FB);
  static const transparent = Color(0x00000000);
}

class _FardaCalendarType {
  const _FardaCalendarType._();

  static TextStyle style({
    required double size,
    required double lineHeight,
    FontWeight weight = FontWeight.w400,
    Color color = _FardaCalendarColors.navy,
    double? letterSpacing,
  }) {
    return TextStyle(
      fontFamily: 'Outfit',
      fontSize: size,
      height: lineHeight / size,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing,
    );
  }
}

List<ConsumerCalendarMarker> _markersForDate(
  List<ConsumerCalendarEvent> events,
  DateTime date,
) {
  final markers = <ConsumerCalendarMarker>{};
  for (final event in events) {
    if (!isSameCalendarDay(event.date, date)) continue;
    final marker = event.marker;
    if (marker != null) markers.add(marker);
  }

  return ConsumerCalendarMarker.values
      .where(markers.contains)
      .toList(growable: false);
}

String _markerSemanticLabel(ConsumerCalendarMarker marker) => switch (marker) {
  ConsumerCalendarMarker.recorded => 'Recorded entry',
  ConsumerCalendarMarker.skipped => 'Skipped entry recorded',
  ConsumerCalendarMarker.snoozed => 'Snoozed reminder',
  ConsumerCalendarMarker.unconfirmed => 'Unconfirmed entry',
  ConsumerCalendarMarker.scheduled => 'Scheduled routine',
  ConsumerCalendarMarker.refill => 'Refill reminder',
};

List<ConsumerCalendarEvent> _prototypeEvents(DateTime today) {
  return [
    ConsumerCalendarEvent(
      id: 'sample-recorded',
      date: DateTime(today.year, today.month, today.day - 2),
      type: ConsumerCalendarEventType.routine,
      status: ConsumerCalendarEventStatus.recorded,
      eyebrow: '9:00 AM · Morning',
      title: 'You confirmed your morning entry',
      description: 'Self-reported at 9:04 AM · Sample history',
      actionLabel: 'View record details',
    ),
    ConsumerCalendarEvent(
      id: 'sample-unconfirmed',
      date: DateTime(today.year, today.month, today.day - 1),
      type: ConsumerCalendarEventType.routine,
      status: ConsumerCalendarEventStatus.unconfirmed,
      eyebrow: '9:00 AM · Morning',
      title: 'No confirmation saved',
      description: 'An empty record does not tell us what happened.',
      actionLabel: 'View record details',
    ),
    ConsumerCalendarEvent(
      id: 'sample-today',
      date: today,
      type: ConsumerCalendarEventType.routine,
      status: ConsumerCalendarEventStatus.pending,
      eyebrow: '9:00 AM · Morning',
      title: 'Not yet confirmed',
      description: 'You can add or correct your record.',
      actionLabel: 'Add an entry',
    ),
    ConsumerCalendarEvent(
      id: 'sample-refill',
      date: DateTime(today.year, today.month, today.day + 2),
      type: ConsumerCalendarEventType.refill,
      status: ConsumerCalendarEventStatus.planned,
      eyebrow: 'Your refill planning reminder',
      title: 'Check in with your pharmacy',
      description: 'Your chosen reminder date, not a promised pickup date.',
      actionLabel: 'Open refill station',
    ),
  ];
}

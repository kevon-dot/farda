import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'calendar_models.dart';

typedef ConsumerCalendarEventCallback = void Function(
  ConsumerCalendarEvent event,
);

/// The consumer-v2 calendar translated from the Figma handoff (node 2:12).
///
/// State is intentionally local. Initial values, records, and every outward
/// action are injectable so a route/controller can connect the screen later
/// without this presentation layer making network or persistence calls.
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

  List<ConsumerCalendarEvent> get _events =>
      widget.events ?? _prototypeEvents(_today);

  @override
  void initState() {
    super.initState();
    _today = calendarDay(widget.today ?? DateTime.now());
    _selectedDate = calendarDay(widget.initialSelectedDate ?? _today);
    _visibleMonth = calendarMonth(
      widget.initialVisibleMonth ?? _selectedDate,
    );
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
    setState(() {
      _selectedDate = normalized;
      _visibleMonth = calendarMonth(normalized);
    });
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

  void _selectFilter(ConsumerCalendarFilter filter) {
    if (_filter == filter) return;
    setState(() => _filter = filter);
    widget.onFilterChanged?.call(filter);
  }

  void _returnToToday() {
    final changedMonth =
        _visibleMonth.year != _today.year || _visibleMonth.month != _today.month;
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
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 32),
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
                    const SizedBox(height: 24),
                  ],
                  const _PageIntroduction(),
                  const SizedBox(height: 20),
                  _CalendarCard(
                    visibleMonth: _visibleMonth,
                    selectedDate: _selectedDate,
                    today: _today,
                    events: _events,
                    onPreviousMonth: () => _changeMonth(-1),
                    onNextMonth: () => _changeMonth(1),
                    onDateSelected: _selectDate,
                  ),
                  const SizedBox(height: 16),
                  _FilterRow(
                    selectedFilter: _filter,
                    onFilterSelected: _selectFilter,
                    onTodayPressed: _returnToToday,
                  ),
                  const SizedBox(height: 20),
                  _SelectedDayAgenda(
                    selectedDate: _selectedDate,
                    filter: _filter,
                    events: _events,
                    onEventAction: widget.onEventAction,
                  ),
                  const SizedBox(height: 24),
                  const _FriendlyCalendarNote(),
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
          label: onProfilePressed == null
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

class _PageIntroduction extends StatelessWidget {
  const _PageIntroduction();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'YOUR DAYS, AT A GLANCE',
            style: _FardaCalendarType.style(
              size: 10,
              lineHeight: 14,
              weight: FontWeight.w600,
              color: _FardaCalendarColors.muted,
              letterSpacing: 1.35,
            ),
          ),
          const SizedBox(height: 9),
          Text(
            'A rhythm\nthat fits you.',
            style: _FardaCalendarType.style(
              size: 34,
              lineHeight: 37,
              weight: FontWeight.w600,
              letterSpacing: -0.7,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Tap a day. See what\'s planned, what\'s recorded, and what\'s still unknown.',
            style: _FardaCalendarType.style(
              size: 14,
              lineHeight: 20,
              color: _FardaCalendarColors.muted,
            ),
          ),
        ],
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
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.onDateSelected,
  });

  final DateTime visibleMonth;
  final DateTime selectedDate;
  final DateTime today;
  final List<ConsumerCalendarEvent> events;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final ValueChanged<DateTime> onDateSelected;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _FardaCalendarColors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _FardaCalendarColors.line),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A142C55),
            offset: Offset(0, 5),
            blurRadius: 15,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(13, 16, 13, 15),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: math.max(320.0, constraints.maxWidth).toDouble(),
                child: Column(
                  children: [
                    _MonthNavigation(
                      visibleMonth: visibleMonth,
                      onPreviousMonth: onPreviousMonth,
                      onNextMonth: onNextMonth,
                    ),
                    const SizedBox(height: 16),
                    const _WeekdayLabels(),
                    const SizedBox(height: 7),
                    _MonthGrid(
                      visibleMonth: visibleMonth,
                      selectedDate: selectedDate,
                      today: today,
                      events: events,
                      onDateSelected: onDateSelected,
                    ),
                    const SizedBox(height: 12),
                    const Divider(
                      height: 1,
                      color: _FardaCalendarColors.line,
                    ),
                    const SizedBox(height: 13),
                    const _CalendarLegend(),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _MonthNavigation extends StatelessWidget {
  const _MonthNavigation({
    required this.visibleMonth,
    required this.onPreviousMonth,
    required this.onNextMonth,
  });

  final DateTime visibleMonth;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;

  @override
  Widget build(BuildContext context) {
    final monthLabel = DateFormat('MMMM yyyy').format(visibleMonth);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _CalendarIconButton(
          icon: Icons.chevron_left_rounded,
          tooltip: 'Previous month',
          semanticLabel: 'Show the previous month before $monthLabel',
          onPressed: onPreviousMonth,
        ),
        Expanded(
          child: Semantics(
            header: true,
            liveRegion: true,
            label: 'Calendar month, $monthLabel',
            child: ExcludeSemantics(
              child: Text(
                monthLabel,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _FardaCalendarType.style(
                  size: 19,
                  lineHeight: 24,
                  weight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
        _CalendarIconButton(
          icon: Icons.chevron_right_rounded,
          tooltip: 'Next month',
          semanticLabel: 'Show the next month after $monthLabel',
          onPressed: onNextMonth,
        ),
      ],
    );
  }
}

class _CalendarIconButton extends StatelessWidget {
  const _CalendarIconButton({
    required this.icon,
    required this.tooltip,
    required this.semanticLabel,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final String semanticLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      onTap: onPressed,
      child: ExcludeSemantics(
        child: IconButton(
          onPressed: onPressed,
          tooltip: tooltip,
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          style: IconButton.styleFrom(
            foregroundColor: _FardaCalendarColors.navy,
            side: const BorderSide(color: _FardaCalendarColors.line),
            shape: const CircleBorder(),
          ),
          icon: Icon(icon, size: 22),
        ),
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
                      size: 11,
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
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 7,
          mainAxisSpacing: 2,
          crossAxisSpacing: 2,
          childAspectRatio: 1,
        ),
        itemCount: cellCount,
        itemBuilder: (context, index) {
          final day = index - mondayOffset + 1;
          if (day < 1 || day > daysInMonth) {
            return const SizedBox.shrink();
          }

          final date = DateTime(
            visibleMonth.year,
            visibleMonth.month,
            day,
          );
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
    final statusDescription = markers.isEmpty
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
        child: Material(
          color: selected
              ? _FardaCalendarColors.navy
              : _FardaCalendarColors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
            side: today && !selected
                ? const BorderSide(color: _FardaCalendarColors.todayOutline)
                : BorderSide.none,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
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
                      color: selected
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
                        for (var index = 0; index < markers.length; index++) ...[
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
    );
  }
}

class _CalendarLegend extends StatelessWidget {
  const _CalendarLegend();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Calendar status legend',
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        children: const [
          _LegendItem(
            marker: ConsumerCalendarMarker.recorded,
            label: 'Recorded',
          ),
          _LegendItem(
            marker: ConsumerCalendarMarker.unconfirmed,
            label: 'Unconfirmed',
          ),
          _LegendItem(
            marker: ConsumerCalendarMarker.refill,
            label: 'Refill reminder',
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
            color: selected
                ? selectedColor
                : _FardaCalendarColors.accentBlue,
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
    required this.onTodayPressed,
  });

  final ConsumerCalendarFilter selectedFilter;
  final ValueChanged<ConsumerCalendarFilter> onFilterSelected;
  final VoidCallback onTodayPressed;

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
        TextButton(
          onPressed: onTodayPressed,
          style: TextButton.styleFrom(
            foregroundColor: _FardaCalendarColors.navy,
            minimumSize: const Size(48, 44),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            textStyle: _FardaCalendarType.style(
              size: 12,
              lineHeight: 17,
              weight: FontWeight.w600,
            ),
          ),
          child: const Text('Today'),
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
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: 'Show ${filter.label.toLowerCase()} calendar items',
      onTap: onPressed,
      child: ExcludeSemantics(
        child: Material(
          color: selected
              ? _FardaCalendarColors.navy
              : _FardaCalendarColors.transparent,
          shape: StadiumBorder(
            side: BorderSide(
              color: selected
                  ? _FardaCalendarColors.navy
                  : _FardaCalendarColors.line,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 13),
                child: Center(
                  widthFactor: 1,
                  child: Text(
                    filter.label,
                    style: _FardaCalendarType.style(
                      size: 12,
                      lineHeight: 17,
                      weight: selected ? FontWeight.w600 : FontWeight.w400,
                      color: selected
                          ? _FardaCalendarColors.white
                          : _FardaCalendarColors.navy,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectedDayAgenda extends StatelessWidget {
  const _SelectedDayAgenda({
    required this.selectedDate,
    required this.filter,
    required this.events,
    required this.onEventAction,
  });

  final DateTime selectedDate;
  final ConsumerCalendarFilter filter;
  final List<ConsumerCalendarEvent> events;
  final ConsumerCalendarEventCallback? onEventAction;

  @override
  Widget build(BuildContext context) {
    final selectedEvents = events
        .where(
          (event) =>
              isSameCalendarDay(event.date, selectedDate) &&
              event.isVisibleFor(filter),
        )
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            DateFormat('EEEE, MMMM d').format(selectedDate),
            style: _FardaCalendarType.style(
              size: 14,
              lineHeight: 20,
              weight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (selectedEvents.isEmpty)
          _EmptyAgendaCard(filter: filter)
        else
          for (var index = 0; index < selectedEvents.length; index++) ...[
            _EventCard(
              event: selectedEvents[index],
              onAction: selectedEvents[index].actionLabel == null ||
                      onEventAction == null
                  ? null
                  : () => onEventAction!(selectedEvents[index]),
            ),
            if (index != selectedEvents.length - 1)
              const SizedBox(height: 10),
          ],
      ],
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event, required this.onAction});

  final ConsumerCalendarEvent event;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final marker = event.marker;
    return Semantics(
      container: true,
      label: '${event.eyebrow}. ${event.title}. ${event.description}',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _FardaCalendarColors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _FardaCalendarColors.line),
          boxShadow: const [
            BoxShadow(
              color: Color(0x08142C55),
              offset: Offset(0, 4),
              blurRadius: 12,
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: event.type == ConsumerCalendarEventType.refill
                      ? _FardaCalendarColors.sand
                      : _FardaCalendarColors.paleBlue,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: marker == null
                      ? const Icon(
                          Icons.schedule_rounded,
                          size: 20,
                          color: _FardaCalendarColors.navy,
                        )
                      : _StatusMark(
                          marker: marker,
                          selected: false,
                          size: 9,
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ExcludeSemantics(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            event.eyebrow.toUpperCase(),
                            style: _FardaCalendarType.style(
                              size: 10,
                              lineHeight: 14,
                              weight: FontWeight.w600,
                              color: _FardaCalendarColors.muted,
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            event.title,
                            style: _FardaCalendarType.style(
                              size: 18,
                              lineHeight: 24,
                              weight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            event.description,
                            style: _FardaCalendarType.style(
                              size: 12,
                              lineHeight: 17,
                              color: _FardaCalendarColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (event.actionLabel != null && onAction != null) ...[
                      const SizedBox(height: 8),
                      Semantics(
                        button: true,
                        label: event.actionLabel,
                        onTap: onAction,
                        child: ExcludeSemantics(
                          child: TextButton.icon(
                            onPressed: onAction,
                            style: TextButton.styleFrom(
                              foregroundColor: _FardaCalendarColors.navy,
                              minimumSize: const Size(44, 44),
                              padding: EdgeInsets.zero,
                              tapTargetSize: MaterialTapTargetSize.padded,
                              alignment: Alignment.centerLeft,
                              textStyle: _FardaCalendarType.style(
                                size: 12,
                                lineHeight: 17,
                                weight: FontWeight.w600,
                              ),
                            ),
                            iconAlignment: IconAlignment.end,
                            icon: const Icon(
                              Icons.chevron_right_rounded,
                              size: 16,
                            ),
                            label: Text(event.actionLabel!),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyAgendaCard extends StatelessWidget {
  const _EmptyAgendaCard({required this.filter});

  final ConsumerCalendarFilter filter;

  @override
  Widget build(BuildContext context) {
    final message = switch (filter) {
      ConsumerCalendarFilter.all =>
        'Nothing is planned or recorded on this day.',
      ConsumerCalendarFilter.routines =>
        'No routine entries are saved for this day.',
      ConsumerCalendarFilter.refills =>
        'No refill reminder is saved for this day.',
    };

    return Semantics(
      container: true,
      label: 'A little breathing room. $message',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _FardaCalendarColors.paleBlue,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: ExcludeSemantics(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.light_mode_outlined,
                  size: 20,
                  color: _FardaCalendarColors.accentBlue,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'A little breathing room.',
                        style: _FardaCalendarType.style(
                          size: 16,
                          lineHeight: 21,
                          weight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        message,
                        style: _FardaCalendarType.style(
                          size: 12,
                          lineHeight: 17,
                          color: _FardaCalendarColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FriendlyCalendarNote extends StatelessWidget {
  const _FriendlyCalendarNote();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label:
          'A blank day is not a failure. It is just a record you can review.',
      child: Row(
        children: [
          const ExcludeSemantics(
            child: SizedBox(
              width: 78,
              height: 78,
              child: CustomPaint(painter: _CalendarCompanionPainter()),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'A blank day isn\'t a failure.\nIt\'s just a record you can review.',
              style: _FardaCalendarType.style(
                size: 12,
                lineHeight: 17,
                color: _FardaCalendarColors.muted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CalendarCompanionPainter extends CustomPainter {
  const _CalendarCompanionPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width / 120;
    final scaleY = size.height / 120;
    canvas.save();
    canvas.scale(scaleX, scaleY);

    canvas.drawOval(
      const Rect.fromLTWH(25, 105, 70, 10),
      Paint()..color = const Color(0x1A142C55),
    );

    final body = Path()
      ..moveTo(25, 72)
      ..cubicTo(14, 43, 32, 15, 58, 15)
      ..cubicTo(88, 15, 101, 40, 96, 67)
      ..lineTo(89, 92)
      ..cubicTo(86, 103, 70, 104, 64, 96)
      ..cubicTo(57, 107, 43, 108, 37, 98)
      ..close();
    canvas.drawPath(body, Paint()..color = _FardaCalendarColors.navy);

    canvas.drawCircle(
      const Offset(45, 54),
      3.6,
      Paint()..color = _FardaCalendarColors.ivory,
    );
    canvas.drawCircle(
      const Offset(69, 54),
      3.6,
      Paint()..color = _FardaCalendarColors.ivory,
    );

    final smile = Path()
      ..moveTo(52, 68)
      ..quadraticBezierTo(58, 73, 64, 67);
    canvas.drawPath(
      smile,
      Paint()
        ..color = _FardaCalendarColors.ivory
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );

    final calendarRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(36, 73, 48, 32),
      const Radius.circular(6),
    );
    canvas.drawRRect(calendarRect, Paint()..color = _FardaCalendarColors.ivory);
    final calendarInk = Paint()
      ..color = _FardaCalendarColors.amber
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(36, 83), const Offset(84, 83), calendarInk);
    canvas.drawLine(const Offset(47, 70), const Offset(47, 78), calendarInk);
    canvas.drawLine(const Offset(73, 70), const Offset(73, 78), calendarInk);

    final check = Path()
      ..moveTo(49, 93)
      ..lineTo(55, 98)
      ..lineTo(66, 88);
    canvas.drawPath(
      check,
      Paint()
        ..color = _FardaCalendarColors.navy
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CalendarCompanionPainter oldDelegate) => false;
}

class _FardaCalendarColors {
  const _FardaCalendarColors._();

  static const navy = Color(0xFF142C55);
  static const accentBlue = Color(0xFF365C99);
  static const paleBlue = Color(0xFFE9EEF7);
  static const ivory = Color(0xFFF6F5F0);
  static const white = Color(0xFFFFFFFF);
  static const muted = Color(0xFF58677D);
  static const line = Color(0xFFDCE2EB);
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
      ConsumerCalendarMarker.unconfirmed => 'Unconfirmed entry',
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
      title: 'Morning entry · Not yet confirmed',
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
      description:
          'Your chosen reminder date, not a promised pickup date.',
      actionLabel: 'Open refill station',
    ),
  ];
}

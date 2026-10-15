import 'package:flutter/material.dart';

import 'today_models.dart';
import 'today_routine_card.dart';

/// Figma-aligned consumer Today experience.
///
/// This widget owns presentation state only. It does not call a network or
/// infer that medication was taken from a reminder, call, or vial event.
class FardaTodayScreen extends StatefulWidget {
  const FardaTodayScreen({
    super.key,
    this.initialDate,
    this.initialDoseStatus = TodayDoseStatus.pending,
    this.initiallySnoozed = false,
    this.userInitials = 'YO',
    this.greetingName = 'you',
    this.morningTimeLabel = '9:00 AM',
    this.medicationLabel = 'Morning routine',
    this.hasRoutine = true,
    this.liveRecords = false,
    this.routines = const [],
    this.showBottomNavigation = true,
    this.onDaySelected,
    this.onDoseChanged,
    this.onLogDoseRequested,
    this.onSnoozed,
    this.onMoreOptions,
    this.onReminderMilestoneSelected,
    this.onOpenCalendar,
    this.onOpenRefills,
    this.onOpenProfile,
    this.onTodayTap,
    this.onEveningRoutineTap,
    this.onReviewRoutineTap,
    this.onPersistDose,
    this.onPersistSnooze,
    this.onPersistDoseForId,
    this.onPersistSnoozeForId,
    this.onCorrectRoutine,
  }) : assert(
         !initiallySnoozed || initialDoseStatus == TodayDoseStatus.pending,
         'Only a pending routine can be snoozed.',
       );

  static const confirmDoseButtonKey = Key('today_confirm_dose_button');
  static const recordSkippedButtonKey = Key('today_record_skipped_button');
  static const resetDoseButtonKey = Key('today_reset_dose_button');

  /// Defaults to the user's current local calendar date when omitted.
  final DateTime? initialDate;
  final TodayDoseStatus initialDoseStatus;
  final bool initiallySnoozed;
  final String userInitials;
  final String greetingName;
  final String morningTimeLabel;
  final String medicationLabel;
  final bool hasRoutine;
  final bool liveRecords;
  final List<TodayRoutineRecord> routines;
  final bool showBottomNavigation;

  final ValueChanged<DateTime>? onDaySelected;
  final ValueChanged<TodayDoseSnapshot>? onDoseChanged;
  final VoidCallback? onLogDoseRequested;
  final VoidCallback? onSnoozed;
  final VoidCallback? onMoreOptions;
  final ValueChanged<TodayReminderMilestone>?
  onReminderMilestoneSelected;
  final VoidCallback? onOpenCalendar;
  final VoidCallback? onOpenRefills;
  final VoidCallback? onOpenProfile;
  final VoidCallback? onTodayTap;
  final VoidCallback? onEveningRoutineTap;
  final VoidCallback? onReviewRoutineTap;
  /// Returns an error to display, or null after the server accepts the write.
  final Future<String?> Function(TodayDoseStatus status)? onPersistDose;
  final Future<String?> Function()? onPersistSnooze;
  final Future<String?> Function(String id, TodayDoseStatus status)?
      onPersistDoseForId;
  final Future<String?> Function(String id)? onPersistSnoozeForId;
  final ValueChanged<String>? onCorrectRoutine;

  @override
  State<FardaTodayScreen> createState() => _FardaTodayScreenState();
}

class _FardaTodayScreenState extends State<FardaTodayScreen> {
  final ScrollController _scrollController = ScrollController();

  late DateTime _selectedDate;
  late DateTime _visibleWeekStart;
  late TodayDoseStatus _doseStatus;
  late bool _isSnoozed;
  TodayReminderMilestoneType? _previewedMilestone;
  bool _saving = false;
  String? _selectedRoutineId;

  TodayRoutineRecord? get _activeRoutine {
    if (!widget.liveRecords || widget.routines.isEmpty) return null;
    for (final routine in widget.routines) {
      if (routine.id == _selectedRoutineId) return routine;
    }
    return widget.routines.first;
  }

  TodayDoseStatus get _activeStatus => _activeRoutine?.status ?? _doseStatus;
  bool get _activeSnoozed => _activeRoutine?.isSnoozed ?? _isSnoozed;
  String get _activeTime => _activeRoutine?.timeLabel ?? widget.morningTimeLabel;
  String get _activeLabel =>
      _activeRoutine?.medicationLabel ?? widget.medicationLabel;

  @override
  void initState() {
    super.initState();
    _selectedDate = _dateOnly(widget.initialDate ?? DateTime.now());
    _visibleWeekStart = _startOfWeek(_selectedDate);
    _doseStatus = widget.initialDoseStatus;
    _isSnoozed = widget.initiallySnoozed;
    if (widget.routines.isNotEmpty) {
      _selectedRoutineId = widget.routines.first.id;
    }
  }

  @override
  void didUpdateWidget(covariant FardaTodayScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextInitialDate = widget.initialDate;
    if (nextInitialDate != null &&
        nextInitialDate != oldWidget.initialDate &&
        !_isSameDay(_selectedDate, nextInitialDate)) {
      _selectedDate = _dateOnly(nextInitialDate);
      _visibleWeekStart = _startOfWeek(_selectedDate);
      _selectedRoutineId =
          widget.routines.isEmpty ? null : widget.routines.first.id;
    }
    if (widget.initialDoseStatus != oldWidget.initialDoseStatus) {
      _doseStatus = widget.initialDoseStatus;
      _isSnoozed = widget.initiallySnoozed &&
          widget.initialDoseStatus == TodayDoseStatus.pending;
    } else if (widget.initiallySnoozed != oldWidget.initiallySnoozed &&
        _doseStatus == TodayDoseStatus.pending) {
      _isSnoozed = widget.initiallySnoozed;
    }
    if (widget.routines.isNotEmpty &&
        !widget.routines.any((routine) => routine.id == _selectedRoutineId)) {
      _selectedRoutineId = widget.routines.first.id;
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _selectDay(DateTime date) {
    final normalized = _dateOnly(date);
    if (!_isSameDay(_selectedDate, normalized)) {
      setState(() => _selectedDate = normalized);
    }
    widget.onDaySelected?.call(normalized);
    widget.onOpenCalendar?.call();
  }

  void _publishDoseState() {
    widget.onDoseChanged?.call(
      TodayDoseSnapshot(status: _doseStatus, isSnoozed: _isSnoozed),
    );
  }

  void _setDoseStatus(TodayDoseStatus status) {
    setState(() {
      _doseStatus = status;
      _isSnoozed = false;
    });
    _publishDoseState();
  }

  Future<void> _openDoseConfirmation() async {
    final routineId = _activeRoutine?.id;
    widget.onLogDoseRequested?.call();
    final shouldSave = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: _sheetBarrier,
      builder: (sheetContext) => _FardaSheet(
        eyebrow: 'YOUR RECORD',
        title: widget.liveRecords ? 'Log this dose?' : 'Log your morning dose?',
        body: 'Only save this if you took it. This is your report.',
        children: [
          _SheetNotice(
            icon: Icons.medication_rounded,
            title: _activeLabel,
            detail: '$_activeTime · ${_longDate(_selectedDate)}',
          ),
          const SizedBox(height: 18),
          _SheetButton(
            key: FardaTodayScreen.confirmDoseButtonKey,
            label: 'Yes, I took it',
            onPressed: () => Navigator.of(sheetContext).pop(true),
          ),
          const SizedBox(height: 8),
          _SheetButton(
            label: 'Go back',
            isSecondary: true,
            onPressed: () => Navigator.of(sheetContext).pop(false),
          ),
        ],
      ),
    );

    if (!mounted || shouldSave != true) return;
    if (!await _persistDose(TodayDoseStatus.confirmed, routineId)) return;
    if (!widget.liveRecords) _setDoseStatus(TodayDoseStatus.confirmed);
    _showMessage(widget.liveRecords
        ? 'Your entry is saved.'
        : 'Your morning entry is saved.');
  }

  Future<bool> _persistDose(TodayDoseStatus status, String? routineId) async {
    if (_saving) return false;
    final persist = widget.onPersistDose;
    final persistById = widget.onPersistDoseForId;
    if (widget.liveRecords && persistById == null && persist == null) {
      return false;
    }
    if (persistById != null && routineId == null && persist == null) {
      return false;
    }
    if (persistById == null && persist == null) return true;
    setState(() => _saving = true);
    try {
      final error = persistById != null && routineId != null
          ? await persistById(routineId, status)
          : await persist!(status);
      if (!mounted) return false;
      if (error != null) {
        _showMessage(error);
        return false;
      }
      return true;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _snooze() async {
    if (_saving) return;
    if (_activeSnoozed) {
      _showMessage('This reminder is already snoozed.');
      return;
    }
    if (widget.liveRecords) {
      final persist = widget.onPersistSnooze;
      final persistById = widget.onPersistSnoozeForId;
      final routineId = _activeRoutine?.id;
      if (persist == null && (persistById == null || routineId == null)) {
        return;
      }
      setState(() => _saving = true);
      try {
        final error = persistById != null && routineId != null
            ? await persistById(routineId)
            : await persist!();
        if (!mounted) return;
        if (error != null) {
          _showMessage(error);
          return;
        }
      } finally {
        if (mounted) setState(() => _saving = false);
      }
    }
    if (!widget.liveRecords) setState(() => _isSnoozed = true);
    widget.onSnoozed?.call();
    _publishDoseState();
    _showMessage('Reminder snoozed. No dose was logged.');
  }

  Future<void> _openMoreOptions() async {
    final routineId = _activeRoutine?.id;
    widget.onMoreOptions?.call();
    final result = await showModalBottomSheet<_MoreOption>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: _sheetBarrier,
      builder: (sheetContext) => _FardaSheet(
        eyebrow: 'YOUR RECORD',
        title: 'More options',
        body: 'Skipped records what happened; it does not change your plan.',
        children: [
          _SheetButton(
            key: FardaTodayScreen.recordSkippedButtonKey,
            label: 'Record as skipped',
            isSecondary: true,
            onPressed: () =>
                Navigator.of(sheetContext).pop(_MoreOption.skipped),
          ),
          const SizedBox(height: 8),
          _SheetButton(
            label: 'Review my routine',
            isSecondary: true,
            onPressed: () =>
                Navigator.of(sheetContext).pop(_MoreOption.reviewRoutine),
          ),
          const SizedBox(height: 8),
          _SheetButton(
            label: 'Cancel',
            onPressed: () => Navigator.of(sheetContext).pop(),
          ),
        ],
      ),
    );

    if (!mounted || result == null) return;
    switch (result) {
      case _MoreOption.skipped:
        if (!await _persistDose(TodayDoseStatus.skipped, routineId)) return;
        if (!widget.liveRecords) _setDoseStatus(TodayDoseStatus.skipped);
        _showMessage('Saved as skipped. You can correct this any time.');
        break;
      case _MoreOption.reviewRoutine:
        widget.onReviewRoutineTap?.call();
        break;
    }
  }

  Future<void> _openCorrection() async {
    if (widget.liveRecords) {
      final id = _activeRoutine?.id;
      if (id != null && widget.onCorrectRoutine != null) {
        widget.onCorrectRoutine!(id);
      } else {
        widget.onReviewRoutineTap?.call();
      }
      return;
    }
    final shouldReset = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: _sheetBarrier,
      builder: (sheetContext) => _FardaSheet(
        eyebrow: 'CORRECT YOUR RECORD',
        title: 'Mark this as unconfirmed?',
        body:
            'This removes the saved status from this routine occurrence. You can add a new entry afterward.',
        children: [
          _SheetButton(
            key: FardaTodayScreen.resetDoseButtonKey,
            label: 'Yes, correct this entry',
            onPressed: () => Navigator.of(sheetContext).pop(true),
          ),
          const SizedBox(height: 8),
          _SheetButton(
            label: 'Keep my entry',
            isSecondary: true,
            onPressed: () => Navigator.of(sheetContext).pop(false),
          ),
        ],
      ),
    );

    if (!mounted || shouldReset != true) return;
    _setDoseStatus(TodayDoseStatus.pending);
    _showMessage('Your routine is not yet confirmed.');
  }

  void _selectMilestone(TodayReminderMilestone milestone) {
    setState(() => _previewedMilestone = milestone.type);
    widget.onReminderMilestoneSelected?.call(milestone);
  }

  void _handleTodayTap() {
    widget.onTodayTap?.call();
    if (!_scrollController.hasClients) return;
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      _scrollController.jumpTo(0);
      return;
    }
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  void _showMessage(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message, style: _type(size: 13, lineHeight: 18)),
          backgroundColor: _soft,
          behavior: SnackBarBehavior.floating,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final week = List<DateTime>.generate(
      7,
      (index) => _visibleWeekStart.add(Duration(days: index)),
    );
    final previewedMilestone = _milestoneFor(_previewedMilestone);

    return Scaffold(
      backgroundColor: _canvas,
      bottomNavigationBar: widget.showBottomNavigation
          ? _TodayBottomNavigation(
              onTodayTap: _handleTodayTap,
              onCalendarTap: widget.onOpenCalendar,
              onRefillsTap: widget.onOpenRefills,
              onYouTap: widget.onOpenProfile,
            )
          : null,
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 390),
            child: SingleChildScrollView(
              controller: _scrollController,
              // The shell owns navigation in live mode. Keep enough scroll
              // extent for actions near the end of a short routine list.
              padding: EdgeInsets.fromLTRB(
                22, 8, 22, widget.showBottomNavigation ? 28 : 112,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _BrandHeader(
                    initials: widget.userInitials,
                    onProfileTap: widget.onOpenProfile,
                  ),
                  const SizedBox(height: 20),
                  _Greeting(
                    name: widget.greetingName,
                    selectedDate: _selectedDate,
                  ),
                  const SizedBox(height: 20),
                  _WeekStrip(
                    dates: week,
                    selectedDate: _selectedDate,
                    onSelected: _selectDay,
                  ),
                  const SizedBox(height: 20),
                  if (widget.liveRecords && widget.routines.length > 1) ...[
                    Text(
                      'Your routines · ${widget.routines.length}',
                      style: _type(size: 18, lineHeight: 24, weight: FontWeight.w600),
                    ),
                    const SizedBox(height: 10),
                    for (final routine in widget.routines) ...[
                      _RoutineSelector(
                        routine: routine,
                        selected: routine.id == _activeRoutine?.id,
                        onTap: _saving ? null : () => setState(() => _selectedRoutineId = routine.id),
                      ),
                      const SizedBox(height: 8),
                    ],
                    const SizedBox(height: 12),
                  ],
                  if (widget.liveRecords && widget.hasRoutine) ...[
                    Text(_activeLabel,
                        style: _type(size: 15, lineHeight: 21, weight: FontWeight.w600)),
                    const SizedBox(height: 8),
                  ],
                  if (widget.hasRoutine) FardaTodayRoutineCard(
                    timeLabel: _activeTime,
                    status: _activeStatus,
                    isSnoozed: _activeSnoozed,
                    neutralCopy: widget.liveRecords,
                    onOpenLog: _openDoseConfirmation,
                    onSnooze: _snooze,
                    onMoreOptions: _openMoreOptions,
                    onCorrectEntry: _openCorrection,
                  ) else _NavigationCard(
                    icon: Icons.add_circle_outline,
                    title: 'No routine on this day',
                    detail: 'Add or review a routine in your account.',
                    onTap: widget.onReviewRoutineTap,
                  ),
                  if (!widget.liveRecords) ...[
                  const SizedBox(height: 20),
                  _ReminderRhythmCard(
                    selectedType: _previewedMilestone ??
                        TodayReminderMilestoneType.routineDue,
                    footerText: previewedMilestone?.accessibilityHint ??
                        'Calls only when you enable them',
                    onSelected: _selectMilestone,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Ahead of the day',
                    style: _type(
                      size: 18,
                      lineHeight: 24,
                      weight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _NavigationCard(
                    icon: Icons.medication_rounded,
                    title: 'Evening routine',
                    detail: '8:00 PM · Manual reminder',
                    onTap: widget.onEveningRoutineTap,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'A little head start',
                    style: _type(
                      size: 18,
                      lineHeight: 24,
                      weight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _NavigationCard(
                    icon: Icons.inventory_2_outlined,
                    title: 'Let’s plan your refill',
                    detail: 'About 6 days of supply · Estimate',
                    onTap: widget.onOpenRefills,
                  ),
                  const SizedBox(height: 20),
                  const _HelpfulContext(),
                  ],
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
  const _BrandHeader({required this.initials, required this.onProfileTap});

  final String initials;
  final VoidCallback? onProfileTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'farda.',
          style: _type(size: 30, lineHeight: 39, weight: FontWeight.w600),
        ),
        Semantics(
          button: true,
          label: 'Open your profile',
          child: Material(
            color: _soft,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onProfileTap,
              child: SizedBox.square(
                dimension: 36,
                child: Center(
                  child: Text(
                    initials,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: _type(
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
      ],
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting({required this.name, required this.selectedDate});

  final String name;
  final DateTime selectedDate;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hi, $name.',
                style: _type(
                  size: 14,
                  lineHeight: 20,
                  color: _secondaryText,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Today, at\nyour pace.',
                style: _type(
                  size: 34,
                  lineHeight: 37,
                  weight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        AnimatedSwitcher(
          duration: MediaQuery.maybeOf(context)?.disableAnimations ?? false
              ? Duration.zero
              : const Duration(milliseconds: 180),
          child: Container(
            key: ValueKey(_dateKey(selectedDate)),
            width: 60,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _soft,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _shortMonth(selectedDate).toUpperCase(),
                  style: _type(
                    size: 10,
                    lineHeight: 14,
                    weight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${selectedDate.day}',
                  style: _type(
                    size: 28,
                    lineHeight: 36,
                    weight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _WeekStrip extends StatelessWidget {
  const _WeekStrip({
    required this.dates,
    required this.selectedDate,
    required this.onSelected,
  });

  final List<DateTime> dates;
  final DateTime selectedDate;
  final ValueChanged<DateTime> onSelected;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'This week',
      child: Row(
        children: [
          for (var index = 0; index < dates.length; index++) ...[
            Expanded(
              child: _WeekDay(
                date: dates[index],
                isSelected: _isSameDay(dates[index], selectedDate),
                onTap: () => onSelected(dates[index]),
              ),
            ),
            if (index != dates.length - 1) const SizedBox(width: 5),
          ],
        ],
      ),
    );
  }
}

class _WeekDay extends StatelessWidget {
  const _WeekDay({
    required this.date,
    required this.isSelected,
    required this.onTap,
  });

  final DateTime date;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = isSelected ? Colors.white : _navy;
    return Semantics(
      button: true,
      selected: isSelected,
      label: _longDate(date),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: Key('today_day_${_dateKey(date)}'),
          onTap: onTap,
          child: AnimatedContainer(
            duration: MediaQuery.maybeOf(context)?.disableAnimations ?? false
                ? Duration.zero
                : const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            constraints: const BoxConstraints(minHeight: 62),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: isSelected ? _navy : _card,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _weekdayInitial(date),
                  style: _type(
                    size: 10,
                    lineHeight: 14,
                    color: isSelected ? Colors.white : _secondaryText,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${date.day}',
                  style: _type(
                    size: 17,
                    lineHeight: 22,
                    weight: FontWeight.w600,
                    color: foreground,
                  ),
                ),
                const SizedBox(height: 4),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFFD6E3FB) : _statusBlue,
                    shape: BoxShape.circle,
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

class _ReminderRhythmCard extends StatelessWidget {
  const _ReminderRhythmCard({
    required this.selectedType,
    required this.footerText,
    required this.onSelected,
  });

  final TodayReminderMilestoneType selectedType;
  final String footerText;
  final ValueChanged<TodayReminderMilestone> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _soft,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'YOUR REMINDER RHYTHM',
            style: _type(
              size: 10,
              lineHeight: 14,
              weight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Text('Three gentle nudges.', style: _type(size: 14, lineHeight: 20)),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var index = 0; index < _reminderMilestones.length; index++) ...[
                Expanded(
                  child: _MilestoneButton(
                    milestone: _reminderMilestones[index],
                    isSelected:
                        _reminderMilestones[index].type == selectedType,
                    onTap: () => onSelected(_reminderMilestones[index]),
                  ),
                ),
                if (index != _reminderMilestones.length - 1)
                  const SizedBox(width: 10),
              ],
            ],
          ),
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 180),
            child: Text(
              footerText,
              key: ValueKey(footerText),
              style: _type(
                size: 10,
                lineHeight: 14,
                color: _secondaryText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MilestoneButton extends StatelessWidget {
  const _MilestoneButton({
    required this.milestone,
    required this.isSelected,
    required this.onTap,
  });

  final TodayReminderMilestone milestone;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: isSelected,
      label:
          '${milestone.timeLabel}, ${milestone.label}. ${milestone.accessibilityHint}',
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: Key('today_milestone_${milestone.type.name}'),
          onTap: onTap,
          child: AnimatedContainer(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected ? _card : const Color(0x80FFFFFF),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected ? const Color(0xFFB6C8E3) : _border,
              ),
              boxShadow: isSelected
                  ? const [BoxShadow(color: Color(0x0F142C55), blurRadius: 8, offset: Offset(0, 3))]
                  : null,
            ),
            child: Column(
              children: [
                AnimatedContainer(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 180),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: isSelected ? _navy : _statusBlue,
                    shape: BoxShape.circle,
                    boxShadow: isSelected
                        ? const [
                            BoxShadow(
                              color: Color(0x33142C55),
                              blurRadius: 0,
                              spreadRadius: 3,
                            ),
                          ]
                        : null,
                  ),
                ),
                const SizedBox(height: 5),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    milestone.timeLabel,
                    style: _type(
                      size: 22,
                      lineHeight: 29,
                      weight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  milestone.label,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  style: _type(
                    size: 10,
                    lineHeight: 14,
                    color: _secondaryText,
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

class _NavigationCard extends StatelessWidget {
  const _NavigationCard({
    required this.icon,
    required this.title,
    required this.detail,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _card,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _soft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 22, color: _navy),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: _type(
                        size: 14,
                        lineHeight: 20,
                        weight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      detail,
                      style: _type(
                        size: 12,
                        lineHeight: 17,
                        color: _secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: _navy),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoutineSelector extends StatelessWidget {
  const _RoutineSelector({
    required this.routine,
    required this.selected,
    required this.onTap,
  });

  final TodayRoutineRecord routine;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final status = switch (routine.status) {
      TodayDoseStatus.confirmed => 'Taken · self-reported',
      TodayDoseStatus.skipped => 'Skipped · self-reported',
      TodayDoseStatus.pending when routine.isSnoozed => 'Snoozed · unconfirmed',
      TodayDoseStatus.pending => 'Not yet confirmed',
    };
    return Semantics(
      button: true,
      selected: selected,
      label: '${routine.medicationLabel}, ${routine.timeLabel}, $status',
      child: Material(
        color: selected ? _soft : _card,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: Key('today_routine_${routine.id}'),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(
                  switch (routine.status) {
                    TodayDoseStatus.confirmed => Icons.check_circle_outline_rounded,
                    TodayDoseStatus.skipped => Icons.remove_circle_outline_rounded,
                    TodayDoseStatus.pending => Icons.schedule_rounded,
                  },
                  color: _navy,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(routine.medicationLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _type(size: 14, lineHeight: 20, weight: FontWeight.w600)),
                      Text('${routine.timeLabel} · $status',
                          style: _type(size: 12, lineHeight: 17, color: _secondaryText)),
                    ],
                  ),
                ),
                Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    size: 18, color: _navy),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HelpfulContext extends StatelessWidget {
  const _HelpfulContext();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _soft,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, size: 18, color: _navy),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'No vial yet? Your reminders and manual journal work on their own.',
              style: _type(
                size: 12,
                lineHeight: 17,
                color: _secondaryText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TodayBottomNavigation extends StatelessWidget {
  const _TodayBottomNavigation({
    required this.onTodayTap,
    required this.onCalendarTap,
    required this.onRefillsTap,
    required this.onYouTap,
  });

  final VoidCallback onTodayTap;
  final VoidCallback? onCalendarTap;
  final VoidCallback? onRefillsTap;
  final VoidCallback? onYouTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 86,
      child: Material(
        color: _card,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: _border)),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 390),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 11, 22, 9),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _BottomNavItem(
                        label: 'Today',
                        icon: Icons.home_rounded,
                        isSelected: true,
                        onTap: onTodayTap,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _BottomNavItem(
                        label: 'Calendar',
                        icon: Icons.calendar_month_rounded,
                        onTap: onCalendarTap,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _BottomNavItem(
                        label: 'Refills',
                        icon: Icons.inventory_2_outlined,
                        onTap: onRefillsTap,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _BottomNavItem(
                        label: 'You',
                        icon: Icons.person_outline_rounded,
                        onTap: onYouTap,
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

class _BottomNavItem extends StatelessWidget {
  const _BottomNavItem({
    required this.label,
    required this.icon,
    required this.onTap,
    this.isSelected = false,
  });

  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: isSelected,
      label: label,
      child: InkResponse(
        onTap: onTap,
        radius: 32,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 36,
              height: 34,
              decoration: BoxDecoration(
                color: isSelected ? _soft : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                size: 22,
                color: isSelected ? _navy : _secondaryText,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              style: _type(
                size: 10,
                lineHeight: 14,
                weight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? _navy : _secondaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FardaSheet extends StatelessWidget {
  const _FardaSheet({
    required this.eyebrow,
    required this.title,
    required this.body,
    required this.children,
  });

  final String eyebrow;
  final String title;
  final String body;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return SafeArea(
      top: false,
      child: Container(
        padding: EdgeInsets.fromLTRB(22, 12, 22, 22 + bottomInset),
        decoration: const BoxDecoration(
          color: _canvas,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _border,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Text(
                eyebrow,
                style: _type(
                  size: 10,
                  lineHeight: 14,
                  weight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: _type(
                  size: 28,
                  lineHeight: 33,
                  weight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                body,
                style: _type(
                  size: 14,
                  lineHeight: 20,
                  color: _secondaryText,
                ),
              ),
              const SizedBox(height: 20),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetNotice extends StatelessWidget {
  const _SheetNotice({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _soft,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, size: 22, color: _navy),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: _type(
                    size: 14,
                    lineHeight: 20,
                    weight: FontWeight.w600,
                  ),
                ),
                Text(
                  detail,
                  style: _type(
                    size: 12,
                    lineHeight: 17,
                    color: _secondaryText,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetButton extends StatelessWidget {
  const _SheetButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isSecondary = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool isSecondary;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: FilledButton(
        style: FilledButton.styleFrom(
          elevation: 0,
          backgroundColor: isSecondary ? _soft : _navy,
          foregroundColor: isSecondary ? _navy : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: _type(
            size: 14,
            lineHeight: 19,
            weight: FontWeight.w600,
            color: isSecondary ? _navy : Colors.white,
          ),
        ),
        onPressed: onPressed,
        child: Text(label),
      ),
    );
  }
}

enum _MoreOption { skipped, reviewRoutine }

const _canvas = Color(0xFFF6F5F0);
const _card = Color(0xFFFFFFFF);
const _soft = Color(0xFFE9EEF7);
const _navy = Color(0xFF142C55);
const _secondaryText = Color(0xFF58677D);
const _border = Color(0xFFDCE2EB);
const _statusBlue = Color(0xFF8AA4CF);
const _sheetBarrier = Color(0x590B1D3C);

const _reminderMilestones = <TodayReminderMilestone>[
  TodayReminderMilestone(
    type: TodayReminderMilestoneType.liveActivity,
    timeLabel: '8:50',
    label: 'Live Activity',
    accessibilityHint: 'A heads-up appears ten minutes before your routine.',
  ),
  TodayReminderMilestone(
    type: TodayReminderMilestoneType.routineDue,
    timeLabel: '9:00',
    label: 'Routine due',
    accessibilityHint: 'Your routine becomes active right on time.',
  ),
  TodayReminderMilestone(
    type: TodayReminderMilestoneType.callReminder,
    timeLabel: '9:10',
    label: 'Call reminder',
    accessibilityHint: 'Calls only when you enable them.',
  ),
];

TodayReminderMilestone? _milestoneFor(TodayReminderMilestoneType? type) {
  if (type == null) return null;
  for (final milestone in _reminderMilestones) {
    if (milestone.type == type) return milestone;
  }
  return null;
}

TextStyle _type({
  required double size,
  required double lineHeight,
  FontWeight weight = FontWeight.w400,
  Color color = _navy,
}) {
  return TextStyle(
    fontFamily: 'Outfit',
    fontSize: size,
    height: lineHeight / size,
    fontWeight: weight,
    color: color,
  );
}

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

DateTime _startOfWeek(DateTime date) {
  return _dateOnly(date).subtract(Duration(days: date.weekday - 1));
}

bool _isSameDay(DateTime first, DateTime second) {
  return first.year == second.year &&
      first.month == second.month &&
      first.day == second.day;
}

String _dateKey(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

String _shortMonth(DateTime date) => _shortMonths[date.month - 1];

String _weekdayInitial(DateTime date) => _weekdayInitials[date.weekday - 1];

String _longDate(DateTime date) {
  return '${_longWeekdays[date.weekday - 1]}, ${_longMonths[date.month - 1]} ${date.day}, ${date.year}';
}

const _shortMonths = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

const _longMonths = <String>[
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

const _weekdayInitials = <String>['M', 'T', 'W', 'T', 'F', 'S', 'S'];

const _longWeekdays = <String>[
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

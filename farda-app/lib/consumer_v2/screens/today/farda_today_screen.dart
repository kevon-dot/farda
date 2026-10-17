import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../design_system/farda_consumer_tokens.dart' as design;
import 'farda_companion.dart';
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
    this.receiptClock,
    this.initialDoseStatus = TodayDoseStatus.pending,
    this.initiallySnoozed = false,
    this.userInitials = 'YO',
    this.greetingName = 'you',
    this.morningTimeLabel = '9:00 AM',
    this.medicationLabel = 'Morning routine',
    this.hasRoutine = true,
    this.hasPrescriptions = true,
    this.onAddPrescription,
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

  /// Injectable clock for deterministic receipt rendering and time labels.
  final DateTime Function()? receiptClock;
  final TodayDoseStatus initialDoseStatus;
  final bool initiallySnoozed;
  final String userInitials;
  final String greetingName;
  final String morningTimeLabel;
  final String medicationLabel;
  final bool hasRoutine;
  final bool hasPrescriptions;
  final VoidCallback? onAddPrescription;
  final bool liveRecords;
  final List<TodayRoutineRecord> routines;
  final bool showBottomNavigation;

  final ValueChanged<DateTime>? onDaySelected;
  final ValueChanged<TodayDoseSnapshot>? onDoseChanged;
  final VoidCallback? onLogDoseRequested;
  final VoidCallback? onSnoozed;
  final VoidCallback? onMoreOptions;
  final ValueChanged<TodayReminderMilestone>? onReminderMilestoneSelected;
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
  final GlobalKey _savedEntryKey = GlobalKey();

  late DateTime _selectedDate;
  late DateTime _visibleWeekStart;
  late TodayDoseStatus _doseStatus;
  late bool _isSnoozed;
  TodayReminderMilestoneType? _previewedMilestone;
  bool _saving = false;
  String? _selectedRoutineId;
  _TodayReceipt? _receipt;
  bool _showCheckIn = false;
  String? _checkInRoutineId;
  String? _checkInLabel;
  String? _checkInSchedule;
  String? _receiptRoutineId;
  String? _receiptLabel;
  String? _receiptSchedule;
  DateTime? _receiptAt;
  DateTime? _receiptSnoozedUntil;

  TodayRoutineRecord? get _activeRoutine {
    if (!widget.liveRecords || widget.routines.isEmpty) return null;
    for (final routine in widget.routines) {
      if (routine.id == _selectedRoutineId) return routine;
    }
    return widget.routines.first;
  }

  TodayDoseStatus get _activeStatus => _activeRoutine?.status ?? _doseStatus;
  bool get _activeSnoozed => _activeRoutine?.isSnoozed ?? _isSnoozed;
  String get _activeTime =>
      _activeRoutine?.timeLabel ?? widget.morningTimeLabel;
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
      _receipt = null;
      _showCheckIn = false;
    }
    if (widget.initialDoseStatus != oldWidget.initialDoseStatus) {
      _doseStatus = widget.initialDoseStatus;
      _isSnoozed =
          widget.initiallySnoozed &&
          widget.initialDoseStatus == TodayDoseStatus.pending;
    } else if (widget.initiallySnoozed != oldWidget.initiallySnoozed &&
        _doseStatus == TodayDoseStatus.pending) {
      _isSnoozed = widget.initiallySnoozed;
    }
    if (widget.routines.isNotEmpty &&
        !widget.routines.any((routine) => routine.id == _selectedRoutineId)) {
      _selectedRoutineId = widget.routines.first.id;
    }
    if (widget.liveRecords && _receipt != null) {
      for (final routine in widget.routines) {
        if (routine.id != _receiptRoutineId) continue;
        if (_receipt == _TodayReceipt.confirmed) {
          _receiptAt = routine.recordedAt?.toLocal();
        } else {
          _receiptSnoozedUntil = routine.snoozedUntil?.toLocal();
        }
        break;
      }
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
      setState(() {
        _selectedDate = normalized;
        _receipt = null;
        _showCheckIn = false;
      });
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

  void _openDoseConfirmation() {
    if (_saving) return;
    widget.onLogDoseRequested?.call();
    setState(() {
      _checkInRoutineId = _activeRoutine?.id;
      _checkInLabel = _activeLabel;
      _checkInSchedule = _activeTime;
      _showCheckIn = true;
    });
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  Future<void> _confirmDose() async {
    final routineId = _checkInRoutineId;
    if (!await _persistDose(TodayDoseStatus.confirmed, routineId)) return;
    if (!widget.liveRecords) _setDoseStatus(TodayDoseStatus.confirmed);
    _showSavedReceipt(
      _TodayReceipt.confirmed,
      routineId: routineId,
      label: _checkInLabel ?? _activeLabel,
      schedule: _checkInSchedule ?? _activeTime,
    );
  }

  void _showSavedReceipt(
    _TodayReceipt receipt, {
    required String? routineId,
    required String label,
    required String schedule,
  }) {
    if (!mounted) return;
    setState(() {
      _receipt = receipt;
      _showCheckIn = false;
      _receiptRoutineId = routineId;
      _receiptLabel = label;
      _receiptSchedule = schedule;
      final canonical = widget.routines.where(
        (routine) => routine.id == routineId,
      );
      _receiptAt =
          widget.liveRecords
              ? (canonical.isEmpty
                  ? null
                  : canonical.first.recordedAt?.toLocal())
              : (widget.receiptClock?.call() ?? DateTime.now());
      _receiptSnoozedUntil =
          widget.liveRecords
              ? (canonical.isEmpty
                  ? null
                  : canonical.first.snoozedUntil?.toLocal())
              : (widget.receiptClock?.call() ?? DateTime.now()).add(
                const Duration(minutes: 15),
              );
    });
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  void _returnToToday() {
    setState(() {
      _receipt = null;
      _showCheckIn = false;
      _receiptRoutineId = null;
      _receiptLabel = null;
      _receiptSchedule = null;
      _receiptAt = null;
      _receiptSnoozedUntil = null;
    });
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
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
      final error =
          persistById != null && routineId != null
              ? await persistById(routineId, status)
              : await persist!(status);
      if (!mounted) return false;
      if (error != null) {
        _showMessage(error);
        return false;
      }
      return true;
    } catch (_) {
      if (mounted) _showMessage('Couldn’t save your entry. Please try again.');
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _snooze() async {
    if (_saving) return;
    final routineId = _showCheckIn ? _checkInRoutineId : _activeRoutine?.id;
    final routineLabel =
        _showCheckIn ? (_checkInLabel ?? _activeLabel) : _activeLabel;
    final routineTime =
        _showCheckIn ? (_checkInSchedule ?? _activeTime) : _activeTime;
    if (_activeSnoozed) {
      _showMessage('This reminder is already snoozed.');
      return;
    }
    if (widget.liveRecords) {
      final persist = widget.onPersistSnooze;
      final persistById = widget.onPersistSnoozeForId;
      if (persist == null && (persistById == null || routineId == null)) {
        return;
      }
      setState(() => _saving = true);
      try {
        final error =
            persistById != null && routineId != null
                ? await persistById(routineId)
                : await persist!();
        if (!mounted) return;
        if (error != null) {
          _showMessage(error);
          return;
        }
      } catch (_) {
        if (mounted) {
          _showMessage('Couldn’t snooze this reminder. Please try again.');
        }
        return;
      } finally {
        if (mounted) setState(() => _saving = false);
      }
    }
    if (!widget.liveRecords) setState(() => _isSnoozed = true);
    widget.onSnoozed?.call();
    _publishDoseState();
    _showSavedReceipt(
      _TodayReceipt.snoozed,
      routineId: routineId,
      label: routineLabel,
      schedule: routineTime,
    );
  }

  Future<void> _openMoreOptions() async {
    if (_saving) return;
    final routineId = _activeRoutine?.id;
    widget.onMoreOptions?.call();
    final result = await showModalBottomSheet<_MoreOption>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: _sheetBarrier,
      builder:
          (sheetContext) => _FardaSheet(
            eyebrow: 'YOUR RECORD',
            title: 'More options',
            body:
                'Skipped records what happened; it does not change your plan.',
            children: [
              _SheetButton(
                key: FardaTodayScreen.recordSkippedButtonKey,
                label: 'Record as skipped',
                isSecondary: true,
                onPressed:
                    () => Navigator.of(sheetContext).pop(_MoreOption.skipped),
              ),
              const SizedBox(height: 8),
              _SheetButton(
                label: 'Review my routine',
                isSecondary: true,
                onPressed:
                    () => Navigator.of(
                      sheetContext,
                    ).pop(_MoreOption.reviewRoutine),
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
      final id = _receiptRoutineId ?? _activeRoutine?.id;
      if (_receipt != null) _returnToToday();
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
      builder:
          (sheetContext) => _FardaSheet(
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
    if (_receipt != null) _returnToToday();
    if (_showCheckIn) _returnToToday();
    _showMessage('Your routine is not yet confirmed.');
  }

  void _selectMilestone(TodayReminderMilestone milestone) {
    setState(() => _previewedMilestone = milestone.type);
    widget.onReminderMilestoneSelected?.call(milestone);
  }

  void _handleTodayTap() {
    widget.onTodayTap?.call();
    if (_receipt != null) _returnToToday();
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

  Widget _buildReceipt(BuildContext context) {
    final savedAt = _receiptAt;
    final savedTime =
        savedAt == null
            ? null
            : TimeOfDay.fromDateTime(savedAt).format(context);
    final schedule = _receiptSchedule ?? _activeTime;
    final label = _receiptLabel ?? _activeLabel;
    if (_receipt == _TodayReceipt.snoozed) {
      final nextTime =
          _receiptSnoozedUntil == null
              ? null
              : TimeOfDay.fromDateTime(_receiptSnoozedUntil!).format(context);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _ReceiptIntroduction(
            headline: 'We’ll remind\nyou again.',
            detail: 'Reminder snoozed. Your record is unconfirmed.',
          ),
          const SizedBox(height: 16),
          design.FardaSceneCard(
            scene: design.FardaScene.today,
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const _ReceiptCompanion(size: 140),
                const SizedBox(height: 16),
                Text(
                  '15 minutes',
                  style: _type(
                    size: 34,
                    lineHeight: 37,
                    weight: FontWeight.w600,
                    color: _canvas,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  nextTime == null
                      ? 'Reminder rescheduled'
                      : 'Next reminder · $nextTime',
                  style: _type(
                    size: 18,
                    lineHeight: 24,
                    weight: FontWeight.w600,
                    color: _canvas,
                  ),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Reminder time changed.\nPrescription directions stay the same.',
                    style: _type(size: 14, lineHeight: 20, color: _canvas),
                  ),
                ),
                const SizedBox(height: 16),
                _ReceiptButton(
                  label: 'Back to today',
                  onPressed: _returnToToday,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: _ReceiptLink(
              label: 'Ready now? Log my dose',
              dark: true,
              onPressed: () {
                _returnToToday();
                _openDoseConfirmation();
              },
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ReceiptIntroduction(
          headline: 'You’re all set.',
          detail:
              widget.liveRecords
                  ? 'You confirmed your $label entry.'
                  : 'You confirmed your morning entry.',
        ),
        const SizedBox(height: 16),
        design.FardaSceneCard(
          scene: design.FardaScene.today,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${widget.liveRecords ? 'YOUR ROUTINE' : 'YOUR MORNING'} · $schedule',
                style: _type(
                  size: 10,
                  lineHeight: 14,
                  weight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'More room\nfor your day.',
                          style: _type(
                            size: 26,
                            lineHeight: 30,
                            weight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 9),
                        Text(
                          'Your entry is saved.',
                          style: _type(
                            size: 12,
                            lineHeight: 17,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const _ReceiptCompanion(size: 100),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                savedTime == null
                    ? 'You confirmed'
                    : 'You confirmed · $savedTime',
                style: _type(size: 12, lineHeight: 17, color: Colors.white),
              ),
              const SizedBox(height: 16),
              _ReceiptButton(
                label: 'Review my entry',
                onPressed: () {
                  final entry = _savedEntryKey.currentContext;
                  if (entry == null) return;
                  Scrollable.ensureVisible(
                    entry,
                    duration:
                        MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 240),
                  );
                },
              ),
              const SizedBox(height: 16),
              _ReceiptLink(
                label: 'Correct this entry',
                onPressed: _openCorrection,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          key: _savedEntryKey,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'YOUR ${widget.liveRecords ? 'ROUTINE' : 'MORNING'} ENTRY',
                style: _type(
                  size: 10,
                  lineHeight: 14,
                  weight: FontWeight.w600,
                  color: _secondaryText,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Taken · You confirmed',
                style: _type(size: 18, lineHeight: 24, weight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              Text(
                '${DateFormat.MMMMd().format(_selectedDate)}${savedTime == null ? '' : ' · $savedTime'}\nSource: your check-in',
                style: _type(size: 14, lineHeight: 20, color: _secondaryText),
              ),
              const SizedBox(height: 16),
              _ReceiptLink(
                label: 'Correct this entry',
                onPressed: _openCorrection,
                dark: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: _ReceiptLink(
            label: 'Back to today',
            onPressed: _returnToToday,
            dark: true,
          ),
        ),
      ],
    );
  }

  Widget _buildCheckIn(BuildContext context) {
    final label = _checkInLabel ?? _activeLabel;
    final schedule = _checkInSchedule ?? _activeTime;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'YOUR MORNING ROUTINE',
          style: _type(
            size: 10,
            lineHeight: 14,
            weight: FontWeight.w600,
            color: _secondaryText,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Your record.\nYour choice.',
          style: _type(size: 34, lineHeight: 37, weight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          'Only you can confirm what happened.',
          style: _type(size: 14, lineHeight: 20, color: _secondaryText),
        ),
        const SizedBox(height: 16),
        design.FardaSceneCard(
          scene: design.FardaScene.today,
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF315181),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$label · $schedule',
                    style: _type(size: 12, lineHeight: 17, color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Did you take your dose?',
                style: _type(
                  size: 24,
                  lineHeight: 28,
                  weight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Save only what you can confirm.',
                style: _type(size: 12, lineHeight: 17, color: Colors.white),
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 48,
                child: FilledButton(
                  key: FardaTodayScreen.confirmDoseButtonKey,
                  onPressed: _saving ? null : _confirmDose,
                  style: FilledButton.styleFrom(
                    backgroundColor: _canvas,
                    foregroundColor: _navy,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    'Yes, I took it · save entry',
                    style: _type(
                      size: 14,
                      lineHeight: 19,
                      weight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height:
                    MediaQuery.sizeOf(context).width < 350 &&
                            MediaQuery.textScalerOf(context).scale(14) > 16
                        ? 64
                        : 48,
                child: OutlinedButton(
                  onPressed: _saving ? null : _snooze,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFF6684B1)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    'Remind me in 15 minutes',
                    style: _type(
                      size: 14,
                      lineHeight: 19,
                      weight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _saving ? null : _returnToToday,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(44),
                ),
                child: Text(
                  'Not now',
                  style: _type(
                    size: 14,
                    lineHeight: 19,
                    weight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'A PRIVATE CHECK-IN',
                style: _type(
                  size: 10,
                  lineHeight: 14,
                  weight: FontWeight.w600,
                  color: _secondaryText,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Your answer shapes your record.',
                style: _type(size: 18, lineHeight: 24, weight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                'A reminder is not a dose confirmation. You can correct an entry later.',
                style: _type(size: 14, lineHeight: 20, color: _secondaryText),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final week = List<DateTime>.generate(
      7,
      (index) => DateTime(
        _visibleWeekStart.year,
        _visibleWeekStart.month,
        _visibleWeekStart.day + index,
      ),
    );
    final previewedMilestone = _milestoneFor(_previewedMilestone);

    return Scaffold(
      backgroundColor: _canvas,
      bottomNavigationBar:
          widget.showBottomNavigation
              ? _TodayBottomNavigation(
                onTodayTap: _handleTodayTap,
                onCalendarTap: widget.onOpenCalendar,
                onRefillsTap: widget.onOpenRefills,
                onYouTap: widget.onOpenProfile,
              )
              : null,
      body: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 390),
            child: SingleChildScrollView(
              controller: _scrollController,
              // The shell owns navigation in live mode. Keep enough scroll
              // extent for actions near the end of a short routine list.
              padding: EdgeInsets.fromLTRB(
                22,
                8,
                22,
                widget.showBottomNavigation ? 28 : 112,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _BrandHeader(
                    initials: widget.userInitials,
                    onProfileTap: widget.onOpenProfile,
                  ),
                  if (_receipt != null) ...[
                    const SizedBox(height: 16),
                    _buildReceipt(context),
                  ] else if (_showCheckIn) ...[
                    const SizedBox(height: 16),
                    _buildCheckIn(context),
                  ] else ...[
                    const SizedBox(height: 16),
                    _Greeting(
                      name: widget.greetingName,
                      selectedDate: _selectedDate,
                    ),
                    const SizedBox(height: 16),
                    _WeekStrip(
                      dates: week,
                      selectedDate: _selectedDate,
                      onSelected: _selectDay,
                    ),
                    const SizedBox(height: 16),
                    if (widget.liveRecords && widget.routines.length > 1) ...[
                      Text(
                        'Your routines · ${widget.routines.length}',
                        style: _type(
                          size: 18,
                          lineHeight: 24,
                          weight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      for (final routine in widget.routines) ...[
                        _RoutineSelector(
                          routine: routine,
                          selected: routine.id == _activeRoutine?.id,
                          onTap:
                              _saving
                                  ? null
                                  : () => setState(
                                    () => _selectedRoutineId = routine.id,
                                  ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      const SizedBox(height: 12),
                    ],
                    if (widget.liveRecords &&
                        widget.hasRoutine &&
                        widget.routines.length > 1) ...[
                      Text(
                        _activeLabel,
                        style: _type(
                          size: 15,
                          lineHeight: 21,
                          weight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (widget.hasRoutine)
                      FardaTodayRoutineCard(
                        timeLabel: _activeTime,
                        status: _activeStatus,
                        isSnoozed: _activeSnoozed,
                        neutralCopy: widget.liveRecords,
                        isSaving: _saving,
                        onOpenLog: _openDoseConfirmation,
                        onSnooze: _snooze,
                        onMoreOptions: _openMoreOptions,
                        onCorrectEntry: _openCorrection,
                      )
                    else
                      _NavigationCard(
                        icon: Icons.add_circle_outline,
                        title:
                            widget.hasPrescriptions
                                ? 'No routine on this day'
                                : 'Add medication',
                        detail:
                            widget.hasPrescriptions
                                ? 'Review your saved medication and reminders.'
                                : 'Scan your label or enter it in a few small steps.',
                        onTap:
                            widget.hasPrescriptions
                                ? widget.onReviewRoutineTap
                                : widget.onAddPrescription,
                      ),
                    if (widget.liveRecords && widget.hasRoutine) ...[
                      const SizedBox(height: 16),
                      _LiveReminderRhythm(
                        time: _activeTime,
                        onReviewRoutineTap: widget.onReviewRoutineTap,
                      ),
                    ],
                    if (!widget.liveRecords) ...[
                      const SizedBox(height: 16),
                      _ReminderRhythmCard(
                        selectedType:
                            _previewedMilestone ??
                            TodayReminderMilestoneType.routineDue,
                        footerText:
                            previewedMilestone?.accessibilityHint ??
                            'Calls are optional',
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _TodayReceipt { confirmed, snoozed }

class _ReceiptIntroduction extends StatelessWidget {
  const _ReceiptIntroduction({required this.headline, required this.detail});

  final String headline;
  final String detail;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'A LITTLE BREATHING ROOM',
        style: _type(
          size: 10,
          lineHeight: 14,
          weight: FontWeight.w600,
          color: _secondaryText,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        headline,
        style: _type(size: 34, lineHeight: 37, weight: FontWeight.w600),
      ),
      const SizedBox(height: 8),
      Text(
        detail,
        style: _type(size: 14, lineHeight: 20, color: _secondaryText),
      ),
    ],
  );
}

class _ReceiptCompanion extends StatelessWidget {
  const _ReceiptCompanion({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: const BoxDecoration(color: _canvas, shape: BoxShape.circle),
    child: FardaCompanion(size: size, mood: FardaCompanionMood.quiet),
  );
}

class _ReceiptButton extends StatelessWidget {
  const _ReceiptButton({required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: 48,
    child: FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: _canvas,
        foregroundColor: _navy,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Text(
        label,
        style: _type(size: 14, lineHeight: 19, weight: FontWeight.w600),
      ),
    ),
  );
}

class _ReceiptLink extends StatelessWidget {
  const _ReceiptLink({
    required this.label,
    required this.onPressed,
    this.dark = false,
  });
  final String label;
  final VoidCallback onPressed;
  final bool dark;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: InkWell(
      onTap: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: _type(
              size: 12,
              lineHeight: 17,
              weight: FontWeight.w600,
              color: dark ? _navy : Colors.white,
            ),
          ),
          const SizedBox(width: 6),
          Icon(
            Icons.chevron_right_rounded,
            size: 14,
            color: dark ? _navy : Colors.white,
          ),
        ],
      ),
    ),
  );
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
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 18;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hello, $name.',
                style: _type(size: 14, lineHeight: 20, color: _secondaryText),
              ),
              const SizedBox(height: 4),
              Text(
                'Make room\nfor your day.',
                style: _type(
                  size: largeText ? 28 : 34,
                  lineHeight: largeText ? 32 : 37,
                  weight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        if (!largeText) const SizedBox(width: 16),
        if (!largeText)
          AnimatedSwitcher(
            duration:
                MediaQuery.maybeOf(context)?.disableAnimations ?? false
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
            child: Container(
              key: ValueKey(_dateKey(selectedDate)),
              width: 60,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFF8ECD8),
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
            if (index != dates.length - 1)
              SizedBox(width: MediaQuery.sizeOf(context).width <= 340 ? 2 : 5),
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
            duration:
                MediaQuery.maybeOf(context)?.disableAnimations ?? false
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            constraints: const BoxConstraints(minHeight: 60),
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
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
                  duration:
                      MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 180),
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
            style: _type(size: 10, lineHeight: 14, weight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (
                var index = 0;
                index < _reminderMilestones.length;
                index++
              ) ...[
                Expanded(
                  child: _MilestoneButton(
                    milestone: _reminderMilestones[index],
                    isSelected: _reminderMilestones[index].type == selectedType,
                    onTap: () => onSelected(_reminderMilestones[index]),
                  ),
                ),
                if (index != _reminderMilestones.length - 1)
                  const SizedBox(width: 10),
              ],
            ],
          ),
          const SizedBox(height: 8),
          AnimatedSwitcher(
            duration:
                MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
            child: Text(
              footerText,
              key: ValueKey(footerText),
              style: _type(size: 10, lineHeight: 14, color: _secondaryText),
            ),
          ),
        ],
      ),
    );
  }
}

/// The live view only displays details backed by the selected occurrence.
/// Delivery preferences are managed in the routine settings.
class _LiveReminderRhythm extends StatelessWidget {
  const _LiveReminderRhythm({required this.time, this.onReviewRoutineTap});

  final String time;
  final VoidCallback? onReviewRoutineTap;

  @override
  Widget build(BuildContext context) => Container(
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
          style: _type(size: 10, lineHeight: 14, weight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        Text(
          time,
          style: _type(size: 22, lineHeight: 29, weight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          'Your scheduled routine',
          style: _type(size: 12, lineHeight: 17, color: _secondaryText),
        ),
        if (onReviewRoutineTap != null) ...[
          const SizedBox(height: 8),
          TextButton(
            onPressed: onReviewRoutineTap,
            style: TextButton.styleFrom(
              foregroundColor: _navy,
              padding: EdgeInsets.zero,
              alignment: Alignment.centerLeft,
              minimumSize: const Size.fromHeight(44),
            ),
            child: Text(
              'Review reminder settings',
              style: _type(size: 12, lineHeight: 17, weight: FontWeight.w600),
            ),
          ),
        ],
      ],
    ),
  );
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
            duration:
                MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              children: [
                AnimatedContainer(
                  duration:
                      MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 180),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: isSelected ? _navy : _statusBlue,
                    shape: BoxShape.circle,
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
                  style: _type(size: 10, lineHeight: 14, color: _secondaryText),
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
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: _navy,
              ),
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
                Icon(switch (routine.status) {
                  TodayDoseStatus.confirmed =>
                    Icons.check_circle_outline_rounded,
                  TodayDoseStatus.skipped =>
                    Icons.remove_circle_outline_rounded,
                  TodayDoseStatus.pending => Icons.schedule_rounded,
                }, color: _navy),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        routine.medicationLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _type(
                          size: 14,
                          lineHeight: 20,
                          weight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '${routine.timeLabel} · $status',
                        style: _type(
                          size: 12,
                          lineHeight: 17,
                          color: _secondaryText,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 18,
                  color: _navy,
                ),
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
              style: _type(size: 12, lineHeight: 17, color: _secondaryText),
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
                        iconName: 'nav-today',
                        isSelected: true,
                        onTap: onTodayTap,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _BottomNavItem(
                        label: 'Calendar',
                        iconName: 'nav-calendar',
                        onTap: onCalendarTap,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _BottomNavItem(
                        label: 'Refills',
                        iconName: 'nav-refills',
                        onTap: onRefillsTap,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _BottomNavItem(
                        label: 'You',
                        iconName: 'nav-you',
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
    required this.iconName,
    required this.onTap,
    this.isSelected = false,
  });

  final String label;
  final String iconName;
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
              child: Center(
                child: design.FardaVectorIcon(
                  iconName,
                  size: 22,
                  color: isSelected ? _navy : _secondaryText,
                ),
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
                style: _type(size: 10, lineHeight: 14, weight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: _type(size: 28, lineHeight: 33, weight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              Text(
                body,
                style: _type(size: 14, lineHeight: 20, color: _secondaryText),
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

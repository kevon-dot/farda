import 'package:flutter/material.dart';

import 'you_models.dart';
import 'you_pages.dart';
import 'you_widgets.dart';

export 'you_models.dart' show FardaYouDestination, FardaYouKeys;

/// Consumer-v2 profile, settings, and preview experience from the Farda Figma
/// handoff (profile node 2:18 and its connected screens).
///
/// All state in this feature is intentionally local. It does not place calls,
/// schedule notifications, connect to hardware, send invitations, persist
/// health information, or write a dose record. The app shell can replace these
/// previews with real routes and approved services in a later integration.
class FardaYouScreen extends StatefulWidget {
  const FardaYouScreen({
    super.key,
    this.initialDestination = FardaYouDestination.overview,
    this.profileLabel = 'YO',
    this.showBrandHeader = true,
    this.bottomNavigationBar,
    this.onNativePreviewChanged,
  });

  final FardaYouDestination initialDestination;
  final String profileLabel;
  final bool showBrandHeader;

  /// Allows the app shell to supply its own bottom navigation without this
  /// feature depending on shared routes. Native-surface previews hide it.
  final Widget? bottomNavigationBar;

  /// Lets a parent shell hide its navigation while an OS-surface preview is
  /// being demonstrated.
  final ValueChanged<bool>? onNativePreviewChanged;

  @override
  State<FardaYouScreen> createState() => _FardaYouScreenState();
}

class _FardaYouScreenState extends State<FardaYouScreen> {
  late FardaYouDestination _destination;
  final List<FardaYouDestination> _history = [];

  bool _showCompanion = true;
  bool _privatePreviews = true;
  bool _callReminders = false;
  bool _liveActivities = true;
  int _callDelayMinutes = 10;

  String _medicationName = 'Daily medication';
  TimeOfDay _reminderTime = const TimeOfDay(hour: 9, minute: 0);
  bool _labelReviewed = false;

  int _vialSetupStep = 0;

  bool _circleConnected = false;
  bool _shareRoutineSummaries = false;
  bool _shareRefillReminders = false;
  bool _shareMissedConfirmation = false;

  FardaLivePreviewState _liveState = FardaLivePreviewState.due;
  bool _expandedIsland = false;
  bool _sampleEntryConfirmed = false;

  FardaCallPreviewStage _callStage = FardaCallPreviewStage.ringing;
  bool _callEntryConfirmed = false;

  @override
  void initState() {
    super.initState();
    _destination = widget.initialDestination;
    if (_destination == FardaYouDestination.liveActivity && !_liveActivities) {
      _liveState = FardaLivePreviewState.off;
    }
    _notifyNativePreviewAfterFrame();
  }

  @override
  void didUpdateWidget(covariant FardaYouScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialDestination != oldWidget.initialDestination) {
      setState(() {
        _history.clear();
        _destination = widget.initialDestination;
      });
      _notifyNativePreviewAfterFrame();
    }
  }

  String get _formattedReminderTime {
    final hour = _reminderTime.hourOfPeriod == 0
        ? 12
        : _reminderTime.hourOfPeriod;
    final minute = _reminderTime.minute.toString().padLeft(2, '0');
    final period = _reminderTime.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  bool _isNative(FardaYouDestination destination) =>
      destination == FardaYouDestination.liveActivity ||
      destination == FardaYouDestination.callPreview;

  bool get _isNativePreview => _isNative(_destination);

  void _notifyNativePreviewAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onNativePreviewChanged?.call(_isNativePreview);
    });
  }

  void _open(FardaYouDestination destination) {
    if (destination == _destination) return;
    setState(() {
      _history.add(_destination);
      _destination = destination;
      if (destination == FardaYouDestination.liveActivity) {
        if (!_liveActivities) {
          _liveState = FardaLivePreviewState.off;
        } else if (_liveState == FardaLivePreviewState.off) {
          _liveState = FardaLivePreviewState.due;
        }
      }
      if (destination == FardaYouDestination.callPreview) {
        _callStage = FardaCallPreviewStage.ringing;
        _callEntryConfirmed = false;
      }
    });
    widget.onNativePreviewChanged?.call(_isNative(destination));
  }

  void _back() {
    late FardaYouDestination destination;
    setState(() {
      if (_history.isNotEmpty) {
        destination = _history.removeLast();
      } else {
        destination = FardaYouDestination.overview;
      }
      _destination = destination;
    });
    widget.onNativePreviewChanged?.call(_isNative(destination));
  }

  void _returnTo(FardaYouDestination destination) {
    setState(() {
      _history.clear();
      _destination = destination;
    });
    widget.onNativePreviewChanged?.call(_isNative(destination));
  }

  void _showMessage(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: FardaYouPalette.navy,
        ),
      );
  }

  Future<void> _showPrivacyDetails() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: FardaYouPalette.ivory,
        title: const Text('Privacy in this preview'),
        content: Text(
          'Medication names stay hidden on the sample Lock Screen by default. '
          'The controls here live only in memory: closing this screen resets '
          'them, and nothing is uploaded or shared.',
          style: fardaYouText(
            size: 14,
            height: 20,
            color: FardaYouPalette.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<void> _editRoutine() async {
    final nameController = TextEditingController(text: _medicationName);
    var selectedTime = _reminderTime;
    final result = await showDialog<_RoutineEditResult>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: FardaYouPalette.ivory,
          title: const Text('Make the reminder yours'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  maxLength: 80,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Display name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Future reminder time',
                  style: fardaYouText(
                    size: 12,
                    weight: FontWeight.w600,
                    color: FardaYouPalette.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showTimePicker(
                        context: dialogContext,
                        initialTime: selectedTime,
                      );
                      if (picked != null) {
                        setDialogState(() => selectedTime = picked);
                      }
                    },
                    icon: const Icon(Icons.schedule_rounded),
                    label: Text(selectedTime.format(dialogContext)),
                  ),
                ),
                const SizedBox(height: 12),
                const FardaYouNotice(
                  text:
                      'This changes future reminder timing only. It does not change prescription directions or past entries.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isEmpty) return;
                Navigator.of(dialogContext).pop(
                  _RoutineEditResult(name: name, time: selectedTime),
                );
              },
              child: const Text('Save future reminder'),
            ),
          ],
        ),
      ),
    );
    nameController.dispose();

    if (!mounted || result == null) return;
    setState(() {
      _medicationName = result.name;
      _reminderTime = result.time;
    });
    _showMessage('Future reminder updated locally. Past entries are unchanged.');
  }

  Future<void> _reviewLabel() async {
    var checked = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: FardaYouPalette.ivory,
          title: const Text('Review the original label'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const FardaYouNotice(
                  text:
                      'This preview does not scan or interpret a prescription. Unreadable details must remain blank.',
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  value: checked,
                  onChanged: (value) =>
                      setDialogState(() => checked = value ?? false),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(
                    'I checked these details against the original label or with my pharmacist.',
                    style: fardaYouText(size: 13, height: 19),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: checked
                  ? () => Navigator.of(dialogContext).pop(true)
                  : null,
              child: const Text('Save reviewed status'),
            ),
          ],
        ),
      ),
    );

    if (!mounted || confirmed != true) return;
    setState(() => _labelReviewed = true);
    _showMessage('Reviewed status saved locally. No directions were generated.');
  }

  Future<void> _changeCallReminders(bool enabled) async {
    if (!enabled) {
      final disable = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: FardaYouPalette.ivory,
          title: const Text('Turn off call reminders?'),
          content: Text(
            'This only changes the local preview. There are no scheduled calls to cancel.',
            style: fardaYouText(
              size: 14,
              height: 20,
              color: FardaYouPalette.textSecondary,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Keep on'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Turn off preview'),
            ),
          ],
        ),
      );
      if (!mounted || disable != true) return;
      setState(() => _callReminders = false);
      _showMessage('Call reminders are off in this preview.');
      return;
    }

    var verified = false;
    var consent = false;
    final allow = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: FardaYouPalette.ivory,
          title: const Text('Calls, only with your say-so'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const FardaYouNotice(
                  text:
                      'Demo number: ••• ••• 0142. No OTP is sent and no phone number is contacted.',
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  value: verified,
                  onChanged: (value) =>
                      setDialogState(() => verified = value ?? false),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(
                    'Simulate successful verification of my own number.',
                    style: fardaYouText(size: 13, height: 19),
                  ),
                ),
                CheckboxListTile(
                  value: consent,
                  onChanged: (value) =>
                      setDialogState(() => consent = value ?? false),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(
                    'I choose automated routine-reminder calls in this preview. I can turn them off at any time.',
                    style: fardaYouText(size: 13, height: 19),
                  ),
                ),
                Text(
                  'A phone OTP is not permission to call. Real consent, quiet hours, retries, and opt-out handling still require implementation and review.',
                  style: fardaYouText(
                    size: 11,
                    height: 16,
                    color: FardaYouPalette.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: verified && consent
                  ? () => Navigator.of(dialogContext).pop(true)
                  : null,
              child: const Text('Enable in this preview'),
            ),
          ],
        ),
      ),
    );

    if (!mounted || allow != true) return;
    setState(() => _callReminders = true);
    _showMessage('Call reminders enabled locally. No call was scheduled.');
  }

  Future<void> _editCallDelay() async {
    final selected = await showDialog<int>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        backgroundColor: FardaYouPalette.ivory,
        title: const Text('Give yourself some room'),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              'Call only if the routine is still unconfirmed. This changes reminder timing, not prescription directions.',
              style: fardaYouText(
                size: 13,
                height: 19,
                color: FardaYouPalette.textSecondary,
              ),
            ),
          ),
          for (final minutes in const [10, 20, 30])
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(minutes),
              child: Semantics(
                selected: minutes == _callDelayMinutes,
                child: Row(
                  children: [
                    Icon(
                      minutes == _callDelayMinutes
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_off_rounded,
                      color: FardaYouPalette.navy,
                    ),
                    const SizedBox(width: 12),
                    Text('After $minutes minutes'),
                  ],
                ),
              ),
            ),
        ],
      ),
    );

    if (!mounted || selected == null) return;
    setState(() => _callDelayMinutes = selected);
    _showMessage('Reminder delay updated locally.');
  }

  Future<void> _previewInvitation() async {
    var accepted = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: FardaYouPalette.ivory,
          title: const Text('Share just enough'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Preview access for one sample supporter. They receive only the permissions currently switched on—never medication names, remote vial controls, or emergency access.',
                  style: fardaYouText(
                    size: 14,
                    height: 20,
                    color: FardaYouPalette.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  value: accepted,
                  onChanged: (value) =>
                      setDialogState(() => accepted = value ?? false),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(
                    'Simulate that a verified recipient reviewed and accepted this invitation.',
                    style: fardaYouText(size: 13, height: 19),
                  ),
                ),
                const FardaYouNotice(
                  text: 'No message or invitation will be sent.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: accepted
                  ? () => Navigator.of(dialogContext).pop(true)
                  : null,
              child: const Text('Add sample supporter'),
            ),
          ],
        ),
      ),
    );

    if (!mounted || confirmed != true) return;
    setState(() => _circleConnected = true);
    _showMessage('Sample access added locally. No one was contacted.');
  }

  Future<void> _revokeCircleAccess() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: FardaYouPalette.ivory,
        title: const Text('Remove sample access?'),
        content: Text(
          'The sample supporter and all three local sharing permissions will be cleared.',
          style: fardaYouText(
            size: 14,
            height: 20,
            color: FardaYouPalette.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep access'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: FardaYouPalette.danger,
            ),
            child: const Text('Remove access'),
          ),
        ],
      ),
    );

    if (!mounted || confirmed != true) return;
    setState(() {
      _circleConnected = false;
      _shareRoutineSummaries = false;
      _shareRefillReminders = false;
      _shareMissedConfirmation = false;
    });
    _showMessage('Sample access and permissions removed.');
  }

  Future<void> _reviewLiveEntry() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: FardaYouPalette.ivory,
        title: const Text('Log your morning dose?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Only confirm if you already took it. This saves your own report in this preview; it is not proof of ingestion.',
              style: fardaYouText(
                size: 14,
                height: 20,
                color: FardaYouPalette.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            FardaYouCard(
              child: Row(
                children: [
                  const FardaYouIconTile(icon: Icons.medication_outlined),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '$_medicationName\n$_formattedReminderTime · Today',
                      style: fardaYouText(size: 13, height: 19),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Go back'),
          ),
          FilledButton(
            key: FardaYouKeys.confirmSampleEntry,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Yes, save my sample entry'),
          ),
        ],
      ),
    );

    if (!mounted || confirmed != true) return;
    setState(() {
      _sampleEntryConfirmed = true;
      _liveState = FardaLivePreviewState.confirmed;
    });
    _showMessage('Sample entry saved locally. No backend record was created.');
  }

  void _confirmCallEntry() {
    setState(() {
      _callEntryConfirmed = true;
      _sampleEntryConfirmed = true;
      _liveState = FardaLivePreviewState.confirmed;
      _callStage = FardaCallPreviewStage.ended;
    });
    _showMessage('Sample entry confirmed locally. No call or API was used.');
  }

  Future<void> _stopCallsFromPreview() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: FardaYouPalette.ivory,
        title: const Text('Stop call reminders?'),
        content: Text(
          'This turns off the local preference and ends the current simulation. No real subscription or scheduled call exists.',
          style: fardaYouText(
            size: 14,
            height: 20,
            color: FardaYouPalette.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep on'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Stop preview calls'),
          ),
        ],
      ),
    );

    if (!mounted || confirmed != true) return;
    setState(() {
      _callReminders = false;
      _callStage = FardaCallPreviewStage.ended;
    });
    _showMessage('Call reminders are off in this preview.');
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final page = switch (_destination) {
      FardaYouDestination.overview => FardaYouOverviewPage(
          key: const ValueKey(FardaYouDestination.overview),
          profileLabel: widget.profileLabel,
          showBrandHeader: widget.showBrandHeader,
          showCompanion: _showCompanion,
          privatePreviews: _privatePreviews,
          onDestinationSelected: _open,
          onCompanionChanged: (value) =>
              setState(() => _showCompanion = value),
          onPrivatePreviewsChanged: (value) =>
              setState(() => _privatePreviews = value),
          onPrivacyPressed: _showPrivacyDetails,
        ),
      FardaYouDestination.routine => FardaRoutinePage(
          key: const ValueKey(FardaYouDestination.routine),
          profileLabel: widget.profileLabel,
          showBrandHeader: widget.showBrandHeader,
          showCompanion: _showCompanion,
          medicationName: _medicationName,
          reminderTime: _formattedReminderTime,
          labelReviewed: _labelReviewed,
          onBack: _back,
          onEditRoutine: _editRoutine,
          onReviewLabel: _reviewLabel,
          onOpenReminders: () => _open(FardaYouDestination.reminders),
        ),
      FardaYouDestination.reminders => FardaReminderPreferencesPage(
          key: const ValueKey(FardaYouDestination.reminders),
          profileLabel: widget.profileLabel,
          showBrandHeader: widget.showBrandHeader,
          showCompanion: _showCompanion,
          callReminders: _callReminders,
          liveActivities: _liveActivities,
          privatePreviews: _privatePreviews,
          callDelayMinutes: _callDelayMinutes,
          onBack: _back,
          onCallRemindersChanged: _changeCallReminders,
          onLiveActivitiesChanged: (value) {
            setState(() {
              _liveActivities = value;
              _liveState = value
                  ? FardaLivePreviewState.due
                  : FardaLivePreviewState.off;
            });
            _showMessage(
              value
                  ? 'Live Activities enabled in this preview only.'
                  : 'Live Activities turned off in this preview.',
            );
          },
          onPrivatePreviewsChanged: (value) =>
              setState(() => _privatePreviews = value),
          onEditDelay: _editCallDelay,
          onOpenLivePreview: () =>
              _open(FardaYouDestination.liveActivity),
          onOpenCallPreview: () => _open(FardaYouDestination.callPreview),
        ),
      FardaYouDestination.vial => FardaVialPage(
          key: const ValueKey(FardaYouDestination.vial),
          profileLabel: widget.profileLabel,
          showBrandHeader: widget.showBrandHeader,
          setupStep: _vialSetupStep,
          onBack: _back,
          onAdvanceSetup: () {
            setState(() {
              if (_vialSetupStep < 4) _vialSetupStep += 1;
            });
            _showMessage(
              _vialSetupStep >= 4
                  ? 'Sample setup complete. No vial was contacted.'
                  : 'Advanced one local setup step. No Bluetooth was used.',
            );
          },
          onOpenRoutine: () => _open(FardaYouDestination.routine),
        ),
      FardaYouDestination.circle => FardaCirclePage(
          key: const ValueKey(FardaYouDestination.circle),
          profileLabel: widget.profileLabel,
          showBrandHeader: widget.showBrandHeader,
          showCompanion: _showCompanion,
          connected: _circleConnected,
          routineSummaries: _shareRoutineSummaries,
          refillReminders: _shareRefillReminders,
          missedConfirmation: _shareMissedConfirmation,
          onBack: _back,
          onRoutineSummariesChanged: (value) =>
              setState(() => _shareRoutineSummaries = value),
          onRefillRemindersChanged: (value) =>
              setState(() => _shareRefillReminders = value),
          onMissedConfirmationChanged: (value) =>
              setState(() => _shareMissedConfirmation = value),
          onInvite: _previewInvitation,
          onRevoke: _revokeCircleAccess,
        ),
      FardaYouDestination.liveActivity => FardaLiveActivityPreviewPage(
          key: const ValueKey(FardaYouDestination.liveActivity),
          state: _sampleEntryConfirmed
              ? FardaLivePreviewState.confirmed
              : _liveState,
          privatePreviews: _privatePreviews,
          expandedIsland: _expandedIsland,
          callDelayMinutes: _callDelayMinutes,
          medicationName: _medicationName,
          onBack: _back,
          onStateChanged: (state) {
            setState(() {
              _sampleEntryConfirmed = false;
              _liveState = state;
              _liveActivities = state != FardaLivePreviewState.off;
            });
          },
          onIslandToggled: () =>
              setState(() => _expandedIsland = !_expandedIsland),
          onOpenRoutine: () => _returnTo(FardaYouDestination.routine),
          onOpenReminderSettings: () =>
              _returnTo(FardaYouDestination.reminders),
          onReviewEntry: _reviewLiveEntry,
        ),
      FardaYouDestination.callPreview => FardaCallPreviewPage(
          key: const ValueKey(FardaYouDestination.callPreview),
          stage: _callStage,
          callDelayMinutes: _callDelayMinutes,
          callRemindersEnabled: _callReminders,
          entryConfirmed: _callEntryConfirmed,
          onBack: _back,
          onAnswer: () =>
              setState(() => _callStage = FardaCallPreviewStage.answered),
          onDecline: () {
            setState(() => _callStage = FardaCallPreviewStage.ended);
            _showMessage('Call preview declined. No entry was changed.');
          },
          onPrivateCheckIn: () =>
              setState(() => _callStage = FardaCallPreviewStage.checkIn),
          onReviewEntry: () =>
              setState(() => _callStage = FardaCallPreviewStage.confirm),
          onConfirmEntry: _confirmCallEntry,
          onSnooze: () {
            setState(() => _callStage = FardaCallPreviewStage.ended);
            _showMessage('Snoozed in the preview. No entry was added.');
          },
          onEnd: () {
            setState(() => _callStage = FardaCallPreviewStage.ended);
            _showMessage('Call preview ended. No entry was added.');
          },
          onStopCalls: _stopCallsFromPreview,
        ),
    };

    return PopScope<Object?>(
      canPop: _destination == FardaYouDestination.overview,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: _isNativePreview
            ? FardaYouPalette.navyDeep
            : FardaYouPalette.ivory,
        bottomNavigationBar:
            _isNativePreview ? null : widget.bottomNavigationBar,
        body: SafeArea(
          child: AnimatedSwitcher(
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: page,
          ),
        ),
      ),
    );
  }
}

class _RoutineEditResult {
  const _RoutineEditResult({required this.name, required this.time});

  final String name;
  final TimeOfDay time;
}

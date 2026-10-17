import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:farda/application/authentication/storage/auth_storage.dart';
import 'package:farda/services/consumer_live_activity_coordinator.dart';
import 'package:farda/services/live_activity_registration.dart';
import 'package:farda/services/live_activity_service.dart';

import 'consumer_controller.dart';
import 'consumer_forms.dart';
import 'prescription_onboarding.dart';
import 'consumer_widgets.dart';
import 'data/consumer_models.dart';
import 'data/consumer_repository.dart';

/// Native consumer home. Production and demo repositories are selected at the
/// route boundary, never as a fallback after network or authentication failure.
class ConsumerApp extends StatefulWidget {
  const ConsumerApp({
    super.key,
    required this.repository,
    this.initialTab = 0,
    this.onSignIn,
    this.onSignOut,
    this.onOpenHardware,
    this.onControllerReady,
    this.routineLinks,
    this.onResetDemo,
  });
  final ConsumerRepository repository;
  final int initialTab;
  final VoidCallback? onSignIn;
  final Future<void> Function()? onSignOut;
  final VoidCallback? onOpenHardware;
  final ValueChanged<ConsumerController>? onControllerReady;
  final Stream<String>? routineLinks;
  final VoidCallback? onResetDemo;
  @override
  State<ConsumerApp> createState() => ConsumerAppState();
}

class ConsumerAppState extends State<ConsumerApp> with WidgetsBindingObserver {
  late final ConsumerController controller;
  String? _page;
  String _preview = 'before';
  bool _agenda = false;
  StreamSubscription<String>? _links;
  ConsumerLiveActivityCoordinator? _liveActivities;
  LiveActivityTokenRegistrar? _liveActivityRegistrar;
  DateTime? _liveSnapshot;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    controller = ConsumerController(widget.repository)..addListener(_changed);
    controller.tab = widget.initialTab.clamp(0, 3).toInt();
    widget.onControllerReady?.call(controller);
    _links = widget.routineLinks?.listen(openRoutine);
    final registration = widget.repository;
    if (!widget.repository.isDemo &&
        registration is LiveActivityRegistrationRepository) {
      _liveActivityRegistrar = LiveActivityTokenRegistrar(
        repository: registration as LiveActivityRegistrationRepository,
        sessions: AuthStorage.sessionStore,
        onRegistered: () {
          if (mounted && !controller.loading) return controller.load();
        },
      );
      _liveActivities = ConsumerLiveActivityCoordinator(
        service: LiveActivityService(),
        onOpenRoutine: (id, _) => openRoutine(id),
        onEvent: (event) {
          if (event.type == 'pushToken' || event.type == 'pushToStartToken') {
            unawaited(_liveActivityRegistrar!.handle(event).catchError((_) {}));
          }
        },
      )..attach();
      AuthStorage.sessionRevision.addListener(_sessionChanged);
    }
    controller.load();
  }

  void _changed() {
    final snapshot = controller.snapshot;
    if (snapshot != null && snapshot.fetchedAt != _liveSnapshot) {
      _liveSnapshot = snapshot.fetchedAt;
      final enabled = snapshot.preferences.liveActivitiesEnabled;
      final remote = snapshot.capabilities.liveActivityDeliveryEnabled;
      unawaited(
        _liveActivities?.reconcile(
              occurrences: snapshot.occurrences
                  .where(
                    (entry) => entry.status == OccurrenceStatus.unconfirmed,
                  )
                  .map(
                    (entry) => LiveRoutineActivity(
                      occurrenceId: entry.id,
                      dueAt: entry.scheduledFor,
                      windowEndsAt: entry.scheduledFor.add(
                        const Duration(hours: 1),
                      ),
                      updatedAt: entry.updatedAt ?? entry.scheduledFor,
                      revision: entry.revision,
                      phase: LiveRoutinePhase.headsUp,
                      snoozedUntil: entry.snoozedUntil,
                      requestPushToken: remote,
                    ),
                  ),
              enabled: enabled,
            ) ??
            Future.value(),
      );
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AuthStorage.sessionRevision.removeListener(_sessionChanged);
    _links?.cancel();
    unawaited(_liveActivities?.dispose() ?? Future.value());
    controller.removeListener(_changed);
    controller.dispose();
    super.dispose();
  }

  void _sessionChanged() {
    // Session expiry and account replacement both invalidate the owner of any
    // visible ActivityKit surface immediately. The newly authenticated account
    // will reconcile and register its own tokens from a fresh snapshot.
    unawaited(_liveActivities?.signOut() ?? Future.value());
  }

  Future<void> _signOut() async {
    await _liveActivities?.signOut();
    try {
      await _liveActivityRegistrar?.revoke();
    } catch (_) {
      // The authenticated server sign-out also revokes every account token.
    }
    await widget.onSignOut?.call();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !controller.loading) {
      controller.load();
    }
  }

  ConsumerSnapshot? get data => controller.snapshot;
  bool get demo => widget.repository.isDemo;
  void _open(String page) => setState(() => _page = page);
  String _time(DateTime time) => DateFormat.jm().format(time.toLocal());
  String _name(ConsumerOccurrence o) =>
      data?.prescription(o.prescriptionId)?.name ?? 'Your medication';

  /// Native notification/deep-link actions only open a review. No implicit log.
  Future<void> openRoutine(String occurrenceId) async {
    await controller.load();
    if (!mounted) return;
    ConsumerOccurrence? target;
    for (final item in data?.occurrences ?? <ConsumerOccurrence>[]) {
      if (item.id == occurrenceId) {
        target = item;
        break;
      }
    }
    if (target == null) {
      _message(
        'This reminder is not in your current record. Refresh the calendar to review it.',
      );
      return;
    }
    _entry(target);
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  Future<void> _sheet(Widget child) async {
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: ConsumerPalette.cream,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .94,
        maxWidth: 600,
      ),
      builder: (_) => Theme(data: ConsumerPalette.theme, child: child),
    );
  }

  void _addPrescription() => Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => PrescriptionOnboarding(controller: controller),
    ),
  );
  void _entry(ConsumerOccurrence occurrence, {bool noteOnly = false}) => _sheet(
    ConsumerEntryForm(
      controller: controller,
      occurrence: occurrence,
      medicationName: _name(occurrence),
      noteOnly: noteOnly,
    ),
  );
  Future<void> _snooze(ConsumerOccurrence occurrence) async {
    final error = await controller.mutate(
      () => widget.repository.snoozeOccurrence(
        occurrence.id,
        const Duration(minutes: 15),
      ),
    );
    if (!mounted) return;
    _message(
      error ??
          (demo
              ? 'Sample reminder snoozed for 15 minutes.'
              : 'Reminder snoozed for 15 minutes.'),
    );
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: ConsumerPalette.theme,
    child: PopScope(
      canPop: _page == null,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _page != null) setState(() => _page = null);
      },
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Column(
                children: [
                  if (demo)
                    Material(
                      color: ConsumerPalette.warm,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.science_outlined,
                              size: 16,
                              color: ConsumerPalette.amber,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'DEMO · Sample data · No calls or pharmacy requests',
                                style: consumerText(
                                  10,
                                  color: ConsumerPalette.amber,
                                  weight: FontWeight.w500,
                                ),
                              ),
                            ),
                            if (widget.onResetDemo != null)
                              IconButton(
                                tooltip: 'Reset demo',
                                visualDensity: VisualDensity.compact,
                                onPressed: widget.onResetDemo,
                                icon: const Icon(
                                  Icons.restart_alt_rounded,
                                  size: 18,
                                  color: ConsumerPalette.amber,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: controller.load,
                      color: ConsumerPalette.navy,
                      child: ListView(
                        key: ValueKey('${_page ?? controller.tab}'),
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(22, 10, 22, 30),
                        children: [
                          _topBar(),
                          if (controller.error != null)
                            ConsumerNotice(
                              controller.error!,
                              attention: true,
                              action:
                                  controller.sessionExpired
                                      ? widget.onSignIn
                                      : controller.load,
                              actionLabel:
                                  controller.sessionExpired
                                      ? 'Sign in'
                                      : 'Refresh',
                            ),
                          if (controller.loading)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 6),
                              child: LinearProgressIndicator(
                                minHeight: 2,
                                color: ConsumerPalette.blue,
                                backgroundColor: ConsumerPalette.pale,
                              ),
                            ),
                          if (data != null && controller.error != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Text(
                                'Showing the last loaded record · ${_time(data!.fetchedAt)}',
                                style: consumerText(
                                  11,
                                  color: ConsumerPalette.muted,
                                ),
                              ),
                            ),
                          ..._content(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        bottomNavigationBar:
            _page != null
                ? null
                : NavigationBar(
                  selectedIndex: controller.tab,
                  onDestinationSelected: controller.selectTab,
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.home_outlined),
                      selectedIcon: Icon(Icons.home_rounded),
                      label: 'Today',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.calendar_month_outlined),
                      selectedIcon: Icon(Icons.calendar_month_rounded),
                      label: 'Calendar',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.inventory_2_outlined),
                      selectedIcon: Icon(Icons.inventory_2_rounded),
                      label: 'Refills',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.person_outline_rounded),
                      selectedIcon: Icon(Icons.person_rounded),
                      label: 'You',
                    ),
                  ],
                ),
      ),
    ),
  );

  Widget _topBar() => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      children: [
        if (_page != null)
          IconButton(
            tooltip: 'Back to your space',
            onPressed: () => setState(() => _page = null),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
        Text(
          'farda',
          style: consumerText(
            32,
            weight: FontWeight.w600,
          ).copyWith(letterSpacing: -1.8),
        ),
        const Spacer(),
        IconButton(
          tooltip: 'Your space',
          onPressed: () {
            setState(() => _page = null);
            controller.selectTab(3);
          },
          icon: Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: ConsumerPalette.pale,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.person_outline_rounded, size: 20),
          ),
        ),
      ],
    ),
  );

  List<Widget> _content() {
    if (_page != null) {
      return switch (_page) {
        'routines' => _routines(),
        'reminders' => _reminders(),
        'vial' => _vial(),
        'circle' => _circle(),
        'live' => _livePreview(),
        'privacy' => _privacy(),
        _ => _today(),
      };
    }
    return switch (controller.tab) {
      1 => _calendar(),
      2 => _refills(),
      3 => _you(),
      _ => _today(),
    };
  }

  List<Widget> _today() {
    final next = controller.nextOccurrence;
    final today = controller.today;
    final hasMeds = data?.prescriptions.isNotEmpty ?? false;
    final period =
        controller.clock().hour < 12
            ? 'morning'
            : controller.clock().hour < 17
            ? 'afternoon'
            : 'evening';
    return [
      ConsumerHeading(
        'Make room\nfor your day.',
        eyebrow: 'GOOD ${period.toUpperCase()}.',
      ),
      _weekStrip(),
      const SizedBox(height: 20),
      if (data == null && controller.loading)
        _loadingCard()
      else if (data == null)
        _empty(
          'Your routine belongs here.',
          'Sign in or refresh to see your own reminders.',
          Icons.cloud_outlined,
          action: widget.onSignIn,
          actionLabel: 'Sign in',
        )
      else if (!hasMeds)
        _welcomeCard()
      else if (next != null)
        _routineHero(next)
      else
        _empty(
          'A little breathing room.',
          today.isEmpty
              ? 'No reminders are scheduled for today. Your routines and previous records are still here.'
              : 'Today’s entries are recorded. You can review or correct them at any time.',
          Icons.check_circle_outline_rounded,
          action: () => controller.selectTab(1),
          actionLabel: 'View my calendar',
        ),
      if (hasMeds) _cadence(next?.scheduledFor),
      if (today.isNotEmpty) ...[
        _section(
          'The rest of your day',
          action: () => controller.selectTab(1),
          label: 'View all',
        ),
        ...today.where((o) => o.id != next?.id).map(_occurrenceCard),
        if (today.length == 1 && next != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: Text(
              'Nothing else scheduled today.',
              style: consumerText(13, color: ConsumerPalette.muted),
            ),
          ),
      ],
      if (hasMeds)
        ConsumerCard(
          color: ConsumerPalette.pale,
          child: ConsumerLink(
            'Stay ahead of your next refill',
            'Check your supply and plan the next step',
            Icons.inventory_2_outlined,
            onTap: () => controller.selectTab(2),
          ),
        ),
      if (data?.warnings.isNotEmpty ?? false)
        ...data!.warnings.map(
          (warning) => ConsumerNotice(warning, attention: true),
        ),
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          children: [
            const Icon(
              Icons.bluetooth_disabled,
              size: 16,
              color: ConsumerPalette.muted,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Your routine works with or without a vial.',
                style: consumerText(11, color: ConsumerPalette.muted),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  Widget _weekStrip() {
    final now = ConsumerController.day(controller.clock());
    final monday = now.subtract(Duration(days: now.weekday - 1));
    return Row(
      children: List.generate(7, (i) {
        final date = monday.add(Duration(days: i));
        final selected = date == now;
        return Expanded(
          child: Semantics(
            selected: selected,
            label: DateFormat.yMMMMEEEEd().format(date),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                controller.selectDay(date);
                controller.selectTab(1);
              },
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color:
                      selected
                          ? ConsumerPalette.navy
                          : ConsumerPalette.pale.withValues(alpha: .55),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    Text(
                      DateFormat.E().format(date).substring(0, 1),
                      style: consumerText(
                        10,
                        color:
                            selected ? Colors.white70 : ConsumerPalette.muted,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      '${date.day}',
                      style: consumerText(
                        16,
                        weight: FontWeight.w600,
                        color: selected ? Colors.white : ConsumerPalette.navy,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _routineHero(ConsumerOccurrence occurrence) {
    final snoozed =
        occurrence.snoozedUntil != null &&
        occurrence.snoozedUntil!.isAfter(controller.clock());
    final before = occurrence.scheduledFor.isAfter(controller.clock());
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [ConsumerPalette.navy, ConsumerPalette.deep],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x24142C55),
            blurRadius: 22,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'YOUR ROUTINE · ${_time(occurrence.scheduledFor)}',
            style: consumerText(
              10,
              color: const Color(0xFFCBD7EB),
              weight: FontWeight.w600,
            ).copyWith(letterSpacing: 1.2),
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder:
                (context, constraints) => Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            snoozed
                                ? 'A little\nbreathing room.'
                                : 'A moment\nfor your routine.',
                            style: consumerText(
                              28,
                              color: Colors.white,
                              weight: FontWeight.w600,
                              height: 1.1,
                            ).copyWith(letterSpacing: -.7),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _name(occurrence),
                            style: consumerText(
                              13,
                              color: const Color(0xFFD7E2F3),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (controller.showCompanion &&
                        MediaQuery.textScalerOf(context).scale(14) < 23)
                      const ConsumerCompanion(size: 98),
                  ],
                ),
          ),
          const SizedBox(height: 22),
          ConsumerPill(
            snoozed
                ? 'Snoozed until ${_time(occurrence.snoozedUntil!)}'
                : before
                ? 'Coming up · ${_time(occurrence.scheduledFor)}'
                : 'Awaiting your confirmation',
            light: true,
            icon: snoozed ? Icons.snooze_rounded : Icons.schedule_rounded,
          ),
          const SizedBox(height: 18),
          ConsumerButton(
            'Log my dose',
            light: true,
            onPressed: controller.saving ? null : () => _entry(occurrence),
          ),
          const SizedBox(height: 8),
          ConsumerButton(
            'Remind in 15 min',
            secondary: true,
            onPressed: controller.saving ? null : () => _snooze(occurrence),
          ),
          TextButton(
            onPressed: () => _entry(occurrence, noteOnly: true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFD7E2F3),
            ),
            child: const Text('Add a note without logging'),
          ),
        ],
      ),
    );
  }

  Widget _welcomeCard() => ConsumerCard(
    color: ConsumerPalette.pale,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (controller.showCompanion)
          const Align(
            alignment: Alignment.centerRight,
            child: ConsumerCompanion(size: 110),
          ),
        Text(
          'A calmer routine\nstarts here.',
          style: consumerText(28, weight: FontWeight.w600, height: 1.12),
        ),
        const SizedBox(height: 12),
        Text(
          'Add your prescription details, choose a reminder, and make a little space in your day.',
          style: consumerText(14, color: ConsumerPalette.muted),
        ),
        const SizedBox(height: 22),
        ConsumerButton(
          'Add my first routine',
          icon: Icons.add_rounded,
          onPressed: _addPrescription,
        ),
      ],
    ),
  );

  Widget _cadence(DateTime? time) {
    final now = controller.clock();
    final due = time?.toLocal() ?? DateTime(now.year, now.month, now.day, 9);
    final calls = data?.preferences.callsEnabled ?? false;
    return ConsumerCard(
      color: ConsumerPalette.pale,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'YOUR REMINDER RHYTHM',
            style: consumerText(
              9,
              color: ConsumerPalette.blue,
              weight: FontWeight.w600,
            ).copyWith(letterSpacing: 1.3),
          ),
          const SizedBox(height: 8),
          Text(
            'A heads-up. A moment. A real ring.',
            style: consumerText(16, weight: FontWeight.w600),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 18,
            runSpacing: 16,
            children: [
              _cadenceStep(
                _time(due.subtract(const Duration(minutes: 10))),
                data?.preferences.liveActivitiesEnabled == true
                    ? 'Live · opted in'
                    : 'Live · opt in',
                Icons.view_day_outlined,
              ),
              _cadenceStep(_time(due), 'Routine due', Icons.circle_outlined),
              _cadenceStep(
                _time(due.add(const Duration(minutes: 10))),
                calls ? 'Call · if eligible' : 'Call · opt in',
                Icons.phone_outlined,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            time == null
                ? 'Example timing for a 9:00 AM routine.'
                : 'Planned rhythm in your phone’s timezone. Snooze, quiet hours and delivery settings apply.',
            style: consumerText(10, color: ConsumerPalette.muted),
          ),
          TextButton(
            onPressed: () => _open('reminders'),
            child: const Text('Make reminders yours'),
          ),
        ],
      ),
    );
  }

  Widget _cadenceStep(String time, String label, IconData icon) => SizedBox(
    width: 86,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: ConsumerPalette.blue),
        const SizedBox(height: 7),
        Text(time, style: consumerText(13, weight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(label, style: consumerText(10, color: ConsumerPalette.muted)),
      ],
    ),
  );

  Widget _section(
    String title, {
    VoidCallback? action,
    String label = 'Edit',
  }) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 8),
    child: Row(
      children: [
        Expanded(
          child: Text(title, style: consumerText(19, weight: FontWeight.w600)),
        ),
        if (action != null) TextButton(onPressed: action, child: Text(label)),
      ],
    ),
  );

  String _status(ConsumerOccurrence o) => switch (o.status) {
    OccurrenceStatus.taken => 'Taken · Reported by you',
    OccurrenceStatus.skipped => 'Skipped · Reported by you',
    OccurrenceStatus.cancelled => 'Cancelled reminder',
    OccurrenceStatus.unconfirmed =>
      o.scheduledFor.isAfter(controller.clock())
          ? 'Planned reminder'
          : 'Unconfirmed',
  };
  Widget _occurrenceCard(ConsumerOccurrence o) => ConsumerCard(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: ConsumerPalette.pale,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                o.status == OccurrenceStatus.taken
                    ? Icons.check_rounded
                    : o.status == OccurrenceStatus.skipped
                    ? Icons.remove_rounded
                    : Icons.medication_outlined,
                color: ConsumerPalette.blue,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _name(o),
                    style: consumerText(15, weight: FontWeight.w600),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${_time(o.scheduledFor)} · ${_status(o)}',
                    style: consumerText(12, color: ConsumerPalette.muted),
                  ),
                  if (o.snoozedUntil != null &&
                      o.snoozedUntil!.isAfter(controller.clock()))
                    Text(
                      'Snoozed until ${_time(o.snoozedUntil!)}',
                      style: consumerText(12, color: ConsumerPalette.blue),
                    ),
                ],
              ),
            ),
          ],
        ),
        if (o.note?.isNotEmpty ?? false)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              o.note!,
              style: consumerText(13, color: ConsumerPalette.muted),
            ),
          ),
        if (o.status != OccurrenceStatus.cancelled)
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: () => _entry(o),
                child: Text(
                  o.status == OccurrenceStatus.unconfirmed
                      ? 'Add my entry'
                      : 'Review / correct',
                ),
              ),
              TextButton(
                onPressed: () => _entry(o, noteOnly: true),
                child: const Text('Edit note'),
              ),
            ],
          ),
      ],
    ),
  );

  List<Widget> _calendar() {
    final month = controller.visibleMonth;
    final count = DateTime(month.year, month.month + 1, 0).day;
    final offset = (month.weekday - 1) % 7;
    final selected = controller.occurrencesFor(controller.selectedDate);
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 22;
    final agenda = _agenda || largeText;
    return [
      const ConsumerHeading(
        'A rhythm\nthat fits you.',
        eyebrow: 'YOUR CALENDAR',
        subtitle: 'A clear record. Room for real life.',
      ),
      ConsumerCard(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Previous month',
                  onPressed:
                      controller.loading
                          ? null
                          : () => controller.moveMonth(-1),
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Expanded(
                  child: Text(
                    DateFormat.yMMMM().format(month),
                    textAlign: TextAlign.center,
                    style: consumerText(17, weight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  tooltip: 'Next month',
                  onPressed:
                      controller.loading ? null : () => controller.moveMonth(1),
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
            if (!agenda) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children:
                      ['M', 'T', 'W', 'T', 'F', 'S', 'S']
                          .map(
                            (label) => Expanded(
                              child: Text(
                                label,
                                textAlign: TextAlign.center,
                                style: consumerText(
                                  10,
                                  color: ConsumerPalette.muted,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                ),
              ),
              LayoutBuilder(
                builder:
                    (context, constraints) => Wrap(
                      children: List.generate(offset + count, (index) {
                        final width = constraints.maxWidth / 7;
                        if (index < offset) {
                          return SizedBox(width: width, height: 52);
                        }
                        final day = DateTime(
                          month.year,
                          month.month,
                          index - offset + 1,
                        );
                        final records = controller.occurrencesFor(day);
                        final chosen = day == controller.selectedDate;
                        final recorded = records.any(
                          (o) =>
                              o.status == OccurrenceStatus.taken ||
                              o.status == OccurrenceStatus.skipped,
                        );
                        final pending = records.any(
                          (o) =>
                              o.status == OccurrenceStatus.unconfirmed &&
                              !o.scheduledFor.isAfter(controller.clock()),
                        );
                        return SizedBox(
                          width: width,
                          height: 52,
                          child: Semantics(
                            label:
                                '${DateFormat.yMMMMEEEEd().format(day)}, ${records.length} reminders${recorded ? ', has recorded entries' : ''}${pending ? ', has unconfirmed entries' : ''}',
                            selected: chosen,
                            child: InkWell(
                              onTap: () => controller.selectDay(day),
                              borderRadius: BorderRadius.circular(13),
                              child: Container(
                                margin: const EdgeInsets.all(2),
                                decoration: BoxDecoration(
                                  color:
                                      chosen
                                          ? ConsumerPalette.navy
                                          : Colors.transparent,
                                  borderRadius: BorderRadius.circular(13),
                                  border:
                                      day ==
                                                  ConsumerController.day(
                                                    controller.clock(),
                                                  ) &&
                                              !chosen
                                          ? Border.all(
                                            color: ConsumerPalette.line,
                                          )
                                          : null,
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      '${day.day}',
                                      style: consumerText(
                                        14,
                                        weight:
                                            chosen
                                                ? FontWeight.w600
                                                : FontWeight.w400,
                                        color:
                                            chosen
                                                ? Colors.white
                                                : ConsumerPalette.navy,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    SizedBox(
                                      height: 5,
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          if (recorded)
                                            _dot(
                                              chosen
                                                  ? Colors.white
                                                  : ConsumerPalette.blue,
                                            ),
                                          if (pending)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                left: 2,
                                              ),
                                              child: _dot(
                                                chosen
                                                    ? Colors.white
                                                    : ConsumerPalette.muted,
                                                hollow: true,
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
                      }),
                    ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  _legend('Recorded', false),
                  _legend('Unconfirmed', true),
                ],
              ),
            ] else
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Agenda view keeps your dates and entries easy to read.',
                  style: consumerText(13, color: ConsumerPalette.muted),
                ),
              ),
            Row(
              children: [
                TextButton(
                  onPressed: controller.jumpToday,
                  child: const Text('Today'),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed:
                      largeText
                          ? null
                          : () => setState(() => _agenda = !_agenda),
                  icon: Icon(
                    agenda ? Icons.calendar_month : Icons.list_rounded,
                    size: 17,
                  ),
                  label: Text(agenda ? 'Month view' : 'Agenda view'),
                ),
              ],
            ),
          ],
        ),
      ),
      Wrap(
        spacing: 8,
        children:
            ['all', 'routine', 'refills']
                .map(
                  (filter) => ChoiceChip(
                    label: Text(
                      {
                        'all': 'All',
                        'routine': 'Routine',
                        'refills': 'Refills',
                      }[filter]!,
                    ),
                    selected: controller.calendarFilter == filter,
                    onSelected: (_) => controller.setFilter(filter),
                    selectedColor: ConsumerPalette.pale,
                    showCheckmark: false,
                  ),
                )
                .toList(),
      ),
      const SizedBox(height: 18),
      if (controller.calendarFilter == 'refills')
        ..._refillAgenda(agenda ? null : controller.selectedDate)
      else if (agenda)
        ..._agendaEntries()
      else ...[
        Text(
          DateFormat.MMMMEEEEd().format(controller.selectedDate),
          style: consumerText(16, weight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        if (selected.isEmpty)
          _empty(
            'Nothing recorded here.',
            'A blank day is just a record you can review.',
            Icons.calendar_today_outlined,
          )
        else
          ...selected.map(_occurrenceCard),
      ],
      if (controller.calendarFilter == 'all')
        ..._refillAgenda(
          agenda ? null : controller.selectedDate,
          showEmpty: false,
        ),
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(
          children: [
            if (controller.showCompanion)
              const ConsumerCompanion(size: 72, quiet: true),
            Expanded(
              child: Text(
                'A blank day isn’t a failure.\nYour record is here to help you.',
                style: consumerText(12, color: ConsumerPalette.muted),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      Text(
        'Times are shown in your phone’s timezone.',
        style: consumerText(11, color: ConsumerPalette.muted),
      ),
    ];
  }

  Widget _dot(Color color, {bool hollow = false}) => Container(
    width: 5,
    height: 5,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: hollow ? null : color,
      border: hollow ? Border.all(color: color) : null,
    ),
  );
  Widget _legend(String text, bool hollow) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _dot(ConsumerPalette.blue, hollow: hollow),
      const SizedBox(width: 5),
      Text(text, style: consumerText(10, color: ConsumerPalette.muted)),
    ],
  );
  List<Widget> _agendaEntries() {
    final entries =
        (data?.occurrences ?? <ConsumerOccurrence>[]).where((o) {
            final date = o.scheduledFor.toLocal();
            return date.year == controller.visibleMonth.year &&
                date.month == controller.visibleMonth.month;
          }).toList()
          ..sort((a, b) => a.scheduledFor.compareTo(b.scheduledFor));
    if (entries.isEmpty) {
      return [
        _empty(
          'Nothing recorded this month.',
          'Your routine will appear here when reminders are scheduled.',
          Icons.calendar_month_outlined,
        ),
      ];
    }
    DateTime? previous;
    final widgets = <Widget>[];
    for (final entry in entries) {
      final date = ConsumerController.day(entry.scheduledFor.toLocal());
      if (date != previous) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 12, 0, 10),
            child: Text(
              DateFormat.MMMMEEEEd().format(date),
              style: consumerText(16, weight: FontWeight.w600),
            ),
          ),
        );
      }
      widgets.add(_occurrenceCard(entry));
      previous = date;
    }
    return widgets;
  }

  List<Widget> _refillAgenda(DateTime? day, {bool showEmpty = true}) {
    final records =
        (data?.inventory ?? <ConsumerInventory>[]).where((supply) {
          final planned = supply.plannedFor?.toLocal();
          if (planned == null || supply.refillId == null) return false;
          return day != null
              ? ConsumerController.day(planned) == day
              : planned.year == controller.visibleMonth.year &&
                  planned.month == controller.visibleMonth.month;
        }).toList();
    if (records.isEmpty) {
      return showEmpty
          ? [
            _empty(
              'Your refill plans.',
              'No refill planning date is recorded here. Plan the next step in your refill station.',
              Icons.inventory_2_outlined,
              action: () => controller.selectTab(2),
              actionLabel: 'Open refill station',
            ),
          ]
          : [];
    }
    return records
        .map(
          (supply) => ConsumerCard(
            color: ConsumerPalette.warm,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Refill plan · ${DateFormat.MMMd().format(supply.plannedFor!.toLocal())}',
                  style: consumerText(
                    13,
                    color: ConsumerPalette.amber,
                    weight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  data?.prescription(supply.prescriptionId)?.name ??
                      'Your prescription',
                  style: consumerText(18, weight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text(
                  'You reported: ${supply.stage.name}. This is not a promised pickup date.',
                  style: consumerText(12, color: ConsumerPalette.amber),
                ),
                TextButton(
                  onPressed: () => controller.selectTab(2),
                  child: const Text('Review refill'),
                ),
              ],
            ),
          ),
        )
        .toList();
  }

  List<Widget> _refills() => [
    const ConsumerHeading(
      'The refill\nstation.',
      eyebrow: 'ONE LESS LAST-MINUTE THING',
      subtitle:
          'Your prescriptions, supply, and next steps. In one calm place.',
    ),
    if (data == null)
      _empty(
        'Your supply, in view.',
        'Refresh your account to see your prescriptions.',
        Icons.inventory_2_outlined,
      )
    else if (data!.prescriptions.isEmpty)
      _empty(
        'Start with your prescription.',
        'Add the label details first, then keep track of your supply here.',
        Icons.medication_outlined,
        action: _addPrescription,
        actionLabel: 'Add a prescription',
      )
    else
      ...data!.prescriptions.map(_refillCard),
    const ConsumerNotice(
      'Refill availability comes from your pharmacy or prescriber. Planning here does not submit an order or confirm eligibility.',
    ),
    ConsumerCard(
      color: ConsumerPalette.pale,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Need a renewal?',
            style: consumerText(18, weight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'If you have no refills left or your supply is running low, contact your pharmacy or prescriber using the details on your label.',
            style: consumerText(13, color: ConsumerPalette.muted),
          ),
        ],
      ),
    ),
  ];

  Widget _refillCard(ConsumerPrescription prescription) {
    final supply = data!.supply(prescription.id);
    final estimated = supply?.estimatedDays;
    final stage = supply?.stage ?? RefillStage.planning;
    final inventoryEnabled = data!.capabilities.inventoryEnabled;
    final refillsEnabled = data!.capabilities.refillsEnabled;
    return ConsumerCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ConsumerPill(
            'YOUR PRESCRIPTION',
            icon: Icons.medication_outlined,
          ),
          const SizedBox(height: 14),
          Text(
            prescription.name,
            style: consumerText(23, weight: FontWeight.w600),
          ),
          if (prescription.pharmacy?.isNotEmpty ?? false)
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                prescription.pharmacy!,
                style: consumerText(12, color: ConsumerPalette.muted),
              ),
            ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: ConsumerPalette.pale,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        estimated != null
                            ? 'ESTIMATED SUPPLY'
                            : 'YOUR LAST COUNT',
                        style: consumerText(
                          9,
                          color: ConsumerPalette.blue,
                          weight: FontWeight.w600,
                        ).copyWith(letterSpacing: 1),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        estimated != null
                            ? '$estimated days'
                            : supply?.quantity != null
                            ? '${supply!.quantity} at last count'
                            : 'Not counted yet',
                        style: consumerText(
                          estimated != null ? 34 : 23,
                          weight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        supply?.countedAt != null
                            ? 'Your count · ${DateFormat.MMMd().format(supply!.countedAt!.toLocal())}'
                            : 'Add a count when you’re ready.',
                        style: consumerText(11, color: ConsumerPalette.muted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 62,
                  height: 95,
                  child: Image.asset(
                    'assets/images/vial_bottle.png',
                    fit: BoxFit.contain,
                    errorBuilder:
                        (_, __, ___) =>
                            const Icon(Icons.medication_outlined, size: 42),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            estimated != null
                ? 'An estimate from your count and fixed schedule. Not a live measurement.'
                : 'A days-left estimate needs a confirmed count and a supported fixed schedule.',
            style: consumerText(11, color: ConsumerPalette.muted),
          ),
          TextButton.icon(
            onPressed:
                inventoryEnabled
                    ? () => _sheet(
                      ConsumerCountForm(
                        controller: controller,
                        prescription: prescription,
                      ),
                    )
                    : null,
            icon: const Icon(Icons.edit_outlined, size: 17),
            label: const Text('Update my count'),
          ),
          const Divider(height: 28),
          Text(
            'Your refill journey',
            style: consumerText(17, weight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          ...[
            'Plan ahead',
            'Contact pharmacy',
            'Pharmacy review',
            'Receive & count',
          ].asMap().entries.map(
            (step) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color:
                          step.key <= stage.index
                              ? ConsumerPalette.navy
                              : ConsumerPalette.pale,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${step.key + 1}',
                      style: consumerText(
                        11,
                        color:
                            step.key <= stage.index
                                ? Colors.white
                                : ConsumerPalette.muted,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(step.value, style: consumerText(13))),
                ],
              ),
            ),
          ),
          if (supply?.refillId != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: ConsumerPill(
                'You reported: ${stage.name}',
                icon: Icons.person_outline,
              ),
            ),
          ConsumerButton(
            stage == RefillStage.received
                ? supply?.receiptReconciled == true
                    ? 'Receipt reconciled'
                    : 'Reconcile my refill'
                : stage == RefillStage.planning
                ? supply?.refillId == null
                    ? 'Plan my refill'
                    : 'Continue with my pharmacy'
                : stage == RefillStage.contacted
                ? 'Update pharmacy progress'
                : 'I received my refill',
            onPressed:
                refillsEnabled &&
                        !(stage == RefillStage.received &&
                            supply?.receiptReconciled == true)
                    ? () => _refillAction(prescription, stage)
                    : null,
          ),
          if (stage == RefillStage.received)
            TextButton.icon(
              onPressed:
                  controller.saving
                      ? null
                      : () async {
                        if (supply?.receiptReconciled != true) {
                          final proceed = await showDialog<bool>(
                            context: context,
                            builder:
                                (context) => AlertDialog(
                                  title: const Text('Start a new plan?'),
                                  content: const Text(
                                    'Your previous receipt has not been reconciled. Starting a new plan skips that stock-tracking step in this view and leaves your last count unchanged. Reconcile it first if you want to include that refill.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed:
                                          () => Navigator.pop(context, false),
                                      child: const Text('Go back'),
                                    ),
                                    TextButton(
                                      onPressed:
                                          () => Navigator.pop(context, true),
                                      child: const Text(
                                        'Skip and start a new plan',
                                      ),
                                    ),
                                  ],
                                ),
                          );
                          if (proceed != true || !mounted) return;
                        }
                        final error = await controller.mutate(
                          () => widget.repository.updateRefill(
                            prescription.id,
                            RefillStage.planning,
                            startNew: true,
                          ),
                        );
                        if (mounted) {
                          _message(
                            error ?? 'A new refill plan is ready for you.',
                          );
                        }
                      },
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Plan my next refill'),
            ),
          if (supply?.stale == true)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'This count is out of date. Recount your supply before relying on it.',
                style: consumerText(12, color: ConsumerPalette.amber),
              ),
            ),
          if (!refillsEnabled || !inventoryEnabled)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'Supply and refill updates are not available for this account yet. Your prescription details remain available.',
                style: consumerText(11, color: ConsumerPalette.muted),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _refillAction(
    ConsumerPrescription prescription,
    RefillStage stage,
  ) async {
    if (data?.supply(prescription.id)?.refillId == null) {
      final error = await controller.mutate(
        () => widget.repository.updateRefill(
          prescription.id,
          RefillStage.planning,
        ),
      );
      if (mounted) {
        _message(
          error ??
              'Your refill plan is saved. Contact your pharmacy for the next step.',
        );
      }
      return;
    }
    if (stage == RefillStage.received) {
      _sheet(
        data?.supply(prescription.id)?.quantity == null
            ? ConsumerCountForm(
              controller: controller,
              prescription: prescription,
            )
            : ConsumerReceiptForm(
              controller: controller,
              prescription: prescription,
            ),
      );
      return;
    }
    final next = RefillStage.values[stage.index + 1];
    final accepted = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(
              stage == RefillStage.planning
                  ? 'Your pharmacy is next.'
                  : stage == RefillStage.contacted
                  ? 'Is your refill ready?'
                  : 'Have you received it?',
            ),
            content: Text(
              stage == RefillStage.planning
                  ? 'Use the contact details on your prescription label to reach your pharmacy. When you have contacted them, record that step here. This does not submit a refill request.'
                  : stage == RefillStage.contacted
                  ? 'Only mark ready after checking with your pharmacy. This is saved as your own update.'
                  : 'Record only a refill you actually received. Your inventory count stays unchanged until you update it.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Not yet'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(
                  stage == RefillStage.planning
                      ? 'I contacted my pharmacy'
                      : 'Yes, record my update',
                ),
              ),
            ],
          ),
    );
    if (accepted != true || !mounted) return;
    final error = await controller.mutate(
      () => widget.repository.updateRefill(prescription.id, next),
    );
    if (mounted) _message(error ?? 'Your refill update is saved.');
  }

  List<Widget> _you() => [
    Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Expanded(
          child: ConsumerHeading('A little\nmore you.', eyebrow: 'YOUR SPACE'),
        ),
        if (controller.showCompanion &&
            MediaQuery.textScalerOf(context).scale(14) < 22)
          const ConsumerCompanion(size: 106, quiet: true),
      ],
    ),
    ConsumerCard(
      child: Column(
        children: [
          ConsumerLink(
            'Your routine',
            'Medications, labels & reminder times',
            Icons.medication_outlined,
            onTap: () => _open('routines'),
          ),
          const Divider(height: 1),
          ConsumerLink(
            'Reminders that reach you',
            'Live Activities & optional calls',
            Icons.notifications_none_rounded,
            onTap: () => _open('reminders'),
          ),
          const Divider(height: 1),
          ConsumerLink(
            'Your vial',
            'Connect when you’re ready',
            Icons.bluetooth_rounded,
            onTap: () => _open('vial'),
          ),
          const Divider(height: 1),
          ConsumerLink(
            'Your circle',
            'Support on your terms',
            Icons.people_outline_rounded,
            onTap: () => _open('circle'),
          ),
        ],
      ),
    ),
    ConsumerCard(
      child: Column(
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: controller.showCompanion,
            onChanged: controller.setCompanion,
            title: Text(
              'A friendly face',
              style: consumerText(15, weight: FontWeight.w600),
            ),
            subtitle: Text(
              'Show the Farda companion',
              style: consumerText(12, color: ConsumerPalette.muted),
            ),
          ),
          const Divider(height: 18),
          ConsumerLink(
            'Your data & privacy',
            'Private reminders and account controls',
            Icons.lock_outline_rounded,
            onTap: () => _open('privacy'),
          ),
        ],
      ),
    ),
    if (demo)
      const ConsumerNotice(
        'This sample session stays in memory and resets when you leave. Nothing is sent to a phone, pharmacy, or vial.',
      )
    else if (widget.onSignOut != null)
      TextButton(
        onPressed: () async {
          await _signOut();
        },
        child: const Text('Sign out'),
      ),
  ];

  List<Widget> _routines() => [
    const ConsumerHeading(
      'Your routine.',
      eyebrow: 'MAKE IT YOURS',
      subtitle:
          'Reminder times belong to you. Prescription directions stay as reviewed.',
    ),
    if (data?.prescriptions.isEmpty ?? true)
      _empty(
        'Your first routine.',
        'Add the details from your label to get started.',
        Icons.medication_outlined,
      ),
    ...?data?.prescriptions.map(
      (p) => ConsumerCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ConsumerPill(
              'MANUAL TRACKING',
              icon: Icons.medication_outlined,
            ),
            const SizedBox(height: 14),
            Text(p.name, style: consumerText(23, weight: FontWeight.w600)),
            const SizedBox(height: 12),
            Text(
              p.directions?.isNotEmpty == true
                  ? p.directions!
                  : 'Directions need a label review.',
              style: consumerText(14, color: ConsumerPalette.muted),
            ),
            const Divider(height: 30),
            Text(
              p.times.isEmpty
                  ? 'Review scheduled reminders in your calendar.'
                  : 'Daily · ${p.times.join(', ')}',
              style: consumerText(16, weight: FontWeight.w600),
            ),
            const SizedBox(height: 5),
            Text(
              p.timeZone,
              style: consumerText(12, color: ConsumerPalette.muted),
            ),
            if (p.pharmacy?.isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(p.pharmacy!, style: consumerText(13)),
              ),
            TextButton(
              onPressed: () {
                setState(() => _page = null);
                controller.selectTab(1);
              },
              child: const Text('Review my calendar'),
            ),
            TextButton.icon(
              onPressed:
                  () => _sheet(
                    ConsumerPrescriptionForm(
                      controller: controller,
                      editing: p,
                    ),
                  ),
              icon: const Icon(Icons.schedule_rounded, size: 17),
              label: const Text('Edit future reminders'),
            ),
          ],
        ),
      ),
    ),
    ConsumerButton(
      'Add a prescription',
      icon: Icons.add_rounded,
      onPressed: data == null ? null : _addPrescription,
    ),
    const SizedBox(height: 18),
    const ConsumerNotice(
      'For variable or as-needed directions, check the label and your pharmacy. A daily reminder is not a dosing recommendation.',
    ),
  ];

  List<Widget> _reminders() {
    final preferences =
        data?.preferences ?? const ConsumerReminderPreferences();
    final capabilities = data?.capabilities ?? const ConsumerCapabilities();
    return [
      const ConsumerHeading(
        'A heads-up.\nThen a real ring.',
        eyebrow: 'RIGHT THERE WITH YOU',
        subtitle:
            'Ten minutes before. A moment when it’s due. An optional call ten minutes later.',
      ),
      _cadence(controller.nextOccurrence?.scheduledFor),
      ConsumerCard(
        child: Column(
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: preferences.callsEnabled,
              onChanged:
                  data == null ||
                          controller.saving ||
                          ((!capabilities.voiceEnabled ||
                                  (!capabilities.phoneVerified && !demo)) &&
                              !preferences.callsEnabled)
                      ? null
                      : (value) => _setCalls(value),
              title: Text(
                'Phone-call reminders',
                style: consumerText(16, weight: FontWeight.w600),
              ),
              subtitle: Text(
                demo
                    ? 'Demo only · No number is contacted'
                    : capabilities.voiceEnabled
                    ? capabilities.phoneVerified
                        ? 'Your choice, with a verified phone number'
                        : 'Verify your phone before enabling calls'
                    : 'Call delivery is not enabled for this account yet',
                style: consumerText(12, color: ConsumerPalette.muted),
              ),
            ),
            const Divider(height: 28),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: preferences.liveActivitiesEnabled,
              onChanged:
                  data == null || controller.saving
                      ? null
                      : (value) async {
                        final error = await controller.mutate(
                          () => widget.repository.saveReminderPreferences(
                            preferences.copyWith(liveActivitiesEnabled: value),
                          ),
                        );
                        if (mounted && error != null) _message(error);
                      },
              title: Text(
                'Live Activities',
                style: consumerText(16, weight: FontWeight.w600),
              ),
              subtitle: Text(
                'A private glance on supported iPhones',
                style: consumerText(12, color: ConsumerPalette.muted),
              ),
            ),
            if (!capabilities.liveActivityDeliveryEnabled && !demo)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'This saves your preference. Automatic background delivery is not enabled yet.',
                  style: consumerText(11, color: ConsumerPalette.muted),
                ),
              ),
            const Divider(height: 28),
            ConsumerLink(
              'Quiet hours',
              preferences.quietHoursStart == preferences.quietHoursEnd
                  ? 'Calls quiet all day · ${preferences.timeZone}'
                  : '${preferences.quietHoursStart}–${preferences.quietHoursEnd} · ${preferences.timeZone}',
              Icons.nights_stay_outlined,
              onTap: _quietHours,
            ),
          ],
        ),
      ),
      ConsumerCard(
        color: ConsumerPalette.pale,
        child: Row(
          children: [
            if (controller.showCompanion)
              const ConsumerCompanion(size: 76, quiet: true),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Only when you want it.',
                    style: consumerText(17, weight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Names stay private. You choose calls, and you can turn them off any time.',
                    style: consumerText(12, color: ConsumerPalette.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      ConsumerButton(
        'Preview the reminder experience',
        secondary: true,
        icon: Icons.play_circle_outline,
        onPressed: () => _open('live'),
      ),
      const SizedBox(height: 18),
      const ConsumerNotice(
        'A call is a reminder, not a completed entry. Logging or snoozing updates the same routine. Phone and platform settings can affect delivery.',
      ),
    ];
  }

  Future<void> _setCalls(bool value) async {
    if (data == null) return;
    if (value) {
      final accepted = await showDialog<bool>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('A real ring, when you choose.'),
              content: Text(
                demo
                    ? 'Enable simulated calls in this demo? No phone number will be contacted.'
                    : data!.callConsentText ??
                        'Refresh your reminder preferences to review the current call consent wording.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Not now'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(
                    demo ? 'Enable demo calls' : 'I agree to reminder calls',
                  ),
                ),
              ],
            ),
      );
      if (accepted != true || !mounted) return;
    }
    final error = await controller.mutate(
      () => widget.repository.saveReminderPreferences(
        data!.preferences.copyWith(callsEnabled: value),
        callConsent: value,
      ),
    );
    if (mounted) {
      _message(
        error ??
            (value
                ? 'Your call preference is saved.'
                : 'Call reminders are turned off.'),
      );
    }
  }

  Future<void> _quietHours() async {
    if (data == null) return;
    final p = data!.preferences;
    final zone = await showDialog<String>(
      context: context,
      builder:
          (context) => SimpleDialog(
            title: const Text('Quiet-hours timezone'),
            children:
                {
                      'America/Los_Angeles': 'Pacific · Los Angeles',
                      'America/Denver': 'Mountain · Denver',
                      'America/Chicago': 'Central · Chicago',
                      'America/New_York': 'Eastern · New York',
                      'UTC': 'UTC',
                      if (![
                        'America/Los_Angeles',
                        'America/Denver',
                        'America/Chicago',
                        'America/New_York',
                        'UTC',
                      ].contains(p.timeZone))
                        p.timeZone: p.timeZone,
                    }.entries
                    .map(
                      (entry) => SimpleDialogOption(
                        onPressed: () => Navigator.pop(context, entry.key),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(entry.value),
                        ),
                      ),
                    )
                    .toList(),
          ),
    );
    if (zone == null || !mounted) return;
    TimeOfDay parse(String time) {
      final split = time.split(':');
      return TimeOfDay(
        hour: int.tryParse(split.first) ?? 21,
        minute: int.tryParse(split.last) ?? 0,
      );
    }

    final start = await showTimePicker(
      context: context,
      initialTime: parse(p.quietHoursStart),
      helpText: 'QUIET HOURS START',
    );
    if (start == null || !mounted) return;
    final end = await showTimePicker(
      context: context,
      initialTime: parse(p.quietHoursEnd),
      helpText: 'QUIET HOURS END',
    );
    if (end == null || !mounted) return;
    if (start == end) {
      final allDay = await showDialog<bool>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('Keep calls quiet all day?'),
              content: const Text(
                'Matching start and end times silence reminder calls throughout the day. Your routine record stays available.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Go back'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Quiet all day'),
                ),
              ],
            ),
      );
      if (allDay != true || !mounted) return;
    }
    String format(TimeOfDay t) =>
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    final error = await controller.mutate(
      () => widget.repository.saveReminderPreferences(
        p.copyWith(
          timeZone: zone,
          quietHoursStart: format(start),
          quietHoursEnd: format(end),
        ),
      ),
    );
    if (mounted) _message(error ?? 'Quiet hours saved in $zone.');
  }

  List<Widget> _vial() => [
    const ConsumerHeading(
      'Good things\nare on the way.',
      eyebrow: 'YOUR FARDA VIAL',
      subtitle: 'A helper for your routine. Connect when you’re ready.',
    ),
    ConsumerCard(
      color: ConsumerPalette.pale,
      child: Column(
        children: [
          SizedBox(
            height: 190,
            child: Image.asset(
              'assets/images/vial_bottle.png',
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Your routine can start today.',
            style: consumerText(20, weight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'No vial status is available in this view. Manual logging and your calendar remain available.',
            textAlign: TextAlign.center,
            style: consumerText(13, color: ConsumerPalette.muted),
          ),
        ],
      ),
    ),
    ConsumerButton(
      demo ? 'Explore sample setup' : 'Set up my vial',
      icon: Icons.bluetooth_rounded,
      onPressed:
          demo
              ? () => _message(
                'Sample setup: identify your vial, confirm ownership, then calibrate. No hardware command is sent.',
              )
              : widget.onOpenHardware,
    ),
    const SizedBox(height: 18),
    const ConsumerNotice(
      'A vial movement is an observation. It does not confirm that a dose was taken.',
    ),
    ConsumerCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Out of touch?',
            style: consumerText(18, weight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'Keep your record manually if the vial is offline. Battery and last-sync information should be checked when the vial reconnects.',
            style: consumerText(13, color: ConsumerPalette.muted),
          ),
          const SizedBox(height: 14),
          Text(
            'If you cannot access your medication, follow the vial’s supplied access instructions and contact support. Do not rely on the app to open a powered-off vial.',
            style: consumerText(13, color: ConsumerPalette.muted),
          ),
        ],
      ),
    ),
  ];

  List<Widget> _circle() => [
    const ConsumerHeading(
      'Your circle.\nYour choice.',
      eyebrow: 'CARE, WITHOUT THE PRESSURE',
      subtitle: 'Invite support, on your terms.',
    ),
    ConsumerCard(
      color: ConsumerPalette.pale,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (controller.showCompanion)
            const ConsumerCompanion(size: 110, quiet: true),
          Text(
            'Just you, for now.',
            style: consumerText(24, weight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Text(
            'Your routine is private. Sharing will need a verified invitation, acceptance, and the permissions you choose.',
            style: consumerText(14, color: ConsumerPalette.muted),
          ),
        ],
      ),
    ),
    ConsumerCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'You stay in control.',
            style: consumerText(19, weight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          ...[
            'Choose which routine to share',
            'Choose what someone can see',
            'Remove access whenever you need',
          ].map(
            (s) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.check_circle_outline_rounded,
                    size: 19,
                    color: ConsumerPalette.blue,
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(s, style: consumerText(14))),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
    const ConsumerNotice(
      'Support-circle invitations are not enabled yet. No contact has access through this screen.',
    ),
  ];

  List<Widget> _privacy() => [
    const ConsumerHeading(
      'Your routine.\nYour information.',
      eyebrow: 'PRIVACY & CONTROL',
    ),
    ConsumerCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _privacyItem(
            Icons.lock_outline_rounded,
            'Private at a glance',
            'Medication names are hidden in reminder previews by default.',
          ),
          _privacyItem(
            Icons.phone_outlined,
            'Calls are your choice',
            'Turn off call reminders at any time in reminder preferences.',
          ),
          _privacyItem(
            Icons.edit_outlined,
            'Your record can be corrected',
            'Open a calendar entry to add a note or correct what you reported.',
          ),
          _privacyItem(
            Icons.people_outline,
            'Sharing requires a choice',
            'Adding someone to your contacts does not give them access to your routine.',
          ),
        ],
      ),
    ),
    ConsumerButton(
      'Review reminder privacy',
      secondary: true,
      onPressed: () => _open('reminders'),
    ),
    const SizedBox(height: 16),
    const ConsumerNotice(
      'Self-service export and deletion are not available in this build. Contact the Farda team for account-data requests.',
    ),
  ];
  Widget _privacyItem(IconData icon, String title, String detail) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: ConsumerPalette.blue, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: consumerText(15, weight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(
                detail,
                style: consumerText(13, color: ConsumerPalette.muted),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  List<Widget> _livePreview() {
    final before = _preview == 'before';
    final call = _preview == 'call';
    return [
      const ConsumerHeading(
        'A glance.\nA little nudge.',
        eyebrow: 'REMINDER PREVIEW',
        subtitle:
            'An example 9:00 AM routine. This preview does not start a call or a Live Activity.',
      ),
      Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          for (final item
              in {
                'before': '8:50 · Heads-up',
                'due': '9:00 · Due',
                'call': '9:10 · Call',
              }.entries)
            ChoiceChip(
              label: Text(item.value),
              selected: _preview == item.key,
              onSelected: (_) => setState(() => _preview = item.key),
              selectedColor: ConsumerPalette.pale,
            ),
        ],
      ),
      const SizedBox(height: 18),
      Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(32),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF335682), ConsumerPalette.deep],
          ),
        ),
        child: Column(
          children: [
            const Icon(
              Icons.lock_outline_rounded,
              size: 18,
              color: Colors.white70,
            ),
            const SizedBox(height: 12),
            Text(
              before
                  ? '8:50'
                  : call
                  ? '9:10'
                  : '9:00',
              style: consumerText(
                66,
                color: Colors.white,
                weight: FontWeight.w500,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 22),
            if (call) ...[
              if (controller.showCompanion) const ConsumerCompanion(size: 120),
              Text(
                'Farda',
                style: consumerText(
                  32,
                  color: Colors.white,
                  weight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Your routine reminder',
                style: consumerText(15, color: Colors.white70),
              ),
              const SizedBox(height: 22),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '“Hi, this is your automated Farda reminder. Your routine is ready when you are. Open Farda to check in. To stop reminder calls, press 9.”',
                  style: consumerText(15, color: Colors.white),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Illustrative caller screen. Your phone and carrier control the actual appearance.',
                textAlign: TextAlign.center,
                style: consumerText(11, color: Colors.white70),
              ),
            ] else ...[
              ConsumerCard(
                color: const Color(0xFFF0F3F9),
                margin: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'farda',
                          style: consumerText(20, weight: FontWeight.w600),
                        ),
                        const Spacer(),
                        const Icon(Icons.lock_outline, size: 15),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      before ? 'A little heads-up' : 'Your routine is ready',
                      style: consumerText(23, weight: FontWeight.w600),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      before
                          ? 'Your routine starts in 10 minutes.'
                          : 'Your active reminder · 9:00 AM',
                      style: consumerText(12, color: ConsumerPalette.muted),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      before ? '10:00' : 'Now',
                      style: consumerText(35, weight: FontWeight.w600),
                    ),
                    Text(
                      before
                          ? 'until your routine'
                          : 'Optional call reminder at 9:10',
                      style: consumerText(11, color: ConsumerPalette.muted),
                    ),
                    const SizedBox(height: 18),
                    ConsumerButton(
                      before ? 'View my routine' : 'Open & log',
                      onPressed: () => _open('routines'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Row(
                  children: [
                    Text(
                      'f.',
                      style: consumerText(
                        19,
                        color: Colors.white,
                        weight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Your routine',
                        style: consumerText(12, color: Colors.white),
                      ),
                    ),
                    Text(
                      before ? '10:00' : 'Now',
                      style: consumerText(12, color: const Color(0xFFBBD0F0)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Compact Dynamic Island study',
                style: consumerText(10, color: Colors.white70),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 18),
      const ConsumerNotice(
        'Opening, answering, or dismissing a reminder never records a dose. Your check-in is a separate, explicit action.',
      ),
    ];
  }

  Widget _empty(
    String title,
    String detail,
    IconData icon, {
    VoidCallback? action,
    String actionLabel = 'Continue',
  }) => ConsumerCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 30, color: ConsumerPalette.blue),
        const SizedBox(height: 17),
        Text(title, style: consumerText(23, weight: FontWeight.w600)),
        const SizedBox(height: 10),
        Text(detail, style: consumerText(14, color: ConsumerPalette.muted)),
        if (action != null) ...[
          const SizedBox(height: 20),
          ConsumerButton(actionLabel, secondary: true, onPressed: action),
        ],
      ],
    ),
  );
  Widget _loadingCard() => ConsumerCard(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        children: [
          const CircularProgressIndicator(strokeWidth: 2),
          const SizedBox(height: 18),
          Text(
            'Finding your rhythm…',
            style: consumerText(17, weight: FontWeight.w500),
          ),
        ],
      ),
    ),
  );
}

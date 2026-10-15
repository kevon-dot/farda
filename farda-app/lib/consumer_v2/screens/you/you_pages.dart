import 'package:flutter/material.dart';

import '../today/farda_companion.dart';
import 'you_models.dart';
import 'you_widgets.dart';

class FardaYouOverviewPage extends StatelessWidget {
  const FardaYouOverviewPage({
    super.key,
    required this.profileLabel,
    required this.showBrandHeader,
    required this.showCompanion,
    required this.privatePreviews,
    required this.onDestinationSelected,
    required this.onCompanionChanged,
    required this.onPrivatePreviewsChanged,
    required this.onPrivacyPressed,
    this.liveRecords = false,
  });

  final String profileLabel;
  final bool showBrandHeader;
  final bool showCompanion;
  final bool privatePreviews;
  final ValueChanged<FardaYouDestination> onDestinationSelected;
  final ValueChanged<bool> onCompanionChanged;
  final ValueChanged<bool> onPrivatePreviewsChanged;
  final VoidCallback onPrivacyPressed;
  final bool liveRecords;

  @override
  Widget build(BuildContext context) {
    return FardaYouPageCanvas(
      children: [
        if (showBrandHeader) ...[
          FardaYouBrandHeader(profileLabel: profileLabel, selected: true),
          const SizedBox(height: 24),
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            final companionSize = constraints.maxWidth < 340 ? 88.0 : 110.0;
            return Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'YOUR SPACE',
                        style: fardaYouText(
                          size: 10,
                          height: 14,
                          weight: FontWeight.w600,
                          color: FardaYouPalette.textSecondary,
                          letterSpacing: 1.45,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Semantics(
                        header: true,
                        child: Text(
                          'A little\nmore you.',
                          style: fardaYouText(
                            size: 34,
                            height: 38,
                            weight: FontWeight.w600,
                            letterSpacing: -0.8,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (showCompanion)
                  FardaCompanion(
                    size: companionSize,
                    mood: FardaCompanionMood.quiet,
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 22),
        FardaYouCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(
            children: [
              FardaYouLinkRow(
                key: FardaYouKeys.routineLink,
                title: 'Your routine',
                subtitle: 'Medications, labels & reminder times',
                icon: Icons.medication_outlined,
                onTap: () => onDestinationSelected(
                  FardaYouDestination.routine,
                ),
              ),
              FardaYouLinkRow(
                key: FardaYouKeys.remindersLink,
                title: 'Reminders that reach you',
                subtitle: 'Notifications, Live Activities & calls',
                icon: Icons.notifications_none_rounded,
                onTap: () => onDestinationSelected(
                  FardaYouDestination.reminders,
                ),
              ),
              FardaYouLinkRow(
                key: FardaYouKeys.vialLink,
                title: 'Your vial',
                subtitle: 'Explore the setup preview',
                icon: Icons.local_drink_outlined,
                onTap: () => onDestinationSelected(FardaYouDestination.vial),
              ),
              FardaYouLinkRow(
                key: FardaYouKeys.circleLink,
                title: 'Your circle',
                subtitle: 'Preview sharing options',
                icon: Icons.people_outline_rounded,
                showDivider: false,
                onTap: () => onDestinationSelected(
                  FardaYouDestination.circle,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        FardaYouCard(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
          child: Column(
            children: [
              FardaYouSettingRow(
                title: 'A friendly face',
                subtitle: 'Show the Farda companion',
                trailing: FardaYouSwitch(
                  key: FardaYouKeys.companionToggle,
                  value: showCompanion,
                  onChanged: onCompanionChanged,
                  semanticLabel: 'Show the Farda companion',
                ),
              ),
              FardaYouSettingRow(
                title: 'Quiet on your Lock Screen',
                subtitle: liveRecords
                    ? 'Sample Lock Screen only'
                    : 'Keep medication names private',
                showDivider: false,
                trailing: FardaYouSwitch(
                  key: FardaYouKeys.privacyToggle,
                  value: privatePreviews,
                  onChanged: onPrivatePreviewsChanged,
                  semanticLabel: 'Hide medication names on the Lock Screen',
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: onPrivacyPressed,
                  style: TextButton.styleFrom(
                    foregroundColor: FardaYouPalette.navy,
                    minimumSize: const Size(48, 48),
                    padding: EdgeInsets.zero,
                  ),
                  child: Text(
                    liveRecords ? 'How previews use data' : 'Your data & privacy controls',
                    style: fardaYouText(
                      size: 13,
                      weight: FontWeight.w500,
                      color: FardaYouPalette.navy,
                    ).copyWith(
                      decoration: TextDecoration.underline,
                      decorationColor: FardaYouPalette.navy,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        FardaYouNotice(
          text: liveRecords
              ? 'Companion and Lock Screen privacy controls here are local previews. Reminder preferences are saved separately on the next page.'
              : 'Your routine belongs to you. You choose what to share and how we remind you. Settings in this preview stay on this screen and are not sent anywhere.',
        ),
      ],
    );
  }
}

class FardaRoutinePage extends StatelessWidget {
  const FardaRoutinePage({
    super.key,
    required this.profileLabel,
    required this.showBrandHeader,
    required this.showCompanion,
    required this.medicationName,
    required this.reminderTime,
    required this.labelReviewed,
    required this.onBack,
    required this.onEditRoutine,
    required this.onReviewLabel,
    required this.onOpenReminders,
    this.liveRecords = false,
    this.hasRoutine = true,
    this.additionalRoutineCount = 0,
    this.timeZoneLabel = 'Los Angeles time',
    this.scheduleLabel = 'Morning routine',
    this.directions,
  });

  final String profileLabel;
  final bool showBrandHeader;
  final bool showCompanion;
  final String medicationName;
  final String reminderTime;
  final bool labelReviewed;
  final VoidCallback onBack;
  final VoidCallback onEditRoutine;
  final VoidCallback onReviewLabel;
  final VoidCallback onOpenReminders;
  final bool liveRecords;
  final bool hasRoutine;
  final int additionalRoutineCount;
  final String timeZoneLabel;
  final String scheduleLabel;
  final String? directions;

  @override
  Widget build(BuildContext context) {
    return FardaYouPageCanvas(
      children: [
        if (showBrandHeader) ...[
          FardaYouBrandHeader(profileLabel: profileLabel),
          const SizedBox(height: 8),
        ],
        FardaYouBackButton(onPressed: onBack),
        const SizedBox(height: 4),
        const FardaYouPageHeader(
          eyebrow: 'Make it yours',
          title: 'Your routine.',
          supportingText:
              'Reminder times belong to you. Prescription directions stay as reviewed.',
        ),
        const SizedBox(height: 22),
        if (liveRecords && !hasRoutine) ...[
          const FardaYouNotice(text: 'No routine is saved for this account yet. Add one in account settings.'),
          const SizedBox(height: 12),
          FardaYouSecondaryButton(label: 'Open account settings',
              icon: Icons.add_rounded, onPressed: onEditRoutine),
        ] else ...[
        FardaYouCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const FardaYouIconTile(
                    icon: Icons.medication_outlined,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          medicationName,
                          style: fardaYouText(
                            size: 16,
                            height: 21,
                            weight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          scheduleLabel,
                          style: fardaYouText(
                            size: 12,
                            height: 17,
                            color: FardaYouPalette.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (labelReviewed)
                    const FardaPreviewBadge(label: 'Label reviewed'),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Semantics(
                      label: 'Reminder time $reminderTime every day',
                      child: Text(
                        reminderTime,
                        style: fardaYouText(
                          size: 28,
                          height: 32,
                          weight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: onEditRoutine,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      foregroundColor: FardaYouPalette.navy,
                    ),
                    child: const Text('Edit'),
                  ),
                ],
              ),
              Text(
                'Every day · $timeZoneLabel',
                style: fardaYouText(
                  size: 12,
                  height: 17,
                  color: FardaYouPalette.textSecondary,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                liveRecords
                    ? (directions?.isNotEmpty == true
                        ? directions!
                        : 'Check your original prescription label for directions.')
                    : 'Directions copied from your reviewed label.',
                style: fardaYouText(
                  size: 12,
                  height: 17,
                  color: FardaYouPalette.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (!liveRecords) FardaYouCard(
          child: Row(
            children: [
              const FardaYouIconTile(icon: Icons.dark_mode_outlined),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Evening routine',
                      style: fardaYouText(
                        size: 15,
                        height: 20,
                        weight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '8:00 PM · Manual reminder',
                      style: fardaYouText(
                        size: 12,
                        height: 17,
                        color: FardaYouPalette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (liveRecords && additionalRoutineCount > 0) ...[
          FardaYouNotice(text: '$additionalRoutineCount more routine(s) are saved. Open account settings to review them.'),
          const SizedBox(height: 12),
        ],
        FardaYouSecondaryButton(
          label: labelReviewed
              ? 'Review label confirmation'
              : liveRecords ? 'Review in account settings' : 'Review a prescription label',
          icon: Icons.document_scanner_outlined,
          onPressed: onReviewLabel,
        ),
        const SizedBox(height: 12),
        const FardaYouNotice(
          text:
              'Scans can help with typing. Unclear directions stay blank until you check the original label or ask your pharmacy. Farda does not generate dosing instructions.',
        ),
        ],
        if (showCompanion) ...[
          const SizedBox(height: 18),
          Row(
            children: [
              const FardaCompanion(
                size: 78,
                mood: FardaCompanionMood.resting,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Travel coming up?',
                      style: fardaYouText(
                        size: 14,
                        weight: FontWeight.w600,
                      ),
                    ),
                    TextButton(
                      onPressed: onOpenReminders,
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        alignment: Alignment.centerLeft,
                        padding: EdgeInsets.zero,
                        foregroundColor: FardaYouPalette.navy,
                      ),
                      child: const Text('Review reminder preferences'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class FardaReminderPreferencesPage extends StatelessWidget {
  const FardaReminderPreferencesPage({
    super.key,
    required this.profileLabel,
    required this.showBrandHeader,
    required this.showCompanion,
    required this.callReminders,
    required this.liveActivities,
    required this.privatePreviews,
    required this.callDelayMinutes,
    required this.onBack,
    required this.onCallRemindersChanged,
    required this.onLiveActivitiesChanged,
    required this.onPrivatePreviewsChanged,
    required this.onEditDelay,
    required this.onOpenLivePreview,
    required this.onOpenCallPreview,
    this.liveRecords = false,
    this.preferencesAvailable = true,
    this.saving = false,
    this.canEnableCalls = true,
    this.canEnableLiveActivities = true,
    this.quietHoursLabel = '9:00 PM – 8:00 AM',
  });

  final String profileLabel;
  final bool showBrandHeader;
  final bool showCompanion;
  final bool callReminders;
  final bool liveActivities;
  final bool privatePreviews;
  final int callDelayMinutes;
  final VoidCallback onBack;
  final ValueChanged<bool> onCallRemindersChanged;
  final ValueChanged<bool> onLiveActivitiesChanged;
  final ValueChanged<bool> onPrivatePreviewsChanged;
  final VoidCallback onEditDelay;
  final VoidCallback onOpenLivePreview;
  final VoidCallback onOpenCallPreview;
  final bool liveRecords;
  final bool preferencesAvailable;
  final bool saving;
  final bool canEnableCalls;
  final bool canEnableLiveActivities;
  final String quietHoursLabel;

  @override
  Widget build(BuildContext context) {
    return FardaYouPageCanvas(
      children: [
        if (showBrandHeader) ...[
          FardaYouBrandHeader(profileLabel: profileLabel),
          const SizedBox(height: 8),
        ],
        FardaYouBackButton(onPressed: onBack),
        const SizedBox(height: 4),
        FardaYouPageHeader(
          eyebrow: 'Choose your rhythm',
          title: liveRecords
              ? 'Reminders on\nyour terms.'
              : 'A heads-up.\nThen a real ring.',
          supportingText: liveRecords
              ? 'Choose the reminder channels available for your account.'
              : 'A little before. Right on time. A call when you want one.',
        ),
        const SizedBox(height: 20),
        if (!liveRecords) ...[
          FardaReminderCadence(callDelayMinutes: callDelayMinutes),
          const SizedBox(height: 14),
        ],
        FardaYouCard(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
          child: Column(
            children: [
              FardaYouSettingRow(
                title: 'Phone-call reminders',
                subtitle: liveRecords
                    ? (preferencesAvailable
                        ? (callReminders
                            ? 'On for your account'
                            : canEnableCalls
                                ? 'Off until you opt in'
                                : 'Verify your phone in account settings')
                        : 'Preferences unavailable; refresh your account')
                    : (callReminders ? 'Enabled in this local preview only' : 'Off until you explicitly opt in'),
                trailing: FardaYouSwitch(
                  key: FardaYouKeys.callToggle,
                  value: callReminders,
                  onChanged: saving || !preferencesAvailable ||
                          (liveRecords && !callReminders && !canEnableCalls)
                      ? null : onCallRemindersChanged,
                  semanticLabel: 'Phone-call reminders',
                ),
              ),
              FardaYouSettingRow(
                title: 'Live Activities',
                subtitle: liveRecords
                    ? (liveActivities
                        ? 'On for your account'
                        : canEnableLiveActivities
                            ? 'Off for your account'
                            : 'Delivery is unavailable for this account')
                    : 'Preview starts 10 minutes before your routine',
                trailing: FardaYouSwitch(
                  key: FardaYouKeys.liveActivityToggle,
                  value: liveActivities,
                  onChanged: saving || !preferencesAvailable ||
                          (liveRecords && !liveActivities && !canEnableLiveActivities)
                      ? null : onLiveActivitiesChanged,
                  semanticLabel: 'Live Activities',
                ),
              ),
              FardaYouSettingRow(
                title: 'Private previews',
                subtitle: liveRecords
                    ? 'Sample Lock Screen only'
                    : 'Keep medication names off Lock Screens',
                trailing: FardaYouSwitch(
                  value: privatePreviews,
                  onChanged: onPrivatePreviewsChanged,
                  semanticLabel: 'Private Lock Screen previews',
                ),
              ),
              if (!liveRecords) FardaYouSettingRow(
                title: 'Call after $callDelayMinutes minutes',
                subtitle: 'Only if this routine is still unconfirmed',
                showDivider: false,
                trailing: TextButton(
                  onPressed: onEditDelay,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    foregroundColor: FardaYouPalette.navy,
                  ),
                  child: const Text('Edit'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        FardaYouCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const FardaYouIconTile(icon: Icons.bedtime_outlined),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Your quiet hours',
                          style: fardaYouText(
                            size: 16,
                            weight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          quietHoursLabel,
                          style: fardaYouText(
                            size: 22,
                            height: 27,
                            weight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                liveRecords
                    ? 'Saved quiet hours for your account. Change them in account settings.'
                    : 'Quiet hours shown for this local preview.',
                style: fardaYouText(
                  size: 12,
                  height: 18,
                  color: FardaYouPalette.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final stack = constraints.maxWidth < 390 ||
                MediaQuery.textScalerOf(context).scale(14) > 18;
            final live = FardaYouSecondaryButton(
              key: FardaYouKeys.liveActivityLink,
              label: 'Preview Lock Screen',
              icon: Icons.lock_outline_rounded,
              onPressed: onOpenLivePreview,
            );
            final call = FardaYouPrimaryButton(
              key: FardaYouKeys.callPreviewLink,
              label: 'Preview reminder call',
              icon: Icons.phone_outlined,
              onPressed: onOpenCallPreview,
            );
            if (stack) {
              return Column(
                children: [live, const SizedBox(height: 10), call],
              );
            }
            return Row(
              children: [
                Expanded(child: live),
                const SizedBox(width: 10),
                Expanded(child: call),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        const FardaYouNotice(
          text:
              'These are local interface previews. No number is contacted, no notification is scheduled, and answering a simulated call never confirms a dose.',
        ),
        if (showCompanion) ...[
          const SizedBox(height: 16),
          const Align(
            alignment: Alignment.centerRight,
            child: FardaCompanion(
              size: 74,
              mood: FardaCompanionMood.waving,
            ),
          ),
        ],
      ],
    );
  }
}

class FardaVialPage extends StatelessWidget {
  const FardaVialPage({
    super.key,
    required this.profileLabel,
    required this.showBrandHeader,
    required this.setupStep,
    required this.onBack,
    required this.onAdvanceSetup,
    required this.onOpenRoutine,
  });

  final String profileLabel;
  final bool showBrandHeader;
  final int setupStep;
  final VoidCallback onBack;
  final VoidCallback onAdvanceSetup;
  final VoidCallback onOpenRoutine;

  @override
  Widget build(BuildContext context) {
    final connected = setupStep >= 4;
    const steps = [
      ('Find your vial', 'Local discovery preview', Icons.search_rounded),
      ('Confirm the physical vial', 'Check the code on the vial', Icons.qr_code_rounded),
      ('Bind it to this profile', 'Ownership and recovery still need backend support', Icons.link_rounded),
      ('Calibrate and verify', 'Requires validated hardware instructions', Icons.tune_rounded),
    ];

    return FardaYouPageCanvas(
      children: [
        if (showBrandHeader) ...[
          FardaYouBrandHeader(profileLabel: profileLabel),
          const SizedBox(height: 8),
        ],
        FardaYouBackButton(onPressed: onBack),
        const SizedBox(height: 4),
        FardaYouPageHeader(
          eyebrow: 'Your Farda vial',
          title: connected ? 'A helpful little\nconnection.' : 'Good things\nare on the way.',
          supportingText: connected
              ? 'Sample connection complete. This is not a live hardware status.'
              : 'Your app is ready. Connect your vial when it arrives.',
        ),
        const SizedBox(height: 20),
        FardaYouCard(
          color: FardaYouPalette.paleBlue,
          borderColor: Colors.transparent,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 330;
              final art = Image.asset(
                'assets/images/vial_bottle.png',
                width: compact ? 88 : 112,
                height: compact ? 130 : 164,
                fit: BoxFit.contain,
                semanticLabel: 'Farda vial concept',
              );
              final copy = Column(
                crossAxisAlignment: compact
                    ? CrossAxisAlignment.center
                    : CrossAxisAlignment.start,
                children: [
                  Text(
                    connected
                        ? 'Connected in this preview.'
                        : 'A calmer routine,\nin your hands.',
                    textAlign: compact ? TextAlign.center : TextAlign.left,
                    style: fardaYouText(
                      size: 22,
                      height: 27,
                      weight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  FardaPreviewBadge(
                    label: connected ? 'Simulated connection' : 'Coming soon',
                  ),
                ],
              );
              if (compact) {
                return Column(children: [art, const SizedBox(height: 8), copy]);
              }
              return Row(
                children: [
                  art,
                  const SizedBox(width: 18),
                  Expanded(child: copy),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 14),
        FardaYouCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                connected ? 'Preview setup complete' : 'When your vial arrives',
                style: fardaYouText(
                  size: 18,
                  height: 23,
                  weight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              for (var index = 0; index < steps.length; index++)
                _VialStep(
                  title: steps[index].$1,
                  subtitle: steps[index].$2,
                  icon: steps[index].$3,
                  completed: setupStep > index,
                  current: setupStep == index && !connected,
                  showDivider: index < steps.length - 1,
                ),
              if (!connected) ...[
                const SizedBox(height: 14),
                FardaYouPrimaryButton(
                  label: 'Simulate next setup step',
                  onPressed: onAdvanceSetup,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        const FardaYouNotice(
          text:
              'A vial movement or weight change can prompt a check-in. It never proves ingestion and never creates a taken entry without your explicit confirmation.',
        ),
        const SizedBox(height: 12),
        FardaYouSecondaryButton(
          label: 'Explore your routine',
          icon: Icons.medication_outlined,
          onPressed: onOpenRoutine,
        ),
        const SizedBox(height: 14),
        FardaYouCard(
          color: FardaYouPalette.ivory,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hardware still to be verified',
                style: fardaYouText(
                  size: 15,
                  weight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Safe access, pairing, sensing, battery behavior, offline recovery, and sync durability require testing on the actual vial.',
                style: fardaYouText(
                  size: 12,
                  height: 18,
                  color: FardaYouPalette.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _VialStep extends StatelessWidget {
  const _VialStep({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.completed,
    required this.current,
    required this.showDivider,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool completed;
  final bool current;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Semantics(
          label:
              '$title. ${completed ? 'Completed in preview' : current ? 'Current preview step' : 'Not started'}',
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: completed
                        ? FardaYouPalette.navy
                        : current
                            ? FardaYouPalette.paleBlue
                            : FardaYouPalette.ivory,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: current
                          ? FardaYouPalette.blue
                          : Colors.transparent,
                    ),
                  ),
                  child: Icon(
                    completed ? Icons.check_rounded : icon,
                    color: completed
                        ? Colors.white
                        : FardaYouPalette.navy,
                    size: 21,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: fardaYouText(
                          size: 14,
                          height: 19,
                          weight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: fardaYouText(
                          size: 11,
                          height: 16,
                          color: FardaYouPalette.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (showDivider)
          const Divider(height: 1, color: FardaYouPalette.border),
      ],
    );
  }
}

class FardaCirclePage extends StatelessWidget {
  const FardaCirclePage({
    super.key,
    required this.profileLabel,
    required this.showBrandHeader,
    required this.showCompanion,
    required this.connected,
    required this.routineSummaries,
    required this.refillReminders,
    required this.missedConfirmation,
    required this.onBack,
    required this.onRoutineSummariesChanged,
    required this.onRefillRemindersChanged,
    required this.onMissedConfirmationChanged,
    required this.onInvite,
    required this.onRevoke,
  });

  final String profileLabel;
  final bool showBrandHeader;
  final bool showCompanion;
  final bool connected;
  final bool routineSummaries;
  final bool refillReminders;
  final bool missedConfirmation;
  final VoidCallback onBack;
  final ValueChanged<bool> onRoutineSummariesChanged;
  final ValueChanged<bool> onRefillRemindersChanged;
  final ValueChanged<bool> onMissedConfirmationChanged;
  final VoidCallback onInvite;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    return FardaYouPageCanvas(
      children: [
        if (showBrandHeader) ...[
          FardaYouBrandHeader(profileLabel: profileLabel),
          const SizedBox(height: 8),
        ],
        FardaYouBackButton(onPressed: onBack),
        const SizedBox(height: 4),
        const FardaYouPageHeader(
          eyebrow: 'Support that feels right',
          title: 'Your circle.\nYour choice.',
          supportingText:
              'Invite someone you trust, with clear choices about what they see.',
        ),
        const SizedBox(height: 20),
        FardaYouCard(
          color: FardaYouPalette.paleBlue,
          borderColor: Colors.transparent,
          child: Column(
            children: [
              if (showCompanion)
                const FardaCompanion(
                  size: 106,
                  mood: FardaCompanionMood.quiet,
                )
              else
                const FardaYouIconTile(
                  icon: Icons.people_outline_rounded,
                  size: 72,
                ),
              const SizedBox(height: 10),
              Text(
                connected
                    ? 'Sample supporter'
                    : 'A little support, on your terms.',
                textAlign: TextAlign.center,
                style: fardaYouText(
                  size: 18,
                  height: 23,
                  weight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                connected
                    ? 'Accepted in this local preview only.'
                    : 'Your circle is empty for now.',
                textAlign: TextAlign.center,
                style: fardaYouText(
                  size: 13,
                  height: 18,
                  color: FardaYouPalette.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        FardaYouCard(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Choose what you share',
                style: fardaYouText(
                  size: 18,
                  height: 23,
                  weight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              FardaYouSettingRow(
                title: 'Routine summaries',
                subtitle: 'Only entries you choose to share',
                trailing: FardaYouSwitch(
                  value: routineSummaries,
                  onChanged: onRoutineSummariesChanged,
                  semanticLabel: 'Share routine summaries',
                ),
              ),
              FardaYouSettingRow(
                title: 'Refill reminders',
                subtitle: 'Help planning the next refill',
                trailing: FardaYouSwitch(
                  value: refillReminders,
                  onChanged: onRefillRemindersChanged,
                  semanticLabel: 'Share refill reminders',
                ),
              ),
              FardaYouSettingRow(
                title: 'A missed confirmation',
                subtitle: 'A nudge only when you enable it',
                showDivider: false,
                trailing: FardaYouSwitch(
                  value: missedConfirmation,
                  onChanged: onMissedConfirmationChanged,
                  semanticLabel: 'Share missed confirmations',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (connected)
          FardaYouSecondaryButton(
            label: 'Remove sample access',
            icon: Icons.person_remove_outlined,
            foregroundColor: FardaYouPalette.danger,
            onPressed: onRevoke,
          )
        else
          FardaYouPrimaryButton(
            label: 'Preview an invitation',
            icon: Icons.person_add_alt_1_outlined,
            onPressed: onInvite,
          ),
        const SizedBox(height: 12),
        const FardaYouNotice(
          text:
              'Real invitations need a verified recipient, their acceptance, and explicit permissions. A supporter cannot control your medication or vial. This preview contacts no one.',
        ),
      ],
    );
  }
}

class FardaLiveActivityPreviewPage extends StatelessWidget {
  const FardaLiveActivityPreviewPage({
    super.key,
    required this.state,
    required this.privatePreviews,
    required this.expandedIsland,
    required this.callDelayMinutes,
    required this.medicationName,
    required this.onBack,
    required this.onStateChanged,
    required this.onIslandToggled,
    required this.onOpenRoutine,
    required this.onOpenReminderSettings,
    required this.onReviewEntry,
  });

  final FardaLivePreviewState state;
  final bool privatePreviews;
  final bool expandedIsland;
  final int callDelayMinutes;
  final String medicationName;
  final VoidCallback onBack;
  final ValueChanged<FardaLivePreviewState> onStateChanged;
  final VoidCallback onIslandToggled;
  final VoidCallback onOpenRoutine;
  final VoidCallback onOpenReminderSettings;
  final VoidCallback onReviewEntry;

  @override
  Widget build(BuildContext context) {
    final copy = _liveCopy(state, callDelayMinutes);
    final clock = state == FardaLivePreviewState.before ? '8:50' : '9:00';
    final chips = <(FardaLivePreviewState, String)>[
      (FardaLivePreviewState.before, '10 min before'),
      (FardaLivePreviewState.due, 'Due'),
      (FardaLivePreviewState.snoozed, 'Snoozed'),
      (FardaLivePreviewState.stale, 'Stale'),
      (FardaLivePreviewState.off, 'Off'),
    ];

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF476DA4), Color(0xFF203D69), Color(0xFF102449)],
          stops: [0, 0.52, 1],
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 34),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextButton.icon(
                  onPressed: onBack,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    minimumSize: const Size(48, 48),
                    padding: EdgeInsets.zero,
                  ),
                  icon: const Icon(Icons.arrow_back_rounded, size: 20),
                  label: const Text('Reminder settings'),
                ),
                const SizedBox(height: 4),
                Center(
                  child: Column(
                    children: [
                      const Icon(
                        Icons.lock_outline_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Wednesday, October 14',
                        style: fardaYouText(size: 15, color: Colors.white),
                      ),
                      Text(
                        clock,
                        style: fardaYouText(
                          size: 68,
                          height: 76,
                          weight: FontWeight.w600,
                          color: Colors.white,
                          letterSpacing: -2,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                FardaYouCard(
                  radius: 26,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'farda.',
                              style: fardaYouText(
                                size: 24,
                                weight: FontWeight.w600,
                                letterSpacing: -1.2,
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.lock_outline_rounded,
                            size: 15,
                            color: FardaYouPalette.textSecondary,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'Private preview',
                            style: fardaYouText(
                              size: 11,
                              color: FardaYouPalette.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        copy.$1,
                        style: fardaYouText(
                          size: 26,
                          height: 31,
                          weight: FontWeight.w600,
                          letterSpacing: -0.45,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        '${privatePreviews ? '' : '$medicationName · '}${copy.$2}',
                        style: fardaYouText(
                          size: 14,
                          height: 20,
                          color: FardaYouPalette.textSecondary,
                        ),
                      ),
                      if (state == FardaLivePreviewState.before ||
                          state == FardaLivePreviewState.due) ...[
                        const SizedBox(height: 17),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                state == FardaLivePreviewState.before
                                    ? '10:00'
                                    : 'Now',
                                style: fardaYouText(
                                  size: 31,
                                  height: 35,
                                  weight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Text(
                              state == FardaLivePreviewState.before
                                  ? 'Until your routine'
                                  : 'Call preview at 9:${callDelayMinutes.toString().padLeft(2, '0')}',
                              textAlign: TextAlign.right,
                              style: fardaYouText(
                                size: 12,
                                height: 17,
                                color: FardaYouPalette.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 16),
                      _LiveAction(
                        state: state,
                        onOpenRoutine: onOpenRoutine,
                        onOpenSettings: onOpenReminderSettings,
                        onReviewEntry: onReviewEntry,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Center(
                  child: Text(
                    state == FardaLivePreviewState.off
                        ? 'Fallback notification concept · No Live Activity is scheduled.'
                        : 'Illustrative Lock Screen · No timer or notification is running.',
                    textAlign: TextAlign.center,
                    style: fardaYouText(
                      size: 11,
                      height: 16,
                      color: Colors.white.withValues(alpha: 0.76),
                    ),
                  ),
                ),
                if (state != FardaLivePreviewState.off) ...[
                  const SizedBox(height: 18),
                  _DynamicIslandPreview(
                    state: state,
                    expanded: expandedIsland,
                    caption: copy.$2,
                    onToggle: onIslandToggled,
                  ),
                ],
                const SizedBox(height: 18),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final chip in chips)
                      Semantics(
                        button: true,
                        selected: state == chip.$1,
                        child: ChoiceChip(
                          label: Text(chip.$2),
                          selected: state == chip.$1,
                          showCheckmark: false,
                          onSelected: (_) => onStateChanged(chip.$1),
                          backgroundColor: Colors.white.withValues(alpha: 0.11),
                          selectedColor: Colors.white,
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.25),
                          ),
                          labelStyle: fardaYouText(
                            size: 11,
                            weight: FontWeight.w500,
                            color: state == chip.$1
                                ? FardaYouPalette.navy
                                : Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                FardaReminderCadence(
                  callDelayMinutes: callDelayMinutes,
                  activeIndex: switch (state) {
                    FardaLivePreviewState.before => 0,
                    FardaLivePreviewState.due => 1,
                    _ => 2,
                  },
                  onStepPressed: (index) {
                    onStateChanged(
                      switch (index) {
                        0 => FardaLivePreviewState.before,
                        1 => FardaLivePreviewState.due,
                        _ => FardaLivePreviewState.due,
                      },
                    );
                  },
                  onDark: true,
                ),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    '8:50 heads-up → 9:00 routine → 9:${callDelayMinutes.toString().padLeft(2, '0')} optional call.\nTapping a preview never changes your routine record.',
                    textAlign: TextAlign.center,
                    style: fardaYouText(
                      size: 11,
                      height: 16,
                      color: Colors.white.withValues(alpha: 0.78),
                    ),
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

(String, String) _liveCopy(
  FardaLivePreviewState state,
  int callDelayMinutes,
) {
  return switch (state) {
    FardaLivePreviewState.before => (
        'A little heads-up.',
        'Your morning routine starts in 10 minutes.',
      ),
    FardaLivePreviewState.due => (
        'Your routine is ready.',
        '9:00 AM · Your active reminder.',
      ),
    FardaLivePreviewState.snoozed => (
        'A little breathing room.',
        'Reminder snoozed · 15 minutes.',
      ),
    FardaLivePreviewState.stale => (
        'Open Farda to check.',
        'This preview is out of date.',
      ),
    FardaLivePreviewState.confirmed => (
        'Your entry is saved.',
        'Confirmed by you · Ending activity.',
      ),
    FardaLivePreviewState.off => (
        'Regular reminders still work.',
        'Live Activities are turned off.',
      ),
  };
}

class _LiveAction extends StatelessWidget {
  const _LiveAction({
    required this.state,
    required this.onOpenRoutine,
    required this.onOpenSettings,
    required this.onReviewEntry,
  });

  final FardaLivePreviewState state;
  final VoidCallback onOpenRoutine;
  final VoidCallback onOpenSettings;
  final VoidCallback onReviewEntry;

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      FardaLivePreviewState.before => FardaYouPrimaryButton(
          label: 'View my routine',
          onPressed: onOpenRoutine,
        ),
      FardaLivePreviewState.due => FardaYouPrimaryButton(
          label: 'Open & review an entry',
          icon: Icons.check_rounded,
          onPressed: onReviewEntry,
        ),
      FardaLivePreviewState.off => FardaYouSecondaryButton(
          label: 'Open reminder settings',
          onPressed: onOpenSettings,
        ),
      FardaLivePreviewState.confirmed => FardaYouSecondaryButton(
          label: 'View my routine',
          onPressed: onOpenRoutine,
        ),
      FardaLivePreviewState.stale => FardaYouSecondaryButton(
          label: 'Open Farda settings',
          onPressed: onOpenSettings,
        ),
      FardaLivePreviewState.snoozed => const FardaPreviewBadge(
          label: 'No entry was added',
        ),
    };
  }
}

class _DynamicIslandPreview extends StatelessWidget {
  const _DynamicIslandPreview({
    required this.state,
    required this.expanded,
    required this.caption,
    required this.onToggle,
  });

  final FardaLivePreviewState state;
  final bool expanded;
  final String caption;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final status = state == FardaLivePreviewState.stale
        ? 'Check Farda'
        : state == FardaLivePreviewState.confirmed
            ? 'Entry saved'
            : 'Your routine';
    final time = state == FardaLivePreviewState.before
        ? '10:00'
        : state == FardaLivePreviewState.snoozed
            ? '15 min'
            : 'Now';
    return Center(
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: expanded ? 340 : 280,
            constraints: const BoxConstraints(maxWidth: double.infinity),
            padding: EdgeInsets.symmetric(
              horizontal: expanded ? 20 : 16,
              vertical: expanded ? 18 : 12,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFF07111F),
              borderRadius: BorderRadius.circular(expanded ? 30 : 24),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'f.',
                      style: fardaYouText(
                        size: 21,
                        weight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        status,
                        style: fardaYouText(size: 13, color: Colors.white),
                      ),
                    ),
                    Text(
                      time,
                      style: fardaYouText(
                        size: 14,
                        weight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                if (expanded) ...[
                  const SizedBox(height: 12),
                  Text(
                    caption,
                    style: fardaYouText(
                      size: 12,
                      height: 17,
                      color: Colors.white.withValues(alpha: 0.75),
                    ),
                  ),
                ],
              ],
            ),
          ),
          TextButton(
            onPressed: onToggle,
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              minimumSize: const Size(48, 48),
            ),
            child: Text(
              expanded ? 'Show compact Island' : 'Show expanded Island',
            ),
          ),
        ],
      ),
    );
  }
}

class FardaCallPreviewPage extends StatelessWidget {
  const FardaCallPreviewPage({
    super.key,
    required this.stage,
    required this.callDelayMinutes,
    required this.callRemindersEnabled,
    required this.entryConfirmed,
    required this.onBack,
    required this.onAnswer,
    required this.onDecline,
    required this.onPrivateCheckIn,
    required this.onReviewEntry,
    required this.onConfirmEntry,
    required this.onSnooze,
    required this.onEnd,
    required this.onStopCalls,
  });

  final FardaCallPreviewStage stage;
  final int callDelayMinutes;
  final bool callRemindersEnabled;
  final bool entryConfirmed;
  final VoidCallback onBack;
  final VoidCallback onAnswer;
  final VoidCallback onDecline;
  final VoidCallback onPrivateCheckIn;
  final VoidCallback onReviewEntry;
  final VoidCallback onConfirmEntry;
  final VoidCallback onSnooze;
  final VoidCallback onEnd;
  final VoidCallback onStopCalls;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF284E83), Color(0xFF142C55), Color(0xFF091831)],
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 8, 22, 30),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520, minHeight: 700),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: onBack,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      minimumSize: const Size(48, 48),
                      padding: EdgeInsets.zero,
                    ),
                    icon: const Icon(Icons.arrow_back_rounded, size: 20),
                    label: const Text('Reminder settings'),
                  ),
                ),
                const SizedBox(height: 6),
                const FardaPreviewBadge(
                  label: 'Local simulation · no call is placed',
                  onDark: true,
                ),
                const SizedBox(height: 24),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: _CallStageContent(
                    key: ValueKey(stage),
                    stage: stage,
                    callDelayMinutes: callDelayMinutes,
                    callRemindersEnabled: callRemindersEnabled,
                    entryConfirmed: entryConfirmed,
                    onAnswer: onAnswer,
                    onDecline: onDecline,
                    onPrivateCheckIn: onPrivateCheckIn,
                    onReviewEntry: onReviewEntry,
                    onConfirmEntry: onConfirmEntry,
                    onSnooze: onSnooze,
                    onEnd: onEnd,
                    onStopCalls: onStopCalls,
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

class _CallStageContent extends StatelessWidget {
  const _CallStageContent({
    super.key,
    required this.stage,
    required this.callDelayMinutes,
    required this.callRemindersEnabled,
    required this.entryConfirmed,
    required this.onAnswer,
    required this.onDecline,
    required this.onPrivateCheckIn,
    required this.onReviewEntry,
    required this.onConfirmEntry,
    required this.onSnooze,
    required this.onEnd,
    required this.onStopCalls,
  });

  final FardaCallPreviewStage stage;
  final int callDelayMinutes;
  final bool callRemindersEnabled;
  final bool entryConfirmed;
  final VoidCallback onAnswer;
  final VoidCallback onDecline;
  final VoidCallback onPrivateCheckIn;
  final VoidCallback onReviewEntry;
  final VoidCallback onConfirmEntry;
  final VoidCallback onSnooze;
  final VoidCallback onEnd;
  final VoidCallback onStopCalls;

  @override
  Widget build(BuildContext context) {
    return switch (stage) {
      FardaCallPreviewStage.ringing => _RingingCall(
          onAnswer: onAnswer,
          onDecline: onDecline,
        ),
      FardaCallPreviewStage.answered => _AnsweredCall(
          callDelayMinutes: callDelayMinutes,
          callRemindersEnabled: callRemindersEnabled,
          onPrivateCheckIn: onPrivateCheckIn,
          onEnd: onEnd,
          onStopCalls: onStopCalls,
        ),
      FardaCallPreviewStage.checkIn => _CallCheckIn(
          onReviewEntry: onReviewEntry,
          onSnooze: onSnooze,
          onEnd: onEnd,
        ),
      FardaCallPreviewStage.confirm => _CallConfirm(
          onConfirmEntry: onConfirmEntry,
          onEnd: onEnd,
        ),
      FardaCallPreviewStage.ended => _CallEnded(
          entryConfirmed: entryConfirmed,
        ),
    };
  }
}

class _RingingCall extends StatelessWidget {
  const _RingingCall({required this.onAnswer, required this.onDecline});

  final VoidCallback onAnswer;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'INCOMING CALL · ILLUSTRATIVE SYSTEM UI',
          textAlign: TextAlign.center,
          style: fardaYouText(
            size: 10,
            weight: FontWeight.w600,
            color: Colors.white.withValues(alpha: 0.78),
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 22),
        const FardaCompanion(
          size: 142,
          mood: FardaCompanionMood.waving,
        ),
        const SizedBox(height: 10),
        Text(
          'Farda',
          style: fardaYouText(
            size: 42,
            height: 48,
            weight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        Text(
          'A gentle ring. Just for you.',
          style: fardaYouText(
            size: 16,
            height: 22,
            color: Colors.white.withValues(alpha: 0.8),
          ),
        ),
        const SizedBox(height: 34),
        FardaYouCard(
          color: Colors.white.withValues(alpha: 0.1),
          borderColor: Colors.white.withValues(alpha: 0.15),
          child: Text(
            'Caller name and appearance depend on your phone, carrier, and caller-branding support.',
            textAlign: TextAlign.center,
            style: fardaYouText(
              size: 13,
              height: 19,
              color: Colors.white.withValues(alpha: 0.82),
            ),
          ),
        ),
        const SizedBox(height: 42),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _RoundCallButton(
              label: 'Decline',
              icon: Icons.call_end_rounded,
              color: const Color(0xFFB95160),
              onPressed: onDecline,
            ),
            _RoundCallButton(
              label: 'Answer demo',
              icon: Icons.phone_rounded,
              color: const Color(0xFFADC8ED),
              foreground: FardaYouPalette.navy,
              onPressed: onAnswer,
            ),
          ],
        ),
      ],
    );
  }
}

class _RoundCallButton extends StatelessWidget {
  const _RoundCallButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
    this.foreground = Colors.white,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: InkResponse(
        onTap: onPressed,
        radius: 55,
        child: SizedBox(
          width: 108,
          child: Column(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: Icon(icon, color: foreground, size: 29),
              ),
              const SizedBox(height: 10),
              Text(
                label,
                textAlign: TextAlign.center,
                style: fardaYouText(size: 13, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnsweredCall extends StatelessWidget {
  const _AnsweredCall({
    required this.callDelayMinutes,
    required this.callRemindersEnabled,
    required this.onPrivateCheckIn,
    required this.onEnd,
    required this.onStopCalls,
  });

  final int callDelayMinutes;
  final bool callRemindersEnabled;
  final VoidCallback onPrivateCheckIn;
  final VoidCallback onEnd;
  final VoidCallback onStopCalls;

  @override
  Widget build(BuildContext context) {
    return _CallScriptLayout(
      eyebrow: 'CONNECTED · AUTOMATED PREVIEW · 9:${callDelayMinutes.toString().padLeft(2, '0')}',
      title: 'A friendly\nreminder.',
      script:
          '“Hi, this is the Farda reminder you asked to preview. Your routine is ready when you are. Open Farda to check in.”',
      note:
          'No medication name is spoken. Answering does not change your record.${callRemindersEnabled ? '' : ' Call reminders remain off.'}',
      actions: [
        FardaYouPrimaryButton(
          label: '1 · Optional private check-in',
          onPressed: onPrivateCheckIn,
          backgroundColor: Colors.white,
          foregroundColor: FardaYouPalette.navy,
        ),
        FardaYouSecondaryButton(
          label: 'End reminder preview',
          foregroundColor: Colors.white,
          onPressed: onEnd,
        ),
        FardaYouSecondaryButton(
          label: '9 · Stop reminder calls',
          foregroundColor: Colors.white,
          onPressed: onStopCalls,
        ),
      ],
    );
  }
}

class _CallCheckIn extends StatelessWidget {
  const _CallCheckIn({
    required this.onReviewEntry,
    required this.onSnooze,
    required this.onEnd,
  });

  final VoidCallback onReviewEntry;
  final VoidCallback onSnooze;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    return _CallScriptLayout(
      eyebrow: 'PRIVATE CHECK-IN · PREVIEW ONLY',
      title: 'Your record.\nYour choice.',
      script:
          '“If you already took your morning dose, choose review entry. Nothing is saved until you confirm one more time.”',
      note:
          'This is a front-end simulation. Identity verification and secure phone input are not implemented.',
      actions: [
        FardaYouPrimaryButton(
          label: '1 · Review a self-reported entry',
          onPressed: onReviewEntry,
          backgroundColor: Colors.white,
          foregroundColor: FardaYouPalette.navy,
        ),
        FardaYouSecondaryButton(
          label: '2 · Remind me in 15 minutes',
          foregroundColor: Colors.white,
          onPressed: onSnooze,
        ),
        FardaYouSecondaryButton(
          label: 'End without saving',
          foregroundColor: Colors.white,
          onPressed: onEnd,
        ),
      ],
    );
  }
}

class _CallConfirm extends StatelessWidget {
  const _CallConfirm({
    required this.onConfirmEntry,
    required this.onEnd,
  });

  final VoidCallback onConfirmEntry;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    return _CallScriptLayout(
      eyebrow: 'ONE FINAL CHECK',
      title: 'Save that to\nyour record?',
      script:
          '“Confirm only if you already took it. This saves your own report; it is not proof of ingestion.”',
      note:
          'A call connection, answer, or vial movement never creates a taken entry.',
      actions: [
        FardaYouPrimaryButton(
          key: FardaYouKeys.confirmSampleEntry,
          label: 'Confirm my self-reported entry',
          icon: Icons.check_rounded,
          onPressed: onConfirmEntry,
          backgroundColor: Colors.white,
          foregroundColor: FardaYouPalette.navy,
        ),
        FardaYouSecondaryButton(
          label: 'End without saving',
          foregroundColor: Colors.white,
          onPressed: onEnd,
        ),
      ],
    );
  }
}

class _CallEnded extends StatelessWidget {
  const _CallEnded({required this.entryConfirmed});

  final bool entryConfirmed;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'CALL PREVIEW ENDED',
          style: fardaYouText(
            size: 10,
            weight: FontWeight.w600,
            color: Colors.white.withValues(alpha: 0.75),
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 22),
        const FardaCompanion(
          size: 124,
          mood: FardaCompanionMood.quiet,
        ),
        const SizedBox(height: 14),
        Text(
          entryConfirmed ? 'Your sample entry\nis confirmed.' : 'Your day.\nYour pace.',
          textAlign: TextAlign.center,
          style: fardaYouText(
            size: 34,
            height: 39,
            weight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          entryConfirmed
              ? 'Saved only in this local screen state. No health record or backend was changed.'
              : 'No routine entry was added or changed.',
          textAlign: TextAlign.center,
          style: fardaYouText(
            size: 14,
            height: 20,
            color: Colors.white.withValues(alpha: 0.78),
          ),
        ),
        const SizedBox(height: 24),
        FardaYouCard(
          color: Colors.white.withValues(alpha: 0.1),
          borderColor: Colors.white.withValues(alpha: 0.15),
          child: Text(
            'Voicemail is off by default. If separately enabled later, it should say only: “This is Farda. Please open your app when convenient.”',
            textAlign: TextAlign.center,
            style: fardaYouText(
              size: 12,
              height: 18,
              color: Colors.white.withValues(alpha: 0.82),
            ),
          ),
        ),
      ],
    );
  }
}

class _CallScriptLayout extends StatelessWidget {
  const _CallScriptLayout({
    required this.eyebrow,
    required this.title,
    required this.script,
    required this.note,
    required this.actions,
  });

  final String eyebrow;
  final String title;
  final String script;
  final String note;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          eyebrow,
          textAlign: TextAlign.center,
          style: fardaYouText(
            size: 10,
            weight: FontWeight.w600,
            color: Colors.white.withValues(alpha: 0.76),
            letterSpacing: 1.05,
          ),
        ),
        const SizedBox(height: 24),
        const FardaCompanion(
          size: 94,
          mood: FardaCompanionMood.quiet,
        ),
        const SizedBox(height: 12),
        Text(
          title,
          textAlign: TextAlign.center,
          style: fardaYouText(
            size: 34,
            height: 39,
            weight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 20),
        FardaYouCard(
          color: Colors.white.withValues(alpha: 0.1),
          borderColor: Colors.white.withValues(alpha: 0.15),
          child: Column(
            children: [
              Text(
                script,
                textAlign: TextAlign.center,
                style: fardaYouText(
                  size: 17,
                  height: 25,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                note,
                textAlign: TextAlign.center,
                style: fardaYouText(
                  size: 12,
                  height: 18,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        for (var index = 0; index < actions.length; index++) ...[
          actions[index],
          if (index < actions.length - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

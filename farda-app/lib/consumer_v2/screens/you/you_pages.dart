import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../design_system/farda_consumer_tokens.dart' as design;
import '../../design_system/farda_scene.dart';
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
          const SizedBox(height: 16),
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            final compact =
                constraints.maxWidth < 340 ||
                MediaQuery.textScalerOf(context).scale(14) > 18;
            return FardaSceneCard(
              scene: FardaScene.you,
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 98),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'YOUR SPACE',
                            style: fardaYouText(
                              size: 10,
                              height: 14,
                              weight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Semantics(
                            header: true,
                            child: Text(
                              'A little\nmore you.',
                              style: fardaYouText(
                                size: compact ? 28 : 32,
                                height: compact ? 32 : 35,
                                weight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (showCompanion && !compact) ...[
                      const SizedBox(width: 10),
                      Container(
                        width: 98,
                        height: 98,
                        decoration: const BoxDecoration(
                          color: FardaYouPalette.ivory,
                          shape: BoxShape.circle,
                        ),
                        child: const design.FardaCompanion(
                          size: 98,
                          pose: design.FardaCompanionPose.quiet,
                          floating: true,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        FardaYouCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              FardaYouLinkRow(
                key: FardaYouKeys.routineLink,
                title: 'Your routine',
                subtitle: 'Medications & reminder times',
                vectorIcon: 'icon-pill',
                onTap: () => onDestinationSelected(FardaYouDestination.routine),
              ),
              const SizedBox(height: 16),
              FardaYouLinkRow(
                key: FardaYouKeys.remindersLink,
                title: 'Reminders that reach you',
                subtitle: 'Live Activities & calls',
                vectorIcon: 'icon-bell',
                onTap:
                    () => onDestinationSelected(FardaYouDestination.reminders),
              ),
              const SizedBox(height: 16),
              FardaYouLinkRow(
                key: FardaYouKeys.vialLink,
                title: 'Your vial',
                subtitle: 'Vial preview',
                vectorIcon: 'icon-vial',
                preview: true,
                onTap: () => onDestinationSelected(FardaYouDestination.vial),
              ),
              const SizedBox(height: 16),
              FardaYouLinkRow(
                key: FardaYouKeys.circleLink,
                title: 'Your circle',
                subtitle: 'Sharing preview',
                vectorIcon: 'icon-circle',
                preview: true,
                onTap: () => onDestinationSelected(FardaYouDestination.circle),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        FardaYouCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              FardaYouSettingRow(
                title: 'A friendly face',
                subtitle: 'Companion preview',
                compact: true,
                showDivider: false,
                trailing: FardaYouSwitch(
                  key: FardaYouKeys.companionToggle,
                  value: showCompanion,
                  onChanged: onCompanionChanged,
                  semanticLabel: 'Show the Farda companion',
                ),
              ),
              const SizedBox(height: 16),
              FardaYouSettingRow(
                title: 'Quiet on your lock screen',
                subtitle: 'Privacy preview · hide names',
                compact: true,
                showDivider: false,
                trailing: FardaYouSwitch(
                  key: FardaYouKeys.privacyToggle,
                  value: privatePreviews,
                  onChanged: onPrivatePreviewsChanged,
                  semanticLabel:
                      'Hide medication names in the local Lock Screen preview',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const FardaYouNotice(text: 'Your routine. Your choices.'),
        const SizedBox(height: 48),
        TextButton(
          onPressed: onPrivacyPressed,
          child: Text(
            liveRecords ? 'How previews use data' : 'Preview privacy details',
          ),
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
    this.onAddPrescription,
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
  final VoidCallback? onAddPrescription;

  @override
  Widget build(BuildContext context) {
    return FardaYouPageCanvas(
      children: [
        if (showBrandHeader) ...[
          FardaYouBrandHeader(profileLabel: profileLabel),
          const SizedBox(height: 16),
        ],
        const FardaYouPageHeader(
          eyebrow: 'Make it yours',
          title: 'Your routine.',
          supportingText: 'Your reminder times. Your reviewed directions.',
        ),
        const SizedBox(height: 16),
        if (liveRecords && !hasRoutine) ...[
          const FardaYouNotice(
            text:
                'No medication is saved yet. Start with your prescription label.',
          ),
          const SizedBox(height: 12),
          FardaYouSecondaryButton(
            label:
                onAddPrescription == null
                    ? 'Open account settings'
                    : 'Add medication',
            icon: Icons.add_rounded,
            onPressed: onAddPrescription ?? onEditRoutine,
          ),
        ] else ...[
          FardaYouCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final badgeBelow =
                        constraints.maxWidth < 280 ||
                        MediaQuery.textScalerOf(context).scale(14) > 18;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const FardaYouIconTile(
                              vectorIcon: 'icon-pill',
                              size: 40,
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
                            if (labelReviewed && !badgeBelow)
                              const FardaPreviewBadge(label: 'Label reviewed'),
                          ],
                        ),
                        if (labelReviewed && badgeBelow) ...[
                          const SizedBox(height: 12),
                          const FardaPreviewBadge(label: 'Label reviewed'),
                        ],
                      ],
                    );
                  },
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
          if (!liveRecords)
            FardaYouCard(
              child: Row(
                children: [
                  const FardaYouIconTile(vectorIcon: 'icon-pill', size: 40),
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
            FardaYouNotice(
              text:
                  '$additionalRoutineCount more routine(s) are saved. Open account settings to review them.',
            ),
            const SizedBox(height: 12),
          ],
          FardaYouSecondaryButton(
            label:
                labelReviewed
                    ? 'Review label confirmation'
                    : liveRecords
                    ? 'Review in account settings'
                    : 'Review a prescription label',
            icon: Icons.document_scanner_outlined,
            onPressed: onReviewLabel,
          ),
          const SizedBox(height: 16),
          const FardaYouNotice(
            text: 'Check scanned directions against your label or pharmacy.',
          ),
        ],
        if (liveRecords && hasRoutine && onAddPrescription != null) ...[
          const SizedBox(height: 16),
          FardaYouSecondaryButton(
            label: 'Add medication',
            icon: Icons.add_rounded,
            onPressed: onAddPrescription!,
          ),
        ],
        if (showCompanion) ...[
          const SizedBox(height: 18),
          Row(
            children: [
              const design.FardaCompanion(
                size: 90,
                pose: design.FardaCompanionPose.calendar,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Travel plans?',
                      style: fardaYouText(size: 14, weight: FontWeight.w600),
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
        FardaYouBackButton(onPressed: onBack),
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
    this.quietHoursTimeZone = '',
    this.onEditQuietHours,
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
  final String quietHoursTimeZone;
  final VoidCallback? onEditQuietHours;

  @override
  Widget build(BuildContext context) {
    return FardaYouPageCanvas(
      children: [
        if (showBrandHeader) ...[
          FardaYouBrandHeader(profileLabel: profileLabel),
          const SizedBox(height: 16),
        ],
        FardaYouPageHeader(
          eyebrow: 'Choose your rhythm',
          title: 'Reminders, your way.',
          supportingText: 'A heads-up. A call, if you choose.',
        ),
        const SizedBox(height: 16),
        _FardaRhythmCard(
          liveRecords: liveRecords,
          callDelayMinutes: callDelayMinutes,
        ),
        const SizedBox(height: 16),
        FardaYouCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              FardaYouSettingRow(
                title: 'Call reminders',
                subtitle:
                    liveRecords
                        ? (preferencesAvailable
                            ? (callReminders
                                ? 'On · 10 minutes after your routine'
                                : canEnableCalls
                                ? 'Off · 10 minutes after your routine'
                                : 'Verify your phone in account settings')
                            : 'Preferences unavailable; refresh your account')
                        : '10 minutes after your routine',
                compact: true,
                showDivider: false,
                trailing: FardaYouSwitch(
                  key: FardaYouKeys.callToggle,
                  value: callReminders,
                  onChanged:
                      saving ||
                              !preferencesAvailable ||
                              (liveRecords && !callReminders && !canEnableCalls)
                          ? null
                          : onCallRemindersChanged,
                  semanticLabel: 'Phone-call reminders',
                ),
              ),
              const SizedBox(height: 16),
              FardaYouSettingRow(
                title: 'Live Activities',
                subtitle:
                    liveRecords
                        ? (liveActivities
                            ? 'On · 10 minutes before your routine'
                            : canEnableLiveActivities
                            ? 'Off · 10 minutes before your routine'
                            : 'Delivery is unavailable for this account')
                        : '10 minutes before your routine',
                compact: true,
                showDivider: false,
                trailing: FardaYouSwitch(
                  key: FardaYouKeys.liveActivityToggle,
                  value: liveActivities,
                  onChanged:
                      saving ||
                              !preferencesAvailable ||
                              (liveRecords &&
                                  !liveActivities &&
                                  !canEnableLiveActivities)
                          ? null
                          : onLiveActivitiesChanged,
                  semanticLabel: 'Live Activities',
                ),
              ),
              const SizedBox(height: 16),
              FardaYouSettingRow(
                title: 'Private previews',
                subtitle: 'Hide names in this preview only',
                compact: true,
                showDivider: false,
                trailing: FardaYouSwitch(
                  value: privatePreviews,
                  onChanged: onPrivatePreviewsChanged,
                  semanticLabel: 'Private local Lock Screen preview',
                ),
              ),
              if (!liveRecords) ...[
                const SizedBox(height: 16),
                FardaYouSettingRow(
                  title: 'Call after $callDelayMinutes minutes',
                  subtitle: 'Only if this routine is still unconfirmed',
                  showDivider: false,
                  compact: true,
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
            ],
          ),
        ),
        const SizedBox(height: 16),
        FardaYouCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your quiet hours',
                style: fardaYouText(
                  size: 18,
                  height: 24,
                  weight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                quietHoursLabel,
                style: fardaYouText(
                  size: 26,
                  height: 30,
                  weight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                liveRecords
                    ? (preferencesAvailable
                        ? 'Calls wait during quiet hours · $quietHoursTimeZone'
                        : 'Preferences unavailable; refresh your account')
                    : 'Calls wait during quiet hours.',
                style: fardaYouText(
                  size: 12,
                  height: 17,
                  color: FardaYouPalette.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  TextButton(
                    key: FardaYouKeys.callPreviewLink,
                    onPressed: onOpenCallPreview,
                    child: const Text('Preview the reminder call ›'),
                  ),
                  if (liveRecords && onEditQuietHours != null)
                    TextButton(
                      key: FardaYouKeys.quietHoursEdit,
                      onPressed:
                          saving || !preferencesAvailable
                              ? null
                              : onEditQuietHours,
                      child: const Text('Edit quiet hours'),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const FardaYouNotice(
          text: 'Calls are optional. Answering does not confirm a dose.',
        ),
        FardaYouBackButton(onPressed: onBack),
        FardaYouSecondaryButton(
          key: FardaYouKeys.liveActivityLink,
          label: 'Preview Lock Screen',
          icon: Icons.lock_outline_rounded,
          onPressed: onOpenLivePreview,
        ),
      ],
    );
  }
}

class _FardaRhythmCard extends StatelessWidget {
  const _FardaRhythmCard({
    required this.liveRecords,
    required this.callDelayMinutes,
  });

  final bool liveRecords;
  final int callDelayMinutes;

  @override
  Widget build(BuildContext context) {
    final milestones =
        liveRecords
            ? const [
              ('−10m', 'Live Activity'),
              ('Due', 'Routine due'),
              ('+10m', 'Call reminder'),
            ]
            : [
              ('8:50', 'Live Activity'),
              ('9:00', 'Routine due'),
              (
                '9:${callDelayMinutes.toString().padLeft(2, '0')}',
                'Call reminder',
              ),
            ];
    return FardaYouCard(
      color: FardaYouPalette.navy,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'YOUR REMINDER RHYTHM',
            style: fardaYouText(
              size: 10,
              height: 14,
              weight: FontWeight.w600,
              color: FardaYouPalette.ivory,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final milestone in milestones)
                Expanded(
                  child: Column(
                    children: [
                      const CircleAvatar(
                        radius: 4,
                        backgroundColor: FardaYouPalette.ivory,
                      ),
                      const SizedBox(height: 5),
                      Text(
                        milestone.$1,
                        style: fardaYouText(
                          size: 22,
                          height: 29,
                          weight: FontWeight.w600,
                          color: FardaYouPalette.ivory,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        milestone.$2,
                        textAlign: TextAlign.center,
                        style: fardaYouText(
                          size: 10,
                          height: 14,
                          color: FardaYouPalette.ivory,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Calls are optional',
            style: fardaYouText(
              size: 10,
              height: 14,
              color: FardaYouPalette.ivory,
            ),
          ),
        ],
      ),
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
    final connected = setupStep >= 3;
    const steps = [
      ('Pair your vial', 'Preview the Bluetooth setup', 'icon-vial'),
      (
        'Match the right medication',
        'Check the label before loading',
        'icon-pill',
      ),
      ('Set your routine', 'Review times and reminders', 'icon-clock'),
    ];

    return FardaYouPageCanvas(
      children: [
        if (showBrandHeader) ...[
          FardaYouBrandHeader(profileLabel: profileLabel),
          const SizedBox(height: 16),
        ],
        FardaYouPageHeader(
          eyebrow: 'Vial preview',
          title: 'Meet your vial.',
          supportingText: 'A local preview. No device connects.',
        ),
        const SizedBox(height: 16),
        FardaYouCard(
          color: FardaYouPalette.navy,
          padding: const EdgeInsets.all(22),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact =
                  constraints.maxWidth < 280 ||
                  MediaQuery.textScalerOf(context).scale(14) > 18;
              final art = Semantics(
                label: 'Farda vial concept preview',
                child: SvgPicture.asset(
                  'assets/figma/vial.svg',
                  width: 90,
                  height: 140,
                ),
              );
              final copy = Column(
                crossAxisAlignment:
                    compact
                        ? CrossAxisAlignment.center
                        : CrossAxisAlignment.start,
                children: [
                  Text(
                    'A calmer\nroutine,\nin your hands.',
                    textAlign: compact ? TextAlign.center : TextAlign.left,
                    style: fardaYouText(
                      size: 22,
                      height: 28,
                      weight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  FardaPreviewBadge(label: 'Preview', onDark: true),
                ],
              );
              if (compact) {
                return Column(children: [art, const SizedBox(height: 8), copy]);
              }
              return ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 165),
                child: Row(
                  children: [
                    art,
                    const SizedBox(width: 20),
                    Expanded(child: copy),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        FardaYouCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                connected ? 'Preview setup complete' : 'Explore the setup',
                style: fardaYouText(
                  size: 18,
                  height: 23,
                  weight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              for (var index = 0; index < steps.length; index++)
                _VialStep(
                  title: steps[index].$1,
                  subtitle: steps[index].$2,
                  vectorIcon: steps[index].$3,
                  completed: setupStep > index,
                  current: setupStep == index && !connected,
                  showDivider: false,
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        FardaYouPrimaryButton(
          label: 'Explore your routine',
          onPressed: onOpenRoutine,
        ),
        const SizedBox(height: 16),
        const FardaYouNotice(
          text:
              'Movement prompts a check-in. Only you can confirm a taken entry.',
        ),
        if (!connected) ...[
          const SizedBox(height: 16),
          FardaYouSecondaryButton(
            label: 'Simulate next setup step',
            onPressed: onAdvanceSetup,
          ),
        ],
        const SizedBox(height: 16),
        FardaYouCard(
          color: FardaYouPalette.ivory,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hardware still to be verified',
                style: fardaYouText(size: 15, weight: FontWeight.w600),
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
        FardaYouBackButton(onPressed: onBack),
      ],
    );
  }
}

class _VialStep extends StatelessWidget {
  const _VialStep({
    required this.title,
    required this.subtitle,
    required this.vectorIcon,
    required this.completed,
    required this.current,
    required this.showDivider,
  });

  final String title;
  final String subtitle;
  final String vectorIcon;
  final bool completed;
  final bool current;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Semantics(
          label:
              '$title. ${completed
                  ? 'Completed in preview'
                  : current
                  ? 'Current preview step'
                  : 'Not started'}',
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color:
                        completed
                            ? FardaYouPalette.navy
                            : current
                            ? FardaYouPalette.paleBlue
                            : FardaYouPalette.ivory,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color:
                          current ? FardaYouPalette.blue : Colors.transparent,
                    ),
                  ),
                  child: Center(
                    child:
                        completed
                            ? const Icon(
                              Icons.check_rounded,
                              color: Colors.white,
                              size: 21,
                            )
                            : FardaVectorIcon(vectorIcon),
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
                const FardaVectorIcon('icon-arrow', size: 16),
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
          const SizedBox(height: 16),
        ],
        const FardaYouPageHeader(
          eyebrow: 'Sharing preview',
          title: 'Your circle.\nYour choice.',
          supportingText: 'Try the settings. No invites are sent.',
        ),
        const SizedBox(height: 16),
        FardaYouCard(
          color: FardaYouPalette.navy,
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 110,
                  height: 110,
                  decoration: const BoxDecoration(
                    color: FardaYouPalette.ivory,
                    shape: BoxShape.circle,
                  ),
                  child:
                      showCompanion
                          ? const design.FardaCompanion(
                            size: 110,
                            pose: design.FardaCompanionPose.wave,
                            floating: true,
                          )
                          : const Center(
                            child: Icon(
                              Icons.people_outline_rounded,
                              color: FardaYouPalette.navy,
                              size: 52,
                            ),
                          ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                connected ? 'Sample supporter' : 'Support, on your terms.',
                style: fardaYouText(
                  size: 18,
                  height: 24,
                  weight: FontWeight.w600,
                  color: FardaYouPalette.ivory,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                connected
                    ? 'Accepted in this local preview only.'
                    : 'Preview who sees what.',
                style: fardaYouText(
                  size: 14,
                  height: 20,
                  color: FardaYouPalette.ivory,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (connected)
          FardaYouSecondaryButton(
            label: 'Remove sample access',
            foregroundColor: FardaYouPalette.danger,
            onPressed: onRevoke,
          )
        else
          FardaYouPrimaryButton(
            label: 'Preview an invitation',
            onPressed: onInvite,
          ),
        const SizedBox(height: 16),
        FardaYouCard(
          padding: const EdgeInsets.all(18),
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
              const SizedBox(height: 16),
              FardaYouSettingRow(
                title: 'Routine summaries',
                subtitle: 'Entries you choose to share',
                compact: true,
                showDivider: false,
                trailing: FardaYouSwitch(
                  value: routineSummaries,
                  onChanged: onRoutineSummariesChanged,
                  semanticLabel: 'Share routine summaries',
                ),
              ),
              const SizedBox(height: 16),
              FardaYouSettingRow(
                title: 'Refill reminders',
                subtitle: 'Help planning the next refill',
                compact: true,
                showDivider: false,
                trailing: FardaYouSwitch(
                  value: refillReminders,
                  onChanged: onRefillRemindersChanged,
                  semanticLabel: 'Share refill reminders',
                ),
              ),
              const SizedBox(height: 16),
              FardaYouSettingRow(
                title: 'A missed confirmation',
                subtitle: 'Only when you enable it',
                compact: true,
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
        const SizedBox(height: 16),
        const FardaYouNotice(
          text: 'Preview only. Sharing starts off; no access is granted.',
        ),
        FardaYouBackButton(onPressed: onBack),
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
        padding: const EdgeInsets.fromLTRB(22, 8, 22, 34),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Column(
                        children: [
                          Text(
                            'Wednesday, October 14',
                            style: fardaYouText(
                              size: 16,
                              height: 21,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            clock,
                            style: fardaYouText(
                              size: 80,
                              height: 104,
                              weight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 212),
                    FardaYouCard(
                      radius: 24,
                      padding: const EdgeInsets.all(20),
                      color: FardaYouPalette.ivory,
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
                          if (state == FardaLivePreviewState.due) ...[
                            const SizedBox(height: 10),
                            TextButton(
                              onPressed:
                                  () => onStateChanged(
                                    FardaLivePreviewState.snoozed,
                                  ),
                              style: TextButton.styleFrom(
                                foregroundColor: FardaYouPalette.navy,
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(48, 44),
                              ),
                              child: const Text('Remind me in 15 minutes  ›'),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: Text(
                        'Swipe up to open Farda',
                        textAlign: TextAlign.center,
                        style: fardaYouText(
                          size: 12,
                          height: 17,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: Text(
                        state == FardaLivePreviewState.off
                            ? 'Illustrative preview · No Live Activity is scheduled.'
                            : 'Illustrative preview · No timer or notification is running.',
                        textAlign: TextAlign.center,
                        style: fardaYouText(
                          size: 11,
                          height: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    if (state != FardaLivePreviewState.off) ...[
                      const SizedBox(height: 150),
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
                              label: Text(
                                chip.$2,
                                style: fardaYouText(
                                  size: 11,
                                  weight: FontWeight.w500,
                                  color:
                                      state == chip.$1
                                          ? FardaYouPalette.navy
                                          : Colors.white,
                                ),
                              ),
                              selected: state == chip.$1,
                              showCheckmark: false,
                              onSelected: (_) => onStateChanged(chip.$1),
                              color: WidgetStateProperty.resolveWith(
                                (states) =>
                                    states.contains(WidgetState.selected)
                                        ? Colors.white
                                        : const Color(0xFF213B66),
                              ),
                              side: BorderSide(
                                color: Colors.white.withValues(alpha: 0.25),
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
                        onStateChanged(switch (index) {
                          0 => FardaLivePreviewState.before,
                          1 => FardaLivePreviewState.due,
                          _ => FardaLivePreviewState.due,
                        });
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
                Positioned(
                  top: 0,
                  left: 0,
                  child: IconButton(
                    tooltip: 'Reminder settings',
                    onPressed: onBack,
                    color: Colors.white,
                    icon: const Icon(Icons.arrow_back_rounded),
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

(String, String) _liveCopy(FardaLivePreviewState state, int callDelayMinutes) {
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
    final status =
        state == FardaLivePreviewState.stale
            ? 'Check Farda'
            : state == FardaLivePreviewState.confirmed
            ? 'Entry saved'
            : 'Your routine';
    final time =
        state == FardaLivePreviewState.before
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
      color: const Color(0xFF0B1D3C),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 8, 22, 30),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520, minHeight: 700),
            child: Stack(
              children: [
                Column(
                  children: [
                    const SizedBox(height: 28),
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
                    const SizedBox(height: 64),
                    const FardaPreviewBadge(
                      label: 'Local simulation · no call is placed',
                      onDark: true,
                    ),
                  ],
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  child: IconButton(
                    tooltip: 'Reminder settings',
                    onPressed: onBack,
                    color: Colors.white,
                    icon: const Icon(Icons.arrow_back_rounded),
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
      FardaCallPreviewStage.ended => _CallEnded(entryConfirmed: entryConfirmed),
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
          'CALL PREVIEW · NO CALL IS PLACED',
          textAlign: TextAlign.center,
          style: fardaYouText(
            size: 10,
            height: 14,
            weight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 22),
        Text(
          'Farda',
          style: fardaYouText(
            size: 42,
            height: 55,
            weight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        Text(
          'A gentle reminder, if you choose.',
          style: fardaYouText(size: 16, height: 21, color: Colors.white),
        ),
        const SizedBox(height: 26),
        Container(
          width: 150,
          height: 150,
          decoration: const BoxDecoration(
            color: FardaYouPalette.ivory,
            shape: BoxShape.circle,
          ),
          child: const design.FardaCompanion(
            size: 150,
            pose: design.FardaCompanionPose.wave,
            floating: true,
          ),
        ),
        const SizedBox(height: 202),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _RoundCallButton(
              label: 'Decline',
              icon: Icons.call_end_rounded,
              color: const Color(0xFFB95160),
              onPressed: onDecline,
            ),
            _RoundCallButton(
              label: 'Answer',
              icon: Icons.phone_rounded,
              color: const Color(0xFFADC8ED),
              foreground: FardaYouPalette.navy,
              onPressed: onAnswer,
            ),
          ],
        ),
        const SizedBox(height: 185),
        Text(
          'Illustrative call screen. Caller appearance depends on your phone and carrier.',
          textAlign: TextAlign.center,
          style: fardaYouText(size: 12, height: 17, color: Colors.white),
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
          width: 160,
          child: Column(
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: Icon(icon, color: foreground, size: 26),
              ),
              const SizedBox(height: 10),
              Text(
                label,
                textAlign: TextAlign.center,
                style: fardaYouText(size: 14, color: Colors.white),
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
    return Column(
      children: [
        Text(
          'Farda',
          style: fardaYouText(
            size: 38,
            height: 49,
            weight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Preview · 00:08',
          style: fardaYouText(size: 14, height: 20, color: Colors.white),
        ),
        const SizedBox(height: 12),
        Container(
          width: 100,
          height: 100,
          decoration: const BoxDecoration(
            color: FardaYouPalette.ivory,
            shape: BoxShape.circle,
          ),
          child: const design.FardaCompanion(
            size: 100,
            pose: design.FardaCompanionPose.quiet,
            floating: true,
          ),
        ),
        const SizedBox(height: 16),
        FardaYouCard(
          color: FardaYouPalette.navy,
          radius: 24,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'A friendly reminder',
                style: fardaYouText(
                  size: 22,
                  height: 29,
                  weight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '“Hi, it’s Farda with your routine reminder. Open the app when you’re ready.”',
                style: fardaYouText(
                  size: 18,
                  height: 24,
                  weight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'No medication name is spoken.',
                style: fardaYouText(size: 12, height: 17, color: Colors.white),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        FardaYouPrimaryButton(
          label: '1   Optional private check-in',
          onPressed: onPrivateCheckIn,
          backgroundColor: FardaYouPalette.ivory,
          foregroundColor: FardaYouPalette.navy,
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: onStopCalls,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(48, 48),
              foregroundColor: FardaYouPalette.ivory,
              side: const BorderSide(color: Color(0xFF365C99)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              textStyle: fardaYouText(size: 14, weight: FontWeight.w600),
            ),
            child: const Text('9   Stop this reminder call'),
          ),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Your record is still unconfirmed.',
            style: fardaYouText(size: 12, height: 17, color: Colors.white),
          ),
        ),
        const SizedBox(height: 220),
        TextButton(
          onPressed: onEnd,
          style: TextButton.styleFrom(foregroundColor: Colors.white),
          child: const Text('End preview'),
        ),
        if (!callRemindersEnabled)
          Text(
            'Call reminders remain off.',
            style: fardaYouText(size: 12, color: Colors.white),
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
  const _CallConfirm({required this.onConfirmEntry, required this.onEnd});

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
        const design.FardaCompanion(
          size: 124,
          pose: design.FardaCompanionPose.quiet,
        ),
        const SizedBox(height: 14),
        Text(
          entryConfirmed
              ? 'Your sample entry\nis confirmed.'
              : 'Your day.\nYour pace.',
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
        const design.FardaCompanion(
          size: 94,
          pose: design.FardaCompanionPose.quiet,
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
                style: fardaYouText(size: 17, height: 25, color: Colors.white),
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

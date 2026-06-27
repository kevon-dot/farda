import 'package:farda/application/caregiver/model/caregiver_grant_model.dart';
import 'package:farda/components/_components.dart';
import 'package:farda/screens/caregiver/caregiver_provider.dart';
import 'package:farda/screens/caregiver/caregiver_view_model.dart';
import 'package:farda/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

/// GTM-517 — the caregiver/patient hub.
///
/// Two tabs:
///   * Caregiving — my invites inbox (accept/decline) + the patients/devices I
///     am authorized to view, each with an in-app missed/late-dose status.
///   * My care team — caregivers I (as patient/owner) invited: outstanding
///     invites + accepted caregivers I can revoke.
///
/// SERVER-AUTHORITATIVE: the screen renders only what the backend returned for
/// the session user. A pending grant shows as an invite/awaiting row and grants
/// NO readable patient data — authorized summaries exist only for accepted
/// grants (see [CaregiverProvider.loadAuthorizedSummaries]).
class ScreenCaregiverHub extends StatefulWidget {
  const ScreenCaregiverHub({super.key});

  @override
  State<ScreenCaregiverHub> createState() => _ScreenCaregiverHubState();
}

class _ScreenCaregiverHubState extends State<ScreenCaregiverHub> {
  @override
  void initState() {
    super.initState();
    // Defer to post-frame so context.read is safe and providers are mounted.
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    final provider = context.read<CaregiverProvider>();
    await provider.loadGrants();
    await provider.loadAuthorizedSummaries();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FardaColors>()!;
    final spacing = theme.extension<Spacing>()!;
    final provider = context.watch<CaregiverProvider>();

    return DefaultTabController(
      length: 2,
      child: ExtendedScaffold(
        appBar: CustomAppBar(
          titleType: AppBarTitleType.text,
          titleText: 'Care',
          onBack: () => context.canPop() ? context.pop() : context.go('/dashboard'),
        ),
        body: SafeArea(
          child: Column(
            children: [
              TabBar(
                labelColor: colors.blue,
                unselectedLabelColor: colors.baseBlack,
                tabs: const [
                  Tab(text: 'Caregiving'),
                  Tab(text: 'My care team'),
                ],
              ),
              if (provider.isLoading) LinearProgressIndicator(color: colors.blue),
              Expanded(
                child: TabBarView(
                  children: [
                    RefreshIndicator(
                      onRefresh: _refresh,
                      child: _CaregivingTab(provider: provider),
                    ),
                    RefreshIndicator(
                      onRefresh: _refresh,
                      child: _CareTeamTab(provider: provider, spacing: spacing),
                    ),
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

/// Tab 1 — what I see as a CAREGIVER: invites inbox + authorized patients.
class _CaregivingTab extends StatelessWidget {
  const _CaregivingTab({required this.provider});

  final CaregiverProvider provider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FardaColors>()!;
    final invites = provider.pendingInvites;
    final patients = provider.authorizedPatients;

    return ListView(
      padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 12.h),
      children: [
        _SectionHeader(title: 'Invites'),
        if (invites.isEmpty)
          _EmptyHint(text: 'No pending invites.')
        else
          ...invites.map((g) => _InviteInboxTile(grant: g, provider: provider)),
        SizedBox(height: 16.h),
        _SectionHeader(title: 'Patients you care for'),
        if (patients.isEmpty)
          _EmptyHint(
            text: 'No authorized patients yet. Accept an invite to begin.',
          )
        else
          ...patients.map(
            (g) => _AuthorizedPatientTile(
              grant: g,
              status: provider.doseStatusFor(g.deviceId ?? ''),
              colors: colors,
            ),
          ),
        // TODO(GTM-537): deliver missed/late-dose alerts as push notifications
        // via Firebase once the caregiver push channel ships. Until then the
        // status below is in-app only.
      ],
    );
  }
}

/// A pending invite awaiting MY acceptance — accept or decline.
class _InviteInboxTile extends StatelessWidget {
  const _InviteInboxTile({required this.grant, required this.provider});

  final CaregiverGrantModel grant;
  final CaregiverProvider provider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FardaColors>()!;
    return Card(
      margin: EdgeInsets.only(bottom: 10.h),
      child: Padding(
        padding: EdgeInsets.all(12.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Device ${grant.deviceId ?? '—'}',
              style: theme.textTheme.titleSmall?.copyWith(color: colors.baseBlack),
            ),
            SizedBox(height: 4.h),
            Text(
              'Invited by ${grant.patientUserId ?? 'a patient'}',
              style: theme.textTheme.bodySmall,
            ),
            SizedBox(height: 10.h),
            Row(
              children: [
                Expanded(
                  child: ButtonPrimary(
                    text: 'Accept',
                    onClick: () => _act(context, accept: true),
                  ),
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: ButtonSecondary(
                    text: 'Decline',
                    onClick: () => _act(context, accept: false),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _act(BuildContext context, {required bool accept}) async {
    final id = grant.id;
    if (id == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final ok = accept
        ? await provider.acceptInvite(id)
        : await provider.declineInvite(id);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? (accept ? 'Invite accepted' : 'Invite declined')
              : 'Something went wrong. Please try again.',
        ),
      ),
    );
  }
}

/// A patient/device I am authorized to view, with adherence/missed-dose status.
class _AuthorizedPatientTile extends StatelessWidget {
  const _AuthorizedPatientTile({
    required this.grant,
    required this.status,
    required this.colors,
  });

  final CaregiverGrantModel grant;
  final DoseAlertStatus status;
  final FardaColors colors;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, color) = _statusLabel(status, colors);
    return Card(
      margin: EdgeInsets.only(bottom: 10.h),
      child: ListTile(
        title: Text(
          'Device ${grant.deviceId ?? '—'}',
          style: theme.textTheme.titleSmall?.copyWith(color: colors.baseBlack),
        ),
        subtitle: Text('Patient ${grant.patientUserId ?? '—'}'),
        trailing: Container(
          padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12.r),
          ),
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  (String, Color) _statusLabel(DoseAlertStatus s, FardaColors colors) {
    switch (s) {
      case DoseAlertStatus.onTrack:
        return ('On track', colors.success);
      case DoseAlertStatus.missedOrLate:
        return ('Missed / late', colors.error);
      case DoseAlertStatus.unknown:
        return ('No recent data', colors.warning);
    }
  }
}

/// Tab 2 — what I see as a PATIENT/OWNER: my care team + invite a caregiver.
class _CareTeamTab extends StatelessWidget {
  const _CareTeamTab({required this.provider, required this.spacing});

  final CaregiverProvider provider;
  final Spacing spacing;

  @override
  Widget build(BuildContext context) {
    final outstanding = provider.outstandingInvites;
    final accepted = provider.myCaregivers;

    return ListView(
      padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 12.h),
      children: [
        ButtonPrimary(
          text: 'Invite a caregiver',
          onClick: () => _showInviteSheet(context, provider),
        ),
        SizedBox(height: 16.h),
        _SectionHeader(title: 'Outstanding invites'),
        if (outstanding.isEmpty)
          _EmptyHint(text: 'No outstanding invites.')
        else
          ...outstanding.map(
            (g) => _CareTeamTile(
              grant: g,
              provider: provider,
              actionLabel: 'Cancel',
              pending: true,
            ),
          ),
        SizedBox(height: 16.h),
        _SectionHeader(title: 'Active caregivers'),
        if (accepted.isEmpty)
          _EmptyHint(text: 'No caregivers have access yet.')
        else
          ...accepted.map(
            (g) => _CareTeamTile(
              grant: g,
              provider: provider,
              actionLabel: 'Revoke',
              pending: false,
            ),
          ),
      ],
    );
  }

  void _showInviteSheet(BuildContext context, CaregiverProvider provider) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _InviteCaregiverSheet(provider: provider),
    );
  }
}

/// A caregiver row on the patient side — pending (cancel) or accepted (revoke).
class _CareTeamTile extends StatelessWidget {
  const _CareTeamTile({
    required this.grant,
    required this.provider,
    required this.actionLabel,
    required this.pending,
  });

  final CaregiverGrantModel grant;
  final CaregiverProvider provider;
  final String actionLabel;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.only(bottom: 10.h),
      child: ListTile(
        title: Text(grant.caregiverUserId ?? 'Caregiver'),
        subtitle: Text(
          pending ? 'Awaiting acceptance · device ${grant.deviceId ?? '—'}'
              : 'Has access · device ${grant.deviceId ?? '—'}',
          style: theme.textTheme.bodySmall,
        ),
        trailing: TextButton(
          onPressed: () => _revoke(context),
          child: Text(actionLabel),
        ),
      ),
    );
  }

  Future<void> _revoke(BuildContext context) async {
    final id = grant.id;
    if (id == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final ok = await provider.revokeGrant(id);
    messenger.showSnackBar(
      SnackBar(
        content: Text(ok ? 'Access updated' : 'Something went wrong. Try again.'),
      ),
    );
  }
}

/// Bottom sheet to invite a caregiver by device id + caregiver user id.
class _InviteCaregiverSheet extends StatefulWidget {
  const _InviteCaregiverSheet({required this.provider});

  final CaregiverProvider provider;

  @override
  State<_InviteCaregiverSheet> createState() => _InviteCaregiverSheetState();
}

class _InviteCaregiverSheetState extends State<_InviteCaregiverSheet> {
  final _deviceCtrl = TextEditingController();
  final _caregiverCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _deviceCtrl.dispose();
    _caregiverCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;
    final canSubmit = CaregiverViewModel.canSubmitInvite(
      deviceId: _deviceCtrl.text,
      caregiverId: _caregiverCtrl.text,
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(20.w, 20.h, 20.w, 20.h + viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Invite a caregiver', style: Theme.of(context).textTheme.titleMedium),
          SizedBox(height: 12.h),
          TextField(
            controller: _deviceCtrl,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Device ID'),
          ),
          SizedBox(height: 10.h),
          TextField(
            controller: _caregiverCtrl,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Caregiver user ID'),
          ),
          SizedBox(height: 16.h),
          ButtonPrimary(
            text: _submitting ? 'Sending…' : 'Send invite',
            onClick: (!canSubmit || _submitting) ? null : _submit,
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await widget.provider.inviteCaregiver(
      _deviceCtrl.text.trim(),
      _caregiverCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    navigator.pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text(ok ? 'Invite sent' : 'Could not send invite. Try again.'),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8.h),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8.h),
      child: Text(text, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}

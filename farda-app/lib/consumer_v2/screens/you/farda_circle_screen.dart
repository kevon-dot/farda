import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:farda/features/consumer/data/consumer_repository.dart';
import 'package:farda/features/consumer/data/circle_models.dart';

import '../../design_system/farda_consumer_tokens.dart' as design;
import 'you_widgets.dart';

/// Family sharing uses canonical account records, independently of a vial.
class FardaCircleScreen extends StatefulWidget {
  const FardaCircleScreen({
    super.key,
    required this.repository,
    required this.onBack,
    this.showBrandHeader = true,
  });
  final ConsumerRepository? repository;
  final VoidCallback onBack;
  final bool showBrandHeader;
  @override
  State<FardaCircleScreen> createState() => _FardaCircleScreenState();
}

class _FardaCircleScreenState extends State<FardaCircleScreen>
    with WidgetsBindingObserver {
  CircleOverview? _circle;
  List<CircleInvitation> _invitations = [];
  List<SharedCircle> _shared = [];
  CircleRoutine? _routine;
  SharedCircle? _selected;
  String? _error;
  bool _loading = true;
  bool _busy = false;
  bool _familyTab = false;
  int _requestGeneration = 0;
  int _mutationGeneration = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void didUpdateWidget(covariant FardaCircleScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.repository, widget.repository)) {
      _requestGeneration++;
      _mutationGeneration++;
      _circle = null;
      _invitations = const [];
      _shared = const [];
      _routine = null;
      _selected = null;
      _error = null;
      _busy = false;
      _load();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _requestGeneration++;
    _mutationGeneration++;
    super.dispose();
  }

  Future<void> _load() async {
    final repo = widget.repository;
    final selected = _selected;
    final generation = ++_requestGeneration;
    bool isCurrent() =>
        mounted &&
        generation == _requestGeneration &&
        identical(repo, widget.repository) &&
        (selected?.access.id == _selected?.access.id);
    if (repo == null) {
      setState(() {
        _loading = false;
        _circle = null;
        _invitations = const [];
        _shared = const [];
        _routine = null;
        _selected = null;
        _error = 'Sign in to invite your family and share your routine.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _routine = null;
      if (selected == null) {
        _circle = null;
        _invitations = const [];
        _shared = const [];
      }
    });
    try {
      if (selected != null) {
        final now = DateTime.now();
        final start = DateTime(now.year, now.month, now.day);
        final routine = await repo.loadSharedCircleRoutine(
          selected.access.id,
          from: start,
          to: DateTime(now.year, now.month, now.day + 1),
        );
        if (isCurrent()) setState(() => _routine = routine);
      } else {
        final results = await Future.wait([
          repo.loadCircle(),
          repo.loadCircleInvitations(),
          repo.loadSharedCircles(),
        ]);
        if (isCurrent()) {
          setState(() {
            _circle = results[0] as CircleOverview;
            _invitations = results[1] as List<CircleInvitation>;
            _shared = results[2] as List<SharedCircle>;
          });
        }
      }
    } catch (_) {
      if (isCurrent()) {
        setState(
          () =>
              _error =
                  selected == null
                      ? 'We couldn’t load your circle. Try again.'
                      : 'This shared routine is unavailable. Access may have changed.',
        );
      }
    }
    if (isCurrent()) setState(() => _loading = false);
  }

  Future<void> _mutate(
    ConsumerRepository repo,
    Future<void> Function(ConsumerRepository repo) action, {
    VoidCallback? onSuccess,
  }) async {
    if (_busy) return;
    if (!identical(repo, widget.repository)) return;
    final generation = ++_mutationGeneration;
    bool isCurrent() =>
        mounted &&
        generation == _mutationGeneration &&
        identical(repo, widget.repository);
    setState(() => _busy = true);
    try {
      await action(repo);
      if (isCurrent()) {
        if (onSuccess != null) setState(onSuccess);
        await _load();
      }
    } catch (_) {
      if (isCurrent()) {
        _message(
          'We couldn’t confirm the change. Refresh before trying again.',
        );
        await _load();
      }
    }
    if (isCurrent()) setState(() => _busy = false);
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  Future<void> _invite() async {
    final repo = widget.repository;
    if (repo == null) return;
    final result = await showModalBottomSheet<_InviteDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _InviteSheet(),
    );
    if (result == null || !mounted || !identical(repo, widget.repository)) {
      return;
    }
    await _mutate(repo, (repo) async {
      final invite = await repo.inviteToCircle(
        result.phone,
        result.permissions,
      );
      if (!mounted || !identical(repo, widget.repository)) return;
      await showDialog<void>(
        context: context,
        builder:
            (context) => AlertDialog(
              scrollable: true,
              title: const Text('Your invitation is ready'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Share this code with ${invite.person.displayName}. They can accept it in their Farda circle.',
                  ),
                  const SizedBox(height: 16),
                  if (invite.inviteCode != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: design.FardaConsumerColors.soft,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: SelectableText(
                        invite.inviteCode!,
                        style: const TextStyle(
                          fontFamily: 'Outfit',
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                          height: 1.5,
                          color: design.FardaConsumerColors.brand,
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  const Text(
                    'Nothing is shared until they accept. No text message has been sent.',
                  ),
                ],
              ),
              actions: [
                if (invite.inviteCode != null)
                  FilledButton(
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: invite.inviteCode!),
                      );
                      if (mounted) _message('Invitation code copied');
                    },
                    child: const Text('Copy code'),
                  ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done'),
                ),
              ],
            ),
      );
    });
  }

  Future<void> _accept(CircleInvitation invite) async {
    final repo = widget.repository;
    if (repo == null) return;
    final code = await showDialog<String>(
      context: context,
      builder: (context) => _AcceptInvitationDialog(invite: invite),
    );
    if (code == null ||
        code.isEmpty ||
        !mounted ||
        !identical(repo, widget.repository)) {
      return;
    }
    await _mutate(repo, (repo) async {
      await repo.acceptCircleInvitation(invite.id, code);
    });
  }

  Future<void> _manage(CircleMember member) async {
    final repo = widget.repository;
    if (repo == null) return;
    final result = await showModalBottomSheet<_MemberEdit>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _PermissionsSheet(member: member),
    );
    if (result == null || !mounted || !identical(repo, widget.repository)) {
      return;
    }
    await _mutate(repo, (repo) async {
      if (result.remove) {
        await repo.removeCircleMember(member.id);
      } else {
        await repo.updateCircleMember(member.id, result.permissions!);
      }
    });
  }

  Widget _title(String value) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 12),
    child: Text(value, style: design.FardaConsumerType.title),
  );
  Widget _person(
    String name,
    String subtitle, {
    required Widget trailing,
    Widget? footer,
  }) => FardaYouCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: design.FardaConsumerColors.soft,
              child: Text(
                name.isEmpty ? '?' : name.characters.first.toUpperCase(),
                style: design.FardaConsumerType.title,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: design.FardaConsumerType.bodyStrong),
                  const SizedBox(height: 3),
                  Text(subtitle, style: design.FardaConsumerType.caption),
                ],
              ),
            ),
            trailing,
          ],
        ),
        if (footer != null) ...[const SizedBox(height: 14), footer],
      ],
    ),
  );
  Widget _permissions(CirclePermissions p) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      if (!p.doseStatus && !p.reminders)
        const _Pill('Sharing paused', Icons.pause_circle_outline),
      if (p.doseStatus) const _Pill('Dose updates', Icons.check_circle_outline),
      if (p.reminders) const _Pill('Reminder times', Icons.schedule),
    ],
  );
  @override
  Widget build(BuildContext context) => Material(
    color: design.FardaConsumerColors.canvas,
    child: FardaYouPageCanvas(
      key: ValueKey(_selected?.access.id ?? 'circle'),
      children: [
        if (widget.showBrandHeader) ...[
          const FardaYouBrandHeader(profileLabel: 'ME'),
          const SizedBox(height: 16),
        ],
        if (_selected != null) ...[
          TextButton.icon(
            onPressed: () {
              setState(() => _selected = null);
              _load();
            },
            icon: const Icon(Icons.arrow_back_rounded),
            label: const Text('Your circle'),
          ),
          FardaYouPageHeader(
            eyebrow: 'Shared with you',
            title: '${_selected!.owner.displayName}’s day',
            supportingText: 'A little support. A little peace of mind.',
          ),
        ] else ...[
          const FardaYouPageHeader(
            eyebrow: 'Family & friends',
            title: 'Closer, even\nfrom here.',
          ),
          const SizedBox(height: 20),
          design.FardaSceneCard(
            scene: design.FardaScene.you,
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    for (final icon in [
                      'icon-circle',
                      'icon-clock',
                      'icon-check',
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: CircleAvatar(
                          radius: 22,
                          backgroundColor: Colors.white.withValues(alpha: .14),
                          child: design.FardaVectorIcon(
                            icon,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  'Your people.\nOn your terms.',
                  style: design.FardaConsumerType.heading.copyWith(
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Share dose updates and reminder times with someone you trust.',
                  style: design.FardaConsumerType.body.copyWith(
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed:
                        widget.repository == null ||
                                widget.repository!.isDemo ||
                                _busy
                            ? null
                            : _invite,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: design.FardaConsumerColors.brand,
                    ),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Invite someone'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('My circle'),
                selected: !_familyTab,
                onSelected: (_) => setState(() => _familyTab = false),
              ),
              ChoiceChip(
                label: Text(
                  'Shared with me${_invitations.isEmpty ? '' : ' · ${_invitations.length}'}',
                ),
                selected: _familyTab,
                onSelected: (_) => setState(() => _familyTab = true),
              ),
            ],
          ),
        ],
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_error != null) ...[
          const SizedBox(height: 20),
          FardaYouNotice(text: _error!),
          TextButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
        ] else if (_routine != null)
          ..._routineContent(_routine!)
        else if (_familyTab) ...[
          if (_invitations.isNotEmpty) _title('You’re invited'),
          for (final invite in _invitations) ...[
            _person(
              invite.person.displayName,
              'Wants to share with you',
              trailing: TextButton(
                onPressed: _busy ? null : () => _accept(invite),
                child: const Text('Review'),
              ),
              footer: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _permissions(invite.permissions),
                  TextButton(
                    onPressed: _busy ? null : () => _decline(invite),
                    child: const Text('Decline invitation'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          _title('People you support'),
          if (_shared.isEmpty)
            const _EmptyCircle(
              title: 'A place for your people',
              detail:
                  'When someone invites you, their shared routine will appear here.',
            ),
          for (final shared in _shared) ...[
            _person(
              shared.owner.displayName,
              'View today’s shared routine',
              trailing: IconButton(
                tooltip: 'Open shared routine',
                onPressed: () {
                  setState(() => _selected = shared);
                  _load();
                },
                icon: const Icon(Icons.arrow_forward_rounded),
              ),
              footer: _permissions(shared.access.permissions),
            ),
            const SizedBox(height: 12),
          ],
        ] else ...[
          _title('People in your circle'),
          if ((_circle?.members.isEmpty ?? true) &&
              (_circle?.pending.isEmpty ?? true))
            const _EmptyCircle(
              title: 'Start with someone you trust',
              detail:
                  'You choose who joins and what they can see. Change your mind anytime.',
            ),
          for (final member in _circle?.members ?? <CircleMember>[]) ...[
            _person(
              member.person.displayName,
              !member.permissions.doseStatus && !member.permissions.reminders
                  ? 'Connected · Sharing paused'
                  : 'Connected · Can view your updates',
              trailing: IconButton(
                tooltip: 'Manage sharing',
                onPressed: _busy ? null : () => _manage(member),
                icon: const Icon(Icons.tune_rounded),
              ),
              footer: _permissions(member.permissions),
            ),
            const SizedBox(height: 12),
          ],
          for (final invite in _circle?.pending ?? <CircleInvitation>[]) ...[
            _person(
              invite.person.displayName,
              'Invitation pending · Nothing shared yet',
              trailing: IconButton(
                tooltip: 'Cancel invitation',
                onPressed: _busy ? null : () => _cancel(invite),
                icon: const Icon(Icons.close_rounded),
              ),
              footer: _permissions(invite.permissions),
            ),
            const SizedBox(height: 12),
          ],
        ],
        const SizedBox(height: 20),
        const FardaYouNotice(
          text:
              'Your circle can view only what you allow. They can’t mark doses or change your routine.',
        ),
        const SizedBox(height: 8),
        if (!_loading && _error == null)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Refresh'),
            ),
          ),
        FardaYouBackButton(onPressed: widget.onBack),
      ],
    ),
  );
  Future<void> _cancel(CircleInvitation invite) async {
    final repo = widget.repository;
    if (repo == null) return;
    final yes = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            scrollable: true,
            title: const Text('Cancel this invitation?'),
            content: Text(
              '${invite.person.displayName} won’t be able to accept it.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Keep invitation'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Cancel invitation'),
              ),
            ],
          ),
    );
    if (yes == true && mounted && identical(repo, widget.repository)) {
      await _mutate(repo, (repo) async {
        await repo.cancelCircleInvitation(invite.id);
      });
    }
  }

  Future<void> _decline(CircleInvitation invite) async {
    final repo = widget.repository;
    if (repo == null) return;
    final yes = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            scrollable: true,
            title: const Text('Decline this invitation?'),
            content: Text(
              'You won’t join ${invite.person.displayName}’s circle.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Keep invitation'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Decline invitation'),
              ),
            ],
          ),
    );
    if (yes == true && mounted && identical(repo, widget.repository)) {
      await _mutate(repo, (repo) => repo.declineCircleInvitation(invite.id));
    }
  }

  Future<void> _leaveSharedCircle() async {
    final selected = _selected;
    final repo = widget.repository;
    if (selected == null || repo == null) return;
    final yes = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            scrollable: true,
            title: const Text('Leave this circle?'),
            content: Text(
              'You’ll no longer see ${selected.owner.displayName}’s shared routine.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Stay connected'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Leave circle'),
              ),
            ],
          ),
    );
    if (yes == true &&
        mounted &&
        identical(repo, widget.repository) &&
        identical(selected, _selected)) {
      await _mutate(
        repo,
        (repo) => repo.leaveSharedCircle(selected.access.id),
        onSuccess: () => _selected = null,
      );
    }
  }

  List<Widget> _routineContent(CircleRoutine routine) => [
    const SizedBox(height: 20),
    _permissions(routine.permissions),
    _title('Today'),
    Text(
      'Updated ${DateFormat.jm().format(routine.fetchedAt.toLocal())} · Times shown in your timezone',
      style: design.FardaConsumerType.caption,
    ),
    const SizedBox(height: 16),
    if (routine.items.isEmpty)
      const _EmptyCircle(
        title: 'Nothing to show today',
        detail:
            'There are no shared entries in this day. You can refresh later.',
      ),
    for (final item in routine.items) ...[
      _RoutineTile(item: item, permissions: routine.permissions),
      const SizedBox(height: 12),
    ],
    const SizedBox(height: 4),
    const FardaYouNotice(
      text:
          'No confirmation doesn’t mean a dose was missed. Reminder times are planned times, not proof a reminder was delivered.',
    ),
    Align(
      alignment: Alignment.centerLeft,
      child: TextButton(
        onPressed: _busy ? null : _leaveSharedCircle,
        child: const Text('Leave this circle'),
      ),
    ),
  ];
}

class _Pill extends StatelessWidget {
  const _Pill(this.label, this.icon);
  final String label;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: design.FardaConsumerColors.soft,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: design.FardaConsumerColors.brand),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            label,
            style: design.FardaConsumerType.caption.copyWith(
              color: design.FardaConsumerColors.brand,
            ),
          ),
        ),
      ],
    ),
  );
}

class _EmptyCircle extends StatelessWidget {
  const _EmptyCircle({required this.title, required this.detail});
  final String title;
  final String detail;
  @override
  Widget build(BuildContext context) => FardaYouCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.people_outline_rounded,
          color: design.FardaConsumerColors.accent,
          size: 30,
        ),
        const SizedBox(height: 14),
        Text(title, style: design.FardaConsumerType.title),
        const SizedBox(height: 8),
        Text(
          detail,
          style: design.FardaConsumerType.body.copyWith(
            color: design.FardaConsumerColors.textSecondary,
          ),
        ),
      ],
    ),
  );
}

class _InviteDraft {
  const _InviteDraft(this.phone, this.permissions);
  final String phone;
  final CirclePermissions permissions;
}

class _MemberEdit {
  const _MemberEdit({this.remove = false, this.permissions});
  final bool remove;
  final CirclePermissions? permissions;
}

class _AcceptInvitationDialog extends StatefulWidget {
  const _AcceptInvitationDialog({required this.invite});

  final CircleInvitation invite;

  @override
  State<_AcceptInvitationDialog> createState() =>
      _AcceptInvitationDialogState();
}

class _AcceptInvitationDialogState extends State<_AcceptInvitationDialog> {
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text('Join ${widget.invite.person.displayName}’s circle'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Enter the invitation code they shared with you.'),
        const SizedBox(height: 16),
        TextField(
          controller: _input,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Invitation code',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Not now'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _input.text.trim()),
        child: const Text('Accept invitation'),
      ),
    ],
  );
}

class _InviteSheet extends StatefulWidget {
  const _InviteSheet();
  @override
  State<_InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends State<_InviteSheet> {
  final phone = TextEditingController();
  bool doses = false;
  bool reminders = false;
  String? error;
  @override
  void dispose() {
    phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _Sheet(
    children: [
      Text('Invite someone close', style: design.FardaConsumerType.heading),
      const SizedBox(height: 8),
      const Text('Use the phone number on their Farda account.'),
      const SizedBox(height: 20),
      TextField(
        controller: phone,
        keyboardType: TextInputType.phone,
        decoration: InputDecoration(
          labelText: 'Phone number',
          hintText: '+1 555 123 4567',
          errorText: error,
          border: const OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 20),
      Text('What can they see?', style: design.FardaConsumerType.title),
      const SizedBox(height: 8),
      _PermissionToggle(
        title: 'Dose updates',
        subtitle: 'Recorded, skipped, or not yet confirmed',
        value: doses,
        onChanged: (v) => setState(() => doses = v),
      ),
      _PermissionToggle(
        title: 'Reminder times',
        subtitle: 'Your planned medication schedule',
        value: reminders,
        onChanged: (v) => setState(() => reminders = v),
      ),
      const SizedBox(height: 16),
      const FardaYouNotice(
        text:
            'They’ll need your invitation code. Sharing begins only after they accept.',
      ),
      const SizedBox(height: 20),
      FilledButton(
        onPressed:
            !doses && !reminders
                ? null
                : () {
                  if (!RegExp(
                    r'^\+[1-9]\d{6,14}$',
                  ).hasMatch(phone.text.replaceAll(RegExp(r'[\s()-]'), ''))) {
                    setState(
                      () =>
                          error = 'Include country code, like +1 555 123 4567',
                    );
                    return;
                  }
                  Navigator.pop(
                    context,
                    _InviteDraft(
                      phone.text.replaceAll(RegExp(r'[\s()-]'), ''),
                      CirclePermissions(
                        doseStatus: doses,
                        reminders: reminders,
                      ),
                    ),
                  );
                },
        child: const Text('Create invitation'),
      ),
    ],
  );
}

class _PermissionsSheet extends StatefulWidget {
  const _PermissionsSheet({required this.member});
  final CircleMember member;
  @override
  State<_PermissionsSheet> createState() => _PermissionsSheetState();
}

class _PermissionsSheetState extends State<_PermissionsSheet> {
  late bool doses = widget.member.permissions.doseStatus;
  late bool reminders = widget.member.permissions.reminders;
  @override
  Widget build(BuildContext context) => _Sheet(
    children: [
      Text(
        'Sharing with ${widget.member.person.displayName}',
        style: design.FardaConsumerType.heading,
      ),
      const SizedBox(height: 20),
      _PermissionToggle(
        title: 'Dose updates',
        subtitle: 'Recorded, skipped, or not yet confirmed',
        value: doses,
        onChanged: (v) => setState(() => doses = v),
      ),
      _PermissionToggle(
        title: 'Reminder times',
        subtitle: 'Your planned medication schedule',
        value: reminders,
        onChanged: (v) => setState(() => reminders = v),
      ),
      const SizedBox(height: 20),
      FilledButton(
        onPressed:
            () => Navigator.pop(
              context,
              _MemberEdit(
                permissions: CirclePermissions(
                  doseStatus: doses,
                  reminders: reminders,
                ),
              ),
            ),
        child: const Text('Save sharing'),
      ),
      const SizedBox(height: 8),
      TextButton(
        onPressed: () async {
          final yes = await showDialog<bool>(
            context: context,
            builder:
                (context) => AlertDialog(
                  scrollable: true,
                  title: const Text('Remove access?'),
                  content: Text(
                    '${widget.member.person.displayName} will no longer see your routine.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Keep access'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Remove access'),
                    ),
                  ],
                ),
          );
          if (yes == true && context.mounted) {
            Navigator.pop(context, const _MemberEdit(remove: true));
          }
        },
        child: const Text(
          'Remove from my circle',
          style: TextStyle(color: FardaYouPalette.danger),
        ),
      ),
    ],
  );
}

class _PermissionToggle extends StatelessWidget {
  const _PermissionToggle({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => SwitchListTile.adaptive(
    contentPadding: EdgeInsets.zero,
    title: Text(title, style: design.FardaConsumerType.bodyStrong),
    subtitle: Text(subtitle, style: design.FardaConsumerType.caption),
    value: value,
    onChanged: onChanged,
  );
}

class _Sheet extends StatelessWidget {
  const _Sheet({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: EdgeInsets.fromLTRB(
      24,
      12,
      24,
      MediaQuery.viewInsetsOf(context).bottom + 28,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  );
}

class _RoutineTile extends StatelessWidget {
  const _RoutineTile({required this.item, required this.permissions});
  final CircleRoutineItem item;
  final CirclePermissions permissions;
  @override
  Widget build(BuildContext context) {
    final state = item.state?.name;
    final reported = item.evidence?.name == 'selfReport';
    final label =
        !permissions.doseStatus
            ? 'Planned reminder'
            : item.evidence == CircleEvidence.deviceObservation
            ? 'Vial activity detected'
            : !reported
            ? 'No confirmation yet'
            : switch (state) {
              'taken' => 'Reported taken',
              'skipped' => 'Reported skipped',
              'snoozed' => 'Snoozed',
              _ => 'No confirmation yet',
            };
    final confirmed = permissions.doseStatus && state == 'taken' && reported;
    return FardaYouCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color:
                      confirmed
                          ? design.FardaConsumerColors.mint
                          : design.FardaConsumerColors.soft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  confirmed ? Icons.check_rounded : Icons.schedule_rounded,
                  color: design.FardaConsumerColors.brand,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.label,
                      style: design.FardaConsumerType.bodyStrong,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.scheduledFor == null
                          ? 'Reminder time not shared'
                          : DateFormat.jm().format(
                            item.scheduledFor!.toLocal(),
                          ),
                      style: design.FardaConsumerType.caption,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(label, style: design.FardaConsumerType.title),
          const SizedBox(height: 5),
          Text(
            permissions.doseStatus
                ? (reported
                    ? 'Recorded by your loved one${item.recordedAt == null ? '' : ' · ${DateFormat.jm().format(item.recordedAt!.toLocal())}'}'
                    : item.evidence?.name == 'deviceObservation'
                    ? 'Vial activity observed · Dose not confirmed'
                    : 'No dose record has been shared')
                : 'Dose updates aren’t shared',
            style: design.FardaConsumerType.caption,
          ),
        ],
      ),
    );
  }
}

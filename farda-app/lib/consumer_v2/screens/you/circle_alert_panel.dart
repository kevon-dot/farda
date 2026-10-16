import 'package:flutter/material.dart';
import 'package:farda/application/authentication/storage/auth_storage.dart';
import 'package:farda/features/consumer/data/circle_alerts.dart';
import '../../design_system/farda_consumer_tokens.dart' as design;
import 'you_widgets.dart';

class CircleAlertPanel extends StatefulWidget {
  const CircleAlertPanel({
    super.key,
    required this.repository,
    required this.isCurrent,
    this.grantId,
    this.personName,
    this.recipient = false,
    this.onFamilyPlan,
  });
  final CircleAlertsRepository repository;
  final bool Function() isCurrent;
  final String? grantId, personName;
  final bool recipient;
  final Future<void> Function()? onFamilyPlan;
  @override
  State<CircleAlertPanel> createState() => _CircleAlertPanelState();
}

class _CircleAlertPanelState extends State<CircleAlertPanel> {
  CircleAlertPolicy? policy;
  List<CircleAlert>? alerts;
  bool loading = true, busy = false, enabled = false, consent = false;
  int grace = 60;
  String start = '22:00', end = '08:00';
  final zone = TextEditingController();
  String? error;
  bool _sessionValid = true;
  bool get current => mounted && _sessionValid && widget.isCurrent();
  @override
  void initState() {
    super.initState();
    AuthStorage.sessionRevision.addListener(_sessionChanged);
    load();
  }

  void _sessionChanged() {
    if (!mounted) return;
    setState(() {
      _sessionValid = false;
      policy = null;
      alerts = null;
      error = null;
      loading = false;
      busy = false;
      enabled = false;
      consent = false;
      zone.clear();
    });
  }

  @override
  void dispose() {
    AuthStorage.sessionRevision.removeListener(_sessionChanged);
    zone.dispose();
    super.dispose();
  }

  Future<void> load() async {
    if (!current) return;
    setState(() {
      loading = true;
      error = null;
      alerts = null;
    });
    try {
      if (widget.grantId == null) {
        final result = await widget.repository.loadCircleAlerts();
        if (current) setState(() => alerts = result);
      } else {
        final result = await widget.repository.loadCircleAlertPolicy(
          widget.grantId!,
          recipient: widget.recipient,
        );
        if (current) {
          setState(() {
            policy = result;
            enabled = result.enabled;
            consent = result.recipientConsented;
            grace = result.gracePeriodMinutes;
            start = result.quietHoursStart;
            end = result.quietHoursEnd;
            zone.text = result.timeZone;
          });
        }
      }
    } catch (_) {
      if (current) {
        setState(() => error = 'Check-ins are unavailable. Please try again.');
      }
    }
    if (current) setState(() => loading = false);
  }

  Future<void> save() async {
    if (!current || busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (widget.recipient) {
        await widget.repository.setCircleAlertConsent(widget.grantId!, consent);
      } else {
        await widget.repository.saveCircleAlertPolicy(
          widget.grantId!,
          CircleAlertPolicy(
            enabled: enabled,
            gracePeriodMinutes: grace,
            quietHoursStart: start,
            quietHoursEnd: end,
            timeZone: zone.text.trim(),
          ),
        );
      }
      if (mounted && current) Navigator.pop(context);
    } catch (_) {
      if (current) {
        setState(
          () =>
              error =
                  'Couldn’t save. Check your timezone and Family plan, then try again.',
        );
      }
    }
    if (current) setState(() => busy = false);
  }

  Future<void> pickTime(bool isStart) async {
    final parts = (isStart ? start : end).split(':');
    final result = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.parse(parts[0]),
        minute: int.parse(parts[1]),
      ),
    );
    if (result != null && current) {
      setState(() {
        final value =
            '${result.hour.toString().padLeft(2, '0')}:${result.minute.toString().padLeft(2, '0')}';
        if (isStart) {
          start = value;
        } else {
          end = value;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final inbox = widget.grantId == null;
    return Material(
      color: design.FardaConsumerColors.canvas,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            24,
            16,
            24,
            MediaQuery.viewInsetsOf(context).bottom + 24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ),
              Text(
                inbox ? 'A little check-in.' : 'Gentle check-ins',
                style: design.FardaConsumerType.heading,
              ),
              const SizedBox(height: 8),
              Text(
                inbox
                    ? 'Updates from the people you support.'
                    : (current
                        ? 'With ${widget.personName ?? 'your circle'}'
                        : 'Your circle'),
                style: design.FardaConsumerType.body,
              ),
              const SizedBox(height: 20),
              if (!current)
                const Text('Your account changed. Close this view to continue.')
              else if (loading)
                const Center(child: CircularProgressIndicator())
              else ...[
                if (error != null) ...[
                  FardaYouNotice(text: error!),
                  TextButton(
                    onPressed: busy ? null : load,
                    child: const Text('Try again'),
                  ),
                ],
                if (inbox && alerts != null) ...[
                  if (alerts!.isEmpty)
                    FardaYouCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.favorite_border,
                            color: design.FardaConsumerColors.brand,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'All quiet here',
                            style: design.FardaConsumerType.title,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Check-ins appear here when both people have opted in. Pull up your circle whenever you’d like.',
                          ),
                        ],
                      ),
                    ),
                  for (final alert in alerts!)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: FardaYouCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              alert.owner.displayName,
                              style: design.FardaConsumerType.bodyStrong,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'No confirmation yet',
                              style: design.FardaConsumerType.title,
                            ),
                            const SizedBox(height: 8),
                            const SizedBox(height: 8),
                            const Text(
                              'A gentle reason to check in. This isn’t proof a dose was missed.',
                            ),
                            if (alert.readAt == null)
                              TextButton(
                                onPressed:
                                    busy
                                        ? null
                                        : () async {
                                          if (!current) return;
                                          setState(() => busy = true);
                                          try {
                                            await widget.repository
                                                .readCircleAlert(alert.id);
                                            if (current) await load();
                                          } catch (_) {
                                            if (current) {
                                              setState(
                                                () =>
                                                    error =
                                                        'Couldn’t mark as read. Try again.',
                                              );
                                            }
                                          }
                                          if (current) {
                                            setState(() => busy = false);
                                          }
                                        },
                                child: const Text('Mark as read'),
                              )
                            else
                              const Text('Read'),
                          ],
                        ),
                      ),
                    ),
                ],
                if (!inbox && policy != null) ...[
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      widget.recipient
                          ? 'Receive check-ins'
                          : 'Allow gentle check-ins',
                      style: design.FardaConsumerType.bodyStrong,
                    ),
                    subtitle: Text(
                      widget.recipient
                          ? 'Let this person’s updates appear in your inbox.'
                          : 'A Family plan feature. Your person must also agree.',
                    ),
                    value: widget.recipient ? consent : enabled,
                    onChanged:
                        busy
                            ? null
                            : (v) => setState(() {
                              if (widget.recipient) {
                                consent = v;
                              } else {
                                enabled = v;
                              }
                            }),
                  ),
                  Text(
                    policy!.enabled && policy!.recipientConsented
                        ? 'Both people have opted in.'
                        : 'Check-ins stay off until both people opt in.',
                    style: design.FardaConsumerType.caption,
                  ),
                  const SizedBox(height: 20),
                  if (!widget.recipient) ...[
                    Text(
                      'Give it a little time',
                      style: design.FardaConsumerType.title,
                    ),
                    Text('$grace minutes after the planned time'),
                    Slider(
                      value: grace.toDouble().clamp(15, 240),
                      min: 15,
                      max: 240,
                      divisions: 15,
                      label: '$grace minutes',
                      onChanged:
                          busy
                              ? null
                              : (v) => setState(() => grace = v.round()),
                    ),
                    Text('Quiet hours', style: design.FardaConsumerType.title),
                    Wrap(
                      spacing: 12,
                      children: [
                        OutlinedButton(
                          onPressed: busy ? null : () => pickTime(true),
                          child: Text('From $start'),
                        ),
                        OutlinedButton(
                          onPressed: busy ? null : () => pickTime(false),
                          child: Text('Until $end'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: zone,
                      enabled: !busy,
                      decoration: const InputDecoration(
                        labelText: 'Timezone',
                        helperText: 'For example: Europe/London or UTC',
                        helperMaxLines: 2,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ] else
                    Text(
                      'After ${policy!.gracePeriodMinutes} minutes · Quiet ${policy!.quietHoursStart}–${policy!.quietHoursEnd} (${policy!.timeZone})',
                      style: design.FardaConsumerType.caption,
                    ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: busy ? null : save,
                    child: Text(busy ? 'Saving…' : 'Save preferences'),
                  ),
                  if (!widget.recipient && widget.onFamilyPlan != null)
                    TextButton(
                      onPressed: busy ? null : widget.onFamilyPlan,
                      child: const Text('Explore Family plan'),
                    ),
                ],
              ],
              const SizedBox(height: 20),
              const FardaYouNotice(
                text:
                    'In-app updates only. No push notification is promised. Check-ins are read-only, and aren’t emergency monitoring.',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

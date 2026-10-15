import 'package:farda/consumer_v2/farda_consumer_shell.dart';
import 'package:flutter/material.dart';

/// Compatibility wrapper retained for the existing authentication flow.
///
/// Login and onboarding already navigate to `/dashboard`; the new consumer
/// shell is mounted here so those flows do not need to change at the same time
/// as the dashboard redesign.
class ScreenDashboardShell extends StatelessWidget {
  final int initialIndex;
  final ValueChanged<int>? onTabSelected;

  const ScreenDashboardShell({
    super.key,
    this.initialIndex = 0,
    this.onTabSelected,
  });

  @override
  Widget build(BuildContext context) {
    return FardaConsumerShell(
      initialIndex: initialIndex,
      onTabSelected: onTabSelected,
    );
  }
}

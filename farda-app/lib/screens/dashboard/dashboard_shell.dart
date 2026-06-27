import 'dart:async';

import 'package:farda/application/authentication/storage/auth_storage.dart';
import 'package:farda/application/reminders/service/notification_service.dart';
import 'package:farda/application/reminders/service/push_service.dart';
import 'package:farda/components/_components.dart';
import 'package:farda/screens/dashboard/calendar/calender_provider.dart';
import 'package:farda/screens/dashboard/calendar/screen_calendar.dart';
import 'package:farda/screens/dashboard/home/screen_home.dart';
import 'package:farda/screens/dashboard/more/screen_more.dart';
import 'package:farda/screens/dashboard/plan/screen_plan.dart';
import 'package:farda/screens/prescription_info/prescription_provider.dart';
import 'package:farda/utilities/auth_gate.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';


class ScreenDashboardShell extends StatefulWidget {
  final Widget? child;
  const ScreenDashboardShell({super.key, this.child});

  @override
  State<ScreenDashboardShell> createState() => _ScreenDashboardShellState();
}

class _ScreenDashboardShellState extends State<ScreenDashboardShell> {
  int currentIndex = 0;
  bool isReverse = false;

  @override
  void initState() {
    super.initState();
    // The dashboard is the authenticated entry point (login navigates here
    // after OTP verification). Trigger the authenticated data fetches now,
    // but only when a valid bearer token exists so we never hit protected
    // endpoints with an empty Authorization header.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchAuthedDataIfSignedIn();
    });
  }

  Future<void> _fetchAuthedDataIfSignedIn() async {
    final token = await AuthStorage.getToken();
    if (!mounted) return;
    if (!AuthGate.shouldFetchAuthedData(token)) return;

    context.read<CalenderProvider>().getCallAllApi();
    context.read<PrescriptionProvider>().getMyPrescriptionApi();

    // Reminder + notification engine (GTM-537): now that we're authenticated,
    // (re)schedule local dose reminders from the backend schedule (survives
    // reinstall + schedule changes), and register the push token when push is
    // enabled (NO-OP otherwise; push is a flagged scaffold). Fire-and-forget so
    // the dashboard renders immediately.
    unawaited(NotificationService.instance.syncSchedule());
    unawaited(PushService().registerIfEnabled());
  }

  void changeIndex(int index) {
    if (index > currentIndex) {
      isReverse = false;
    } else {
      isReverse = true;
    }
    currentIndex = index;
    setState(() {});
  }

  final List<Widget> children = [
    ScreenHome(),
    ScreenPlanHope(),
    ScreenCalendar(),
    ScreenMore(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: widget.child ?? children[currentIndex],
      bottomNavigationBar: BottomNavBar(
        onSelect: changeIndex,
        index: currentIndex,
      ),
    );
  }
}

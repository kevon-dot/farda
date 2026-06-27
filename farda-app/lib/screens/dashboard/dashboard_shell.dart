import 'package:farda/components/_components.dart';
import 'package:farda/screens/dashboard/calendar/screen_calendar.dart';
import 'package:farda/screens/dashboard/home/screen_home.dart';
import 'package:farda/screens/dashboard/more/screen_more.dart';
import 'package:farda/screens/dashboard/plan/screen_plan.dart';
import 'package:flutter/material.dart';


class ScreenDashboardShell extends StatefulWidget {
  final Widget? child;
  const ScreenDashboardShell({super.key, this.child});

  @override
  State<ScreenDashboardShell> createState() => _ScreenDashboardShellState();
}

class _ScreenDashboardShellState extends State<ScreenDashboardShell> {
  int currentIndex = 0;
  bool isReverse = false;
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

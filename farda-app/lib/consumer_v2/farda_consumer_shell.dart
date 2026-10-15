import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'design_system/farda_consumer_tokens.dart';
import 'screens/calendar/farda_calendar_screen.dart';
import 'screens/refills/farda_refills_screen.dart';
import 'screens/today/farda_today_screen.dart';
import 'screens/you/farda_you_screen.dart';

/// The production Flutter entry point for the consumer-v2 Farda experience.
///
/// An [IndexedStack] preserves local page state while changing tabs. This
/// replaces the previous split local-index/ShellRoute navigation behavior.
class FardaConsumerShell extends StatefulWidget {
  const FardaConsumerShell({
    super.key,
    this.initialIndex = 0,
    this.onTabSelected,
  });

  final int initialIndex;
  final ValueChanged<int>? onTabSelected;

  @override
  State<FardaConsumerShell> createState() => _FardaConsumerShellState();
}

class _FardaConsumerShellState extends State<FardaConsumerShell> {
  late int _selectedIndex;
  bool _hideBottomNavigation = false;

  @override
  void initState() {
    super.initState();
    _selectedIndex = _safeIndex(widget.initialIndex);
  }

  @override
  void didUpdateWidget(covariant FardaConsumerShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialIndex != widget.initialIndex) {
      _selectedIndex = _safeIndex(widget.initialIndex);
      if (_selectedIndex != 3) _hideBottomNavigation = false;
    }
  }

  int _safeIndex(int value) {
    if (value < 0) return 0;
    if (value > 3) return 3;
    return value;
  }

  void _selectTab(int index) {
    if (_selectedIndex == index && !_hideBottomNavigation) return;
    setState(() {
      _selectedIndex = index;
      if (index != 3) _hideBottomNavigation = false;
    });
    widget.onTabSelected?.call(index);
  }

  @override
  Widget build(BuildContext context) {
    final consumerTheme = FardaConsumerTheme.from(Theme.of(context));
    return Theme(
      data: consumerTheme,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarBrightness: Brightness.light,
          statusBarIconBrightness: Brightness.dark,
          systemNavigationBarColor: FardaConsumerColors.card,
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
        child: Scaffold(
          backgroundColor: FardaConsumerColors.canvas,
          body: IndexedStack(
            index: _selectedIndex,
            children: [
              FardaTodayScreen(
                showBottomNavigation: false,
                onOpenCalendar: () => _selectTab(1),
                onOpenRefills: () => _selectTab(2),
                onOpenProfile: () => _selectTab(3),
              ),
              const FardaCalendarScreen(),
              const FardaRefillsScreen(),
              FardaYouScreen(
                onNativePreviewChanged: (isNativePreview) {
                  if (_hideBottomNavigation == isNativePreview) return;
                  setState(
                    () => _hideBottomNavigation = isNativePreview,
                  );
                },
              ),
            ],
          ),
          bottomNavigationBar: _hideBottomNavigation
              ? null
              : FardaConsumerNavigationBar(
                  selectedIndex: _selectedIndex,
                  onSelected: _selectTab,
                ),
        ),
      ),
    );
  }
}

class FardaConsumerNavigationBar extends StatelessWidget {
  const FardaConsumerNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const _items = <({String label, IconData icon})>[
    (label: 'Today', icon: Icons.home_outlined),
    (label: 'Calendar', icon: Icons.calendar_today_outlined),
    (label: 'Refills', icon: Icons.sync_rounded),
    (label: 'You', icon: Icons.person_outline_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: FardaConsumerColors.card,
        border: Border(
          top: BorderSide(color: FardaConsumerColors.border, width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(22, 8, 22, 6),
        child: SizedBox(
          height: 62,
          child: Row(
            children: List.generate(_items.length, (index) {
              final item = _items[index];
              final selected = selectedIndex == index;
              return Expanded(
                child: Semantics(
                  selected: selected,
                  button: true,
                  label: '${item.label} tab',
                  child: InkWell(
                    onTap: () => onSelected(index),
                    borderRadius: BorderRadius.circular(
                      FardaConsumerRadius.sm,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          curve: Curves.easeOut,
                          width: 38,
                          height: 32,
                          decoration: BoxDecoration(
                            color: selected
                                ? FardaConsumerColors.soft
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(
                              FardaConsumerRadius.sm,
                            ),
                          ),
                          child: Icon(
                            item.icon,
                            size: 22,
                            color: selected
                                ? FardaConsumerColors.brand
                                : FardaConsumerColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.label,
                          maxLines: 1,
                          style: FardaConsumerType.label.copyWith(
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: selected
                                ? FardaConsumerColors.brand
                                : FardaConsumerColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

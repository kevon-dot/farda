part of '_components.dart';

class CustomTabSelector extends StatelessWidget {
  final List<String> tabs;
  final int selectedIndex;
  final Function(int index) onTabSelected;

  const CustomTabSelector({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    required this.onTabSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FardaColors>()!;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(tabs.length, (index) {
        final isSelected = index == selectedIndex;
        return GestureDetector(
          onTap: () => onTabSelected(index),
          child: Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected ? colors.baseBlack : Colors.transparent,
              borderRadius: BorderRadius.circular(40.r),
            ),
            child: TextMedium(
              text: tabs[index],
              style: TextStyle(
                color: isSelected ? colors.baseWhite : colors.baseBlack,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        );
      }),
    );
  }
}

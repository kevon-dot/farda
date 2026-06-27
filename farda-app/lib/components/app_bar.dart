part of '_components.dart';

enum AppBarTitleType { text, logo }

class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  final AppBarTitleType titleType;
  final String? titleText;
  final Widget? logo;
  final VoidCallback? onBack;
  final bool isChild;
  final bool ? isEndIcon;
  final IconData? iconPath;
  final   VoidCallback? onIconPress;

  const CustomAppBar({
    super.key,
    required this.titleType,
    this.titleText,
    this.iconPath,
    this.isEndIcon,
    this.onIconPress,
    this.logo,
    this.onBack,
    this.isChild = true,
  });

  @override
  Size get preferredSize => Size.fromHeight(76.h);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FardaColors>()!;
    final spacing = theme.extension<Spacing>()!;

    return SafeArea(
      bottom: false,
      child: Container(
        height: preferredSize.height,
        padding: spacing.horizontalDefault,
        decoration: BoxDecoration(color: theme.colorScheme.surface),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Back button (left)
            if (isChild)
              Align(
                alignment: Alignment.centerLeft,
                child: Material(
                  color: Colors.transparent,
                  child: Ink(
                    decoration: BoxDecoration(
                      color: colors.slate.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      splashColor: colors.slate.shade200,
                      highlightColor: colors.slate.shade300,
                      onTap: onBack ?? () => Navigator.of(context).pop(),
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        // adjust touch target size
                        child: SvgPicture.asset(
                          'assets/icons/back.svg',
                          width: 24,
                          height: 24,
                          colorFilter: ColorFilter.mode(
                            colors.slate.shade800,
                            BlendMode.srcIn,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // Title (center)
            Center(
              child:
                  titleType == AppBarTitleType.text
                      ? Text(
                        titleText ?? '',
                        style: theme.textTheme.titleLarge?.merge(
                          TextStyle(fontWeight: FontWeight.w600),
                        ),
                        textAlign: TextAlign.center,
                      )
                      : (logo ?? const SizedBox.shrink()),
            ),
            isEndIcon == true ?  Positioned(
              right: 0,
              child:InkWell(
                onTap: onIconPress,
                child: Icon(iconPath)))  : SizedBox.shrink(), 
          ],
        ),
      ),
    );
  }
}

class MenuItem {
  final String label;
  final String iconPath;
  final String route;

  MenuItem({required this.label, required this.iconPath, required this.route});
}

class BottomNavBar extends StatefulWidget {
  final int index;
  final Function(int index) onSelect;

  const BottomNavBar({super.key, required this.index, required this.onSelect});

  @override
  State<BottomNavBar> createState() => _BottomNavBarState();
}

class _BottomNavBarState extends State<BottomNavBar> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FardaColors>()!;

    final unselectedIcon = ColorFilter.mode(
      colors.slate.shade600,
      BlendMode.srcIn,
    );
    final selectedIcon = ColorFilter.mode(colors.baseBlack, BlendMode.srcIn);
    final iconSize = 18.h;
    final gap = 6.h;

    final menuItems = [
      MenuItem(label: 'Home', iconPath: "assets/icons/home.svg", route: 'home'),
      MenuItem(
        label: 'Plan',
        iconPath: "assets/icons/check_list.svg",
        route: 'plan',
      ),
      MenuItem(
        label: 'Calendar',
        iconPath: "assets/icons/calendar.svg",
        route: 'calendar',
      ),
      MenuItem(label: 'More', iconPath: "assets/icons/more.svg", route: 'more'),
    ];

    return SafeArea(
      top: false,
      child: Container(
        height: kToolbarHeight * 1.3,
        decoration: BoxDecoration(
          color: colors.baseWhite,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              offset: Offset(4, 0),
              blurRadius: 14.r,
            ),
          ],
        ),
        child: Row(
          children:
              menuItems.asMap().entries.map((entry) {
                final i = entry.key;
                final item = entry.value;
                final selected = widget.index == i;
                return Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () {
                      widget.onSelect(i);
                    },
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SvgPicture.asset(
                          item.iconPath,
                          height: iconSize,
                          width: iconSize,
                          colorFilter: selected ? selectedIcon : unselectedIcon,
                        ),
                        SizedBox(height: gap),
                        _menuText(
                          context,
                          text: item.label,
                          isSelected: selected,
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
        ),
      ),
    );
  }

  Widget _menuText(
    BuildContext context, {
    required String text,
    required bool isSelected,
  }) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).extension<FardaColors>()!;
    final color = isSelected ? colors.baseBlack : colors.slate.shade600;
    return Text(
      text,
      style: textTheme.bodyMedium?.copyWith(
        color: color,
        fontSize: 14.sp,
        fontWeight: isSelected ? FontWeight.w500 : FontWeight.w400,
      ),
    );
  }
}

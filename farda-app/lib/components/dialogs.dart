part of './_components.dart';

class ThoughtDialog extends StatelessWidget {
  const ThoughtDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // final textTheme = theme.textTheme;
    final colors = theme.extension<FardaColors>()!;
    // final spacing = theme.extension<Spacing>()!;
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      backgroundColor: colors.baseWhite,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              /// Header row with close button
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.grey),
                  ),
                ],
              ),

              /// Header title
              Row(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SvgPicture.asset(
                    "assets/icons/note.svg",
                    colorFilter: ColorFilter.mode(
                      colors.slate.shade400,
                      BlendMode.srcIn,
                    ),
                  ),
                  TextMedium(
                    text: "Thoughts?",
                    style: TextStyle(
                      color: colors.slate.shade400,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),

              /// Input field
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: TextField(
                  maxLines: 5,
                  decoration: InputDecoration(
                    hintText: "Note",
                    hintStyle: const TextStyle(color: Colors.grey),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 0),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              /// Toolbar icons row
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    onPressed: () {},
                    icon: SvgPicture.asset("assets/icons/note.svg"),
                  ),
                  IconButton(
                    onPressed: () {},
                    icon: SvgPicture.asset("assets/icons/tag.svg"),
                  ),
                  IconButton(
                    onPressed: () {},
                    icon: SvgPicture.asset("assets/icons/list.svg"),
                  ),
                  IconButton(
                    onPressed: () {},
                    icon: SvgPicture.asset("assets/icons/flag.svg"),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              /// Save button
              Container(
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: colors.slate.shade100, width: 1.r),
                  ),
                ),
                padding: EdgeInsets.only(top: 16.h),
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(32),
                      ),
                    ),
                    onPressed: () {
                      // TODO: Save logic
                    },
                    child: const Text(
                      "Save",
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

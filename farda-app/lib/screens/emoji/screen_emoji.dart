import 'package:farda/components/_components.dart';
import 'package:farda/components/custom_snackbar.dart';
import 'package:farda/components/note_dialog.dart';
import 'package:farda/routes/routes.dart';
import 'package:farda/screens/dashboard/calendar/calender_provider.dart';
import 'package:farda/screens/emoji/emoji_provider.dart';
import 'package:farda/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/svg.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

class ScreenEmoji extends StatelessWidget {
  const ScreenEmoji({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FardaColors>()!;
    final spacing = theme.extension<Spacing>()!;
    final emojiProvider = context.watch<EmojiProvider>();
    final calenderProvider = context.watch<CalenderProvider>();
    return ExtendedScaffold(
      body: SafeArea(
        child: Padding(
          padding: spacing.horizontalDefault,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              16.verticalSpace,
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: colors.success[300],
                      shape: BoxShape.circle,
                    ),
                    padding: EdgeInsets.all(8.r),
                    child: TextMedium(
                      text: emojiProvider.feelings[0].emoji,
                      style: TextStyle(fontSize: 32.sp),
                    ),
                  ),
                  GestureDetector(
                    onTap: (){
                      context.pop();
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: colors.slate[100],
                        shape: BoxShape.circle,
                      ),
                      padding: EdgeInsets.all(12.r),
                      child: SvgPicture.asset("assets/icons/close.svg"),
                    ),
                  ),
                ],
              ),
              12.verticalSpace,
              Text(
                "Choose an emoji",
                style: theme.textTheme.titleLarge?.merge(
                  TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              12.verticalSpace,
              TextMedium(text: "What defines the time of the day the most?"),
              42.verticalSpace,
              Expanded(
                child: GridView.count(
                  crossAxisCount: 4,
                  shrinkWrap: true,
                  // physics: NeverScrollableScrollPhysics(),
                  children:
                      emojiProvider.feelings.asMap().entries.map((entry) {
                        final index = entry.key;
                        final item = entry.value;

                        return Center(
                          child: GestureDetector(
                            onTap: () {
                              emojiProvider.selecteEmoji(index, item.name);
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                color: colors.slate.shade100,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: emojiProvider.selected == index ?  colors.slate.shade500 : Colors.transparent,
                                ),
                              ),
                              padding: EdgeInsets.all(12.r),
                              child: TextMedium(
                                text: item.emoji,
                                style: TextStyle(fontSize: 32.sp),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                ),
              ),
              Container(
                padding: EdgeInsets.all(16.w),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: colors.slate.shade100, width: 1.0),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: ButtonTertiary(
                        text: "Skip",
                        onClick: () {
                          context.pop();
                        },
                      ),
                    ),
                    12.horizontalSpace,
                    Expanded(
                      child: ButtonPrimary(
                        text: "Set emoji",
                        onClick: ()async {
                         String  data = await  calenderProvider.setMoodApi(emojiProvider.selectedName);
                         CustomSnackbar.show(context, message: data);
                         showThoughtsDialog(context,calenderProvider );
                          
                        },
                      ),
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

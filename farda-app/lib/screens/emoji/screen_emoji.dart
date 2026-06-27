import 'package:auto_route/auto_route.dart';
import 'package:farda/components/_components.dart';
import 'package:farda/components/custom_snackbar.dart';
import 'package:farda/components/note_dialog.dart';
import 'package:farda/routes/routes.dart';
import 'package:farda/screens/dashboard/calendar/calender_provider.dart';
import 'package:farda/screens/emoji/emoji_provider.dart';
import 'package:farda/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/svg.dart';
import 'package:go_router/go_router.dart';

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
                      Navigator.pop(context);
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
                          Navigator.pop(context);
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

_prescription(
  BuildContext context, {
  required String drName,
  required String address,
  required String patientName,
  required String rxNumber,
  required String storeNumber,
  required String title,
  required String description,
  required String quantity,
  String? notification,
  String? sideEffects,
}) {
  final theme = Theme.of(context);
  final colors = theme.extension<FardaColors>()!;
  return Container(
    padding: EdgeInsets.all(16.r),
    decoration: BoxDecoration(
      border: Border.all(color: colors.slate.shade300),
      borderRadius: BorderRadius.circular(10.r),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            SizedBox(
              height: 60.h,
              width: 60.h,
              child: Center(child: SvgPicture.asset("assets/icons/rx.svg")),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(drName, style: theme.textTheme.titleMedium),
                  Text(address, style: theme.textTheme.titleMedium),
                ],
              ),
            ),
          ],
        ),
        Container(
          padding: EdgeInsets.all(8.r),
          decoration: BoxDecoration(
            border: Border.all(color: colors.slate.shade300),
            borderRadius: BorderRadius.circular(8.r),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    "Patient Name:",
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.slate.shade600,
                    ),
                  ),
                  Text(
                    patientName,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.slate.shade600,
                    ),
                  ),
                ],
              ),
              8.verticalSpace,
              Container(
                padding: EdgeInsets.all(6.r),
                decoration: BoxDecoration(
                  color: colors.warning[50],
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      "RX Number:",
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.slate.shade600,
                      ),
                    ),
                    Text(
                      rxNumber,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.error[500],
                      ),
                    ),
                  ],
                ),
              ),
              4.verticalSpace,
              Container(
                padding: EdgeInsets.all(6.r),
                decoration: BoxDecoration(
                  color: colors.warning[50],
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Store Number:",
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.slate.shade600,
                      ),
                    ),
                    Text(
                      storeNumber,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.error[500],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        12.verticalSpace,
        Text(
          title,
          style: theme.textTheme.titleLarge?.copyWith(fontSize: 16.sp),
        ),
        8.verticalSpace,
        Text(
          description,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.slate.shade600,
          ),
        ),
        8.verticalSpace,
        Text(
          "Qty: $quantity",
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.slate.shade600,
          ),
        ),
        if (notification != null) 8.verticalSpace,
        if (notification != null)
          Text(
            notification,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.slate.shade600,
            ),
          ),
        if (sideEffects != null) 8.verticalSpace,
        if (sideEffects != null)
          Container(
            padding: EdgeInsets.all(12.r),
            decoration: BoxDecoration(
              color: colors.slate.shade100,
              borderRadius: BorderRadius.circular(8.r),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  "Side Effects:",
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.slate.shade800,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                8.verticalSpace,
                Text(
                  sideEffects,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.slate.shade600,
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

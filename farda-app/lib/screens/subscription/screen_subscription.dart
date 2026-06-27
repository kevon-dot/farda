
import 'package:farda/components/_components.dart';
import 'package:farda/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/svg.dart';

class ScreenSubscription extends StatefulWidget {
  const ScreenSubscription({super.key});

  @override
  State<ScreenSubscription> createState() => _ScreenSubscriptionState();
}

class _ScreenSubscriptionState extends State<ScreenSubscription> {
  bool isYearly = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FardaColors>()!;
    final spacing = theme.extension<Spacing>()!;
    return ExtendedScaffold(
      body: Stack(
        children: [
          Positioned(
            right: 0,
            top: 0,
            child: Image.asset(
              "assets/images/image_medicine.png",
              height: 0.18.sh,
            ),
          ),
          Positioned.fill(
            child: SafeArea(
              child: SingleChildScrollView(
                padding: spacing.horizontalDefault,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    32.verticalSpace,
                    TextMedium(
                      text: "Say, hello to\nyour best self.",
                      style: theme.textTheme.titleLarge,
                    ),
                    8.verticalSpace,
                    TextMedium(
                      text:
                          "Members are up to 65% more likely to reach their goals with Premium.",
                    ),
                    42.verticalSpace,
                    _featureWidget(
                      context,
                      point: "Joumal: ",
                      description:
                          "Keep track of your feels and symptoms with ease",
                    ),
                    12.verticalSpace,
                    _featureWidget(
                      context,
                      point: "Automated Pharmacy Notifications: ",
                      description:
                          "Have data analytics and tracking send in pharmacy requests hands-free",
                    ),
                    12.verticalSpace,
                    _featureWidget(
                      context,
                      point: "Zero Ads: ",
                      description:
                          "Track and reach your goals, distraction-free",
                    ),
                    48.verticalSpace,
                    Text(
                      "Select a plan for your free trial.",
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.merge(
                        TextStyle(
                          color: colors.slate.shade800,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    12.verticalSpace,
                    Row(
                      children: [
                        Expanded(
                          child: PricingCard(
                            title: 'YEARLY',
                            price: '\$68.00',
                            period: '/YR',
                            originalPrice: '\$94.88/YR',
                            billingInfo: 'Billed yearly after free trial',
                            isSelected: isYearly,
                            onTap: () {
                              setState(() {
                                isYearly = true;
                              });
                            },
                          ),
                        ),
                        16.horizontalSpace,
                        Expanded(
                          child: PricingCard(
                            title: 'MONTHLY',
                            price: '\$7.99',
                            period: '/MO',
                            originalPrice: '',
                            billingInfo: 'Billed monthly after free trial',
                            isSelected: !isYearly,
                            onTap: () {
                              setState(() {
                                isYearly = false;
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    48.verticalSpace,
                    Text(
                      "Change plans or cancel anytime.",
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.merge(
                        TextStyle(
                          color: colors.slate.shade400,
                          fontSize: 16.sp,
                        ),
                      ),
                    ),
                    12.verticalSpace,
                    ButtonTertiary(
                      text: "Continue for Free",
                      onClick: () {
                        // context.pushRoute(RoutePrescription());
                      },
                    ),
                    12.verticalSpace,
                    ButtonPrimary(
                      text: "Start 1-Month Free Trial",
                      onClick: () {
                        // context.pushRoute(RoutePrescription());
                      },
                    ),
                    8.verticalSpace,
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _featureWidget(
    BuildContext context, {
    required String point,
    required String description,
  }) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8.r),
            color: theme.colorScheme.surface,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                offset: Offset(0, 2),
                blurRadius: 24,
              ),
            ],
          ),
          height: 48.h,
          width: 48.h,
          child: Center(
            child: SvgPicture.asset(
              "assets/icons/premium.svg",
              height: 20.h,
              width: 20.h,
            ),
          ),
        ),
        16.horizontalSpace,
        Expanded(
          child: RichText(
            text: TextSpan(
              style: theme.textTheme.bodyMedium?.copyWith(fontSize: 16.sp),
              children: [
                TextSpan(
                  text: point,
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(
                  text: description,
                  style: TextStyle(fontWeight: FontWeight.w400),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

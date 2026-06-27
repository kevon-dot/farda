import 'package:farda/application/authentication/repo/authentication_repo.dart';
import 'package:farda/components/_components.dart';
import 'package:farda/components/custom_snackbar.dart';
import 'package:farda/screens/login/login_controller.dart';
import 'package:farda/screens/login/login_provider.dart';
import 'package:farda/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/svg.dart';
import 'package:go_router/go_router.dart';

class ScreenLogin extends StatelessWidget {
  const ScreenLogin({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<FardaColors>()!;
    final spacing = theme.extension<Spacing>()!;
    final loginProvider = context.watch<LoginProvider>();
    return ExtendedScaffold(
      appBar: CustomAppBar(
        onBack: () {
          context.go("/");
        },
        titleType: AppBarTitleType.logo,
        logo: Image.asset(
          "assets/images/farda_large_grey.png",
          height: 0.03.sh,
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: spacing.horizontalDefault,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              12.verticalSpace,
              Text(
                "Enter your mobile number",
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.baseBlack,
                  fontSize: 15.sp,
                ),
              ),
              6.verticalSpace,
              PhoneNumberInput(
                onPhoneNumberChanged: (phoneNumber) {
                  loginProvider.updatePhoneNumber(phoneNumber);
                },
                onCountryChanged: (country) {
                  loginProvider.updateCountryCode(country.dialCode);
                },
                hintText: 'Mobile number',
              ),
              20.verticalSpace,
              ButtonPrimary(
                text: loginProvider.isLoading ? "Loading..." : "Continue",
                onClick:
                    loginProvider.isLoading
                        ? null
                        : () => LoginController.onContinueClicked(context),
              ),
              16.verticalSpace,
              DividerTextHorizontal(text: "or"),
              16.verticalSpace,
              ButtonSecondary(
                prefixIcon: SvgPicture.asset("assets/icons/apple.svg"),
                text: "Continue With Apple",
                onClick: () {},
              ),
              12.verticalSpace,
              ButtonSecondary(
                prefixIcon: SvgPicture.asset("assets/icons/google.svg"),
                text: "Continue With Google",
                onClick: () {},
              ),
            ],
          ),
        ),
      ),
    );
  }
}

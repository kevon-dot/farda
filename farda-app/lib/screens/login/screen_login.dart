import 'package:farda/components/_components.dart';
import 'package:farda/features/consumer/consumer_widgets.dart';
import 'package:farda/screens/login/auth_page.dart';
import 'package:farda/screens/login/login_controller.dart';
import 'package:farda/screens/login/login_provider.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

class ScreenLogin extends StatelessWidget {
  const ScreenLogin({super.key});

  @override
  Widget build(BuildContext context) {
    final login = context.watch<LoginProvider>();
    return AuthPage(
      title: 'A little closer\nto your day.',
      subtitle: 'Enter your mobile number. We’ll text you a sign-in code.',
      onBack: () => context.go('/'),
      children: [
        AbsorbPointer(
          absorbing: login.isLoading,
          child: PhoneNumberInput(
            initialPhoneNumber: login.phoneNumber,
            // Match the displayed prefix to the actual sign-in request.
            // The shared input otherwise defaults to the first country.
            initialCountry: Country(
              name: 'Country calling code',
              code: '',
              dialCode: login.countryCode,
              flag: '🌐',
            ),
            onPhoneNumberChanged: login.updatePhoneNumber,
            onCountryChanged:
                (country) => login.updateCountryCode(country.dialCode),
            hintText: 'Mobile number',
          ),
        ),
        const SizedBox(height: 24),
        Semantics(
          liveRegion: login.isLoading,
          child: ConsumerButton(
            login.isLoading ? 'Sending code…' : 'Send code',
            busy: login.isLoading,
            onPressed:
                login.isLoading
                    ? null
                    : () => LoginController.onContinueClicked(context),
          ),
        ),
      ],
    );
  }
}

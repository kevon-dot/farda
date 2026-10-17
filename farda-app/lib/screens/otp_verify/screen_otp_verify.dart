import 'package:farda/features/consumer/consumer_widgets.dart';
import 'package:farda/screens/login/auth_page.dart';
import 'package:farda/screens/login/login_provider.dart';
import 'package:farda/screens/otp_verify/otp_verify_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

class ScreenOtpVerify extends StatefulWidget {
  const ScreenOtpVerify({super.key});

  @override
  State<ScreenOtpVerify> createState() => _ScreenOtpVerifyState();
}

class _ScreenOtpVerifyState extends State<ScreenOtpVerify> {
  final _code = TextEditingController();
  bool _submitting = false;
  bool _resending = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  bool get _busy =>
      _submitting || _resending || context.read<LoginProvider>().isLoading;

  Future<void> _verify() async {
    if (_busy || _code.text.length != 6) return;
    FocusScope.of(context).unfocus();
    setState(() => _submitting = true);
    try {
      await OtpVerifyController.onSubmitPin(context, _code.text);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _resend() async {
    if (_busy) return;
    setState(() => _resending = true);
    try {
      await OtpVerifyController.onResendCode(context);
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  void _back() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final login = context.watch<LoginProvider>();
    final busy = _busy;
    return AuthPage(
      title: 'Check your texts.',
      subtitle:
          'Enter the 6-digit code sent to ${login.countryCode}${login.phoneNumber}.',
      onBack: _back,
      children: [
        AutofillGroup(
          child: TextField(
            key: const Key('auth_code'),
            controller: _code,
            enabled: !busy,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.oneTimeCode],
            autocorrect: false,
            enableSuggestions: false,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            decoration: const InputDecoration(labelText: '6-digit code'),
            style: consumerText(24, weight: FontWeight.w600),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _verify(),
          ),
        ),
        const SizedBox(height: 24),
        Semantics(
          liveRegion: _submitting,
          child: ConsumerButton(
            _submitting ? 'Checking code…' : 'Continue',
            busy: _submitting,
            onPressed: busy || _code.text.length != 6 ? null : _verify,
          ),
        ),
        const SizedBox(height: 12),
        Semantics(
          liveRegion: _resending,
          child: TextButton(
            onPressed: busy ? null : _resend,
            child: Text(_resending ? 'Sending another code…' : 'Resend code'),
          ),
        ),
        TextButton(
          onPressed: busy ? null : _back,
          child: const Text('Use a different number'),
        ),
      ],
    );
  }
}

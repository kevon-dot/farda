import 'package:farda/consumer_v2/design_system/farda_consumer_tokens.dart';
import 'package:farda/features/consumer/consumer_widgets.dart';
import 'package:farda/theme.dart';
import 'package:flutter/material.dart';

/// Shared, keyboard-safe presentation for phone sign-in and verification.
class AuthPage extends StatelessWidget {
  const AuthPage({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onBack,
    required this.children,
  });
  final String title;
  final String subtitle;
  final VoidCallback onBack;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final colors = base.extension<FardaColors>() ?? FardaColors.light;
    final theme = FardaConsumerTheme.from(ConsumerPalette.theme).copyWith(
      extensions: [
        ...base.extensions.values.where(
          (extension) => extension is! FardaColors,
        ),
        colors.copyWith(
          baseBlack: FardaConsumerColors.brand,
          // The existing country/phone control reads these legacy slots.
          // Keep its placeholder readable on the consumer's white input.
          slate: MaterialColor(0xFF142C55, {
            for (final shade in [
              50,
              100,
              200,
              300,
              400,
              500,
              600,
              700,
              800,
              900,
              950,
            ])
              shade: colors.slate[shade]!,
            300: FardaConsumerColors.textSecondary,
            700: FardaConsumerColors.brand,
          }),
        ),
      ],
    );
    return Theme(
      data: theme,
      child: Scaffold(
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 540),
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Back',
                          onPressed: onBack,
                          icon: const Icon(
                            Icons.arrow_back_rounded,
                            color: FardaConsumerColors.brand,
                          ),
                        ),
                        const Spacer(),
                        Text('farda.', style: FardaConsumerType.heading),
                      ],
                    ),
                    const SizedBox(height: 32),
                    Container(
                      alignment: Alignment.centerLeft,
                      child: const DecoratedBox(
                        decoration: BoxDecoration(
                          color: FardaConsumerColors.soft,
                          shape: BoxShape.circle,
                        ),
                        child: Padding(
                          padding: EdgeInsets.all(18),
                          child: Icon(
                            Icons.sms_outlined,
                            size: 28,
                            color: FardaConsumerColors.brand,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Semantics(
                      header: true,
                      child: Text(
                        title,
                        style:
                            MediaQuery.textScalerOf(context).scale(14) > 18
                                ? FardaConsumerType.display.copyWith(
                                  fontSize: 28,
                                  height: 32 / 28,
                                )
                                : FardaConsumerType.display,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      subtitle,
                      style: FardaConsumerType.body.copyWith(
                        color: FardaConsumerColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 28),
                    ...children,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

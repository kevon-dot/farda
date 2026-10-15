import 'package:flutter/material.dart';

/// Hardware enrollment is deliberately unavailable until the exact GATT roles,
/// physical proof and per-device credentials are verified. A BLE address or
/// typed ID is not an authenticated device claim.
class ScreenConnectOnboard extends StatelessWidget {
  const ScreenConnectOnboard({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Your Farda vial')),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Image.asset(
                'assets/images/vial_bottle.png',
                fit: BoxFit.contain,
              ),
            ),
            Text(
              'Good things are on the way.',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 12),
            const Text(
              'Vial setup will be available after hardware verification. You can set up your routine and log doses now.',
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Continue without a vial'),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    ),
  );
}

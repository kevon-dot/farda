import 'package:farda/application/authentication/storage/auth_storage.dart';
import 'package:farda/env.dart';
import 'package:farda/features/consumer/consumer_controller.dart';
import 'package:farda/features/consumer/data/consumer_api_repository.dart';
import 'package:farda/features/consumer/data/consumer_repository.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'farda_consumer_shell.dart';

/// Authenticated entry for the Figma Today and Calendar screens. Preview
/// widgets remain injectable in isolation, but this route never uses fixtures.
class ConsumerV2Entry extends StatefulWidget {
  const ConsumerV2Entry({
    super.key,
    this.initialIndex = 0,
    this.repository,
    this.onTabSelected,
    this.onOpenAccount,
  });

  final int initialIndex;
  final ConsumerRepository? repository;
  final ValueChanged<int>? onTabSelected;
  final VoidCallback? onOpenAccount;

  @override
  State<ConsumerV2Entry> createState() => _ConsumerV2EntryState();
}

class _ConsumerV2EntryState extends State<ConsumerV2Entry>
    with WidgetsBindingObserver {
  late final ConsumerController controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final repository = widget.repository ?? ConsumerApiRepository(
      baseUrl: appBaseUrl,
      tokenInvalidator: AuthStorage.invalidateToken,
      tokenProvider: () async {
        final session = await AuthStorage.getSession();
        return session['access'];
      },
    );
    controller = ConsumerController(repository)..load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !controller.loading) {
      controller.load();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      if (controller.snapshot == null) {
        return Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (controller.loading)
                      const CircularProgressIndicator()
                    else ...[
                      Text(controller.error ?? 'Your routine is unavailable.',
                          textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: controller.sessionExpired
                            ? () => context.go('/login')
                            : controller.load,
                        child: Text(controller.sessionExpired
                            ? 'Sign in again'
                            : 'Try again'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      }

      return Column(
        children: [
          if (controller.error != null)
            MaterialBanner(
              content: const Text('Showing your last loaded record. Refresh to check for updates.'),
              actions: [
                TextButton(onPressed: controller.load, child: const Text('Refresh')),
              ],
            ),
          Expanded(
            child: FardaConsumerShell(
              initialIndex: widget.initialIndex,
              controller: controller,
              onTabSelected: widget.onTabSelected,
              onOpenAccount: widget.onOpenAccount,
            ),
          ),
        ],
      );
    },
  );
}

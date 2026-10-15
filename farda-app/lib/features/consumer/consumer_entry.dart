import 'package:farda/application/authentication/storage/auth_storage.dart';
import 'package:farda/env.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'consumer_app.dart';
import 'consumer_widgets.dart';
import 'data/consumer_api_repository.dart';
import 'data/consumer_demo_repository.dart';
import 'data/consumer_repository.dart';

class ConsumerEntry extends StatefulWidget {
  const ConsumerEntry({super.key, this.demo = false, this.initialTab = 0});
  final bool demo;
  final int initialTab;
  @override
  State<ConsumerEntry> createState() => _ConsumerEntryState();
}

class _ConsumerEntryState extends State<ConsumerEntry> {
  late ConsumerRepository _repository;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _repository =
        widget.demo
            ? ConsumerDemoRepository()
            : ConsumerApiRepository(
              baseUrl: appBaseUrl,
              tokenInvalidator: AuthStorage.invalidateToken,
              tokenProvider: () async {
                final session = await AuthStorage.getSession();
                return session['access'];
              },
            );
  }

  @override
  Widget build(BuildContext context) => ConsumerApp(
    key: ValueKey(_generation),
    repository: _repository,
    initialTab: widget.initialTab,
    onResetDemo:
        widget.demo
            ? () => setState(() {
              _repository = ConsumerDemoRepository();
              _generation++;
            })
            : null,
    onSignIn: () => context.go('/login'),
    onOpenHardware: () => context.push('/screen-connect-onboard'),
    onSignOut:
        widget.demo
            ? null
            : () async {
              final session = await AuthStorage.getSession();
              final token = session['access'];
              final revoked =
                  token == null ? false : await _repository.signOut(token);
              try {
                if (token != null) await AuthStorage.invalidateToken(token);
              } catch (_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Your device session could not be cleared. Please try signing out again.',
                      ),
                    ),
                  );
                }
                if (context.mounted) context.go('/onboard');
                return;
              }
              if (context.mounted) {
                if (!revoked) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Signed out on this device. Server session revocation could not be confirmed.',
                      ),
                    ),
                  );
                }
                context.go('/onboard');
              }
            },
  );
}

class ConsumerWelcome extends StatefulWidget {
  const ConsumerWelcome({super.key});
  @override
  State<ConsumerWelcome> createState() => _ConsumerWelcomeState();
}

class _ConsumerWelcomeState extends State<ConsumerWelcome> {
  String? _sessionMessage;
  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    try {
      final session = await AuthStorage.getSession();
      if (!mounted) return;
      if (session['access']?.isNotEmpty ?? false) context.go('/dashboard');
    } catch (_) {
      if (mounted)
        setState(
          () =>
              _sessionMessage =
                  'Your saved session could not be opened. Please sign in again.',
        );
    }
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: ConsumerPalette.theme,
    child: Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540),
            child: LayoutBuilder(
              builder:
                  (context, constraints) => SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(28, 22, 28, 24),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight - 46,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          if (_sessionMessage != null)
                            ConsumerNotice(_sessionMessage!, attention: true),
                          Text(
                            'farda',
                            style: consumerText(
                              37,
                              weight: FontWeight.w600,
                            ).copyWith(letterSpacing: -2),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(28),
                                  decoration: BoxDecoration(
                                    color: ConsumerPalette.pale,
                                    borderRadius: BorderRadius.circular(36),
                                  ),
                                  child: const Center(
                                    child: ConsumerCompanion(size: 190),
                                  ),
                                ),
                                const ConsumerHeading(
                                  'A little more\nroom for you.',
                                  eyebrow: 'YOUR DAY. YOUR ROUTINE.',
                                  subtitle:
                                      'Helpful reminders, a clear record, and one less thing to hold in mind.',
                                ),
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.check_circle_outline,
                                      color: ConsumerPalette.blue,
                                      size: 17,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Start with or without a Farda vial.',
                                        style: consumerText(
                                          13,
                                          color: ConsumerPalette.muted,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              ConsumerButton(
                                'Get started',
                                icon: Icons.arrow_forward_rounded,
                                onPressed: () => context.go('/login'),
                              ),
                              const SizedBox(height: 10),
                              TextButton(
                                onPressed: () => context.push('/consumer/demo'),
                                child: const Text('Explore the demo'),
                              ),
                              Text(
                                'Demo uses sample data and makes no calls.',
                                textAlign: TextAlign.center,
                                style: consumerText(
                                  11,
                                  color: ConsumerPalette.muted,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
            ),
          ),
        ),
      ),
    ),
  );
}

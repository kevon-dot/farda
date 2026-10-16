import 'package:farda/application/authentication/storage/auth_storage.dart';
import 'package:farda/consumer_v2/screens/membership/farda_membership_screen.dart';
import 'package:farda/env.dart';
import 'package:farda/features/consumer/data/consumer_api_repository.dart';
import 'package:flutter/material.dart';

/// Keep the existing route while using the same account-backed membership UI.
class ScreenSubscription extends StatefulWidget {
  const ScreenSubscription({super.key});

  @override
  State<ScreenSubscription> createState() => _ScreenSubscriptionState();
}

class _ScreenSubscriptionState extends State<ScreenSubscription> {
  late final ConsumerApiRepository _repository = ConsumerApiRepository(
    baseUrl: appBaseUrl,
    tokenProvider: AuthStorage.getToken,
    tokenInvalidator: AuthStorage.invalidateToken,
  );

  @override
  Widget build(BuildContext context) => FardaMembershipScreen(repository: _repository);
}

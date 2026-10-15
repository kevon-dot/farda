import 'dart:convert';

import 'package:farda/application/authentication/storage/session_store.dart';
import 'package:farda/utilities/api_configuration.dart';
import 'package:http/http.dart' as http;

import 'device_observation.dart';
import 'device_outbox.dart';

class HttpObservationUploader implements ObservationUploader {
  HttpObservationUploader({
    required this.client,
    required this.apiRoot,
    required this.sessions,
    this.timeout = const Duration(seconds: 20),
  });
  final http.Client client;
  final String apiRoot;
  final SessionStore sessions;
  final Duration timeout;

  @override
  Future<DeviceReceipt> upload(
    String userId,
    DeviceObservation observation,
  ) async {
    final session = await sessions.read();
    if (session == null || session.userId != userId) {
      throw StateError('Active account changed');
    }
    final request = http.Request(
      'POST',
      apiUri(
        apiRoot,
        'user/devices/${Uri.encodeComponent(observation.deviceId)}/observations',
      ),
    );
    request.followRedirects = false;
    request.headers.addAll({
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${session.token}',
    });
    request.body = jsonEncode(observation.toRequest());
    final response = await client
        .send(request)
        .then(http.Response.fromStream)
        .timeout(timeout);
    if (response.statusCode == 401) {
      // Do not clear a newer account because a previous request returned late.
      await sessions.invalidateToken(session.token);
      throw StateError('Session expired');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Observation upload failed');
    }
    final value = jsonDecode(response.body);
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid receipt');
    }
    final receipt = DeviceReceipt(value);
    if (!receipt.commits(observation)) {
      throw const FormatException('Uncommitted observation receipt');
    }
    return receipt;
  }
}

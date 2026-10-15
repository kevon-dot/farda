import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'consumer_models.dart';
import 'consumer_repository.dart';
import 'label_scan.dart';
import 'package:http_parser/http_parser.dart';

/// The production adapter never substitutes fixture data after a failed request.
/// Transport logs deliberately contain neither bearer tokens nor health records.
class ConsumerApiRepository implements ConsumerRepository, LabelScanRepository {
  ConsumerApiRepository({
    required String baseUrl,
    required Future<String?> Function() tokenProvider,
    Future<bool> Function(String token)? tokenInvalidator,
    http.Client? client,
  }) : _base = baseUrl.replaceFirst(RegExp(r'/+$'), ''),
       _tokenProvider = tokenProvider,
       _tokenInvalidator = tokenInvalidator,
       _client = client ?? http.Client();
  final String _base;
  final Future<String?> Function() _tokenProvider;
  final Future<bool> Function(String token)? _tokenInvalidator;
  final http.Client _client;
  final Map<String, int> _inventoryRevisions = {};
  final Map<String, int> _occurrenceRevisions = {};
  final Map<String, String> _refillIds = {};
  int _writeSequence = 0;
  String? _consentVersion;
  @override
  bool get isDemo => false;

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, Object?>? body,
    Map<String, String>? query,
    String? requestToken,
  }) async {
    String? token;
    try {
      token = requestToken ?? await _tokenProvider();
    } catch (_) {
      throw const ConsumerRepositoryException(
        'Your saved session could not be read. Sign in again to continue.',
        sessionExpired: true,
      );
    }
    if (token == null || token.isEmpty) {
      throw const ConsumerRepositoryException(
        'Sign in to see your private routine.',
        sessionExpired: true,
      );
    }
    final uri = Uri.parse('$_base/$path').replace(queryParameters: query);
    final request =
        http.Request(method, uri)
          ..followRedirects = false
          ..headers.addAll({
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          });
    if (body != null) request.body = jsonEncode(body);
    try {
      final response = await http.Response.fromStream(
        await _client.send(request),
      ).timeout(const Duration(seconds: 20));
      String? currentToken;
      try {
        currentToken = await _tokenProvider();
      } catch (_) {
        throw const ConsumerRepositoryException(
          'Your saved session could not be read. Private records are hidden until you sign in again.',
          sessionExpired: true,
        );
      }
      if (currentToken != token) {
        throw const ConsumerRepositoryException(
          'Your account session changed. Refresh to continue.',
          sessionExpired: true,
          sessionChanged: true,
        );
      }
      String? recovery;
      if (response.statusCode >= 400) {
        try {
          final body = jsonDecode(response.body);
          if (body is Map) {
            const codes = {
              'conflict':
                  'This record changed. Close this form, refresh, and review it before editing.',
              'cancelled_occurrence':
                  'This reminder was cancelled. Choose its active replacement in your calendar.',
              'ambiguous_local_time':
                  'This schedule crosses a daylight-saving time that is ambiguous or unavailable. Choose another reminder time.',
              'no_future_occurrences':
                  'This schedule has no upcoming reminders. Choose a later start date or reminder time.',
              'idempotency_conflict':
                  'This draft changed after an earlier save. Review your prescriptions before creating another.',
            };
            const messages = {
              'Supply changed. Refresh the count before saving.',
              'A more recent count already exists.',
              'This receipt or request was already reconciled with different details.',
              'Confirm you received the refill before reconciling supply.',
              'Record a count first, then confirm whether it includes this refill.',
              'Supply changed. Refresh before adding this receipt.',
              'Your count is newer than this receipt. Reconcile whether it already includes the refill.',
              'This refill plan is closed.',
            };
            recovery = codes[body['code']];
            if (messages.contains(body['error'])) {
              recovery = body['error'] as String;
            }
          }
        } on FormatException {
          /* Unknown upstream bodies stay out of the UI. */
        }
      }
      if (response.statusCode == 401) {
        try {
          await _tokenInvalidator?.call(token);
        } catch (_) {
          throw const ConsumerRepositoryException(
            'Your session ended. Private records are hidden, but device cleanup could not be completed. Try signing out again.',
            sessionExpired: true,
          );
        }
        throw const ConsumerRepositoryException(
          'Your session has ended. Sign in again to continue.',
          sessionExpired: true,
        );
      }
      if (response.statusCode == 403) {
        throw const ConsumerRepositoryException(
          'This account does not have access to that record.',
        );
      }
      if (response.statusCode == 409) {
        throw ConsumerRepositoryException(
          recovery ??
              'This record changed, or this feature needs setup. Refresh and review before trying again.',
        );
      }
      if (response.statusCode == 429) {
        throw const ConsumerRepositoryException(
          'Please wait a moment before trying again.',
        );
      }
      if (response.statusCode == 400 || response.statusCode == 422) {
        throw ConsumerRepositoryException(
          recovery ??
              'Please review the details. The server could not accept this update.',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const ConsumerRepositoryException(
          'Farda could not confirm this request. Please try again.',
        );
      }
      if (response.body.isEmpty) return {};
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const ConsumerRepositoryException(
          'The service returned an unreadable response. Please try again.',
        );
      }
      return decoded;
    } on TimeoutException {
      throw const ConsumerRepositoryException(
        'The connection timed out. Refresh before retrying an update.',
      );
    } on http.ClientException {
      throw const ConsumerRepositoryException(
        'You appear to be offline. Your last loaded record has not changed.',
      );
    } on FormatException {
      throw const ConsumerRepositoryException(
        'The service returned an unreadable response. Please try again.',
      );
    }
  }

  @override
  Future<LabelScanDraft> extractLabel(List<LabelPhoto> photos) async {
    if (photos.isEmpty || photos.length > 4) {
      throw const ConsumerRepositoryException(
        'Add one to four photos of the same label.',
      );
    }
    for (final photo in photos) {
      if (photo.validationError != null) {
        throw ConsumerRepositoryException(photo.validationError!);
      }
    }
    String? token;
    try {
      token = await _tokenProvider();
    } catch (_) {
      throw const ConsumerRepositoryException(
        'Sign in again to scan your label.',
        sessionExpired: true,
      );
    }
    if (token == null || token.isEmpty) {
      throw const ConsumerRepositoryException(
        'Sign in to scan your label.',
        sessionExpired: true,
      );
    }
    final request =
        http.MultipartRequest(
            'POST',
            Uri.parse('$_base/prescriptions/ocr/extract'),
          )
          ..followRedirects = false
          ..headers['Authorization'] = 'Bearer $token';
    for (var i = 0; i < photos.length; i++) {
      final photo = photos[i];
      final extension = photo.mimeType.split('/').last;
      request.files.add(
        http.MultipartFile.fromBytes(
          'image',
          photo.bytes,
          filename: 'label-${i + 1}.$extension',
          contentType: MediaType.parse(photo.mimeType),
        ),
      );
    }
    try {
      final response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 60));
      String? currentToken;
      try {
        currentToken = await _tokenProvider();
      } catch (_) {
        throw const ConsumerRepositoryException(
          'Sign in again to review your label.',
          sessionExpired: true,
        );
      }
      if (currentToken != token) {
        throw const ConsumerRepositoryException(
          'Your account changed. Reopen the scanner.',
          sessionExpired: true,
          sessionChanged: true,
        );
      }
      if (response.statusCode == 401) {
        try {
          await _tokenInvalidator?.call(token);
        } catch (_) {
          throw const ConsumerRepositoryException(
            'Your session ended. Sign in again to continue.',
            sessionExpired: true,
          );
        }
        throw const ConsumerRepositoryException(
          'Your session ended. Sign in again.',
          sessionExpired: true,
        );
      }
      if (response.statusCode == 413) {
        throw const ConsumerRepositoryException(
          'Use up to four photos under 8 MB each, or enter manually.',
        );
      }
      if (response.statusCode == 429) {
        throw const ConsumerRepositoryException(
          'Scanning needs a moment. Try again shortly, or enter manually.',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const ConsumerRepositoryException(
          'We could not read this label. Your photos are still here. Try again or enter manually.',
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>)
        throw const FormatException('Invalid label response');
      return LabelScanDraft.fromJson(decoded);
    } on TimeoutException {
      throw const ConsumerRepositoryException(
        'Scanning took too long. Try again or enter manually. Nothing was saved.',
      );
    } on http.ClientException {
      throw const ConsumerRepositoryException(
        'Check your connection, or enter the label manually. Nothing was saved.',
      );
    } on FormatException {
      throw const ConsumerRepositoryException(
        'We could not read the scan result. Try another photo or enter manually.',
      );
    }
  }

  List<Map<String, dynamic>> _rows(Map<String, dynamic> result) {
    final data = result['data'];
    if (data is! List) {
      throw const ConsumerRepositoryException(
        'Your records could not be read. Please try again.',
      );
    }
    return data.map((row) => Map<String, dynamic>.from(row as Map)).toList();
  }

  @override
  Future<ConsumerSnapshot> loadSnapshot({
    required DateTime from,
    required DateTime to,
  }) async {
    final responses = await Future.wait([
      _request('GET', 'prescriptions'),
      _request(
        'GET',
        'doses',
        query: {
          'from': from.toUtc().toIso8601String(),
          'to': to.toUtc().toIso8601String(),
        },
      ),
    ]);
    final prescriptions =
        _rows(responses[0]).map((p) {
          final schedules =
              (p['schedules'] as List?) ??
              (p['scheduleVersions'] as List?) ??
              [];
          final activeSchedules =
              schedules
                  .whereType<Map>()
                  .where((s) => s['endedAt'] == null)
                  .toList()
                ..sort(
                  (a, b) => ((b['version'] as num?) ?? 0).compareTo(
                    (a['version'] as num?) ?? 0,
                  ),
                );
          final schedule =
              activeSchedules.isNotEmpty
                  ? Map<String, dynamic>.from(activeSchedules.first)
                  : p['schedule'] is Map
                  ? Map<String, dynamic>.from(p['schedule'] as Map)
                  : <String, dynamic>{};
          return ConsumerPrescription(
            id: '${p['id']}',
            name: (p['medicationName'] as String?) ?? 'Medication',
            directions: p['dosageInstructions'] as String?,
            pharmacy: p['pharmacyOrDoctorName'] as String?,
            rxNumber: p['rxNumber'] as String?,
            times:
                (schedule['times'] as List?)?.map((t) => '$t').toList() ?? [],
            timeZone:
                (schedule['timezone'] as String?) ?? 'America/Los_Angeles',
            labelReviewed:
                p['labelReviewed'] == true || p['labelReviewedAt'] != null,
          );
        }).toList();
    final occurrences =
        _rows(responses[1]).map((d) {
          final status = OccurrenceStatus.values.firstWhere(
            (s) => s.name == d['status'],
            orElse: () => OccurrenceStatus.unconfirmed,
          );
          final revision = (d['revision'] as num?)?.toInt() ?? 0;
          _occurrenceRevisions['${d['id']}'] = revision;
          return ConsumerOccurrence(
            id: '${d['id']}',
            prescriptionId: '${d['prescriptionId']}',
            scheduledFor: DateTime.parse(d['scheduledFor'] as String),
            status: status,
            recordedAt: DateTime.tryParse('${d['takenAt'] ?? ''}'),
            note: d['note'] as String?,
            snoozedUntil: DateTime.tryParse('${d['snoozedUntil'] ?? ''}'),
            revision: revision,
            updatedAt: DateTime.tryParse('${d['updatedAt'] ?? ''}'),
            source:
                status == OccurrenceStatus.unconfirmed
                    ? 'Awaiting your confirmation'
                    : 'Reported by you',
          );
        }).toList();
    var preferences = const ConsumerReminderPreferences();
    var capabilities = const ConsumerCapabilities();
    final warnings = <String>[];
    String? callConsentText;
    try {
      final response = await _request('GET', 'reminders/preferences');
      final body =
          response['data'] is Map
              ? Map<String, dynamic>.from(response['data'] as Map)
              : response;
      final p =
          body['preferences'] is Map
              ? Map<String, dynamic>.from(body['preferences'] as Map)
              : body;
      final c =
          body['capabilities'] is Map
              ? Map<String, dynamic>.from(body['capabilities'] as Map)
              : <String, dynamic>{};
      preferences = ConsumerReminderPreferences(
        callsEnabled: p['callsEnabled'] == true,
        liveActivitiesEnabled: p['liveActivitiesEnabled'] == true,
        timeZone: p['timeZone'] as String? ?? 'America/Los_Angeles',
        quietHoursStart: p['quietHoursStart'] as String? ?? '21:00',
        quietHoursEnd: p['quietHoursEnd'] as String? ?? '08:00',
      );
      capabilities = ConsumerCapabilities(
        voiceEnabled: c['voiceEnabled'] == true,
        liveActivityDeliveryEnabled: c['liveActivityDeliveryEnabled'] == true,
        phoneVerified: body['phoneVerified'] == true,
      );
      final consent = body['consent'];
      if (consent is Map) {
        _consentVersion = consent['wordingVersion'] as String?;
        callConsentText = consent['text'] as String?;
      }
    } on ConsumerRepositoryException catch (e) {
      if (e.sessionExpired) rethrow;
      warnings.add(
        'Reminder preferences are unavailable. No new call or Live Activity setting has been applied.',
      );
    }
    final inventory = <ConsumerInventory>[];
    var refillsEnabled = false;
    var inventoryEnabled = prescriptions.isNotEmpty;
    final refills = <String, Map<String, dynamic>>{};
    try {
      final response = await _request('GET', 'refills');
      final rows = response['refills'];
      if (rows is List) {
        refillsEnabled = true;
        _refillIds.clear();
        for (final raw in rows.whereType<Map>()) {
          final row = Map<String, dynamic>.from(raw);
          if (row['status'] == 'cancelled') continue;
          final id = '${row['prescriptionId']}';
          refills.putIfAbsent(id, () => row);
          _refillIds.putIfAbsent(id, () => '${row['id']}');
        }
      }
    } on ConsumerRepositoryException catch (e) {
      if (e.sessionExpired) rethrow;
      warnings.add('Refill progress could not be refreshed.');
    }
    for (final prescription in prescriptions) {
      final refill = refills[prescription.id];
      Map<String, dynamic>? count;
      try {
        final response = await _request(
          'GET',
          'inventory/${Uri.encodeComponent(prescription.id)}',
        );
        if (response['inventory'] is Map) {
          count = Map<String, dynamic>.from(response['inventory'] as Map);
        }
      } on ConsumerRepositoryException catch (e) {
        if (e.sessionExpired) rethrow;
        inventoryEnabled = false;
      }
      final revision = (count?['revision'] as num?)?.toInt() ?? 0;
      _inventoryRevisions[prescription.id] = revision;
      inventory.add(
        ConsumerInventory(
          prescriptionId: prescription.id,
          quantity: (count?['quantity'] as num?)?.toInt(),
          countedAt: DateTime.tryParse('${count?['observedAt'] ?? ''}'),
          revision: revision,
          receiptReconciled: refill?['receiptReconciled'] == true,
          stale: count?['stale'] == true,
          refillId: refill?['id'] as String?,
          plannedFor: DateTime.tryParse('${refill?['plannedFor'] ?? ''}'),
          stage: RefillStage.values.firstWhere(
            (s) => s.name == refill?['status'],
            orElse: () => RefillStage.planning,
          ),
        ),
      );
    }
    capabilities = ConsumerCapabilities(
      voiceEnabled: capabilities.voiceEnabled,
      liveActivityDeliveryEnabled: capabilities.liveActivityDeliveryEnabled,
      phoneVerified: capabilities.phoneVerified,
      inventoryEnabled: inventoryEnabled,
      refillsEnabled: refillsEnabled,
    );
    return ConsumerSnapshot(
      prescriptions: prescriptions,
      occurrences: occurrences,
      inventory: inventory,
      preferences: preferences,
      capabilities: capabilities,
      warnings: warnings,
      callConsentText: callConsentText,
      fetchedAt: DateTime.now(),
    );
  }

  @override
  Future<void> savePrescription(ConsumerPrescriptionDraft draft) async {
    if (draft.validationError != null) {
      throw ConsumerRepositoryException(draft.validationError!);
    }
    await _request('POST', 'prescriptions', body: draft.toJson());
  }

  @override
  Future<void> recordOccurrence(ConsumerOccurrenceUpdate update) async {
    await _request(
      'PATCH',
      'doses/${Uri.encodeComponent(update.id)}',
      body: update.toJson(),
    );
  }

  @override
  Future<void> updateSchedule(
    String prescriptionId,
    ConsumerPrescriptionDraft draft,
  ) async {
    if (draft.validationError != null) {
      throw ConsumerRepositoryException(draft.validationError!);
    }
    final schedule = Map<String, Object?>.from(
      draft.toJson()['schedule'] as Map,
    );
    await _request(
      'POST',
      'prescriptions/${Uri.encodeComponent(prescriptionId)}/schedules',
      body: schedule,
    );
  }

  @override
  Future<void> snoozeOccurrence(String id, Duration duration) async {
    await _request(
      'POST',
      'reminders/occurrences/${Uri.encodeComponent(id)}/snooze',
      body: {
        'minutes': duration.inMinutes,
        if (_occurrenceRevisions[id] != null)
          'revision': _occurrenceRevisions[id],
      },
    );
  }

  @override
  Future<void> saveReminderPreferences(
    ConsumerReminderPreferences preferences, {
    bool callConsent = false,
  }) async {
    if (callConsent && _consentVersion == null) {
      throw const ConsumerRepositoryException(
        'Refresh reminder preferences before enabling calls.',
      );
    }
    await _request(
      'PUT',
      'reminders/preferences',
      body: {
        ...preferences.toJson(callConsent: callConsent),
        if (callConsent) 'consentVersion': _consentVersion,
      },
    );
  }

  @override
  Future<void> updateInventory(String prescriptionId, int quantity) async {
    await _request(
      'PUT',
      'inventory/${Uri.encodeComponent(prescriptionId)}',
      body: {
        'quantity': quantity,
        'observedAt': DateTime.now().toUtc().toIso8601String(),
        if ((_inventoryRevisions[prescriptionId] ?? 0) > 0)
          'revision': _inventoryRevisions[prescriptionId],
        'idempotencyKey':
            'count-${DateTime.now().microsecondsSinceEpoch}-${++_writeSequence}',
      },
    );
  }

  @override
  Future<void> updateRefill(
    String prescriptionId,
    RefillStage stage, {
    bool startNew = false,
  }) async {
    var refillId = startNew ? null : _refillIds[prescriptionId];
    if (refillId == null) {
      final result = await _request(
        'POST',
        'refills',
        body: {
          'prescriptionId': prescriptionId,
          'kind': 'refill',
          'plannedFor': DateTime.now().toUtc().toIso8601String(),
        },
      );
      final refill = result['refill'] is Map ? result['refill'] as Map : result;
      refillId = refill['id'] as String?;
      if (refillId == null) {
        throw const ConsumerRepositoryException(
          'The refill plan could not be read. Refresh before retrying.',
        );
      }
      _refillIds[prescriptionId] = refillId;
    }
    if (stage != RefillStage.planning) {
      await _request(
        'PUT',
        'refills/${Uri.encodeComponent(refillId)}/status',
        body: {'status': stage.name},
      );
    }
  }

  @override
  Future<void> reconcileReceipt(
    String prescriptionId, {
    required int quantity,
    required bool alreadyIncluded,
  }) async {
    final id = _refillIds[prescriptionId];
    final revision = _inventoryRevisions[prescriptionId];
    if (id == null || revision == null || revision < 1) {
      throw const ConsumerRepositoryException(
        'Save a current supply count first, then reconcile the refill you received.',
      );
    }
    await _request(
      'POST',
      'refills/${Uri.encodeComponent(id)}/receipt',
      body: {
        'quantity': quantity,
        'inventoryRevision': revision,
        'alreadyIncluded': alreadyIncluded,
        'idempotencyKey': 'receipt-$id',
      },
    );
  }

  @override
  Future<bool> signOut(String token) async {
    try {
      await _request('POST', 'auth/sign-out', body: {}, requestToken: token);
      return true;
    } on ConsumerRepositoryException catch (error) {
      return error.sessionExpired && !error.sessionChanged;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() => _client.close();
}

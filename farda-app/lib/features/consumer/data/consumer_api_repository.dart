import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:farda/application/authentication/storage/auth_storage.dart';

import 'package:http/http.dart' as http;

import 'consumer_models.dart';
import 'billing.dart';
import 'native_billing.dart';
import 'consumer_repository.dart';
import 'circle_models.dart';
import 'circle_alerts.dart';
import 'label_scan.dart';
import 'refill_agent.dart';
import 'pharmacy_handoff.dart';

import 'package:http_parser/http_parser.dart';

/// The production adapter never substitutes fixture data after a failed request.
/// Transport logs deliberately contain neither bearer tokens nor health records.
class ConsumerApiRepository
    implements
        ConsumerRepository,
        BillingRepository,
        NativeBillingRepository,
        BillingSessionGuard,
        CircleAlertsRepository,
        LabelScanRepository,
        RefillAgentRepository,
        PharmacyHandoffRepository,
        RefillQuestionRepository {
  ConsumerApiRepository({
    required String baseUrl,
    required Future<String?> Function() tokenProvider,
    Future<bool> Function(String token)? tokenInvalidator,
    http.Client? client,
    this.readCacheTtl = const Duration(seconds: 5),
    this.maxReadCacheEntries = 24,
    DateTime Function()? clock,
  }) : _base = baseUrl.replaceFirst(RegExp(r'/+$'), ''),
       _tokenProvider = tokenProvider,
       _tokenInvalidator = tokenInvalidator,
       _client = client ?? http.Client(),
       _clock = clock ?? DateTime.now {
    if (readCacheTtl.isNegative) {
      throw ArgumentError.value(readCacheTtl, 'readCacheTtl');
    }
    if (maxReadCacheEntries < 0) {
      throw ArgumentError.value(maxReadCacheEntries, 'maxReadCacheEntries');
    }
  }
  final String _base;
  final Future<String?> Function() _tokenProvider;
  final Future<bool> Function(String token)? _tokenInvalidator;
  final http.Client _client;
  final Duration readCacheTtl;
  final int maxReadCacheEntries;
  final DateTime Function() _clock;
  final LinkedHashMap<String, _CachedRead> _readCache = LinkedHashMap();
  final Map<String, Future<Map<String, dynamic>>> _inFlightReads = {};
  final Map<String, int> _inventoryRevisions = {};
  final Map<String, int> _occurrenceRevisions = {};
  final Map<String, String> _refillIds = {};
  int _writeSequence = 0;
  int _readGeneration = 0;
  String? _activeToken;
  bool _disposed = false;
  String? _consentVersion;
  @override
  Future<Future<bool> Function()> captureBillingSession() async {
    final revision = AuthStorage.sessionRevision.value;
    final original = await _tokenProvider();
    return () async =>
        AuthStorage.sessionRevision.value == revision &&
        original != null &&
        original.isNotEmpty &&
        await _tokenProvider() == original;
  }

  @override
  Future<BillingCatalog> loadBillingCatalog() async => BillingCatalog.fromJson(
    await _request('GET', 'billing/catalog', cacheRead: true),
  );

  @override
  Future<BillingStatus> loadBillingStatus() async =>
      BillingStatus.fromJson(await _request('GET', 'billing/status'));

  @override
  Future<NativeBillingConfig> loadNativeBillingConfig(String platform) async =>
      NativeBillingConfig.fromJson(
        await _request(
          'GET',
          'billing/native/config',
          query: {'platform': platform},
        ),
      );

  @override
  Future<NativeBillingConfig> prepareNativeBilling(
    String platform,
    Future<bool> Function() sessionCurrent,
  ) async {
    final token = await _tokenProvider();
    if (token == null || !await sessionCurrent()) {
      throw StateError('Session changed');
    }
    return NativeBillingConfig.fromJson(
      await _request(
        'POST',
        'billing/native/prepare',
        body: {'platform': platform},
        requestToken: token,
      ),
    );
  }

  @override
  Future<BillingStatus> syncNativeBilling(
    Future<bool> Function() sessionCurrent,
  ) async {
    final token = await _tokenProvider();
    if (token == null || !await sessionCurrent()) {
      throw StateError('Session changed');
    }
    return BillingStatus.fromJson(
      await _request(
        'POST',
        'billing/native/sync',
        body: {},
        requestToken: token,
      ),
    );
  }

  @override
  Future<Uri> createBillingCheckout(String priceKey, Uri returnUri) async {
    final response = await _request(
      'POST',
      'billing/checkout',
      body: {
        'priceKey': priceKey,
        'successUrl': returnUri.toString(),
        'cancelUrl': returnUri.toString(),
        'channel': 'web',
      },
    );
    return _billingUri(response, 'checkout.stripe.com');
  }

  @override
  Future<Uri> createBillingPortal(Uri returnUri) async => _billingUri(
    await _request(
      'POST',
      'billing/portal',
      body: {'returnUrl': returnUri.toString()},
    ),
    'billing.stripe.com',
  );

  Uri _billingUri(Map<String, dynamic> response, String allowedHost) {
    final uri = Uri.tryParse(response['url'] as String? ?? '');
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != allowedHost ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException('Invalid billing destination');
    }
    return uri;
  }

  @override
  bool get isDemo => false;

  @override
  Future<CircleAlertPolicy> loadCircleAlertPolicy(
    String grantId, {
    bool recipient = false,
  }) async {
    final result = await _request(
      'GET',
      'circle/${recipient ? 'shared-with-me' : 'members'}/${Uri.encodeComponent(grantId)}/${recipient ? 'alert-consent' : 'alert-policy'}',
    );
    return CircleAlertPolicy.fromJson(
      Map<String, dynamic>.from(result['policy'] as Map),
    );
  }

  @override
  Future<void> saveCircleAlertPolicy(
    String grantId,
    CircleAlertPolicy policy,
  ) async {
    await _request(
      'PUT',
      'circle/members/${Uri.encodeComponent(grantId)}/alert-policy',
      body: policy.toJson(),
    );
  }

  @override
  Future<void> setCircleAlertConsent(String grantId, bool consented) async {
    await _request(
      'PUT',
      'circle/shared-with-me/${Uri.encodeComponent(grantId)}/alert-consent',
      body: {'consented': consented},
    );
  }

  @override
  Future<List<CircleAlert>> loadCircleAlerts() async {
    final result = await _request(
      'GET',
      'circle/alerts',
      query: {'limit': '100'},
    );
    return (result['alerts'] as List? ?? [])
        .map((v) => CircleAlert.fromJson(Map<String, dynamic>.from(v as Map)))
        .toList();
  }

  @override
  Future<void> readCircleAlert(String id) async {
    await _request('POST', 'circle/alerts/${Uri.encodeComponent(id)}/read');
  }

  @override
  Future<CircleOverview> loadCircle() async =>
      CircleOverview.fromJson(await _request('GET', 'circle'));

  @override
  Future<List<CircleInvitation>> loadCircleInvitations() async {
    final result = await _request('GET', 'circle/invitations');
    return (result['invitations'] as List? ?? const [])
        .map(
          (v) => CircleInvitation.fromJson(Map<String, dynamic>.from(v as Map)),
        )
        .toList();
  }

  @override
  Future<CircleInvitation> inviteToCircle(
    String phone,
    CirclePermissions permissions,
  ) async {
    final result = await _request(
      'POST',
      'circle/invitations',
      body: {'recipientPhone': phone, 'permissions': permissions.toJson()},
    );
    final invitation = Map<String, dynamic>.from(result['invitation'] as Map);
    return CircleInvitation.fromJson(invitation);
  }

  @override
  Future<void> acceptCircleInvitation(String id, String inviteCode) async {
    await _request(
      'POST',
      'circle/invitations/${Uri.encodeComponent(id)}/accept',
      body: {'inviteCode': inviteCode},
    );
  }

  @override
  Future<void> updateCircleMember(
    String id,
    CirclePermissions permissions,
  ) async {
    await _request(
      'PATCH',
      'circle/members/${Uri.encodeComponent(id)}',
      body: permissions.toJson(),
    );
  }

  @override
  Future<void> removeCircleMember(String id) async {
    await _request('DELETE', 'circle/members/${Uri.encodeComponent(id)}');
  }

  @override
  Future<void> cancelCircleInvitation(String id) async {
    await _request('DELETE', 'circle/invitations/${Uri.encodeComponent(id)}');
  }

  @override
  Future<void> declineCircleInvitation(String id) async {
    await _request(
      'DELETE',
      'circle/invitations/${Uri.encodeComponent(id)}/received',
    );
  }

  @override
  Future<List<SharedCircle>> loadSharedCircles() async {
    final result = await _request('GET', 'circle/shared-with-me');
    return (result['circles'] as List? ?? const []).map((value) {
      final json = Map<String, dynamic>.from(value as Map);
      final owner = CirclePerson.fromJson(
        Map<String, dynamic>.from(json['owner'] as Map),
      );
      final access = Map<String, dynamic>.from(json['access'] as Map);
      return SharedCircle(
        owner: owner,
        access: CircleMember(
          id: access['id'] as String,
          person: owner,
          permissions: CirclePermissions.fromJson(
            Map<String, dynamic>.from(access['permissions'] as Map),
          ),
          acceptedAt: DateTime.parse(access['acceptedAt'] as String),
          updatedAt: DateTime.parse(access['updatedAt'] as String),
        ),
      );
    }).toList();
  }

  @override
  Future<void> leaveSharedCircle(String grantId) async {
    await _request(
      'DELETE',
      'circle/shared-with-me/${Uri.encodeComponent(grantId)}',
    );
  }

  @override
  Future<CircleRoutine> loadSharedCircleRoutine(
    String grantId, {
    required DateTime from,
    required DateTime to,
  }) async => CircleRoutine.fromJson(
    await _request(
      'GET',
      'circle/shared-with-me/${Uri.encodeComponent(grantId)}/routine',
      query: {
        'from': from.toUtc().toIso8601String(),
        'to': to.toUtc().toIso8601String(),
      },
    ),
  );

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, Object?>? body,
    Map<String, String>? query,
    String? requestToken,
    bool cacheRead = false,
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
    if (_disposed) {
      throw const ConsumerRepositoryException(
        'This request was cancelled. Reopen Farda to refresh.',
      );
    }
    _bindSession(token);
    final uri = Uri.parse('$_base/$path').replace(queryParameters: query);
    if (method == 'GET' && body == null) {
      return _read(uri, token, cache: cacheRead);
    }
    final result = await _send(method, uri, token, body: body);
    // A confirmed mutation makes every cached representation suspect. Advance
    // the generation as well as clearing entries so a slower earlier GET cannot
    // repopulate the cache after this write.
    _invalidateReads();
    return result;
  }

  void _bindSession(String token) {
    if (_activeToken == token) return;
    _activeToken = token;
    _invalidateReads();
    _inventoryRevisions.clear();
    _occurrenceRevisions.clear();
    _refillIds.clear();
    _consentVersion = null;
  }

  void _invalidateReads() {
    _readGeneration++;
    _readCache.clear();
  }

  Future<Map<String, dynamic>> _read(
    Uri uri,
    String token, {
    required bool cache,
    int refreshesRemaining = 1,
  }) async {
    final generation = _readGeneration;
    final cacheKey = uri.toString();
    if (cache) {
      final cached = _readCache.remove(cacheKey);
      if (cached != null && cached.expiresAt.isAfter(_clock())) {
        _readCache[cacheKey] = cached;
        await _requireCurrentSession(token);
        return _copy(cached.value);
      }
    }

    final requestKey =
        '$generation\u0000${cache ? 'cached' : 'fresh'}\u0000$cacheKey';
    var future = _inFlightReads[requestKey];
    if (future == null) {
      late final Future<Map<String, dynamic>> owned;
      owned =
          (() async {
            try {
              final value = await _send('GET', uri, token);
              if (!_disposed &&
                  _activeToken == token &&
                  _readGeneration == generation &&
                  cache &&
                  readCacheTtl > Duration.zero &&
                  maxReadCacheEntries > 0) {
                _readCache[cacheKey] = _CachedRead(
                  _copy(value),
                  _clock().add(readCacheTtl),
                );
                while (_readCache.length > maxReadCacheEntries) {
                  _readCache.remove(_readCache.keys.first);
                }
              }
              return value;
            } finally {
              if (identical(_inFlightReads[requestKey], owned)) {
                _inFlightReads.remove(requestKey);
              }
            }
          })();
      _inFlightReads[requestKey] = owned;
      future = owned;
    }
    final value = await future;
    if (_readGeneration != generation) {
      await _requireCurrentSession(token);
      if (refreshesRemaining > 0) {
        return _read(
          uri,
          token,
          cache: cache,
          refreshesRemaining: refreshesRemaining - 1,
        );
      }
      throw const ConsumerRepositoryException(
        'This record changed while it was loading. Refresh to see the latest version.',
      );
    }
    return _copy(value);
  }

  Future<void> _requireCurrentSession(String token) async {
    if (_disposed) {
      throw const ConsumerRepositoryException(
        'This request was cancelled. Reopen Farda to refresh.',
      );
    }
    String? currentToken;
    try {
      currentToken = await _tokenProvider();
    } catch (_) {
      _invalidateReads();
      throw const ConsumerRepositoryException(
        'Your saved session could not be read. Private records are hidden until you sign in again.',
        sessionExpired: true,
      );
    }
    if (currentToken != token || _activeToken != token) {
      _invalidateReads();
      throw const ConsumerRepositoryException(
        'Your account session changed. Refresh to continue.',
        sessionExpired: true,
        sessionChanged: true,
      );
    }
  }

  Map<String, dynamic> _copy(Map<String, dynamic> value) =>
      Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);

  Future<Map<String, dynamic>> _send(
    String method,
    Uri uri,
    String token, {
    Map<String, Object?>? body,
  }) async {
    final request =
        http.Request(method, uri)
          ..followRedirects = false
          ..headers.addAll({
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          });
    if (body != null) request.body = jsonEncode(body);
    try {
      final response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 20));
      await _requireCurrentSession(token);
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
        _invalidateReads();
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
  Future<RefillAgentAnswer> askRefillQuestion(
    String prescriptionId,
    String question,
  ) async => RefillAgentAnswer.fromJson(
    await _request(
      'POST',
      'refills/agent/${Uri.encodeComponent(prescriptionId)}/assist',
      body: {'question': question, 'consent': true},
    ),
  );

  @override
  Future<Future<bool> Function()> capturePharmacySession() =>
      captureBillingSession();

  @override
  Future<List<PharmacyDestination>> loadPharmacyDirectory() async =>
      _rows(
        await _request('GET', 'pharmacies/directory', cacheRead: true),
      ).map(PharmacyDestination.fromJson).toList();

  @override
  Future<PharmacyHandoff> preparePharmacyHandoff(
    String prescriptionId, {
    required String pharmacyId,
    required String purpose,
  }) async {
    final result = await _request(
      'POST',
      'prescriptions/${Uri.encodeComponent(prescriptionId)}/pharmacy-handoff',
      body: {'pharmacyId': pharmacyId, 'purpose': purpose},
    );
    return PharmacyHandoff.fromJson(
      Map<String, dynamic>.from(result['data'] as Map),
    );
  }

  @override
  Future<RefillAgentState> loadRefillAgent(String prescriptionId) async =>
      RefillAgentState.fromJson(
        await _request(
          'GET',
          'refills/agent/${Uri.encodeComponent(prescriptionId)}',
        ),
      );

  @override
  Future<RefillAgentState> submitRefillAgent(
    String prescriptionId, {
    required String reviewToken,
    required String idempotencyKey,
  }) async => RefillAgentState.fromJson(
    await _request(
      'POST',
      'refills/agent/${Uri.encodeComponent(prescriptionId)}/submit',
      body: {
        'reviewToken': reviewToken,
        'confirmed': true,
        'idempotencyKey': idempotencyKey,
      },
    ),
  );

  @override
  Future<RefillAgentState> refreshRefillAgent(String prescriptionId) async =>
      RefillAgentState.fromJson(
        await _request(
          'POST',
          'refills/agent/${Uri.encodeComponent(prescriptionId)}/refresh',
          body: {},
        ),
      );

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
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Invalid label response');
      }
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
    Future<Map<String, dynamic>> optionalRead(String path) async {
      try {
        return await _request('GET', path);
      } on ConsumerRepositoryException catch (error) {
        if (error.sessionExpired) rethrow;
        return {};
      }
    }

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
      optionalRead('reminders/preferences'),
      optionalRead('refills'),
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
      final response = responses[2];
      if (response.isEmpty) {
        throw const ConsumerRepositoryException('Unavailable');
      }
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
    final counts = <String, Map<String, dynamic>?>{};
    try {
      final response = responses[3];
      if (response.isEmpty) {
        throw const ConsumerRepositoryException('Unavailable');
      }
      final batch = response['inventories'];
      if (batch is List) {
        for (final entry in batch.whereType<Map>()) {
          counts['${entry['prescriptionId']}'] =
              entry['inventory'] is Map
                  ? Map<String, dynamic>.from(entry['inventory'] as Map)
                  : null;
        }
      }
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
      // A missing batch entry means unavailable, never an assumed zero count.
      final count = counts[prescription.id];
      if (!counts.containsKey(prescription.id)) inventoryEnabled = false;
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
    if (!inventoryEnabled && prescriptions.isNotEmpty) {
      warnings.add('Supply counts could not be refreshed.');
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
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _activeToken = null;
    _invalidateReads();
    _inFlightReads.clear();
    _client.close();
  }
}

class _CachedRead {
  const _CachedRead(this.value, this.expiresAt);
  final Map<String, dynamic> value;
  final DateTime expiresAt;
}

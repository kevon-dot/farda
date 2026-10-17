import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:farda/features/consumer/data/consumer_api_repository.dart';
import 'package:farda/features/consumer/data/consumer_models.dart';
import 'package:farda/features/consumer/data/label_scan.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class _Client extends http.BaseClient {
  _Client(this.handler);
  final Future<http.StreamedResponse> Function(http.BaseRequest) handler;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handler(request);
}

Map<String, Object?> _draft({Object? medicines, String? directions}) => {
  'requires_review': true,
  'source': 'label_ocr',
  'pharmacy_or_doctor_name': 'Example pharmacy',
  'rx_number': 'RX-FIXTURE',
  'medicines_names':
      medicines ??
      [
        {'medicine_name': 'Example medication', 'instructions': directions},
      ],
};

http.StreamedResponse _response(Object? body, [int status = 200]) =>
    http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status);

LabelPhoto _png([int? size]) {
  final bytes = Uint8List(size ?? 8);
  bytes.setAll(0, [137, 80, 78, 71, 13, 10, 26, 10]);
  return LabelPhoto(bytes: bytes, mimeType: 'image/png');
}

ConsumerApiRepository _repository(
  Future<http.StreamedResponse> Function(http.BaseRequest) send, {
  Future<String?> Function()? tokenProvider,
  Future<bool> Function(String)? tokenInvalidator,
}) => ConsumerApiRepository(
  baseUrl: 'https://fixture.invalid/api/',
  tokenProvider: tokenProvider ?? () async => 'fixture-session',
  tokenInvalidator: tokenInvalidator,
  client: _Client(send),
);

Matcher _safeError({bool expired = false, bool changed = false}) =>
    isA<ConsumerRepositoryException>()
        .having((error) => error.sessionExpired, 'sessionExpired', expired)
        .having((error) => error.sessionChanged, 'sessionChanged', changed)
        .having(
          (error) => error.message,
          'safe message',
          isNot(contains('PRIVATE')),
        );

void main() {
  group('LabelPhoto validation', () {
    test(
      'recognizes JPEG, PNG and WebP by content and rejects MIME mismatch',
      () {
        expect(
          LabelPhoto.detectMime(Uint8List.fromList([255, 216, 255])),
          'image/jpeg',
        );
        expect(_png().validationError, isNull);
        expect(
          LabelPhoto.detectMime(
            Uint8List.fromList(ascii.encode('RIFF0000WEBP')),
          ),
          'image/webp',
        );
        expect(
          LabelPhoto(
            bytes: _png().bytes,
            mimeType: 'image/jpeg',
          ).validationError,
          isNotNull,
        );
        expect(
          LabelPhoto(
            bytes: Uint8List.fromList(ascii.encode('<html>PRIVATE</html>')),
            mimeType: 'image/png',
          ).validationError,
          isNotNull,
        );
      },
    );

    test('accepts exactly 8 MB and rejects empty or larger files', () {
      expect(_png(8 * 1024 * 1024).validationError, isNull);
      expect(_png(8 * 1024 * 1024 + 1).validationError, isNotNull);
      expect(
        LabelPhoto(bytes: Uint8List(0), mimeType: 'image/png').validationError,
        isNotNull,
      );
    });
  });

  group('LabelScanDraft', () {
    test(
      'preserves exact long multiline instructions without truncating or trimming',
      () {
        final directions =
            '  ${List.filled(100, 'Visible continuation.').join('\n')}  ';
        final draft = LabelScanDraft.fromJson(_draft(directions: directions));
        expect(draft.directions, directions);
        expect(draft.manualEntry, isFalse);
      },
    );

    test('missing and blank fields remain unknown', () {
      final draft = LabelScanDraft.fromJson({
        'medicines_names': [
          {'medicine_name': '  ', 'instructions': null},
        ],
      });
      expect(draft.medicationName, isNull);
      expect(draft.directions, isNull);
      expect(draft.pharmacy, isNull);
      expect(draft.rxNumber, isNull);
    });

    for (final entry
        in <String, Object?>{
          'none': [],
          'multiple': [
            {'medicine_name': 'A'},
            {'medicine_name': 'B'},
          ],
          'wrong list type': 'PRIVATE',
          'wrong medicine type': ['PRIVATE'],
        }.entries) {
      test('rejects ${entry.key} medications safely', () {
        expect(
          () => LabelScanDraft.fromJson(_draft(medicines: entry.value)),
          throwsA(_safeError()),
        );
      });
    }
  });

  group('extractLabel transport', () {
    test(
      'uploads all four photos in one authenticated multipart request with redirects disabled',
      () async {
        var calls = 0;
        final photos = List.generate(4, (_) => _png());
        final repository = _repository((request) async {
          calls++;
          expect(request.method, 'POST');
          expect(
            request.url.toString(),
            'https://fixture.invalid/api/prescriptions/ocr/extract',
          );
          expect(request.followRedirects, isFalse);
          expect(request.headers['Authorization'], 'Bearer fixture-session');
          expect(request, isA<http.MultipartRequest>());
          final upload = request as http.MultipartRequest;
          expect(upload.files, hasLength(4));
          expect(upload.fields, isEmpty);
          for (var i = 0; i < 4; i++) {
            expect(upload.files[i].field, 'image');
            expect(upload.files[i].filename, 'label-${i + 1}.png');
            expect(upload.files[i].contentType.toString(), 'image/png');
            expect(upload.files[i].length, photos[i].bytes.length);
          }
          final wire = await upload.finalize().toBytes();
          final encoded = latin1.decode(wire);
          expect(
            'content-disposition'.allMatches(encoded.toLowerCase()),
            hasLength(4),
          );
          return _response(_draft(directions: 'Full visible directions'));
        });
        final result = await repository.extractLabel(photos);
        expect(result.directions, 'Full visible directions');
        expect(calls, 1);
      },
    );

    test(
      'rejects empty, over-limit, oversized and mismatched input before token lookup or upload',
      () async {
        var tokenReads = 0, sends = 0;
        final repository = _repository(
          (_) async {
            sends++;
            return _response(_draft());
          },
          tokenProvider: () async {
            tokenReads++;
            return 'session';
          },
        );
        final cases = <List<LabelPhoto>>[
          [],
          List.generate(5, (_) => _png()),
          [_png(8 * 1024 * 1024 + 1)],
          [LabelPhoto(bytes: _png().bytes, mimeType: 'image/webp')],
        ];
        for (final photos in cases) {
          await expectLater(
            repository.extractLabel(photos),
            throwsA(_safeError()),
          );
        }
        expect(tokenReads, 0);
        expect(sends, 0);
      },
    );

    test(
      'missing or unreadable session never uploads a private photo',
      () async {
        var sends = 0;
        for (final provider in <Future<String?> Function()>[
          () async => null,
          () async => '',
          () async => throw StateError('PRIVATE storage details'),
        ]) {
          final repository = _repository((_) async {
            sends++;
            return _response(_draft());
          }, tokenProvider: provider);
          await expectLater(
            repository.extractLabel([_png()]),
            throwsA(_safeError(expired: true)),
          );
        }
        expect(sends, 0);
      },
    );

    test(
      'discards scan response if account changed during upload and does not invalidate the new account',
      () async {
        var token = 'account-a';
        var invalidations = 0;
        final repository = _repository(
          (_) async {
            token = 'account-b';
            return _response({'PRIVATE': 'wrong-account medical data'}, 401);
          },
          tokenProvider: () async => token,
          tokenInvalidator: (_) async {
            invalidations++;
            return true;
          },
        );
        await expectLater(
          repository.extractLabel([_png()]),
          throwsA(_safeError(expired: true, changed: true)),
        );
        expect(invalidations, 0);
      },
    );

    test('discards scan if session lookup fails after upload', () async {
      var reads = 0;
      final repository = _repository(
        (_) async => _response(_draft()),
        tokenProvider: () async {
          if (++reads == 1) return 'account-a';
          throw StateError('PRIVATE storage details');
        },
      );
      await expectLater(
        repository.extractLabel([_png()]),
        throwsA(_safeError(expired: true)),
      );
    });

    test(
      'dispose blocks a delayed multipart response before PHI is parsed',
      () async {
        final sent = Completer<void>();
        final pending = Completer<http.StreamedResponse>();
        final repository = _repository((_) {
          sent.complete();
          return pending.future;
        });

        final scan = repository.extractLabel([_png()]);
        await sent.future;
        repository.dispose();
        pending.complete(
          _response(
            _draft(directions: 'PRIVATE directions from a cancelled scan'),
          ),
        );

        await expectLater(
          scan,
          throwsA(
            allOf(
              _safeError(),
              isA<ConsumerRepositoryException>().having(
                (error) => error.message,
                'message',
                contains('cancelled'),
              ),
            ),
          ),
        );
      },
    );

    test('dispose maps multipart transport failure to cancellation', () async {
      final sent = Completer<void>();
      final pending = Completer<http.StreamedResponse>();
      final repository = _repository((_) {
        sent.complete();
        return pending.future;
      });

      final scan = repository.extractLabel([_png()]);
      await sent.future;
      repository.dispose();
      pending.completeError(http.ClientException('PRIVATE closed transport'));

      await expectLater(
        scan,
        throwsA(
          allOf(
            _safeError(),
            isA<ConsumerRepositoryException>().having(
              (error) => error.message,
              'message',
              contains('cancelled'),
            ),
          ),
        ),
      );
    });

    test(
      '401 invalidates only the request session and hides server body',
      () async {
        final invalidated = <String>[];
        final repository = _repository(
          (_) async => _response({'error': 'PRIVATE provider detail'}, 401),
          tokenInvalidator: (token) async {
            invalidated.add(token);
            return true;
          },
        );
        await expectLater(
          repository.extractLabel([_png()]),
          throwsA(_safeError(expired: true)),
        );
        expect(invalidated, ['fixture-session']);
      },
    );

    test('401 remains a safe session error when invalidation fails', () async {
      final repository = _repository(
        (_) async => _response({'error': 'PRIVATE provider detail'}, 401),
        tokenInvalidator:
            (_) async => throw StateError('PRIVATE storage failure'),
      );
      await expectLater(
        repository.extractLabel([_png()]),
        throwsA(_safeError(expired: true)),
      );
    });

    for (final status in [302, 400, 413, 422, 429, 500, 503, 504]) {
      test(
        'status $status returns safe recovery without raw provider text',
        () async {
          final repository = _repository(
            (_) async =>
                _response({'error': 'PRIVATE prescription and token'}, status),
          );
          await expectLater(
            repository.extractLabel([_png()]),
            throwsA(_safeError()),
          );
        },
      );
    }

    for (final entry
        in <String, Object?>{
          'scalar': 'PRIVATE response',
          'array': [],
          'malformed field': _draft(
            medicines: [
              {
                'medicine_name': 'Example',
                'instructions': {'PRIVATE': 'data'},
              },
            ],
          ),
          'no medicine': _draft(medicines: []),
          'multiple medicines': _draft(
            medicines: [
              {'medicine_name': 'A'},
              {'medicine_name': 'B'},
            ],
          ),
        }.entries) {
      test('rejects ${entry.key} response safely', () async {
        final repository = _repository((_) async => _response(entry.value));
        await expectLater(
          repository.extractLabel([_png()]),
          throwsA(_safeError()),
        );
      });
    }

    test(
      'malformed JSON and network exceptions do not leak raw details',
      () async {
        final invalidJson = _repository(
          (_) async => http.StreamedResponse(
            Stream.value(utf8.encode('PRIVATE invalid JSON')),
            200,
          ),
        );
        await expectLater(
          invalidJson.extractLabel([_png()]),
          throwsA(_safeError()),
        );
        final offline = _repository(
          (_) async => throw http.ClientException('PRIVATE request details'),
        );
        await expectLater(
          offline.extractLabel([_png()]),
          throwsA(_safeError()),
        );
      },
    );

    testWidgets(
      'timeout covers sending the upload as well as reading its response',
      (tester) async {
        final pending = Completer<http.StreamedResponse>();
        final repository = _repository((_) => pending.future);
        final result = expectLater(
          repository.extractLabel([_png()]),
          throwsA(_safeError()),
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 61));
        // Complete transport too, avoiding an unresolved fake client after timeout.
        pending.complete(_response(_draft()));
        await tester.pump();
        await result;
      },
    );
  });
}

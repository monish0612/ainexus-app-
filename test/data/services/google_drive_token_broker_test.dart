import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_nexus/data/services/google_drive_service.dart';

/// Hermetic tests for the token-broker auth path: the app fetches a short-lived
/// Drive token from the backend (no service-account key in the client) and
/// caches/refreshes it correctly. Uses the [tokenFetcher] seam so nothing hits
/// the network.
void main() {
  group('GoogleDriveService token broker', () {
    test('fetches a token and caches it (single fetch while valid)', () async {
      var calls = 0;
      final svc = GoogleDriveService(
        tokenFetcher: () async {
          calls++;
          return DriveTokenResponse(
            accessToken: 'tok-$calls',
            expiresAt: DateTime.now().add(const Duration(minutes: 50)),
          );
        },
      );

      await svc.ensureAuthForTest();
      expect(svc.debugAccessToken, 'tok-1');
      expect(calls, 1);

      // Still valid → no second fetch.
      await svc.ensureAuthForTest();
      expect(calls, 1);
      expect(svc.debugAccessToken, 'tok-1');
    });

    test('re-fetches when the cached token is within the refresh buffer',
        () async {
      var calls = 0;
      final svc = GoogleDriveService(
        tokenFetcher: () async {
          calls++;
          // Expires in 2 min → inside the 5-min refresh buffer → stale.
          return DriveTokenResponse(
            accessToken: 'tok-$calls',
            expiresAt: DateTime.now().add(const Duration(minutes: 2)),
          );
        },
      );

      await svc.ensureAuthForTest();
      expect(calls, 1);

      // Near-expiry token must be refreshed on the next ensure.
      await svc.ensureAuthForTest();
      expect(calls, 2);
      expect(svc.debugAccessToken, 'tok-2');
    });

    test('force always re-fetches', () async {
      var calls = 0;
      final svc = GoogleDriveService(
        tokenFetcher: () async {
          calls++;
          return DriveTokenResponse(
            accessToken: 'tok-$calls',
            expiresAt: DateTime.now().add(const Duration(minutes: 50)),
          );
        },
      );

      await svc.ensureAuthForTest();
      await svc.ensureAuthForTest(force: true);
      expect(calls, 2);
      expect(svc.debugAccessToken, 'tok-2');
    });

    test('classifies a broker failure into a typed DriveException', () async {
      final svc = GoogleDriveService(
        tokenFetcher: () async => throw DioException(
          requestOptions: RequestOptions(path: '/api/v1/cloud/token'),
          type: DioExceptionType.connectionError,
        ),
      );

      await expectLater(
        svc.ensureAuthForTest(),
        throwsA(isA<DriveException>()
            .having((e) => e.kind, 'kind', DriveErrorKind.network)),
      );
    });
  });

  group('classifyError', () {
    DioException dio(int status, [Object? data]) => DioException(
          requestOptions: RequestOptions(path: '/x'),
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: RequestOptions(path: '/x'),
            statusCode: status,
            data: data,
          ),
        );

    test('503 / not-configured body → notConfigured', () {
      expect(
        GoogleDriveService.classifyError(dio(503)).kind,
        DriveErrorKind.notConfigured,
      );
      expect(
        GoogleDriveService.classifyError(
          dio(500, {'error': 'Cloud storage is not configured on the server'}),
        ).kind,
        DriveErrorKind.notConfigured,
      );
    });

    test('401 / 403 → auth', () {
      expect(GoogleDriveService.classifyError(dio(401)).kind,
          DriveErrorKind.auth);
      expect(GoogleDriveService.classifyError(dio(403)).kind,
          DriveErrorKind.auth);
    });

    test('connection/timeout → network', () {
      final e = DioException(
        requestOptions: RequestOptions(path: '/x'),
        type: DioExceptionType.connectionTimeout,
      );
      expect(GoogleDriveService.classifyError(e).kind, DriveErrorKind.network);
    });

    test('passes through an existing DriveException', () {
      const original = DriveException(DriveErrorKind.auth, 'boom');
      expect(GoogleDriveService.classifyError(original), same(original));
    });

    test('unknown errors fall back to unknown', () {
      expect(GoogleDriveService.classifyError(Exception('weird')).kind,
          DriveErrorKind.unknown);
    });
  });
}

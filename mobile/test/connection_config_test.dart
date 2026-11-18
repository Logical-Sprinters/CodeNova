import 'dart:async';
import 'dart:convert';

import 'package:brandguard/core/auth/demo_auth.dart';
import 'package:brandguard/core/auth/session.dart';
import 'package:brandguard/core/network/api_config.dart';
import 'package:brandguard/core/network/brandguard_api_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class StreamingClient extends http.BaseClient {
  StreamingClient(this.stream);
  final Stream<List<int>> stream;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(stream, 200);
}

void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    session.signOut();
    BrandGuardApiService.clientForTesting = http.Client();
  });

  for (final platform in [
    TargetPlatform.android,
    TargetPlatform.iOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
    TargetPlatform.macOS,
  ]) {
    test(
      '$platform native default never silently selects emulator localhost',
      () {
        debugDefaultTargetPlatformOverride = platform;
        const override = String.fromEnvironment('API_BASE');
        expect(
          BrandGuardApiService.baseUrl,
          ApiConfig.resolveBaseUrl(configuredBase: override, isWeb: false),
        );
        if (override.isEmpty) {
          expect(BrandGuardApiService.baseUrl, ApiConfig.hostedBaseUrl);
          expect(Uri.parse(BrandGuardApiService.baseUrl).scheme, 'https');
        }
      },
    );
  }

  test(
    'web defaults to its own origin, keeping the local browser demo isolated',
    () {
      expect(
        ApiConfig.resolveBaseUrl(
          isWeb: true,
          webOrigin: 'http://localhost:8086',
        ),
        'http://localhost:8086',
      );
      expect(
        ApiConfig.resolveBaseUrl(
          isWeb: true,
          webOrigin: ApiConfig.hostedBaseUrl,
        ),
        ApiConfig.hostedBaseUrl,
      );
    },
  );

  test('explicit API_BASE overrides both native and web and removes trailing slashes', () {
    for (final isWeb in [true, false]) {
      expect(
        ApiConfig.resolveBaseUrl(
          configuredBase: ' https://custom.example/api-proxy/// ',
          isWeb: isWeb,
          webOrigin: 'https://ignored.example',
        ),
        'https://custom.example/api-proxy',
      );
      expect(
        ApiConfig.resolveBaseUrl(
          configuredBase: 'http://10.0.2.2:8000/',
          isWeb: isWeb,
        ),
        'http://10.0.2.2:8000',
      );
    }
  });

  for (final address in [
    'localhost:8000',
    'ftp://server.example',
    'https://user:secret@server.example',
    'https://server.example?key=secret',
    'https://server.example#token',
    'https://',
  ]) {
    test(
      'invalid or credential-bearing API_BASE rejected: ${address.split(':').first}',
      () {
        expect(
          () => ApiConfig.resolveBaseUrl(configuredBase: address, isWeb: false),
          throwsA(isA<ApiConfigurationException>()),
        );
      },
    );
  }

  test('login request uses the selected live origin and keeps password in POST body only', () async {
    session.signOut();
    BrandGuardApiService.clientForTesting = MockClient((request) async {
      expect(
        request.url.origin,
        Uri.parse(BrandGuardApiService.baseUrl).origin,
      );
      expect(request.url.path, '/api/v1/auth/login');
      expect(request.url.query, isEmpty);
      expect(request.headers['Authorization'], isNull);
      expect(jsonDecode(request.body)['password'], 'private-test-password');
      return http.Response(
        '{"access_token":"test-access","refresh_token":"test-refresh","user":{"user_id":"cloud-user","name":"Cloud User","email":"user@example.com","role":"creator"}}',
        200,
      );
    });
    await BrandGuardApiService.login(
      'user@example.com',
      'private-test-password',
    );
    expect(session.userId, 'cloud-user');
  });

  test(
    'socket errors are short and do not dump the old emulator address',
    () async {
      BrandGuardApiService.clientForTesting = MockClient(
        (_) async => throw http.ClientException(
          'SocketException errno = 110 address = 10.0.2.2 port = 34408',
        ),
      );
      await expectLater(
        BrandGuardApiService.request('GET', '/health', authenticated: false),
        throwsA(
          isA<ApiException>().having(
            (e) => e.toString(),
            'safe message',
            allOf(
              contains('internet connection'),
              isNot(contains('SocketException')),
              isNot(contains('10.0.2.2')),
              isNot(contains('34408')),
            ),
          ),
        ),
      );
    },
  );

  test('timeouts produce a friendly actionable error', () async {
    BrandGuardApiService.clientForTesting = MockClient(
      (_) async => throw TimeoutException('raw timeout internals'),
    );
    await expectLater(
      BrandGuardApiService.request('GET', '/health', authenticated: false),
      throwsA(
        isA<ApiException>().having(
          (e) => e.toString(),
          'message',
          contains('Connection timed out'),
        ),
      ),
    );
  });

  test('upload uses the same network-error handling', () async {
    session.signIn(DemoAuth.creator.user, accessToken: 'mock-token');
    BrandGuardApiService.clientForTesting = MockClient(
      (_) async => throw http.ClientException('Raw socket error'),
    );
    await expectLater(
      BrandGuardApiService.uploadDocument(
        'source.txt',
        Uint8List.fromList([65]),
      ),
      throwsA(
        isA<ApiException>().having(
          (e) => e.toString(),
          'message',
          contains('Cannot reach'),
        ),
      ),
    );
  });

  test(
    'malformed signup response cannot silently open an authenticated session',
    () async {
      session.signOut();
      BrandGuardApiService.clientForTesting = MockClient(
        (_) async => http.Response('{"message":"ok"}', 200),
      );
      await expectLater(
        BrandGuardApiService.signup('User', 'user@example.com', 'Password123!'),
        throwsA(isA<ApiException>()),
      );
      expect(session.currentUser, isNull);
    },
  );

  testWidgets(
    'response body is covered by the timeout, not just response headers',
    (tester) async {
      final body = StreamController<List<int>>();
      BrandGuardApiService.clientForTesting = StreamingClient(body.stream);
      Object? failure;
      final operation =
          BrandGuardApiService.request(
            'GET',
            '/health',
            authenticated: false,
          ).then<void>(
            (_) => fail('An unfinished body must not succeed'),
            onError: (Object error) {
              failure = error;
            },
          );
      await tester.pump();
      await tester.pump(const Duration(seconds: 46));
      await operation;
      expect(failure, isA<ApiException>());
      expect(failure.toString(), contains('Connection timed out'));
      await body.close();
      await tester.pump();
    },
  );
}

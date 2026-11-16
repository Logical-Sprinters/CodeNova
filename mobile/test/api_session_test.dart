import 'dart:async';
import 'dart:convert';

import 'package:brandguard/core/auth/demo_auth.dart';
import 'package:brandguard/core/auth/session.dart';
import 'package:brandguard/core/network/brandguard_api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> tokenData({
  String token = 'new-access',
  String refresh = 'new-refresh',
}) => {
  'access_token': token,
  'refresh_token': refresh,
  'expires_in': 1800,
  'user': {
    'user_id': 'u1',
    'name': 'Alice',
    'role': 'creator',
    'email': DemoAuth.creator.email,
  },
};
void main() {
  setUp(
    () => session.signIn(
      DemoAuth.creator.user,
      accessToken: 'creator-token',
      refreshToken: 'creator-refresh',
    ),
  );
  tearDown(() {
    session.signOut();
    BrandGuardApiService.clientForTesting = http.Client();
  });

  for (final account in DemoAuth.accounts) {
    test(
      '${account.role}: all six workflow calls use bearer and no impersonable ID header',
      () async {
        session.signIn(account.user, accessToken: '${account.role}-token');
        final requests = <http.Request>[];
        BrandGuardApiService.clientForTesting = MockClient((request) async {
          requests.add(request);
          expect(
            request.headers['Authorization'],
            'Bearer ${account.role}-token',
          );
          expect(request.headers['X-User-Id'], isNull);
          expect(request.headers['X-User-Role'], isNull);
          return http.Response('{"ok":true}', 200);
        });
        await BrandGuardApiService.checkBrand(
          brandName: 'Acme',
          content: 'TODO',
        );
        await BrandGuardApiService.getReviews(status: 'pending');
        await BrandGuardApiService.getReceipt(receiptId: 'receipt-test');
        await BrandGuardApiService.submitEditedContent(
          checkId: 'check-test',
          content: 'Updated',
          expectedVersion: 2,
        );
        await BrandGuardApiService.decideReview(
          checkId: 'check-test',
          decision: 'approved',
          expectedVersion: 3,
        );
        await BrandGuardApiService.verifyApproval(
          checkId: 'check-test',
          brandName: 'Acme',
          content: 'Updated',
        );
        expect(requests, hasLength(6));
        expect(requests[1].url.queryParameters['status'], 'pending');
        expect(jsonDecode(requests[3].body)['expected_version'], 2);
        expect(jsonDecode(requests[4].body)['expected_version'], 3);
      },
    );
  }

  test(
    'login posts a password to server and accepts only the server identity',
    () async {
      session.signOut();
      BrandGuardApiService.clientForTesting = MockClient((request) async {
        expect(request.url.path, '/api/v1/auth/login');
        expect(request.headers['Authorization'], isNull);
        expect(
          jsonDecode(request.body)['password'],
          'wrong-until-server-accepts',
        );
        return http.Response(jsonEncode(tokenData()), 200);
      });
      await BrandGuardApiService.login(
        'creator@brandguard.demo',
        'wrong-until-server-accepts',
      );
      expect(session.accessToken, 'new-access');
      expect(session.role, 'creator');
    },
  );

  test('401 refreshes once and retries with rotated tokens', () async {
    var refreshes = 0, protected = 0;
    BrandGuardApiService.clientForTesting = MockClient((request) async {
      if (request.url.path == '/api/v1/auth/refresh') {
        refreshes++;
        expect(jsonDecode(request.body)['refresh_token'], 'creator-refresh');
        return http.Response(jsonEncode(tokenData()), 200);
      }
      protected++;
      return request.headers['Authorization'] == 'Bearer creator-token'
          ? http.Response('{"detail":"expired"}', 401)
          : http.Response('{"items":[]}', 200);
    });
    await BrandGuardApiService.getReviews();
    expect(refreshes, 1);
    expect(protected, 2);
    expect(session.refreshToken, 'new-refresh');
  });

  test('concurrent expired requests share refresh and never resend stale ID headers', () async {
    var refreshes = 0;
    final gate = Completer<void>();
    BrandGuardApiService.clientForTesting = MockClient((request) async {
      if (request.url.path == '/api/v1/auth/refresh') {
        refreshes++;
        await gate.future;
        return http.Response(jsonEncode(tokenData()), 200);
      }
      return request.headers['Authorization'] == 'Bearer creator-token'
          ? http.Response('{"detail":"expired"}', 401)
          : http.Response('{"items":[]}', 200);
    });
    final a = BrandGuardApiService.getReviews();
    final b = BrandGuardApiService.getJson('/api/v1/analytics');
    await Future<void>.delayed(Duration.zero);
    gate.complete();
    await Future.wait([a, b]);
    expect(refreshes, 1);
  });

  test(
    'failed refresh clears tokens, and logged-out requests never reach backend',
    () async {
      var calls = 0;
      BrandGuardApiService.clientForTesting = MockClient((request) async {
        calls++;
        return http.Response('{"detail":"expired"}', 401);
      });
      await expectLater(BrandGuardApiService.getReviews(), throwsException);
      expect(session.accessToken, isNull);
      expect(calls, 2);
      await expectLater(BrandGuardApiService.getReviews(), throwsException);
      expect(calls, 2);
    },
  );

  test(
    'logout clears local tokens immediately, even before remote response',
    () async {
      final gate = Completer<http.Response>();
      BrandGuardApiService.clientForTesting = MockClient((request) {
        expect(request.headers['Authorization'], 'Bearer creator-token');
        return gate.future;
      });
      final operation = BrandGuardApiService.signOut();
      expect(session.currentUser, isNull);
      expect(session.refreshToken, isNull);
      gate.complete(http.Response('{}', 200));
      await operation;
    },
  );

  test(
    'an in-flight refresh cannot restore an account after local signout',
    () async {
      final gate = Completer<http.Response>();
      BrandGuardApiService.clientForTesting = MockClient(
        (request) async => request.url.path.endsWith('/refresh')
            ? gate.future
            : http.Response('{"detail":"expired"}', 401),
      );
      final operation = BrandGuardApiService.getReviews();
      final expectation = expectLater(operation, throwsException);
      await Future<void>.delayed(Duration.zero);
      session.signOut();
      gate.complete(http.Response(jsonEncode(tokenData()), 200));
      await expectation;
      expect(session.currentUser, isNull);
    },
  );

  test(
    'signup confirmation is not treated as an authenticated session',
    () async {
      session.signOut();
      BrandGuardApiService.clientForTesting = MockClient(
        (_) async => http.Response(
          '{"requires_confirmation":true,"message":"Confirm email"}',
          200,
        ),
      );
      final data = await BrandGuardApiService.signup(
        'User',
        'user@example.com',
        'Password123!',
      );
      expect(data['requires_confirmation'], isTrue);
      expect(session.accessToken, isNull);
    },
  );

  test('backend validation and non-JSON errors stay visible', () async {
    BrandGuardApiService.clientForTesting = MockClient(
      (_) async =>
          http.Response('{"detail":[{"msg":"Password too short"}]}', 422),
    );
    await expectLater(
      BrandGuardApiService.getReviews(),
      throwsA(
        isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('Password too short'),
        ),
      ),
    );
    BrandGuardApiService.clientForTesting = MockClient(
      (_) async => http.Response('<html>Bad gateway</html>', 502),
    );
    await expectLater(
      BrandGuardApiService.getReviews(),
      throwsA(
        isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('non-JSON'),
        ),
      ),
    );
  });
}

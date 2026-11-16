import 'package:brandguard/core/auth/demo_auth.dart';
import 'package:brandguard/core/auth/session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(session.signOut);
  test('demo values are autofill only and never create a session', () {
    expect(DemoAuth.findAccount(' CREATOR@BRANDGUARD.DEMO ')?.userId, 'u1');
    expect(DemoAuth.findAccount('unknown@example.com'), isNull);
    expect(DemoAuth.reviewer.roleLabel, 'Reviewer');
    expect(session.currentUser, isNull);
  });
  test('signout clears user identity and both tokens', () {
    session.signIn(
      DemoAuth.reviewer.user,
      accessToken: 'access',
      refreshToken: 'refresh',
    );
    expect(session.currentUser?.isReviewer, isTrue);
    session.signOut();
    expect(session.currentUser, isNull);
    expect(session.accessToken, isNull);
    expect(session.refreshToken, isNull);
  });
  test('server user shapes and admin reviewer privileges parse', () {
    expect(
      User.fromJson({'user_id': 'u1', 'name': 'Alice', 'role': 'creator'})
          .isReviewer,
      isFalse,
    );
    expect(
      User.fromJson({'id': 'u2', 'name': 'Bob', 'role': 'reviewer'}).userId,
      'u2',
    );
    expect(
      User.fromJson({'user_id': 'admin', 'role': 'admin'}).isReviewer,
      isTrue,
    );
  });
}

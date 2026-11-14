import 'package:flutter/foundation.dart';

import 'api.dart';
import 'models.dart';

/// Who is holding the phone. No token, no password: a prototype's honest version
/// of sign-in. The API re-reads the role from the users table on every request.
class Session extends ChangeNotifier {
  User? user;

  bool get isSignedIn => user != null;

  bool get canApprove => user?.role == 'reviewer' || user?.role == 'admin';

  void signIn(User value) {
    user = value;
    Api.userId = value.id;
    notifyListeners();
  }

  void signOut() {
    user = null;
    Api.userId = null;
    notifyListeners();
  }
}

/// One session for the whole app. Small enough not to need a state-management
/// package, and adding one would be the second dependency.
final Session session = Session();

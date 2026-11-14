// A thin test that does not need a server: it checks the vocabulary the UI is
// allowed to use. The interesting assertions live in database/tests and
// scripts/smoke.py, where they test behaviour rather than rendering.
import 'package:brandguard/app/theme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every finding status has a colour and a human label', () {
    const List<String> statuses = <String>[
      'CONFIRMED_RULE_MATCH',
      'AI_INTERPRETATION',
      'UNSUPPORTED',
      'SOURCE_CONFLICT_OR_EXPIRED',
      'NEEDS_AUTHORISED_REVIEWER',
    ];
    for (final String status in statuses) {
      expect(StatusStyle.label(status), isNot(status),
          reason: '$status needs a human label');
      expect(StatusStyle.colour(status), isNotNull);
    }
  });

  test('only two statuses block an approval, and unsupported is not one', () {
    expect(StatusStyle.blocksApproval('CONFIRMED_RULE_MATCH'), isTrue);
    expect(StatusStyle.blocksApproval('SOURCE_CONFLICT_OR_EXPIRED'), isTrue);
    expect(StatusStyle.blocksApproval('UNSUPPORTED'), isFalse,
        reason: 'unsupported does not mean false');
    expect(StatusStyle.blocksApproval('NEEDS_AUTHORISED_REVIEWER'), isFalse);
    expect(StatusStyle.blocksApproval('AI_INTERPRETATION'), isFalse);
  });
}

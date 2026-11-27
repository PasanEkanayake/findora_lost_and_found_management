// The main user flows on a real device or emulator:
//
//   flutter test integration_test -d <device id>
//
// They are the same flows the widget tests run (test/support/flows.dart), so
// a failure on a device but not in `flutter test` points at the engine,
// screen size or platform rather than the logic. Like the widget tests they
// use in-memory fakes in place of Supabase — the whole app can't start without
// a real project — so this does not need a backend, an account or a network.
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/flows.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // The device's own screen is used; don't resize it.
  const onDevice = false;

  group('Matches', () {
    testWidgets('two-sided confirmation', (tester) async {
      await twoSidedConfirmationFlow(tester, resizeView: onDevice);
    });

    testWidgets('the other person confirmed first', (tester) async {
      await otherConfirmedFirstFlow(tester, resizeView: onDevice);
    });

    testWidgets('not a match, then undo', (tester) async {
      await dismissAndUndoFlow(tester, resizeView: onDevice);
    });

    testWidgets('paging with Show more', (tester) async {
      await matchesPagingFlow(tester, resizeView: onDevice);
    });

    testWidgets('server-side filters', (tester) async {
      await matchesFilterFlow(tester, resizeView: onDevice);
    });
  });

  group('Connectivity', () {
    testWidgets('offline banner', (tester) async {
      await offlineBannerFlow(tester, resizeView: onDevice);
    });
  });

  group('Moderation', () {
    testWidgets('admin queue, appeals and activity log', (tester) async {
      await adminModerationFlow(tester, resizeView: onDevice);
    });

    testWidgets('owner appeals a hidden post', (tester) async {
      await ownerAppealFlow(tester, resizeView: onDevice);
    });
  });
}

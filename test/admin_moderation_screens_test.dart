import 'package:findora/features/profile/admin_reports_screen.dart';
import 'package:findora/features/profile/data/profile_providers.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_moderation_repositories.dart';
import 'support/flows.dart';
import 'support/test_app.dart';

void main() {
  testWidgets('admin works the queue: restore, remove, appeals, activity log', (tester) async {
    await adminModerationFlow(tester);
  });

  testWidgets('empty queues say so', (tester) async {
    final repo = FakeAdminRepository();
    await pumpApp(
      tester,
      const AdminReportsScreen(),
      overrides: [adminRepositoryProvider.overrideWithValue(repo)],
    );

    expect(find.text('No open reports.'), findsOneWidget);

    await tapText(tester, 'People');
    expect(find.text('No open reports about people.'), findsOneWidget);

    await tapText(tester, 'Appeals');
    expect(find.text('No open appeals.'), findsOneWidget);

    await tapText(tester, 'Activity');
    expect(find.text('Nothing logged yet.'), findsOneWidget);
  });
}

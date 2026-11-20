import 'package:findora/features/profile/data/moderated_item_model.dart';
import 'package:findora/features/profile/data/profile_providers.dart';
import 'package:findora/features/profile/hidden_posts_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/fake_moderation_repositories.dart';
import 'support/flows.dart';
import 'support/test_app.dart';

void main() {
  testWidgets('owner sees why a post is hidden and appeals it, once', (tester) async {
    await ownerAppealFlow(tester);
  });

  testWidgets('nothing hidden: a plain message', (tester) async {
    final repo = FakeModerationRepository([]);
    await pumpApp(
      tester,
      const HiddenPostsScreen(),
      overrides: [moderationRepositoryProvider.overrideWithValue(repo)],
    );

    expect(find.text('None of your posts are hidden.'), findsOneWidget);
  });

  testWidgets('an appeal the server refuses shows its reason and keeps the button', (tester) async {
    final repo = FakeModerationRepository(
      [
        ModeratedItemModel(
          itemId: 'i1',
          title: 'Black wallet',
          itemType: 'lost',
          moderationState: 'auto_hidden',
          moderatedAt: DateTime(2026, 10, 1),
        ),
      ],
      submitError: PostgrestException(
        message: 'You have already appealed this decision.',
        code: '22023',
      ),
    );
    await pumpApp(
      tester,
      const HiddenPostsScreen(),
      overrides: [moderationRepositoryProvider.overrideWithValue(repo)],
    );

    await tapText(tester, 'Appeal');
    await enterDialogText(tester, 'This is definitely my own wallet.');
    await tester.tap(find.widgetWithText(FilledButton, 'Send appeal'));
    await settle(tester);

    expect(find.text('You have already appealed this decision.'), findsOneWidget);
    expect(find.text('Appeal'), findsOneWidget); // still offered; the server decides
    expect(repo.appeals, isEmpty);
  });
}

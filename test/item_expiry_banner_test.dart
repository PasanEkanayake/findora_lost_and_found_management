import 'package:findora/core/providers/auth_providers.dart';
import 'package:findora/features/items/data/item_model.dart';
import 'package:findora/features/items/data/items_providers.dart';
import 'package:findora/features/items/data/items_repository.dart';
import 'package:findora/features/items/widgets/item_expiry_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/test_app.dart';

/// Records renew requests; everything else is unused by the banner.
class _RenewRepository implements ItemsRepository {
  final List<String> renewed = [];
  Object? error;

  @override
  Future<DateTime> renewItem(String itemId) async {
    if (error != null) throw error!;
    renewed.add(itemId);
    return DateTime(2026, 12, 17);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

User _user(String id) => User(
      id: id,
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: '2026-01-01T00:00:00Z',
    );

ItemModel _item({String status = 'open', int daysLeft = 5, String owner = 'me'}) => ItemModel.fromMap({
      'id': 'i1',
      'user_id': owner,
      'type': 'lost',
      'status': status,
      'title': 'Black wallet',
      'created_at': '2026-08-01T10:00:00+00:00',
      'expires_at': DateTime.now().add(Duration(days: daysLeft, hours: 1)).toUtc().toIso8601String(),
      'item_images': <Map<String, dynamic>>[],
    });

void main() {
  Future<_RenewRepository> pump(WidgetTester tester, ItemModel item) async {
    final repo = _RenewRepository();
    await pumpApp(
      tester,
      Scaffold(body: ItemExpiryBanner(item: item)),
      overrides: [
        itemsRepositoryProvider.overrideWithValue(repo),
        currentUserProvider.overrideWithValue(_user('me')),
      ],
    );
    return repo;
  }

  testWidgets('owner, expiring soon: says how long, and Keep it up renews', (tester) async {
    final repo = await pump(tester, _item(daysLeft: 5));

    expect(find.textContaining('expires in 6 days'), findsOneWidget);
    await tester.tap(find.text('Keep it up'));
    await settle(tester);

    expect(repo.renewed, ['i1']);
    expect(find.text("Kept up — it'll stay for another 60 days."), findsOneWidget);
  });

  testWidgets('owner, expired: says so, and Renew brings it back', (tester) async {
    final repo = await pump(tester, _item(status: 'expired', daysLeft: -3));

    expect(find.textContaining('This post has expired'), findsOneWidget);
    await tester.tap(find.text('Renew'));
    await settle(tester);

    expect(repo.renewed, ['i1']);
    expect(find.text('Your post is back up for another 60 days.'), findsOneWidget);
  });

  testWidgets('plenty of time left: nothing is shown', (tester) async {
    await pump(tester, _item(daysLeft: 40));

    expect(find.text('Keep it up'), findsNothing);
    expect(find.textContaining('expires'), findsNothing);
  });

  testWidgets("someone else's post: nothing is shown, even when expired", (tester) async {
    await pump(tester, _item(status: 'expired', daysLeft: -3, owner: 'someone-else'));

    expect(find.text('Renew'), findsNothing);
    expect(find.textContaining('expired'), findsNothing);
  });

  testWidgets('a refused renewal shows the reason', (tester) async {
    final repo = _RenewRepository()
      ..error = PostgrestException(
        message: 'That post was removed, so it can\'t be renewed.',
        code: '22023',
      );
    await pumpApp(
      tester,
      Scaffold(body: ItemExpiryBanner(item: _item(status: 'expired', daysLeft: -3))),
      overrides: [
        itemsRepositoryProvider.overrideWithValue(repo),
        currentUserProvider.overrideWithValue(_user('me')),
      ],
    );

    await tester.tap(find.text('Renew'));
    await settle(tester);

    expect(find.text("That post was removed, so it can't be renewed."), findsOneWidget);
  });
}

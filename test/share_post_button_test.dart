import 'package:findora/features/items/data/item_model.dart';
import 'package:findora/features/items/widgets/share_post_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_app.dart';

ItemModel _item({String status = 'open', String type = 'lost'}) => ItemModel.fromMap({
      'id': 'item-1',
      'user_id': 'u1',
      'type': type,
      'status': status,
      'title': 'Black wallet',
      'created_at': '2026-10-01T10:00:00+00:00',
      'item_images': <Map<String, dynamic>>[],
    });

void main() {
  Widget host(SharePostButton button) => Scaffold(appBar: AppBar(actions: [button]));

  testWidgets('shares the title and link of an open post', (tester) async {
    String? sharedText;
    String? sharedSubject;
    await pumpApp(
      tester,
      host(SharePostButton(
        item: _item(),
        linkBuilder: (id) => 'https://share.example.com/p/$id',
        onShare: (text, subject) async {
          sharedText = text;
          sharedSubject = subject;
        },
      )),
    );

    await tester.tap(find.byIcon(Icons.share_outlined));
    await settle(tester);

    expect(sharedText, 'Lost: Black wallet\nSee it on Findora: https://share.example.com/p/item-1');
    expect(sharedSubject, 'Lost: Black wallet');
  });

  testWidgets('a found post says Found', (tester) async {
    String? sharedText;
    await pumpApp(
      tester,
      host(SharePostButton(
        item: _item(type: 'found'),
        linkBuilder: (id) => 'https://x/p/$id',
        onShare: (text, subject) async => sharedText = text,
      )),
    );

    await tester.tap(find.byIcon(Icons.share_outlined));
    expect(sharedText, startsWith('Found: Black wallet'));
  });

  testWidgets('no link configured: no button', (tester) async {
    await pumpApp(tester, host(SharePostButton(item: _item(), linkBuilder: (_) => null)));

    expect(find.byIcon(Icons.share_outlined), findsNothing);
  });

  testWidgets('a post that is no longer open has nothing to share', (tester) async {
    for (final status in ['expired', 'resolved', 'claimed']) {
      await pumpApp(
        tester,
        host(SharePostButton(item: _item(status: status), linkBuilder: (id) => 'https://x/p/$id')),
      );
      expect(find.byIcon(Icons.share_outlined), findsNothing, reason: status);
    }
  });

  testWidgets('if the share sheet fails, the link is copied instead', (tester) async {
    await pumpApp(
      tester,
      host(SharePostButton(
        item: _item(),
        linkBuilder: (id) => 'https://x/p/$id',
        onShare: (text, subject) async => throw Exception('no share sheet'),
      )),
    );

    await tester.tap(find.byIcon(Icons.share_outlined));
    await settle(tester);

    expect(find.text('Link copied.'), findsOneWidget);
  });
}

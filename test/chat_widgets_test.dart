import 'dart:async';

import 'package:findora/features/chat/data/chat_images.dart';
import 'package:findora/features/chat/widgets/chat_bubble.dart';
import 'package:findora/features/chat/widgets/chat_composer.dart';
import 'package:findora/features/chat/widgets/typing_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_app.dart';

void main() {
  group('ChatComposer', () {
    Widget host(ChatComposer composer) => Scaffold(
          body: Column(children: [const Spacer(), composer]),
        );

    testWidgets('typing, sending and the photo button all report back', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      var sent = 0;
      var attached = 0;
      String? changed;

      await pumpApp(
        tester,
        host(ChatComposer(
          controller: controller,
          onSend: () => sent++,
          onAttachPhoto: () => attached++,
          sendingPhoto: false,
          onChanged: (text) => changed = text,
        )),
      );

      await tester.enterText(find.byType(TextField), 'hello there');
      expect(changed, 'hello there');

      await tester.tap(find.byIcon(Icons.send_rounded));
      expect(sent, 1);

      await tester.tap(find.byIcon(Icons.add_photo_alternate_outlined));
      expect(attached, 1);
    });

    testWidgets('while a photo uploads: progress bar, hint, buttons wait', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await pumpApp(
        tester,
        host(ChatComposer(
          controller: controller,
          onSend: () {},
          onAttachPhoto: () {},
          sendingPhoto: true,
        )),
      );

      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('Sending photo…'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.add_photo_alternate_outlined))
            .onPressed,
        isNull,
      );
      expect(
        tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.send_rounded)).onPressed,
        isNull,
      );
    });
  });

  group('ChatBubble', () {
    final sentAt = DateTime(2026, 10, 1, 14, 5);

    testWidgets('a text message shows its text and time, no photo', (tester) async {
      await pumpApp(
        tester,
        Scaffold(body: ChatBubble(isMine: true, content: 'See you at the gate', createdAt: sentAt)),
      );

      expect(find.text('See you at the gate'), findsOneWidget);
      expect(find.text('2:05 PM'), findsOneWidget);
      expect(find.byType(ChatPhoto), findsNothing);
    });

    testWidgets('a photo is loading: a spinner tile, and no empty caption', (tester) async {
      final never = Completer<String>(); // the signed link never arrives
      await pumpApp(
        tester,
        Scaffold(
          body: ChatBubble(
            isMine: false,
            content: '',
            createdAt: sentAt,
            imagePath: 'm/match/photo.jpg',
          ),
        ),
        overrides: [chatImageUrlProvider.overrideWith((ref, path) => never.future)],
      );

      expect(find.byType(ChatPhoto), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('2:05 PM'), findsOneWidget);
    });

    testWidgets('a photo that fails to load can be retried by tapping it', (tester) async {
      var requests = 0;
      await pumpApp(
        tester,
        Scaffold(
          body: ChatBubble(
            isMine: false,
            content: 'Is this yours?',
            createdAt: sentAt,
            imagePath: 'm/match/photo.jpg',
          ),
        ),
        overrides: [
          chatImageUrlProvider.overrideWith((ref, path) async {
            requests++;
            throw Exception('offline');
          }),
        ],
      );

      expect(find.text("Couldn't load — tap to retry"), findsOneWidget);
      expect(find.text('Is this yours?'), findsOneWidget); // the caption still shows
      expect(requests, 1);

      await tester.tap(find.text("Couldn't load — tap to retry"));
      await settle(tester);
      expect(requests, 2);
    });
  });

  group('TypingIndicator', () {
    testWidgets('shows three dots only while the other person is typing', (tester) async {
      final typing = ValueNotifier<bool>(false);
      addTearDown(typing.dispose);
      final dots = find.descendant(of: find.byType(TypingIndicator), matching: find.byType(Opacity));

      await pumpApp(tester, Scaffold(body: TypingIndicator(typing: typing)));
      expect(dots, findsNothing);

      typing.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(dots, findsNWidgets(3));

      typing.value = false;
      await tester.pump();
      expect(dots, findsNothing);
    });
  });
}

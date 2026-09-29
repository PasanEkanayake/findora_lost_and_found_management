import 'package:flutter/material.dart';

import 'document/document_content.dart';
import 'document/document_screen.dart';

/// Meetup and scam-safety guidance. Findora's whole purpose is arranging
/// in-person handoffs between strangers, so this is core content, not a
/// footnote. Text: `document/document_content.dart` (kSafetyGuidelines).
class SafetyGuidelinesScreen extends StatelessWidget {
  const SafetyGuidelinesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const DocumentScreen(
      title: 'Safety guidelines',
      intro: 'Findora arranges in-person handoffs between people who '
          "don't know each other. These guidelines help you do that safely.",
      sections: kSafetyGuidelines,
    );
  }
}

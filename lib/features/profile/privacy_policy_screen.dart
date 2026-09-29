import 'package:flutter/material.dart';

import 'document/document_content.dart';
import 'document/document_screen.dart';

/// Privacy policy. The text is in `document/document_content.dart`
/// (kPrivacyPolicy); a Markdown copy for publishing lives in
/// docs/PRIVACY_POLICY.md.
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const DocumentScreen(
      title: 'Privacy policy',
      intro: 'Last updated: $kPolicyUpdated',
      sections: kPrivacyPolicy,
    );
  }
}

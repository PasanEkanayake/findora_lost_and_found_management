import 'package:flutter/material.dart';

import '../../../core/widgets/confirm_dialog.dart';

/// A run of digits, spaces and the usual separators that is long enough to be
/// a phone number — 9 to 13 digits, so a 15-digit IMEI (a good ownership
/// proof) or a short serial number doesn't trigger it.
final RegExp _phoneLike = RegExp(r'\+?\d[\d\s().\-]{7,}\d');

bool looksLikePhoneNumber(String text) {
  for (final match in _phoneLike.allMatches(text)) {
    final digits = match.group(0)!.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 9 && digits.length <= 13) return true;
  }
  return false;
}

/// Gives the sender a moment to think before putting a phone number into a
/// chat with someone they've only just matched with. Returns true if the
/// message should be sent.
Future<bool> confirmBeforeSending(BuildContext context, String text) async {
  if (!looksLikePhoneNumber(text)) return true;
  return showConfirmDialog(
    context,
    icon: Icons.phone_outlined,
    title: 'Share a phone number?',
    message: "This message looks like it contains a phone number. Only share it "
        "once you're confident you're talking to the right person — you can "
        "arrange everything in this chat without it.",
    confirmLabel: 'Send anyway',
  );
}

import 'package:flutter/material.dart';

/// The message box at the bottom of both chat screens: a photo button, the
/// text field and the send button, with a thin progress bar above while a
/// photo is uploading.
class ChatComposer extends StatelessWidget {
  const ChatComposer({
    super.key,
    required this.controller,
    required this.onSend,
    required this.onAttachPhoto,
    required this.sendingPhoto,
    this.onChanged,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onAttachPhoto;

  /// True while a photo is being uploaded and sent: the photo button and the
  /// send button wait.
  final bool sendingPhoto;

  /// Called as the text changes (used for the typing indicator).
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (sendingPhoto) const LinearProgressIndicator(minHeight: 2),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 12, 12),
            child: Row(
              children: [
                IconButton(
                  onPressed: sendingPhoto ? null : onAttachPhoto,
                  tooltip: 'Send a photo',
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                ),
                Expanded(
                  child: TextField(
                    controller: controller,
                    onChanged: onChanged,
                    textCapitalization: TextCapitalization.sentences,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: 2000, // matches the database limit
                    buildCounter: (context, {required currentLength, required isFocused, maxLength}) =>
                        null, // keep the compact look; the limit still applies
                    decoration: InputDecoration(
                      hintText: sendingPhoto ? 'Sending photo…' : 'Message',
                    ),
                    onSubmitted: (_) => onSend(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: sendingPhoto ? null : onSend,
                  tooltip: 'Send message',
                  icon: const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
